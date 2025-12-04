trigger LeaveTrigger on Leave__c (before insert, before update, after insert, after update) {
    if(Trigger.isBefore) {
        if(Trigger.isInsert) {
            LeaveTriggerHandler.populateDelegatedApprover(Trigger.new);
            LeaveTriggerHandler.handleBeforeInsertUpdate(Trigger.new);
        }
        if(Trigger.isUpdate) {
            LeaveTriggerHandler.handleBeforeInsertUpdate(Trigger.new);
        }
    }
    if(Trigger.isAfter) {
        if(Trigger.isInsert) {
            LeaveTriggerHandler.submitNewLeavesForApproval(Trigger.new);
        }
        if(Trigger.isUpdate) {
            LeaveTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
