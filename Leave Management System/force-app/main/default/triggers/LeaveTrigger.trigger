trigger LeaveTrigger on Leave__c (before insert, before update) {
    if(Trigger.isBefore) {
        if(Trigger.isInsert) {
            LeaveTriggerHandler.handleBeforeInsertUpdate(Trigger.new);
        }
        if(Trigger.isUpdate) {
            LeaveTriggerHandler.handleBeforeInsertUpdate(Trigger.new);
        }
    }
}
