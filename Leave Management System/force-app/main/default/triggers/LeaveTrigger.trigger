trigger LeaveTrigger on Leave__c (before insert, before update, after insert, after update) {
    if(Trigger.isBefore) {
        if(Trigger.isInsert) {
            LeaveTriggerHandler.handleBeforeInsertUpdate(Trigger.new);
        }
        if(Trigger.isUpdate) {
            LeaveTriggerHandler.handleBeforeInsertUpdate(Trigger.new);
        }
    }
    if(Trigger.isAfter && Trigger.isInsert) {
        LeaveTriggerHandler.submitNewLeavesForApproval(Trigger.new);
    }
}
