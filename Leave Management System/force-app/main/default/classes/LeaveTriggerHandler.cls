public with sharing class LeaveTriggerHandler {
    public static void handleBeforeInsertUpdate(List<Leave__c> newLeaves) {
        Set<Id> ownerIds = new Set<Id>();
        for(Leave__c leave : newLeaves) {
            if(leave.OwnerId != null) {
                ownerIds.add(leave.OwnerId);
            }
        }
        if(ownerIds.isEmpty()) {
            return;
        }
        Map<Id, Leave_Balance__c> balanceMap = new Map<Id, Leave_Balance__c>();
        List<Leave_Balance__c> balances = [
            SELECT 
                Id, SetupOwnerId, Earned_Leave__c, Sick_Leave__c 
            FROM 
                Leave_Balance__c 
            WHERE 
                SetupOwnerId IN :ownerIds 
        ];
        
        for(Leave_Balance__c balance : balances) {
            balanceMap.put(balance.SetupOwnerId, balance);
        }
        Map<Id, Decimal> earnedBookedMap = new Map<Id, Decimal>();
        Map<Id, Decimal> sickBookedMap = new Map<Id, Decimal>();
        List<AggregateResult> bookedLeaves = [
            SELECT 
                OwnerId, 
                SUM(Booked_Earned_Leaves__c) earnedSum, 
                SUM(Booked_Sick_Leaves__c) sickSum
            FROM 
                Leave__c 
            WHERE 
                OwnerId IN :ownerIds
            GROUP BY 
                OwnerId
        ];
        for(AggregateResult ar : bookedLeaves) {
            Id ownerId = (Id)ar.get('OwnerId');
            Decimal earnedSum = (Decimal)ar.get('earnedSum');
            Decimal sickSum = (Decimal)ar.get('sickSum');
            earnedBookedMap.put(ownerId, earnedSum != null ? earnedSum : 0);
            sickBookedMap.put(ownerId, sickSum != null ? sickSum : 0);
        }
        // Ensure every ownerId has a default of 0 to avoid NullPointer on map.get
        for (Id oid : ownerIds) {
            if (!earnedBookedMap.containsKey(oid)) {
                earnedBookedMap.put(oid, 0);
            }
            if (!sickBookedMap.containsKey(oid)) {
                sickBookedMap.put(oid, 0);
            }
        }
        for(Leave__c leave : newLeaves) {
            if(leave.OwnerId != null && leave.Start_Date__c != null && leave.End_Date__c != null) {
                Integer numberOfDays = leave.End_Date__c.daysBetween(leave.Start_Date__c) + 1;
                if(leave.Leave_Type__c == 'Earned_Leave' || leave.Leave_Type__c == 'Sick_Leave') {
                    Leave_Balance__c balance = balanceMap.get(leave.OwnerId);
                    Boolean isBalanceSufficient = true;
                    if(balance != null) {  
                        Decimal availableBalance = 0;
                        if(leave.Leave_Type__c == 'Earned_Leave') {
                            availableBalance = balance.Earned_Leave__c - (earnedBookedMap.containsKey(leave.OwnerId) ? earnedBookedMap.get(leave.OwnerId) : 0);
                            if(numberOfDays > availableBalance) {
                                isBalanceSufficient = false;
                            }
                        } else if(leave.Leave_Type__c == 'Sick_Leave') {
                            availableBalance = balance.Sick_Leave__c - (sickBookedMap.containsKey(leave.OwnerId) ? sickBookedMap.get(leave.OwnerId) : 0);
                            if(numberOfDays > availableBalance) {
                                isBalanceSufficient = false;
                            }
                        }
                    }else {
                        isBalanceSufficient = false;
                    }
                    if(!isBalanceSufficient) {
                        leave.Leave_Type__c = 'Unpaid_Leave';
                    }
                }
            }
        }
        List<Leave__c> existingLeaves = [
            SELECT 
                Id, OwnerId, Status__c 
            FROM 
                Leave__c 
            WHERE 
                OwnerId IN :ownerIds 
        ];
        Map<Id, List<Leave__c>> ownerToLeavesMap = new Map<Id, List<Leave__c>>();
        for(Leave__c existingLeave : existingLeaves) {
            if(!ownerToLeavesMap.containsKey(existingLeave.OwnerId)) {
                ownerToLeavesMap.put(existingLeave.OwnerId, new List<Leave__c>());
            }
            ownerToLeavesMap.get(existingLeave.OwnerId).add(existingLeave);
        }
        for(Leave__c leave : newLeaves) {
            if(leave.OwnerId != null) {
                List<Leave__c> ownerLeaves = ownerToLeavesMap.get(leave.OwnerId);
                Boolean isActiveLeave = (leave.Status__c != null && leave.Status__c == 'Active');
                if(Trigger.isInsert) {
                        if(isActiveLeave) {
                        if(ownerLeaves != null) {
                            for(Leave__c existingLeave : ownerLeaves) {
                                if(existingLeave.Status__c != null && existingLeave.Status__c == 'Active') {
                                    leave.addError('Only one active leave record is allowed per employee.');
                                    break;
                                }
                            }
                        }
                    }
                        }
                if(Trigger.isUpdate) {
                        if(isActiveLeave) {
                        if(ownerLeaves != null) {
                            Integer activeCount = 0;
                            for(Leave__c existingLeave : ownerLeaves) {
                                if(existingLeave.Status__c != null && existingLeave.Status__c == 'Active') {
                                    if(existingLeave.Id != leave.Id) {
                                        activeCount++;
                                    }
                                }
                            }
                            if(activeCount > 0) {
                                leave.addError('Only one active leave record is allowed per employee.');
                            }
                        }
                    }
                }
            }
        }
        populateDelegatedApproverIds(newLeaves);
    }
    private static void populateDelegatedApproverIds(List<Leave__c> leaves) {
        Set<Id> ownerIds = new Set<Id>();
        for(Leave__c leave : leaves) {
            if(leave.OwnerId != null) {
                ownerIds.add(leave.OwnerId);
            }
        }
        if(ownerIds.isEmpty()) {
            return;
        }
        List<User> users = [
            SELECT Id, ManagerId 
            FROM User 
            WHERE Id IN :ownerIds
            WITH USER_MODE
        ];
        Map<Id, Id> userIdToManagerIdMap = new Map<Id, Id>();
        for(User user : users) {
            userIdToManagerIdMap.put(user.Id, user.ManagerId);
        }
        for(Leave__c leave : leaves) {
            if(leave.OwnerId != null && leave.DelegatedApproverId__c == null) {
                if (userIdToManagerIdMap.containsKey(leave.OwnerId) && userIdToManagerIdMap.get(leave.OwnerId) != null) {
                    leave.DelegatedApproverId__c = userIdToManagerIdMap.get(leave.OwnerId);
                }
            }
        }
    }
    private static Boolean isAlreadyRunning = false;
    public static void submitNewLeavesForApproval(List<Leave__c> newLeaves) {
        if (isAlreadyRunning) return;
        isAlreadyRunning = true;
        for (Leave__c leave : newLeaves) {
            if (leave.Status__c == 'Pending') {
                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(leave.Id);
                req.setComments('New leave record submitted for approval.');
                req.setProcessDefinitionNameOrId('Leave_Approval_Process');
                Approval.ProcessResult result = Approval.process(req);
                if (!result.isSuccess()) {
                    System.debug('Approval failed for ' + leave.Id + ': '
                        + result.getErrors());
                }
            }
        }
    }
}
