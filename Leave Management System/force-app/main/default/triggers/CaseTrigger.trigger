
trigger CaseTrigger on Case(after insert,after update){
    if(Trigger.isAfter){
        if(Trigger.isInsert){
            CaseTriggerHandler.reassignCasesForUsersOnLeave(Trigger.new);
        }
        if(Trigger.isUpdate){
            CaseTriggerHandler.reassignCasesForUsersOnLeave(Trigger.new);
        }
    }
}
