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
        Long millisecondsDiff=BusinessHours.diff(defaultHours.Id,startDateTime,endDateTime);
        Decimal totalHours=millisecondsDiff/(1000.0*60.0*60.0);
        Decimal businessDays=totalHours/24.0;
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
            if(existingLeave.Id != newLeave.Id){
                // Check overlap for Approved leaves.
                if(existingLeave.Status__c=='Approved'){
                    if((newStart <= existingLeave.End_Date__c) &&(newEnd >= existingLeave.Start_Date__c)){
                        return true; 
                    }
                }
            }
        }
        return false;
    }
/********************************************************************************************************************
    *@Author:          CRM Team Innovation
    *@methodName:      isEffectivelyActive
    *@Description:     Helper method to determine if a leave is effectively "Active" based on Status and Dates.
    *                  Logic: Status is Approved AND Today is between Start and End Date.
     **********************************************************************************************************************/
    private static Boolean isEffectivelyActive(Leave__c leave){
        if(leave==null||leave.Status__c != 'Approved'||leave.Start_Date__c==null||leave.End_Date__c==null){
            return false;
        }
        Date today=Date.today();
        return(leave.Start_Date__c <= today&&leave.End_Date__c >= today);
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
                OwnerId,Leave_Type__c,SUM(Days_Taken__c) sumDays
            FROM 
                Leave__c
            WHERE 
                OwnerId IN :ownerIds
            AND 
                Leave_Type__c IN('Earned_Leave','Sick_Leave')
            AND 
                Status__c NOT IN('Rejected','Pending')
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
        Date today=Date.today();
        Map<Id,Boolean> ownerHasActiveExistingLeave=new Map<Id,Boolean>();
        List<AggregateResult> activeLeaves=[
            SELECT 
                OwnerId,COUNT(Id) activeCount
            FROM 
                Leave__c
            WHERE 
                OwnerId IN :ownerIds
            AND 
                Id NOT IN :contextIds
            AND 
                Status__c='Approved'
            AND 
                Start_Date__c <= :today
            AND 
                End_Date__c >= :today
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
                Status__c IN('Approved','Pending')
        ];
        for(Leave__c leave:existingLeavesList){
            if(!ownerExistingLeavesMap.containsKey(leave.OwnerId)){
                ownerExistingLeavesMap.put(leave.OwnerId,new List<Leave__c>());
            }
            ownerExistingLeavesMap.get(leave.OwnerId).add(leave);
        }
        for(Leave__c leave:newLeaves){
            if(leave.OwnerId==null) continue;
            // Check Multiple Active Leaves
            Boolean isNewActive=isEffectivelyActive(leave);
            if(isNewActive){
                if(ownerHasActiveExistingLeave.get(leave.OwnerId)){
                    leave.addError('Only one active leave record is allowed per employee.');
                }
            }
            if(leave.Start_Date__c != null&&leave.End_Date__c != null){
                Integer numberOfDays=calculateBusinessDays(leave.Start_Date__c,leave.End_Date__c);
                // Balance Check
                if(leave.Leave_Type__c=='Earned_Leave'||leave.Leave_Type__c=='Sick_Leave'){
                    Leave_Balance__c balance=balanceMap.get(leave.OwnerId);
                    if(balance != null){
                        Decimal bookedEarned=earnedBookedMap.get(leave.OwnerId);
                        Decimal bookedSick=sickBookedMap.get(leave.OwnerId);
                        Decimal earnedTotal=balance.Earned_Leave__c;
                        Decimal sickTotal=balance.Sick_Leave__c;
                        if(leave.Leave_Type__c=='Earned_Leave'){
                            Decimal availableBalance=earnedTotal - bookedEarned;
                            if(availableBalance < 0) availableBalance=0;
                            if(numberOfDays > availableBalance){
                                leave.addError('Please apply for Unpaid Leave because insufficient Earned Leave balance. Available: ' + availableBalance + ' day(s). Requested: ' + numberOfDays + ' day(s).');
                            }
                        } else if(leave.Leave_Type__c=='Sick_Leave'){
                            Decimal availableBalance=sickTotal - bookedSick;
                            if(availableBalance < 0) availableBalance=0;
                            if(numberOfDays > availableBalance){
                                leave.addError('Please apply for Unpaid Leave because insufficient Sick Leave balance. Available: ' + availableBalance + ' day(s). Requested: ' + numberOfDays + ' day(s).');
                            }
                        }
                    } else{
                        leave.addError('Leave balance record not found for the employee.');
                        continue;
                    }
                }
                if(oldMap==null||(oldMap != null &&(leave.Status__c=='Pending'||leave.Status__c=='Approved'))){
                    List<Leave__c> existingApprovedLeaves=ownerExistingLeavesMap.get(leave.OwnerId);
                    if(existingApprovedLeaves != null&&!existingApprovedLeaves.isEmpty()){
                        if(checkForOverlappingDates(leave,existingApprovedLeaves)){
                            leave.addError('You already have leave in this time period. You cannot apply for more leave in the same time period.');
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
    String query='SELECT Id,CaseNumber,OwnerId,Orginal_Owner_Id__c,Subject,Status,Priority,Type,Is_delegated__c,Previous_Owner_Id__c FROM Case WHERE OwnerId IN :ownerIds AND IsClosed=false';
    if(isDelegated != null){
        query += ' AND Is_delegated__c=:isDelegated';
     }
    return Database.query(query);
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
        c.OwnerId=newOwner;
        c.Previous_Owner_Id__c=originalOwner;
        if(c.Orginal_Owner_Id__c==null&&originalOwner != null){
            c.Orginal_Owner_Id__c=originalOwner;
        }
        c.Is_delegated__c=isDelegated;
    }
}
/************************************************************************************************************************
*@Author:      CRM Team Innovation
*@methodName:  buildCaseSummaryLines
*@Description: Common helper to build "case details" text block for emails
 **************************************************************************************************************************/
private static String buildCaseSummaryLines(List<Case> casesList){
    String body='';
    String baseUrl=URL.getOrgDomainUrl().toExternalForm();
    if(casesList==null){
        return body;
    }
    for(Case c:casesList){
        body+= 'Case Number: '+c.CaseNumber+'\n';
        body+= 'Subject: '   +c.Subject   +'\n';
        body+= 'Status: '    +c.Status    +'\n';
        body+= 'Priority: '  +c.Priority  +'\n';
        body+= 'Type: '      +c.Type      +'\n';
        body+= 'View Case: ' + baseUrl + '/' + c.Id + '\n\n';
    }
    return body;
}
    /************************************************************************************************************************
*@Author:      CRM Team Innovation
*@methodName:  getUsersOnLeave
*@param:       userIds-Set of User Ids to check for active leave
*@Description: Helper method to determine which users from a given set are currently on an active leave.
*              Returns a map of UserId -> IsOnLeave(Boolean).
 **************************************************************************************************************************/
    private static Map<Id,Boolean> getUsersOnLeave(Set<Id> userIds){
        Map<Id,Boolean> userOnLeaveMap=new Map<Id,Boolean>();
        for(Id userId:userIds){
            userOnLeaveMap.put(userId,false);
        }
        Date today=Date.today();
        List<Leave__c> activeLeaves=[
            SELECT 
                OwnerId
            FROM 
                Leave__c
            WHERE 
                OwnerId IN :userIds
            AND 
                Status__c='Approved'
            AND 
                Start_Date__c <= :today
            AND 
                End_Date__c >= :today
        ];
        for(Leave__c leave:activeLeaves){
            userOnLeaveMap.put(leave.OwnerId,true);
        }
        return userOnLeaveMap;
    }

    /********************************************************************************************************************
    *@Author:          CRM Team Innovation
    *@methodName:      handleAfterDelete
    *@param:         oldLeaves-List of Leave__c records after delete
    *@Description:     Handle case reassignment when active leave is deleted
     **********************************************************************************************************************/
    public static void handleAfterDelete(List<Leave__c> oldLeaves){
        if(oldLeaves==null||oldLeaves.isEmpty()) return;
        List<Leave__c> dummyNewLeaves=new List<Leave__c>();
        Map<Id,Leave__c> oldMap=new Map<Id,Leave__c>();
        for(Leave__c lv:oldLeaves){
            // If the deleted leave was effectively active,we simulate a transition to inactive
            if(isEffectivelyActive(lv)){
                Leave__c dummyNew=lv.clone(true);
                dummyNew.Status__c='Rejected'; // Change status to something not active
                dummyNewLeaves.add(dummyNew);
                oldMap.put(lv.Id,lv);
            }
        }
        if(!dummyNewLeaves.isEmpty()){
            handleAfterUpdate(dummyNewLeaves,oldMap);
        }
    }
/************************************************************************************************************************
*@Author:      CRM Team Innovation
*@methodName:  handleAfterUpdate
*@param:       newLeaves-List of Leave__c records after update
*@param:       oldMap-Map of Leave__c records before update
*@Description: Handle case reassignment when leave status changes to Active or Inactive
 **************************************************************************************************************************/
    public static void handleAfterUpdate(List<Leave__c> newLeaves,Map<Id,Leave__c> oldMap){
        if(newLeaves==null||newLeaves.isEmpty()||oldMap==null||oldMap.isEmpty()){
            return;
        }
        // 1. Identify activated and inactivated leaves(Effective Status changes)
        List<Leave__c> activatedLeaves=new List<Leave__c>();
        List<Leave__c> inactivatedLeaves=new List<Leave__c>();
        for(Leave__c newLeave:newLeaves){
            Leave__c oldLeave=oldMap.get(newLeave.Id);
            if(oldLeave==null) continue;
            Boolean isNewActive=isEffectivelyActive(newLeave);
            Boolean isOldActive=isEffectivelyActive(oldLeave);
            if(isNewActive&&!isOldActive){
                activatedLeaves.add(newLeave);
            } else if(!isNewActive&&isOldActive){
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
    for(User u:allUserMap.values()){
        if(allOwnerIds.contains(u.Id)){
            ownerToDelegateMap.put(u.Id,u.DelegatedApproverId);
            if(u.DelegatedApproverId!=null){
                delegateIds.add(u.DelegatedApproverId);
            }
        }
    }
    // 4.  Case query – via getCases
    Set<Id> caseOwnerIds=new Set<Id>();
    caseOwnerIds.addAll(allOwnerIds);
    caseOwnerIds.addAll(delegateIds);
    List<Case> allOpenCases=getCases(caseOwnerIds,null);
    // 4.1 Get all cases that are currently delegated(Is_delegated__c=true)
    List<Case> delegatedCases=getCases(caseOwnerIds,true);
    // Group all cases by current owner
    Map<Id,List<Case>> ownerToCasesMap=new Map<Id,List<Case>>();
    Set<Id> processedCaseIds=new Set<Id>();
    for(Case c:allOpenCases){
        // Skip if we've already processed this case ID to prevent duplicates
        if(processedCaseIds.contains(c.Id)){
            continue;
        }
        processedCaseIds.add(c.Id);
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
    // For cases that need to be reassigned to queue because delegate went on leave
    List<Case> casesToReassignToQueue=new List<Case>();
    // Set to track which cases have already been added to allCasesToUpdate to prevent duplicates
    Set<Id> addedCaseIds=new Set<Id>();
    // 6. Determine who is currently on leave(both owners and their delegates)
    Set<Id> leaveCheckIds=new Set<Id>();
    leaveCheckIds.addAll(allOwnerIds);
    leaveCheckIds.addAll(delegateIds);
    Map<Id,Boolean> isOnLeave=getUsersOnLeave(leaveCheckIds);
    // 7. Scenario: Check for cases that need to be reassigned to queue because their delegate is now on leave
    Id caseQueueId=[SELECT 
                        Id 
                    FROM 
                        Group 
                    WHERE 
                        Name='Case Queue'
                    LIMIT 1].Id;
    if(caseQueueId != null&&!delegateIds.isEmpty()){
        for(Case c:delegatedCases){
            c.Previous_Owner_Id__c=c.OwnerId;
            if(isOnLeave.get(c.OwnerId)==true){
                c.OwnerId=caseQueueId;
                c.Is_delegated__c=true;
                // Only process each case once to avoid duplicates
                if(!addedCaseIds.contains(c.Id)){
                    casesToReassignToQueue.add(c);
                    allCasesToUpdate.add(c);
                    addedCaseIds.add(c.Id);
                }
            }
        }
    }
    
    // 8. Scenario Owner goes Active(delegate or queue)
    if(!activeOwnerIds.isEmpty()){
        for(Id ownerId:activeOwnerIds){
            List<Case> userCases=ownerToCasesMap.get(ownerId);
            if(userCases==null||userCases.isEmpty()){
                continue;
            }
            Id delegateId=ownerToDelegateMap.get(ownerId);
            if(delegateId!=null&&!isOnLeave.get(delegateId)){
                // Reassign all of this owner's cases to delegate in memory
                List<Case> casesForThisOwner=new List<Case>(userCases);
                reassignCases(casesForThisOwner,delegateId,ownerId,true);
                // Only add to allCasesToUpdate if not already added
                for(Case c:casesForThisOwner){
                    if(!addedCaseIds.contains(c.Id)){
                        allCasesToUpdate.add(c);
                        addedCaseIds.add(c.Id);
                    }
                }
                List<Case> delegateBucket=delegateToCasesActivatedMap.get(delegateId);
                if(delegateBucket==null){
                    delegateBucket=new List<Case>();
                    delegateToCasesActivatedMap.put(delegateId,delegateBucket);
                }
                delegateBucket.addAll(casesForThisOwner);
            } else{
                casesToMoveToQueue.addAll(userCases);
            }
        }
    }
    // 9. Scenario – Owner goes Inactive(return delegated cases)
    // Priority: Try to return to Orginal_Owner_Id__c first. If not available(null or user still on leave),
    if(!inactiveOwnerIds.isEmpty()){
        // Cases delegated from any of the inactive owners
        List<Case> casesToReturn=[
            SELECT 
                Id,OwnerId,Orginal_Owner_Id__c,Previous_Owner_Id__c,Is_delegated__c,CaseNumber,Subject,Status,Priority,Type
            FROM 
                Case
            WHERE 
                (Orginal_Owner_Id__c IN :inactiveOwnerIds OR Previous_Owner_Id__c IN :inactiveOwnerIds)
            AND 
                Is_delegated__c=true 
            AND 
                IsClosed=false
        ];
        if(!casesToReturn.isEmpty()){
            for(Case c:casesToReturn){
                Boolean handled=false;
                Id originalOwnerId=c.Orginal_Owner_Id__c;
                // Check if the Id of owner of that leave is on Orginal_Owner_Id_c
                if(originalOwnerId != null&&inactiveOwnerIds.contains(originalOwnerId)){
                    if(isOnLeave.containsKey(originalOwnerId) ? !isOnLeave.get(originalOwnerId):true){
                        c.OwnerId=originalOwnerId;
                        c.Is_delegated__c=false;
                        handled=true;
                    }
                }
                // if not ,then check for the Previous_Owner_Id__c field
                if(!handled&&c.Previous_Owner_Id__c != null&&inactiveOwnerIds.contains(c.Previous_Owner_Id__c)){
                    if(isOnLeave.containsKey(c.Previous_Owner_Id__c) ? !isOnLeave.get(c.Previous_Owner_Id__c):true){
                        c.OwnerId=c.Previous_Owner_Id__c;
                        c.Is_delegated__c=true;
                        handled=true;
                    }
                }
                if(handled){
                    if(!addedCaseIds.contains(c.Id)){
                        allCasesToUpdate.add(c);
                        addedCaseIds.add(c.Id);
                    }
                    // Email buckets: if returned to original owner(not delegated)
                    if(!c.Is_delegated__c&&originalOwnerId != null){
                        List<Case> originalBucket=originalOwnerToCasesReturnedMap.get(originalOwnerId);
                        if(originalBucket==null){
                            originalBucket=new List<Case>();
                            originalOwnerToCasesReturnedMap.put(originalOwnerId,originalBucket);
                        }
                        originalBucket.add(c);
                    }
                }
            }
        }
    }
    // 10. Cases with no delegate or delegate on leave → Case_Queue
    if(caseQueueId != null&&!casesToMoveToQueue.isEmpty()){
        for(Case c:casesToMoveToQueue){
            Id originalOwnerId=c.OwnerId;
            c.OwnerId=caseQueueId;
            c.Is_delegated__c=true;
            if(c.Orginal_Owner_Id__c==null){
                c.Orginal_Owner_Id__c=originalOwnerId;
            }
            if(!addedCaseIds.contains(c.Id)){
                allCasesToUpdate.add(c);
                addedCaseIds.add(c.Id);
            }
        }
    }
    // Single bulk DML for all case changes
    if(!allCasesToUpdate.isEmpty()){
        Database.update(allCasesToUpdate,false);
    }
    // 12. Emails – now both owners and delegates are in allUserMap
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
