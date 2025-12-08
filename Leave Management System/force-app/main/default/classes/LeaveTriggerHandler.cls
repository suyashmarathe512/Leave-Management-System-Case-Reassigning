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
    private static Integer calculateBusinessDays(Date startDate,Date endDate){
        Integer businessDays=0;
        Date current=startDate;
        while(current <= endDate){
            DateTime dt=DateTime.newInstance(current,Time.newInstance(0,0,0,0));
            String dayOfWeek=dt.format('EEEE');
            if(dayOfWeek!='Saturday'&&dayOfWeek!='Sunday'){
                businessDays++;
            }
            current=current.addDays(1);
        }
        return businessDays;
    }
    /********************************************************************************************************************
     * @Author:          CRM Team Innovation
     * @methodName:      checkForOverlappingDates
     * @param:         newLeave-Leave__c record being validated
     * @param:         existingLeaves-List of existing Leave__c records to compare against
     * @Description:     Helper method to check if a new leave record overlaps with existing ones
     **********************************************************************************************************************/
    private static Boolean checkForOverlappingDates(Leave__c newLeave,List<Leave__c> existingLeaves){
        if(newLeave.Start_Date__c == null || newLeave.End_Date__c == null){
            return false;
        }
        Date newStart=newLeave.Start_Date__c;
        Date newEnd=newLeave.End_Date__c;
        for(Leave__c existingLeave:existingLeaves){
            if(existingLeave.Id!=newLeave.Id){
                if(existingLeave.Status__c == 'Active' || existingLeave.Status__c == 'Approved'){
                    if((newStart <= existingLeave.End_Date__c) &&(newEnd >= existingLeave.Start_Date__c)){
                        return true; 
                    }
                }
            }
        }
        return false;
    }
    /****************************************************************************************************************************
    * @Author:         CRM Team Innovation
    * @methodName:     sendEmail
    * @param:        toAddress - Recipient email address
    * @param:        subject - Email subject
    * @param:        body - Email body content
    * @Description:    Helper method to send email notifications
    *****************************************************************************************************************************/
    private static void sendEmail(String toAddress,String subject,String body){
        if(String.isBlank(toAddress) || String.isBlank(subject) || String.isBlank(body)){
            return;
        }
        Messaging.SingleEmailMessage email=new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ toAddress });
        email.setSubject(subject);
        email.setPlainTextBody(body);
        try{
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email },false);
        } catch(Exception ex){
        }
    }
    /********************************************************************************************************************
    * @Author:        CRM Team Innovation
    * @methodName:    handleBeforeInsertUpdate
    * @param:        newLeaves-List of Leave__c records before insert/update
    * @Description:    Validate leave applications and adjust leave types based on balances before insert/update
    **********************************************************************************************************************/
    public static void handleBeforeInsertUpdate(List<Leave__c> newLeaves,Map<Id,Leave__c> oldMap){
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
        List<AggregateResult> bookedLeaves=[
            SELECT
                OwnerId,
                Leave_Type__c,
                SUM(Days_Taken__c) sumDays
            FROM
                Leave__c
            WHERE
                OwnerId IN :ownerIds
            AND
                Leave_Type__c IN('Earned_Leave','Sick_Leave')
            GROUP BY
                OwnerId,Leave_Type__c
        ];
        for(AggregateResult ar:bookedLeaves){
            Id ownerId=(Id)ar.get('OwnerId');
            String leaveType=(String)ar.get('Leave_Type__c');
            Decimal sumDays=(Decimal)ar.get('sumDays');
            if(leaveType == 'Earned_Leave'){
                earnedBookedMap.put(ownerId,sumDays!=null ? sumDays:0);
            } else if(leaveType == 'Sick_Leave'){
                sickBookedMap.put(ownerId,sumDays!=null ? sumDays:0);
            }
        }
        for(Id oid:ownerIds){
            if(!earnedBookedMap.containsKey(oid)){
                earnedBookedMap.put(oid,0);
            }
            if(!sickBookedMap.containsKey(oid)){
                sickBookedMap.put(oid,0);
            }
        }
        Set<Id> contextIds=new Set<Id>();
        for(Leave__c nl:newLeaves){
            if(nl.Id!=null){
                contextIds.add(nl.Id);
            }
        }
        Map<Id,Boolean> ownerHasActiveExistingLeave=new Map<Id,Boolean>();
        List<AggregateResult> activeLeaves=[
            SELECT
                OwnerId,
                COUNT(Id) activeCount
            FROM
                Leave__c
            WHERE
                OwnerId IN :ownerIds
            AND
                Id NOT IN :contextIds
            AND
                Status__c='Active'
            GROUP BY
                OwnerId
        ];
        for(AggregateResult ar:activeLeaves){
            Id ownerId=(Id)ar.get('OwnerId');
            Integer count=(Integer)ar.get('activeCount');
            ownerHasActiveExistingLeave.put(ownerId,count > 0);
        }
        for(Id oid:ownerIds){
            if(!ownerHasActiveExistingLeave.containsKey(oid)){
                ownerHasActiveExistingLeave.put(oid,false);
            }
        }
        Map<Id,List<Leave__c>> ownerExistingLeavesMap=new Map<Id,List<Leave__c>>();
        List<Leave__c> existingLeavesList=[
            SELECT
                Id,OwnerId,Start_Date__c,End_Date__c,Status__c
            FROM
                Leave__c
            WHERE
                OwnerId IN :ownerIds
            AND
                Id NOT IN :contextIds
            AND
                Status__c IN('Approved','Pending','Active')
        ];
        for(Leave__c leave:existingLeavesList){
            if(!ownerExistingLeavesMap.containsKey(leave.OwnerId)){
                ownerExistingLeavesMap.put(leave.OwnerId,new List<Leave__c>());
            }
            ownerExistingLeavesMap.get(leave.OwnerId).add(leave);
        }
        for(Leave__c leave:newLeaves){
            if(leave.OwnerId == null){
                continue;
            }
            Boolean isActiveLeave=(leave.Status__c!=null&&leave.Status__c == 'Active');
            if(isActiveLeave){
                Boolean hasOtherActive=ownerHasActiveExistingLeave.get(leave.OwnerId);
                if(hasOtherActive == true){
                }
            }
            if(leave.Start_Date__c!=null&&leave.End_Date__c!=null){
                Integer numberOfDays=calculateBusinessDays(leave.Start_Date__c,leave.End_Date__c);
                if(numberOfDays <= 0){
                    leave.addError('Invalid date range. End Date must be on or after Start Date.');
                    continue;
                }
                if(leave.Leave_Type__c == 'Earned_Leave' || leave.Leave_Type__c == 'Sick_Leave'){
                    Leave_Balance__c balance=balanceMap.get(leave.OwnerId);
                    if(balance!=null){
                        Decimal bookedEarned=earnedBookedMap.get(leave.OwnerId);
                        Decimal bookedSick=sickBookedMap.get(leave.OwnerId);
                        Decimal earnedTotal=balance.Earned_Leave__c;
                        Decimal sickTotal=balance.Sick_Leave__c;
                        if(leave.Leave_Type__c == 'Earned_Leave'){
                            Decimal availableBalance=earnedTotal - bookedEarned;
                            if(availableBalance < 0) availableBalance=0;
                            if(numberOfDays > availableBalance){
                                leave.addError('Please apply for Unpaid Leave becuase insufficient Earned Leave balance. Available: '+availableBalance+' day(s). Requested: '+numberOfDays+' day(s).');
                            }
                        } else if(leave.Leave_Type__c == 'Sick_Leave'){
                            Decimal availableBalance=sickTotal - bookedSick;
                            if(availableBalance < 0) availableBalance=0;
                            if(numberOfDays > availableBalance){
                                leave.addError('Please apply for Unpaid Leave becuase insufficient Sick Leave balance. Available: '+availableBalance+' day(s). Requested: '+numberOfDays+' day(s).');
                            }
                        }
                    } else{
                        leave.addError('Leave balance record not found for the employee.');
                        continue;
                    }
                }
                if(oldMap == null ||(oldMap!=null &&(leave.Status__c == 'Pending' || leave.Status__c == 'Approved'))){
                    List<Leave__c> existingApprovedLeaves=ownerExistingLeavesMap.get(leave.OwnerId);
                    if(existingApprovedLeaves!=null&&!existingApprovedLeaves.isEmpty()){
                        if(checkForOverlappingDates(leave,existingApprovedLeaves)){
                            leave.addError('You already have leave in this time period(' +
                                existingApprovedLeaves[0].Start_Date__c+' to '+existingApprovedLeaves[0].End_Date__c+'). ' +
                                'You cannot apply for more leave in the same time period.');
                        }
                    }
                }
                if(isActiveLeave){
                   
                    List<Leave__c> allActiveLeaves=[
                        SELECT 
                            Id,OwnerId,Status__c,Start_Date__c,End_Date__c
                        FROM 
                            Leave__c
                        WHERE 
                            OwnerId=:leave.OwnerId
                        AND 
                            Status__c='Active'
                        AND 
                            Id NOT IN :contextIds
                    ];
                    if(!allActiveLeaves.isEmpty()){
                       
                        for(Leave__c activeLeave:allActiveLeaves){
                            if((leave.Start_Date__c <= activeLeave.End_Date__c)&&
                            (leave.End_Date__c >= activeLeave.Start_Date__c)){
                                leave.addError('Only one active leave record is allowed per employee.');
                                break;
                            }
                        }
                    }
                }
                if(oldMap!=null){
                    Leave__c oldLeave=oldMap.get(leave.Id);
                    if(oldLeave!=null&&leave.Status__c == 'Approved'&&leave.Start_Date__c == Date.today()){
                        List<Leave__c> allActiveLeaves=[
                            SELECT 
                                Id,OwnerId,Status__c
                            FROM 
                                Leave__c
                            WHERE 
                                OwnerId=:leave.OwnerId
                            AND 
                                Status__c='Active'
                            AND 
                                Id NOT IN :contextIds
                        ];
                        if(allActiveLeaves.isEmpty()){
                            leave.Status__c='Active';
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
        if(isAlreadyRunning) return;
        isAlreadyRunning=true;
        for(Leave__c leave:newLeaves){
            if(leave.Status__c=='Pending'){
                Approval.ProcessSubmitRequest req=new Approval.ProcessSubmitRequest();
                req.setObjectId(leave.Id);
                req.setComments('New leave record submitted for approval.');
                req.setProcessDefinitionNameOrId('Leave_Approval_Process');
                Approval.ProcessResult result=Approval.process(req);
                if(!result.isSuccess()){
                    System.debug('Approval failed for '+leave.Id+': '
                    +result.getErrors());
                }
            }
        }
    }
    /************************************************************************************************************************
     * @Author:          CRM Team Innovation
     * @methodName:      getUserMap
     * @param:         userIds-Set of User Ids to query
     * @Description:     Helper method to query User records and return a map
     **************************************************************************************************************************/
    private static Map<Id,User> getUserMap(Set<Id> userIds){
        return new Map<Id,User>([
            SELECT
                Id,DelegatedApproverId,Email,Name
            FROM
                User
            WHERE
                Id IN :userIds
        ]);
    }
    /************************************************************************************************************************
     * @Author:          CRM Team Innovation
     * @methodName:      getCases
     * @param:         ownerIds-Set of Owner Ids to query
     * @param:         isDelegated-Boolean to filter by Is_delegated__c(null for no filter)
     * @Description:     Helper method to query Case records and return a list
     **************************************************************************************************************************/
    private static List<Case> getCases(Set<Id> ownerIds,Boolean isDelegated){
        String query='SELECT Id,CaseNumber,OwnerId,Orginal_Owner_Id__c,Subject,Status,Priority,Type FROM Case WHERE OwnerId IN :ownerIds AND IsClosed=false';
        if(isDelegated!=null){
            query+=' AND Is_delegated__c=:isDelegated';
        }
        return Database.query(query);
    }
    /************************************************************************************************************************
     * @Author:          CRM Team Innovation
     * @methodName:      reassignCases
     * @param:         casesToUpdate-List of Case records to update
     * @param:         newOwner-New Owner Id to assign
     * @param:         originalOwner-Original Owner Id(can be null)
     * @param:         isDelegated-Boolean flag for Is_delegated__c
     * @Description:     Helper method to reassign cases by setting owner and delegation fields and performing DML
     **************************************************************************************************************************/
    private static void reassignCases(List<Case> casesToUpdate,Id newOwner,Id originalOwner,Boolean isDelegated){
        for(Case c:casesToUpdate){
            c.OwnerId=newOwner;
            c.Orginal_Owner_Id__c=originalOwner;
            c.Is_delegated__c=isDelegated;
        }
        if(!casesToUpdate.isEmpty()){
            Database.update(casesToUpdate,false);
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
        for(Leave__c leave:newLeaves){
            Leave__c oldLeave=oldMap.get(leave.Id);
            if(leave.Status__c=='Active'&&oldLeave.Status__c!='Active'){
                activatedLeaves.add(leave);
            }
            if(leave.Status__c=='Inactive'&&oldLeave.Status__c!='Inactive'){
                inactivatedLeaves.add(leave);
            }
        }
       if(!activatedLeaves.isEmpty()){
        Set<Id> ownerIds=new Set<Id>();
        for(Leave__c leave:activatedLeaves){
            ownerIds.add(leave.OwnerId);
        }
        List<Case> openCases=getCases(ownerIds,null);
        Map<Id,List<Case>> ownerToCasesMap=new Map<Id,List<Case>>();
        for(Case c:openCases){
            if(!ownerToCasesMap.containsKey(c.OwnerId)){
                ownerToCasesMap.put(c.OwnerId,new List<Case>());
            }
            ownerToCasesMap.get(c.OwnerId).add(c);
        }
        List<Case> casesToUpdate=new List<Case>();
        List<Case> casesToAddToQueue=new List<Case>();
        Map<Id,List<Case>> delegatedToCasesMap=new Map<Id,List<Case>>();
        Map<Id,User> ownerToDelegatedUserMap=getUserMap(ownerIds);
        for(Leave__c leave:activatedLeaves){
            List<Case> userCases=ownerToCasesMap.get(leave.OwnerId);
            if(userCases==null||userCases.isEmpty()){
                continue;
            }
            User ownerUser=ownerToDelegatedUserMap.get(leave.OwnerId);
            Id delegatedId=(ownerUser!=null) ? ownerUser.DelegatedApproverId:null;
            if(delegatedId!=null){
                List<Case> casesToReassignForLeave=new List<Case>();
                for(Case c:userCases){
                    casesToReassignForLeave.add(c);
                }
                reassignCases(casesToReassignForLeave,delegatedId,leave.OwnerId,true);
                casesToUpdate.addAll(casesToReassignForLeave);
                if(!delegatedToCasesMap.containsKey(delegatedId)){
                    delegatedToCasesMap.put(delegatedId,new List<Case>());
                }
                delegatedToCasesMap.get(delegatedId).addAll(casesToReassignForLeave);
            }else{
                for(Case c:userCases){
                    casesToAddToQueue.add(c);
                }
            }
        }
        if(!casesToAddToQueue.isEmpty()){
            Id caseQueueId=[
                SELECT
                    Id
                FROM 
                    Group
                WHERE
                    Name='Case_Queue'
                LIMIT 1
            ].Id;

            for(Case c:casesToAddToQueue){
                c.OwnerId=caseQueueId;
            }
            Database.update(casesToAddToQueue,false);
        }
        List<Messaging.SingleEmailMessage> emails=new List<Messaging.SingleEmailMessage>();
        Set<Id> delegatedIds=delegatedToCasesMap.keySet();
        if(!delegatedIds.isEmpty()){
            Map<Id,User> userMap=getUserMap(delegatedIds);
            for(Id delegatedId:delegatedIds){
                User delegatedUser=userMap.get(delegatedId);
                if(delegatedUser!=null&&delegatedUser.Email!=null){
                    List<Case> reassignedCases=delegatedToCasesMap.get(delegatedId);
                    String subject='Reassigned Cases Summary';
                    String body='Dear '+delegatedUser.Name+',\n\n' +
                                'The following cases have been reassigned to you as the delegated user for an employee on leave:\n\n';
                    for(Case c:reassignedCases){
                        body+='Case Number: '+c.CaseNumber+'\n';
                        body+='Subject: '+c.Subject+'\n';
                        body+='Status: '+c.Status+'\n';
                        body+='Priority: '+c.Priority+'\n';
                        body+='Type: '+c.Type+'\n\n';
                    }
                    body+='\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';
                    sendEmail(delegatedUser.Email,subject,body);
                }
            }
        }
    }
        if(!inactivatedLeaves.isEmpty()){
            Set<Id> ownerIds=new Set<Id>();
            for(Leave__c leave:inactivatedLeaves){
                ownerIds.add(leave.OwnerId);
            }
            Map<Id,Id> userIdToDelegatedApproverIdMap=new Map<Id,Id>();
            Map<Id,User> userMap=getUserMap(ownerIds);
            for(User u:userMap.values()){
                userIdToDelegatedApproverIdMap.put(u.Id,u.DelegatedApproverId);
            }
            Set<Id> delegatedIds=new Set<Id>();
            for(Id delegatedId:userIdToDelegatedApproverIdMap.values()){
                if(delegatedId!=null){
                    delegatedIds.add(delegatedId);
                }
            }
            List<Case> delegatedCases=getCases(delegatedIds,true);
            Map<Id,List<Case>> delegatedToCasesMap=new Map<Id,List<Case>>();
            for(Case c:delegatedCases){
                if(!delegatedToCasesMap.containsKey(c.OwnerId)){
                    delegatedToCasesMap.put(c.OwnerId,new List<Case>());
                }
                delegatedToCasesMap.get(c.OwnerId).add(c);
            }
            List<Case> casesToReassign=new List<Case>();
            Map<Id,List<Case>> originalToCasesMap=new Map<Id,List<Case>>();
            for(Leave__c leave:inactivatedLeaves){
                Id delegatedApproverId=userIdToDelegatedApproverIdMap.get(leave.OwnerId);
                List<Case> userCases=delegatedToCasesMap.get(delegatedApproverId);
                if(userCases!=null){
                    List<Case> casesToReassignForLeave=new List<Case>();
                    for(Case c:userCases){
                        if(c.Orginal_Owner_Id__c==leave.OwnerId){
                            casesToReassignForLeave.add(c);
                        }
                    }
                    reassignCases(casesToReassignForLeave,leave.OwnerId,null,false);
                    casesToReassign.addAll(casesToReassignForLeave);
                    if(!originalToCasesMap.containsKey(leave.OwnerId)){
                        originalToCasesMap.put(leave.OwnerId,new List<Case>());
                    }
                    originalToCasesMap.get(leave.OwnerId).addAll(casesToReassignForLeave);
                }
            }
            List<Messaging.SingleEmailMessage> emails=new List<Messaging.SingleEmailMessage>();
            Set<Id> allUserIds=new Set<Id>();
            for(Leave__c leave:inactivatedLeaves){
                allUserIds.add(leave.OwnerId);
            }
            Map<Id,Id> originalOwnerToDelegatedApproverMap=new Map<Id,Id>();
            Map<Id,User> ownerUserMap=getUserMap(allUserIds);
            for(User u:ownerUserMap.values()){
                originalOwnerToDelegatedApproverMap.put(u.Id,u.DelegatedApproverId);
            }
            for(Leave__c leave:inactivatedLeaves){
                Id delegatedApproverId=originalOwnerToDelegatedApproverMap.get(leave.OwnerId);
                if(delegatedApproverId!=null){
                    allUserIds.add(delegatedApproverId);
                }
            }
            Map<Id,User> fullUserMap=getUserMap(allUserIds);
            for(Leave__c leave:inactivatedLeaves){
                User originalUser=fullUserMap.get(leave.OwnerId);
                Id delegatedApproverId=originalOwnerToDelegatedApproverMap.get(leave.OwnerId);
                User delegatedUser=delegatedApproverId!=null ? fullUserMap.get(delegatedApproverId):null;
                List<Case> reassignedCases=originalToCasesMap.get(leave.OwnerId);
                if(reassignedCases!=null&&!reassignedCases.isEmpty()){
                    if(originalUser!=null&&originalUser.Email!=null){
                        String subject='Cases Reassigned Back to You';
                        String body='Dear '+originalUser.Name+',\n\nYour leave has ended,and the following cases have been reassigned back to you:\n\n';
                        for(Case c:reassignedCases){
                            body+='Case Number: '+c.CaseNumber+'\n';
                            body+='Subject: '+c.Subject+'\n';
                            body+='Status: '+c.Status+'\n';
                            body+='Priority: '+c.Priority+'\n';
                            body+='Type: '+c.Type+'\n\n';
                        }
                        body+='\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';
                        sendEmail(originalUser.Email,subject,body);
                    }
                    if(delegatedUser!=null&&delegatedUser.Email!=null){
                        String subject='Cases Reassigned Back to Original Owner';
                        String body='Dear '+delegatedUser.Name+',\n\nThe leave period has ended,and the following cases have been reassigned back to the original owner:\n\n';
                        for(Case c:reassignedCases){
                            body+='Case Number: '+c.CaseNumber+'\n';
                            body+='Subject: '+c.Subject+'\n';
                            body+='Status: '+c.Status+'\n';
                            body+='Priority: '+c.Priority+'\n';
                            body+='Type: '+c.Type+'\n\n';
                        }
                        body+='\nBest regards,\nLeave Management System';
                        sendEmail(delegatedUser.Email,subject,body);
                    }
                }
            }
            
        }
    }
}
