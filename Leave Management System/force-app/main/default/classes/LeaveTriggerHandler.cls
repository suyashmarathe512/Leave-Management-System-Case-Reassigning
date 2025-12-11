/********************************************************************************************************************
*@Author:          CRM Team Innovation
*@ClassName:        LeaveTriggerHandler
*@Description:      Trigger handler class for Leave__c object to manage leave applications and case reassignments
 **********************************************************************************************************************/
public with sharing class LeaveTriggerHandler{
    /********************************************************************************************************************
    *@Author:          CRM Team Innovation
    *@methodName:      calculateBusinessDays
    *@param:         startDate-Start date of the leave
    *@param:         endDate-End date of the leave
    *@Description:    Helper method to calculate business days between two dates
     **********************************************************************************************************************/
   public static Integer calculateBusinessDays(Date startDate,Date endDate){
        BusinessHours defaultHours=[
            SELECT 
                Id 
            FROM 
                BusinessHours
            WHERE 
                IsDefault=true 
            LIMIT 1
        ];
        DateTime startDateTime=DateTime.newInstanceGMT(
            startDate.year(),startDate.month(),startDate.day(),0,0,0
        );
        DateTime endDateTime=DateTime.newInstanceGMT(
            endDate.year(),endDate.month(),endDate.day(),0,0,0
        );
        Long millisecondsDiff =
            BusinessHours.diff(defaultHours.Id,startDateTime,endDateTime);

        Decimal businessHours=millisecondsDiff / (1000.0*60.0*60.0);
        Decimal businessDays=businessHours / 24.0;
        return businessDays.intValue();
    }
    /********************************************************************************************************************
    *@Author:          CRM Team Innovation
    *@methodName:      checkForOverlappingDates
    *@param:         newLeave-Leave__c record being validated
    *@param:         existingLeaves-List of existing Leave__c records to compare against
    *@Description:     Helper method to check if a new leave record overlaps with existing ones
     **********************************************************************************************************************/
    private static Boolean checkForOverlappingDates(Leave__c newLeave,List<Leave__c> existingLeaves){
        if(newLeave.Start_Date__c==null||newLeave.End_Date__c==null){
            return false;
        }
        Date newStart=newLeave.Start_Date__c;
        Date newEnd=newLeave.End_Date__c;
        for(Leave__c existingLeave:existingLeaves){
            if(existingLeave.Id!=newLeave.Id){
                if(existingLeave.Status__c=='Active'||existingLeave.Status__c=='Approved'){
                    if((newStart <= existingLeave.End_Date__c) &&(newEnd >= existingLeave.Start_Date__c)){
                        return true; 
                    }
                }
            }
        }
        return false;
    }
    /****************************************************************************************************************************
*@Author:         CRM Team Innovation
*@methodName:     sendEmail
*@param:        toAddress - Recipient email address
*@param:        subject - Email subject
*@param:        body - Email body content
*@Description:    Helper method to send email notifications
    *****************************************************************************************************************************/
    private static void sendEmail(String toAddress,String subject,String body){
        if(String.isBlank(toAddress)||String.isBlank(subject)||String.isBlank(body)){
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
*@Author:        CRM Team Innovation
*@methodName:    handleBeforeInsertUpdate
*@param:        newLeaves-List of Leave__c records before insert/update
*@Description:    Validate leave applications and adjust leave types based on balances before insert/update
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
            if(leaveType=='Earned_Leave'){
                earnedBookedMap.put(ownerId,sumDays!=null?sumDays:0);
            } else if(leaveType=='Sick_Leave'){
                sickBookedMap.put(ownerId,sumDays!=null?sumDays:0);
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
            if(leave.OwnerId==null){
                continue;
            }
            Boolean isActiveLeave=(leave.Status__c!=null&&leave.Status__c=='Active');
            if(isActiveLeave){
                Boolean hasOtherActive=ownerHasActiveExistingLeave.get(leave.OwnerId);
                if(hasOtherActive==true){
                }
            }
            if(leave.Start_Date__c!=null&&leave.End_Date__c!=null){
                Integer numberOfDays=calculateBusinessDays(leave.Start_Date__c,leave.End_Date__c);
                if(leave.Leave_Type__c=='Earned_Leave'||leave.Leave_Type__c=='Sick_Leave'){
                    Leave_Balance__c balance=balanceMap.get(leave.OwnerId);
                    if(balance!=null){
                        Decimal bookedEarned=earnedBookedMap.get(leave.OwnerId);
                        Decimal bookedSick=sickBookedMap.get(leave.OwnerId);
                        Decimal earnedTotal=balance.Earned_Leave__c;
                        Decimal sickTotal=balance.Sick_Leave__c;
                        if(leave.Leave_Type__c=='Earned_Leave'){
                            Decimal availableBalance=earnedTotal - bookedEarned;
                            if(availableBalance < 0) availableBalance=0;
                            if(numberOfDays > availableBalance){
                                leave.addError('Please apply for Unpaid Leave becuase insufficient Earned Leave balance. Available: '+availableBalance+' day(s). Requested: '+numberOfDays+' day(s).');
                            }
                        } else if(leave.Leave_Type__c=='Sick_Leave'){
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
                if(oldMap==null ||(oldMap!=null &&(leave.Status__c=='Pending'||leave.Status__c=='Approved'))){
                    List<Leave__c> existingApprovedLeaves=ownerExistingLeavesMap.get(leave.OwnerId);
                    if(existingApprovedLeaves!=null&&!existingApprovedLeaves.isEmpty()){
                        if(checkForOverlappingDates(leave,existingApprovedLeaves)){
                            leave.addError('You already have leave in this time period('+
                                existingApprovedLeaves[0].Start_Date__c+' to '+existingApprovedLeaves[0].End_Date__c+'). '+
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
            }
        }
    }
    /********************************************************************************************************************
    *@Author:          CRM Team Innovation
    *@methodName:      submitNewLeavesForApproval
    *@param:         newLeaves-List of newly inserted Leave__c records
    *@Description:     Submit new leave records for approval if status is 'Pending'
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
    *@Author:          CRM Team Innovation
    *@methodName:      getUserMap
    *@param:         userIds-Set of User Ids to query
    *@Description:     Helper method to query User records and return a map
     **************************************************************************************************************************/
   private static Map<Id,User> getUserMap(Set<Id> ownerIds){
    return new Map<Id,User>([
        SELECT
            Id,DelegatedApproverId,Email,Name
        FROM
            User
        WHERE
            Id IN :ownerIds OR DelegatedApproverId IN :ownerIds
    ]);
}
/************************************************************************************************************************
*@Author:      CRM Team Innovation
*@methodName:  getCases
*@param:       ownerIds-Set of Owner Ids to query
*@param:       isDelegated-Boolean to filter by Is_delegated__c(null for no filter)
*@Description: Helper method to query Case records and return a list
 **************************************************************************************************************************/
private static List<Case> getCases(Set<Id> ownerIds,Boolean isDelegated){
    return [
        SELECT Id,CaseNumber,OwnerId,Orginal_Owner_Id__c,Subject,Status,Priority,Type,Is_delegated__c
        FROM Case
        WHERE OwnerId IN :ownerIds AND IsClosed=false
    ];
}
/************************************************************************************************************************
*@Author:      CRM Team Innovation
*@methodName:  reassignCases
*@param:       casesToUpdate-List of Case records to update
*@param:       newOwner-New Owner Id to assign
*@param:       originalOwner-Original Owner Id(can be null)
*@param:       isDelegated-Boolean flag for Is_delegated__c
*@Description: Helper method to reassign cases by setting owner and delegation fields.
*              No DML here. Caller performs bulk DML once.
 **************************************************************************************************************************/
private static void reassignCases(List<Case> casesToUpdate,Id newOwner,Id originalOwner,Boolean isDelegated){
    if(casesToUpdate==null||casesToUpdate.isEmpty()){
        return;
    }
    for(Case c:casesToUpdate){
        c.OwnerId           =newOwner;
        c.Orginal_Owner_Id__c=originalOwner;
        c.Is_delegated__c   =isDelegated;
    }
}
/************************************************************************************************************************
*@Author:      CRM Team Innovation
*@methodName:  buildCaseSummaryLines
*@Description: Common helper to build "case details" text block for emails
 **************************************************************************************************************************/
private static String buildCaseSummaryLines(List<Case> casesList){
    String body='';
    if(casesList==null){
        return body;
    }
    for(Case c:casesList){
        body+= 'Case Number: '+c.CaseNumber+'\n';
        body+= 'Subject: '   +c.Subject   +'\n';
        body+= 'Status: '    +c.Status    +'\n';
        body+= 'Priority: '  +c.Priority  +'\n';
        body+= 'Type: '      +c.Type      +'\n\n';
    }
    return body;
}
/************************************************************************************************************************
*@Author:      CRM Team Innovation
*@methodName:  handleAfterUpdate
*@param:       newLeaves-List of Leave__c records after update
*@param:       oldMap-Map of Leave__c records before update
*@Description: Handle case reassignment when leave status changes to Active or Inactive
*              - 1 User query total
*              - 1 Case query total(via getCases)
*              - All logic driven from maps
 **************************************************************************************************************************/
    public static void handleAfterUpdate(List<Leave__c> newLeaves,Map<Id,Leave__c> oldMap){
        if(newLeaves==null||newLeaves.isEmpty()||oldMap==null||oldMap.isEmpty()){
            return;
        }
        // 1. Identify activated and inactivated leaves(status changes)
        List<Leave__c> activatedLeaves=new List<Leave__c>();
        List<Leave__c> inactivatedLeaves=new List<Leave__c>();
        for(Leave__c newLeave:newLeaves){
            Leave__c oldLeave=oldMap.get(newLeave.Id);
            if(oldLeave==null){
                continue;
            }
            if(newLeave.Status__c=='Active'&&oldLeave.Status__c!='Active'){
                activatedLeaves.add(newLeave);
            } else if(newLeave.Status__c=='Inactive'&&oldLeave.Status__c!='Inactive'){
                inactivatedLeaves.add(newLeave);
            }
        }
    if(activatedLeaves.isEmpty()&&inactivatedLeaves.isEmpty()){
        return;
    }
    // 2. Collect all involved owner Ids(both Active and Inactive)
    Set<Id> activeOwnerIds=new Set<Id>();
    Set<Id> inactiveOwnerIds=new Set<Id>();
    for(Leave__c leave:activatedLeaves){
        if(leave.OwnerId!=null){
            activeOwnerIds.add(leave.OwnerId);
        }
    }
    for(Leave__c leave:inactivatedLeaves){
        if(leave.OwnerId!=null){
            inactiveOwnerIds.add(leave.OwnerId);
        }
    }
    Set<Id> allOwnerIds=new Set<Id>();
    allOwnerIds.addAll(activeOwnerIds);
    allOwnerIds.addAll(inactiveOwnerIds);
    if(allOwnerIds.isEmpty()){
        return;
    }
    // 3. User queries – single query for all owners and their delegates to handle circular delegations
    Map<Id,User> allUserMap=getUserMap(allOwnerIds);
    // 3.2 Build owner -> delegate map from allUserMap
    Map<Id,Id> ownerToDelegateMap=new Map<Id,Id>();
    Set<Id> delegateIds=new Set<Id>();
    for (User u : allUserMap.values()){
        if (allOwnerIds.contains(u.Id)){
            ownerToDelegateMap.put(u.Id,u.DelegatedApproverId);
            if (u.DelegatedApproverId!=null){
                delegateIds.add(u.DelegatedApproverId);
            }
        }
    }
    // 4. SINGLE Case query – via getCases
    Set<Id> caseOwnerIds=new Set<Id>();
    caseOwnerIds.addAll(allOwnerIds);
    caseOwnerIds.addAll(delegateIds);
    List<Case> allOpenCases=getCases(caseOwnerIds,null);
    // Group all cases by current owner
    Map<Id,List<Case>> ownerToCasesMap=new Map<Id,List<Case>>();
    for(Case c:allOpenCases){
        List<Case> bucket=ownerToCasesMap.get(c.OwnerId);
        if(bucket==null){
            bucket=new List<Case>();
            ownerToCasesMap.put(c.OwnerId,bucket);
        }
        bucket.add(c);
    }
    // 5. Structures for updates and emails
    List<Case> allCasesToUpdate=new List<Case>();
    // For Active: delegateId -> list of cases newly assigned
    Map<Id,List<Case>> delegateToCasesActivatedMap=new Map<Id,List<Case>>();
    // For Inactive: originalOwnerId -> list of cases returned
    Map<Id,List<Case>> originalOwnerToCasesReturnedMap=new Map<Id,List<Case>>();
    // For Active(no delegate): cases that must go to Case_Queue
    List<Case> casesToMoveToQueue=new List<Case>();
    // 6. Scenario Owner goes Active(delegate or queue)
    if(!activeOwnerIds.isEmpty()){
        for(Id ownerId:activeOwnerIds){
            List<Case> userCases=ownerToCasesMap.get(ownerId);
            if(userCases==null||userCases.isEmpty()){
                continue;
            }
            Id delegateId=ownerToDelegateMap.get(ownerId);
            if(delegateId!=null){
                // Reassign all of this owner's cases to delegate in memory
                List<Case> casesForThisOwner=new List<Case>(userCases);
                reassignCases(casesForThisOwner,delegateId,ownerId,true);
                allCasesToUpdate.addAll(casesForThisOwner);
                List<Case> delegateBucket=delegateToCasesActivatedMap.get(delegateId);
                if(delegateBucket==null){
                    delegateBucket=new List<Case>();
                    delegateToCasesActivatedMap.put(delegateId,delegateBucket);
                }
                delegateBucket.addAll(casesForThisOwner);
            } else{
                // No delegate: these will go to queue
                casesToMoveToQueue.addAll(userCases);
            }
        }
    }
    // 7. Scenario – Owner goes Inactive(return delegated cases)
    if(!inactiveOwnerIds.isEmpty()){
        for(Id originalOwnerId:inactiveOwnerIds){
            Id delegateId=ownerToDelegateMap.get(originalOwnerId);
            if(delegateId==null){
                continue;
            }
            List<Case> delegateCases=ownerToCasesMap.get(delegateId);
            if(delegateCases==null||delegateCases.isEmpty()){
                continue;
            }
            List<Case> casesForThisOwner=new List<Case>();
            for(Case c:delegateCases){
                // Only pick cases that were delegated from this owner
                if(c.Is_delegated__c==true&&c.Orginal_Owner_Id__c==originalOwnerId){
                    casesForThisOwner.add(c);
                }
            }
            if(casesForThisOwner.isEmpty()){
                continue;
            }
            // Reassign back to original owner in-memory
            reassignCases(casesForThisOwner,originalOwnerId,null,false);
            allCasesToUpdate.addAll(casesForThisOwner);
            List<Case> originalBucket=originalOwnerToCasesReturnedMap.get(originalOwnerId);
            if(originalBucket==null){
                originalBucket=new List<Case>();
                originalOwnerToCasesReturnedMap.put(originalOwnerId,originalBucket);
            }
            originalBucket.addAll(casesForThisOwner);
        }
    }
    // 8. Cases with no delegate → Case_Queue
    if(!casesToMoveToQueue.isEmpty()){
        List<Group> queueList=[
            SELECT 
                Id
            FROM 
                Group
            WHERE 
                Name='Case_Queue'
            LIMIT 1
        ];
        if (!queueList.isEmpty()){
            Id caseQueueId=queueList[0].Id;
            for (Case c : casesToMoveToQueue){
                c.OwnerId=caseQueueId;
                c.Is_delegated__c=false;
                c.Orginal_Owner_Id__c=null;
            }
            allCasesToUpdate.addAll(casesToMoveToQueue);
        } else{}
    }
    // Single bulk DML for all case changes
    if(!allCasesToUpdate.isEmpty()){
        Database.update(allCasesToUpdate,false);
    }
    // 10. Emails – now both owners and delegates are in allUserMap
    //  Emails to delegates for newly assigned cases(Active)
    for(Id delegateId:delegateToCasesActivatedMap.keySet()){
        User delegatedUser=allUserMap.get(delegateId);
        if(delegatedUser==null||String.isBlank(delegatedUser.Email)){
            continue;
        }
        List<Case> casesForDelegate=delegateToCasesActivatedMap.get(delegateId);
        if(casesForDelegate==null||casesForDelegate.isEmpty()){
            continue;
        }
        String subject='Reassigned Cases Summary';
        String body=
            'Dear '+delegatedUser.Name+',\n\n'+
            'The following cases have been reassigned to you as the delegated user for an employee on leave:\n\n'+
            buildCaseSummaryLines(casesForDelegate)+
            '\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';

        sendEmail(delegatedUser.Email,subject,body);
    }
    // Emails to original owners(and delegates) for returned cases(Inactive)
    for(Id originalOwnerId:originalOwnerToCasesReturnedMap.keySet()){
        List<Case> returnedCases=originalOwnerToCasesReturnedMap.get(originalOwnerId);
        if(returnedCases==null||returnedCases.isEmpty()){
            continue;
        }
        User originalUser=allUserMap.get(originalOwnerId);
        Id delegateId=ownerToDelegateMap.get(originalOwnerId);
        User delegatedUser=(delegateId!=null)?allUserMap.get(delegateId):null;
        String caseLines=buildCaseSummaryLines(returnedCases);
        if(originalUser!=null&&!String.isBlank(originalUser.Email)){
            String subjectOwner='Cases Reassigned Back to You';
            String bodyOwner=
                'Dear '+originalUser.Name+',\n\n'+
                'Your leave has ended,and the following cases have been reassigned back to you:\n\n'+
                caseLines+
                '\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';

            sendEmail(originalUser.Email,subjectOwner,bodyOwner);
        }
        // Email to delegate
        if(delegatedUser!=null&&!String.isBlank(delegatedUser.Email)){
            String subjectDelegate='Cases Reassigned Back to Original Owner';
            String bodyDelegate=
                'Dear '+delegatedUser.Name+',\n\n'+
                'The leave period has ended,and the following cases have been reassigned back to the original owner:\n\n'+
                caseLines+
                '\nBest regards,\nLeave Management System';
            sendEmail(delegatedUser.Email,subjectDelegate,bodyDelegate);
        }
    }
}
}
