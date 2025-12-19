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

    /********************************************************************************************************************
    *@Author:          CRM Team Innovation
    *@methodName:      handleAfterDelete
    *@param:         oldLeaves-List of Leave__c records after delete
    *@Description:     Handle case reassignment when active leave is deleted
     **********************************************************************************************************************/
    public static void handleAfterDelete(List<Leave__c> oldLeaves) {
        Database.executeBatch(new DailyLeaveReassignmentBatch(), 200);
    }
/*******************************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @methodName:      handleAfterUpdate
 * @param:           newLeaves - List of Leave__c (Trigger.new)
 * @param:           oldMap    - Map<Id,Leave__c> (Trigger.oldMap)
 * @Description:     if the leave is of today, then Immediately calls the batch.
 *********************************************************************************************************************/
    public static void handleAfterUpdate(List<Leave__c> newLeaves){
        for(Leave__c leave:newLeaves){
            if(leave.Status__c=='Approved'&&leave.Start_Date__c==Date.today()){
                Database.executeBatch(new DailyLeaveReassignmentBatch(), 200);
            }
        }
    }
}