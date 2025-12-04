/********************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @ClassName:        LeaveTriggerHandler
 * @Description:      Trigger handler class for Leave__c object to manage leave applications and case reassignments
 **********************************************************************************************************************/
public with sharing class LeaveTriggerHandler{
    /********************************************************************************************************************
     * @Author:          CRM Team Innovation
     * @methodName:      handleBeforeInsertUpdate
     * @param:         newLeaves-List of Leave__c records before insert/update
     * @Description:     Validate leave applications and adjust leave types based on balances before insert/update
     **********************************************************************************************************************/
    public static void handleBeforeInsertUpdate(List<Leave__c> newLeaves){
        Set<Id> ownerIds=new Set<Id>();
        for(Leave__c leave:newLeaves){
            if(leave.OwnerId!=null){
                ownerIds.add(leave.OwnerId);
            }
        }
        Map<Id,Leave_Balance__c> balanceMap=new Map<Id,Leave_Balance__c>();
        List<Leave_Balance__c> balances=[
            SELECT 
                Id,SetupOwnerId,Earned_Leave__c,Sick_Leave__c 
            FROM 
                Leave_Balance__c 
            WHERE 
                SetupOwnerId IN :ownerIds 
        ];
        
        for(Leave_Balance__c balance:balances){
            balanceMap.put(balance.SetupOwnerId,balance);
        }
        Map<Id,Decimal> earnedBookedMap=new Map<Id,Decimal>();
        Map<Id,Decimal> sickBookedMap=new Map<Id,Decimal>();
        List<AggregateResult> earndBookedLeaves=[
            SELECT 
                OwnerId,
                SUM(Days_Taken__c) earnedSum
            FROM 
                Leave__c 
            WHERE 
                OwnerId 
            IN 
                :ownerIds 
            AND 
                Leave_Type__c = 'Earned_Leave'
            GROUP BY 
                OwnerId
        ];
        for(AggregateResult ar:earndBookedLeaves){
            Id ownerId=(Id)ar.get('OwnerId');
            Decimal earnedSum=(Decimal)ar.get('earnedSum');
            earnedBookedMap.put(ownerId,earnedSum!=null?earnedSum:0);
        }
        List<AggregateResult> sickBookedLeaves=[
            SELECT 
                OwnerId,
                SUM(Days_Taken__c) sickSum
            FROM 
                Leave__c 
            WHERE 
                OwnerId IN :ownerIds AND Leave_Type__c = 'Sick_Leave'
            GROUP BY 
                OwnerId
        ];
        for(AggregateResult ar:sickBookedLeaves){
            Id ownerId=(Id)ar.get('OwnerId');
            Decimal sickSum=(Decimal)ar.get('sickSum');
            sickBookedMap.put(ownerId,sickSum!=null?sickSum:0);
        }
        for (Id oid:ownerIds){
            if (!earnedBookedMap.containsKey(oid)){
                earnedBookedMap.put(oid,0);
            }
            if (!sickBookedMap.containsKey(oid)){
                sickBookedMap.put(oid,0);
            }
        }
        for(Leave__c leave:newLeaves){
            if(leave.OwnerId!=null&&leave.Start_Date__c!=null&&leave.End_Date__c!=null){
                Integer numberOfDays=leave.End_Date__c.daysBetween(leave.Start_Date__c) + 1;
                if(leave.Leave_Type__c=='Earned_Leave'||leave.Leave_Type__c=='Sick_Leave'){
                    Leave_Balance__c balance=balanceMap.get(leave.OwnerId);
                    if(balance!=null){  
                        Decimal availableBalance=0;
                        if(leave.Leave_Type__c=='Earned_Leave'){
                            availableBalance=balance.Earned_Leave__c-(earnedBookedMap.containsKey(leave.OwnerId)?earnedBookedMap.get(leave.OwnerId):0);
                            if(numberOfDays > availableBalance){
                                leave.addError('Insufficient Earned Leave balance. Available balance: ' + availableBalance + ' days.');
                            }
                        }else if(leave.Leave_Type__c=='Sick_Leave'){
                            availableBalance=balance.Sick_Leave__c-(sickBookedMap.containsKey(leave.OwnerId)?sickBookedMap.get(leave.OwnerId):0);
                            if(numberOfDays > availableBalance){
                                leave.addError('Insufficient Sick Leave balance. Available balance: ' + availableBalance + ' days.');
                            }
                        }
                    }else{
                        leave.addError('Leave balance record not found for the employee.');
                        continue;
                    }
                }
            }
        }
        List<Leave__c> existingLeaves=[
            SELECT 
                Id,OwnerId,Status__c,Start_Date__c,End_Date__c
            FROM 
                Leave__c 
            WHERE 
                OwnerId IN :ownerIds 
        ];
        Map<Id,List<Leave__c>> ownerToLeavesMap=new Map<Id,List<Leave__c>>();
        for(Leave__c existingLeave:existingLeaves){
            if(!ownerToLeavesMap.containsKey(existingLeave.OwnerId)){
                ownerToLeavesMap.put(existingLeave.OwnerId,new List<Leave__c>());
            }
            ownerToLeavesMap.get(existingLeave.OwnerId).add(existingLeave);
        }
        for(Leave__c leave:newLeaves){
            if(leave.OwnerId!=null){
                List<Leave__c> ownerLeaves=ownerToLeavesMap.get(leave.OwnerId);
                Boolean isActiveLeave=(leave.Status__c!=null&&leave.Status__c=='Active');
                if(isActiveLeave){
                    if(ownerLeaves!=null){
                        for(Leave__c existingLeave:ownerLeaves){
                            if(existingLeave.Status__c!=null&&existingLeave.Status__c=='Active'){
                                leave.addError('Only one active leave record is allowed per employee.');
                                break;
                            }
                        }
                    }
                }
                if(leave.Start_Date__c!=null&&leave.End_Date__c!=null){
                    if(ownerLeaves!=null){
                        for(Leave__c existingLeave:ownerLeaves){
                            if(existingLeave.Status__c!=null&&existingLeave.Status__c=='Approved'&&existingLeave.Id!=leave.Id){
                                if((leave.Start_Date__c <= existingLeave.End_Date__c)&&(leave.End_Date__c >= existingLeave.Start_Date__c)){
                                    leave.addError('You already have leave in this time period (' + 
                                                  existingLeave.Start_Date__c + ' to ' + existingLeave.End_Date__c + '). ' +
                                                  'You cannot apply for more leave in the same time period.');
                            break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    /********************************************************************************************************************
     * @Author:          CRM Team Innovation
     * @methodName:      submitNewLeavesForApproval
     * @param:         newLeaves-List of newly inserted Leave__c records
     * @Description:     Submit new leave records for approval if status is 'Pending'
     **********************************************************************************************************************/
    private static Boolean isAlreadyRunning=false;
    public static void submitNewLeavesForApproval(List<Leave__c> newLeaves){
        if (isAlreadyRunning) return;
        isAlreadyRunning=true;
        for (Leave__c leave:newLeaves){
            if (leave.Status__c=='Pending'){
                Approval.ProcessSubmitRequest req=new Approval.ProcessSubmitRequest();
                req.setObjectId(leave.Id);
                req.setComments('New leave record submitted for approval.');
                req.setProcessDefinitionNameOrId('Leave_Approval_Process');
                Approval.ProcessResult result=Approval.process(req);
                if (!result.isSuccess()){
                    System.debug('Approval failed for ' + leave.Id + ': '
                        + result.getErrors());
                }
            }
        }
    }
    /************************************************************************************************************************
     * @Author:          CRM Team Innovation
     * @methodName:      handleAfterUpdate
     * @param:         newLeaves-List of Leave__c records after update
     * @param:         oldMap-Map of Leave__c records before update
     * @Description:     Handle case reassignment when leave status changes to Active or Inactive
     **************************************************************************************************************************/
    public static void handleAfterUpdate(List<Leave__c> newLeaves,Map<Id,Leave__c> oldMap){
        List<Leave__c> activatedLeaves=new List<Leave__c>();
        List<Leave__c> inactivatedLeaves=new List<Leave__c>();
        for (Leave__c leave:newLeaves){
            Leave__c oldLeave=oldMap.get(leave.Id);
            if (leave.Status__c=='Active'&&oldLeave.Status__c!='Active'){
                activatedLeaves.add(leave);
            }
            if (leave.Status__c=='Inactive'&&oldLeave.Status__c!='Inactive'){
                inactivatedLeaves.add(leave);
            }
        }
        if (!activatedLeaves.isEmpty()){
            Set<Id> ownerIds=new Set<Id>();
            for (Leave__c leave:activatedLeaves){
                ownerIds.add(leave.OwnerId);
            }
            List<Case> openCases=[
                SELECT
                    Id,CaseNumber,OwnerId,Orginal_Owner_Id__c,Subject,Status,Priority,Type
                FROM
                    Case
                WHERE
                    OwnerId IN :ownerIds AND IsClosed=false
            ];
            Map<Id,List<Case>> ownerToCasesMap=new Map<Id,List<Case>>();
            for (Case c:openCases){
                if (!ownerToCasesMap.containsKey(c.OwnerId)){
                    ownerToCasesMap.put(c.OwnerId,new List<Case>());
                }
                ownerToCasesMap.get(c.OwnerId).add(c);
            }
            List<Case> casesToUpdate=new List<Case>();
            Map<Id,List<Case>> delegatedToCasesMap=new Map<Id,List<Case>>();
            List<Case> casesToAddToQueue=new List<Case>();
            Set<Id> delegatedApproverIds = new Set<Id>();
            Map<Id, User> existingDelegatedUsers = new Map<Id, User>([SELECT 
                                                                            Id 
                                                                    FROM 
                                                                        User 
                                                                    WHERE 
                                                                        Id 
                                                                    IN 
                                                                        :ownerIds]);
            for (Leave__c leave:activatedLeaves){
                List<Case> userCases=ownerToCasesMap.get(leave.OwnerId);
                if (userCases!=null){
                    if (!existingDelegatedUsers.isEmpty()){
                        for (Case c:userCases){
                            c.OwnerId=existingDelegatedUsers.get(leave.OwnerId).Id;
                            c.Orginal_Owner_Id__c=leave.OwnerId;
                            c.Is_delegated__c=true;
                            casesToUpdate.add(c);
                            if (!delegatedToCasesMap.containsKey(existingDelegatedUsers.get(leave.OwnerId).Id)){
                                delegatedToCasesMap.put(existingDelegatedUsers.get(leave.OwnerId).Id,new List<Case>());
                            }
                            delegatedToCasesMap.get(existingDelegatedUsers.get(leave.OwnerId).Id).add(c);
                        }
                    }else{
                        for (Case c:userCases){
                            casesToAddToQueue.add(c);
                        }
                    }
                }
            }
            if (!casesToUpdate.isEmpty()){
                Database.update(casesToUpdate,false);
            }
            if (!casesToAddToQueue.isEmpty()){
                Id caseQueueId = '03gdL000001dqpOQAQ';
                for (Case c : casesToAddToQueue){
                    c.OwnerId = caseQueueId;
                }
                Database.update(casesToAddToQueue, false);
            }
            List<Messaging.SingleEmailMessage> emails=new List<Messaging.SingleEmailMessage>();
            Set<Id> delegatedIds=delegatedToCasesMap.keySet();
            Map<Id,User> userMap=new Map<Id,User>([
                SELECT 
                    Id,Email,Name
                FROM 
                    User
                WHERE 
                    Id IN :delegatedIds
            ]);
            for (Id delegatedId:delegatedIds){
                User delegatedUser=userMap.get(delegatedId);
                if (delegatedUser!=null&&delegatedUser.Email!=null){
                    List<Case> reassignedCases=delegatedToCasesMap.get(delegatedId);
                    String subject='Reassigned Cases Summary';
                    String body='Dear ' + delegatedUser.Name + ',\n\nThe following cases have been reassigned to you as the delegated user for an employee on leave:\n\n';
                    for (Case c:reassignedCases){
                        body += 'Case Number: ' + c.CaseNumber + '\n';
                        body += 'Subject: ' + c.Subject + '\n';
                        body += 'Status: ' + c.Status + '\n';
                        body += 'Priority: ' + c.Priority + '\n';
                        body += 'Type: ' + c.Type + '\n\n';
                    }
                    body += '\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';
                    Messaging.SingleEmailMessage email=new Messaging.SingleEmailMessage();
                    email.setToAddresses(new String[]{delegatedUser.Email});
                    email.setSubject(subject);
                    email.setPlainTextBody(body);
                    emails.add(email);
                }
            }
            if (!emails.isEmpty()){
                Messaging.sendEmail(emails);
            }
        }
        if (!inactivatedLeaves.isEmpty()){
            Set<Id> ownerIds=new Set<Id>();
            for (Leave__c leave:inactivatedLeaves){
                ownerIds.add(leave.OwnerId);
            }
            Map<Id,Id> userIdToDelegatedApproverIdMap=new Map<Id,Id>();
            List<User> users=[
                SELECT 
                    Id,DelegatedApproverId
                FROM 
                    User
                WHERE 
                    Id 
                IN 
                    :ownerIds
                WITH 
                    USER_MODE
            ];
            for (User u:users){
                userIdToDelegatedApproverIdMap.put(u.Id,u.DelegatedApproverId);
            }
            Set<Id> delegatedIds=new Set<Id>();
            for (Id delegatedId:userIdToDelegatedApproverIdMap.values()){
                if (delegatedId!=null){
                    delegatedIds.add(delegatedId);
                }
            }
            List<Case> delegatedCases=[
                SELECT
                    Id,CaseNumber,OwnerId,Orginal_Owner_Id__c,Subject,Status,Priority,Type
                FROM
                    Case
                WHERE
                    OwnerId IN :delegatedIds AND Is_delegated__c=true AND IsClosed=false
            ];
            Map<Id,List<Case>> delegatedToCasesMap=new Map<Id,List<Case>>();
            for (Case c:delegatedCases){
                if (!delegatedToCasesMap.containsKey(c.OwnerId)){
                    delegatedToCasesMap.put(c.OwnerId,new List<Case>());
                }
                delegatedToCasesMap.get(c.OwnerId).add(c);
            }
            List<Case> casesToReassign=new List<Case>();
            Map<Id,List<Case>> originalToCasesMap=new Map<Id,List<Case>>();
            for (Leave__c leave:inactivatedLeaves){
                Id delegatedApproverId=userIdToDelegatedApproverIdMap.get(leave.OwnerId);
                List<Case> userCases=delegatedToCasesMap.get(delegatedApproverId);
                if (userCases!=null){
                    for (Case c:userCases){
                        if (c.Orginal_Owner_Id__c==leave.OwnerId){
                            c.OwnerId=c.Orginal_Owner_Id__c;
                            c.Is_delegated__c=false;
                            c.Orginal_Owner_Id__c=null;
                            casesToReassign.add(c);
                            if (!originalToCasesMap.containsKey(c.OwnerId)){
                                originalToCasesMap.put(c.OwnerId,new List<Case>());
                            }
                            originalToCasesMap.get(c.OwnerId).add(c);
                        }
                    }
                }
            }
            if (!casesToReassign.isEmpty()){
                Database.update(casesToReassign,false);
            }
            List<Messaging.SingleEmailMessage> emails=new List<Messaging.SingleEmailMessage>();
            Set<Id> allUserIds=new Set<Id>();
            
            // Collect all user IDs that need to be queried (owners and their delegated approvers)
            for (Leave__c leave:inactivatedLeaves){
                allUserIds.add(leave.OwnerId);
            }
            // Query users to get DelegatedApproverId for all involved users
            Map<Id,Id> originalOwnerToDelegatedApproverMap = new Map<Id,Id>();
            List<User> usersWithDelegatedApprovers = [
                SELECT 
                    Id, DelegatedApproverId
                FROM 
                    User
                WHERE 
                    Id IN :allUserIds
            ];
            
            for(User u : usersWithDelegatedApprovers) {
                originalOwnerToDelegatedApproverMap.put(u.Id, u.DelegatedApproverId);
            }
            
            // Add delegated approvers to the set of users to query
            for (Leave__c leave:inactivatedLeaves){
                Id delegatedApproverId = originalOwnerToDelegatedApproverMap.get(leave.OwnerId);
                if (delegatedApproverId != null){
                    allUserIds.add(delegatedApproverId);
                }
            }
            
            Map<Id,User> userMap=new Map<Id,User>([
                SELECT 
                    Id,Email,Name
                FROM 
                    User
                WHERE 
                    Id 
                IN :allUserIds
            ]);

            for (Leave__c leave:inactivatedLeaves){
                User originalUser=userMap.get(leave.OwnerId);
                Id delegatedApproverId = originalOwnerToDelegatedApproverMap.get(leave.OwnerId);
                User delegatedUser = delegatedApproverId != null ? userMap.get(delegatedApproverId) : null;
                List<Case> reassignedCases=originalToCasesMap.get(leave.OwnerId);
                if (reassignedCases!=null&&!reassignedCases.isEmpty()){
                    if (originalUser!=null&&originalUser.Email!=null){
                        String subject='Cases Reassigned Back to You';
                        String body='Dear ' + originalUser.Name + ',\n\nYour leave has ended,and the following cases have been reassigned back to you:\n\n';
                        for (Case c:reassignedCases){
                            body += 'Case Number: ' + c.CaseNumber + '\n';
                            body += 'Subject: ' + c.Subject + '\n';
                            body += 'Status: ' + c.Status + '\n';
                            body += 'Priority: ' + c.Priority + '\n';
                            body += 'Type: ' + c.Type + '\n\n';
                        }
                        body += '\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';
                        Messaging.SingleEmailMessage email=new Messaging.SingleEmailMessage();
                        email.setToAddresses(new String[]{originalUser.Email});
                        email.setSubject(subject);
                        email.setPlainTextBody(body);
                        emails.add(email);
                    }
                    if (delegatedUser!=null&&delegatedUser.Email!=null){
                        String subject='Cases Reassigned Back to Original Owner';
                        String body='Dear ' + delegatedUser.Name + ',\n\nThe leave period has ended,and the following cases have been reassigned back to the original owner:\n\n';
                        for (Case c:reassignedCases){
                            body += 'Case Number: ' + c.CaseNumber + '\n';
                            body += 'Subject: ' + c.Subject + '\n';
                            body += 'Status: ' + c.Status + '\n';
                            body += 'Priority: ' + c.Priority + '\n';
                            body += 'Type: ' + c.Type + '\n\n';
                        }
                        body += '\nBest regards,\nLeave Management System';
                        Messaging.SingleEmailMessage email=new Messaging.SingleEmailMessage();
                        email.setToAddresses(new String[]{delegatedUser.Email});
                        email.setSubject(subject);
                        email.setPlainTextBody(body);
                        emails.add(email);
                    }
                }
            }
            if (!emails.isEmpty()){
                Messaging.sendEmail(emails);
            }
        }
    }
}
