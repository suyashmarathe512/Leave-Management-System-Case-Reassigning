public with sharing class CaseTriggerHandler{
/********************************************************************************************************************
 *@Author:          CRM Team Innovation
 *@methodName:      trackPreviousOwner
 *@param:           newCases - List of Case (Trigger.new)
 *@param:           oldMap   - Map<Id,Case> (Trigger.oldMap)
 *@Description:     BEFORE UPDATE helper. If OwnerId changes,stamp Previous_Owner_Id__c from old OwnerId.
 *                  Must not modify Orginal_Owner__c here or anywhere in this method.
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
            // Only check for user-owned cases, not queue-owned
            if (c.OwnerId != null && String.valueOf(c.OwnerId).startsWith('005')) {
                ownerIds.add(c.OwnerId);
            }
        }
        if (!ownerIds.isEmpty()){
            Date today=Date.today();
            List<Leave__c> leaves=[SELECT 
                                        Id,OwnerId
                                    FROM 
                                        Leave__c
                                    WHERE 
                                        OwnerId IN :ownerIds
                                    AND 
                                        Status__c='Approved'
                                    AND 
                                        Start_Date__c<=:today
                                    AND 
                                        End_Date__c>=:today];
            if(!leaves.isEmpty()){
                List<Case> casesToUpdate = new List<Case>();
                Map<Id, List<Case>> emailsForDelegates = new Map<Id, List<Case>>();
                CaseReassignment.processActivations(leaves, casesToUpdate, emailsForDelegates);
                if (!casesToUpdate.isEmpty()) {
                    // Use a map to deduplicate cases before update to prevent errors.
                    Map<Id, Case> finalCasesToUpdate = new Map<Id, Case>(casesToUpdate);
                    update finalCasesToUpdate.values();
                }

                if (emailsForDelegates != null && !emailsForDelegates.isEmpty()) {
                    CaseReassignment.sendAllNotifications(emailsForDelegates, null, null);
                }
            }
        }
    }
}
