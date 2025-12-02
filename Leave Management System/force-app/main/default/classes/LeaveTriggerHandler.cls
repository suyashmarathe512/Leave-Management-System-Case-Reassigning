public with sharing class LeaveTriggerHandler {
    
    public static void handleBeforeInsertUpdate(List<Leave__c> newLeaves) {
        // Collect all owner IDs from the new leaves
        Set<Id> ownerIds = new Set<Id>();
        
        for(Leave__c leave : newLeaves) {
            if(leave.OwnerId != null) {
                ownerIds.add(leave.OwnerId);
            }
        }
        
        // If no owners, nothing to validate
        if(ownerIds.isEmpty()) {
            return;
        }
        
        // Query existing leave records for these owners
        List<Leave__c> existingLeaves = [
            SELECT Id, OwnerId, Status__c 
            FROM Leave__c 
            WHERE OwnerId IN :ownerIds 
        ];
        
        // Create a map of owner to existing leave records for easy lookup
        Map<Id, List<Leave__c>> ownerToLeavesMap = new Map<Id, List<Leave__c>>();
        for(Leave__c existingLeave : existingLeaves) {
            if(!ownerToLeavesMap.containsKey(existingLeave.OwnerId)) {
                ownerToLeavesMap.put(existingLeave.OwnerId, new List<Leave__c>());
            }
            ownerToLeavesMap.get(existingLeave.OwnerId).add(existingLeave);
        }
        
        // Check for active leave records
        for(Leave__c leave : newLeaves) {
            if(leave.OwnerId != null) {
                List<Leave__c> ownerLeaves = ownerToLeavesMap.get(leave.OwnerId);
                
                // Check if this leave record is active
                Boolean isActiveLeave = (leave.Status__c != null && leave.Status__c == 'Active');
                
                if(Trigger.isInsert) {
                    // For inserts, if there's already an active leave record for this owner, throw an error
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
                    // If we're inserting a non-active leave, it's fine as long as we don't exceed 1 total record
                    // (But we're focusing on active records restriction for now)
                }
                
                if(Trigger.isUpdate) {
                    // For updates, we need to check if we're trying to make a second active record
                    if(isActiveLeave) {
                        if(ownerLeaves != null) {
                            // Count how many active records already exist for this owner
                            Integer activeCount = 0;
                            for(Leave__c existingLeave : ownerLeaves) {
                                if(existingLeave.Status__c != null && existingLeave.Status__c == 'Active') {
                                    // If this is the same record being updated, don't count it
                                    if(existingLeave.Id != leave.Id) {
                                        activeCount++;
                                    }
                                }
                            }
                            
                            // If there's already an active record for this owner (and it's not the current record)
                            if(activeCount > 0) {
                                leave.addError('Only one active leave record is allowed per employee.');
                            }
                        }
                    }
                }
            }
        }
        
        // Populate DelegatedApproverId based on OwnerId
        populateDelegatedApproverIds(newLeaves);
    }
    
    private static void populateDelegatedApproverIds(List<Leave__c> leaves) {
        // Get all unique OwnerIds from the leaves
        Set<Id> ownerIds = new Set<Id>();
        for(Leave__c leave : leaves) {
            if(leave.OwnerId != null && leave.DelegatedApproverId == null) {
                ownerIds.add(leave.OwnerId);
            }
        }
        
        // If no owners or all already have delegated approver, nothing to do
        if(ownerIds.isEmpty()) {
            return;
        }
        
        // Query for user information to determine approvers
        // This is a simplified approach - in a real system, you'd typically have a 
        // manager relationship or a custom object mapping users to approvers
        List<User> users = [
            SELECT Id, ManagerId 
            FROM User 
            WHERE Id IN :ownerIds
        ];
        
        // Create a map of user to manager for quick lookup
        Map<Id, Id> userIdToManagerIdMap = new Map<Id, Id>();
        for(User user : users) {
            userIdToManagerIdMap.put(user.Id, user.ManagerId);
        }
        
        // Populate DelegatedApproverId for each leave record
        for(Leave__c leave : leaves) {
            if(leave.OwnerId != null && leave.DelegatedApproverId == null) {
                // Set the delegated approver to the manager of the owner
                leave.DelegatedApproverId = userIdToManagerIdMap.get(leave.OwnerId);
            }
        }
    }
}
