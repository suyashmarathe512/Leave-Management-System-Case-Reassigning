public with sharing class CaseTriggerHandler {
/********************************************************************************************************************
 *@Author:          CRM Team Innovation
 *@methodName:      reassignCasesForUsersOnLeave
 *@param:         newCases-List of new Case records to check for reassignment
 *@Description:     This method checks if the owners of the newly created Case records are on active leave.
    *                  If they are, it invokes the LeaveTriggerHandler to handle the reassignment logic.
 **********************************************************************************************************************/
public static void reassignCasesForUsersOnLeave(List<Case> newCases) {
    Set<Id> ownerIds = new Set<Id>();
    for (Case c : newCases) {
        ownerIds.add(c.OwnerId);
    }
    if (!ownerIds.isEmpty()) {
        List<Leave__c> leaves = [SELECT 
                                Id,OwnerId,Start_Date__c,End_Date__c,Status__c,Leave_Type__c,
                                Days_Taken__c
                            FROM 
                                Leave__c
                            WHERE 
                                OwnerId IN :ownerIds
                            AND 
                                Status__c = 'Active'];
        Map<Id, Leave__c> oldleaveMapDummy = new Map<Id, Leave__c>();
        for(Leave__c lv : leaves){
            Leave__c oldLeave = lv.clone();
            oldLeave.Status__c = 'Pending';
            oldleaveMapDummy.put(lv.Id, oldLeave);
        }
        if(!leaves.isEmpty()){
            LeaveTriggerHandler.handleAfterUpdate(leaves, oldleaveMapDummy);
        }
        }
    }
}