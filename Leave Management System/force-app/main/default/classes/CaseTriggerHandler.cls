public with sharing class CaseTriggerHandler{
/********************************************************************************************************************
 *@Author:          CRM Team Innovation
 *@methodName:      trackPreviousOwner
 *@param:           newCases - List of Case (Trigger.new)
 *@param:           oldMap   - Map<Id,Case> (Trigger.oldMap)
 *@Description:     BEFORE UPDATE helper. If OwnerId changes,stamp Previous_Owner_Id__c from old OwnerId.
 *                  Must not modify Orginal_Owner_Id__c here or anywhere in this method.
 **********************************************************************************************************************/
public static void trackPreviousOwner(List<Case> newCases,Map<Id,Case> oldMap){
    if (newCases==null||newCases.isEmpty()||oldMap==null||oldMap.isEmpty()) return;
    for (Case c:newCases){
        Case oldC=oldMap.get(c.Id);
        if (oldC==null) continue;
        if (c.OwnerId!=oldC.OwnerId&&oldC.OwnerId!=null){
            c.Previous_Owner_Id__c=oldC.OwnerId;
        }
    }
}
/********************************************************************************************************************
 *@Author:          CRM Team Innovation
 *@methodName:      reassignCasesForUsersOnLeave
 *@param:         newCases-List of new/updated Case records to check for reassignment
 *@Description:     This method checks if the owners of the newly created/updated Case records are on active leave.
    *                  If they are,it invokes the LeaveTriggerHandler to handle the reassignment logic.
 **********************************************************************************************************************/
public static void reassignCasesForUsersOnLeave(List<Case> newCases){
    Set<Id> ownerIds=new Set<Id>();
    for (Case c:newCases){
        ownerIds.add(c.OwnerId);
    }
    if (!ownerIds.isEmpty()){
        List<Leave__c> leaves=[SELECT 
                                    Id,OwnerId,Start_Date__c,End_Date__c,Status__c,Leave_Type__c,Days_Taken__c
                                FROM 
                                    Leave__c
                                WHERE 
                                    OwnerId IN :ownerIds
                                AND 
                                    Status__c='Active'];
        Map<Id,Leave__c> oldleaveMapDummy=new Map<Id,Leave__c>();
        for(Leave__c lv:leaves){
            Leave__c oldLeave=lv.clone();
            oldLeave.Status__c='Pending';
            oldleaveMapDummy.put(lv.Id,oldLeave);
        }
        if(!leaves.isEmpty()){
            LeaveTriggerHandler.handleAfterUpdate(leaves,oldleaveMapDummy);
        }
        }
    }
}