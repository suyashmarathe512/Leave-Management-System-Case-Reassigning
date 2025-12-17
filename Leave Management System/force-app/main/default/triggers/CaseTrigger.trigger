
trigger CaseTrigger on Case(before update,after insert,after update){
    if(Trigger.isBefore){
        if(Trigger.isUpdate){
            CaseTriggerHandler.trackPreviousOwner(Trigger.new,Trigger.oldMap);
        }
    }
    if(Trigger.isAfter){
        if(Trigger.isInsert){
            CaseTriggerHandler.reassignCasesForUsersOnLeave(Trigger.new);
        }
        if(Trigger.isUpdate){
            CaseTriggerHandler.reassignCasesForUsersOnLeave(Trigger.new);
        }
    }
}
