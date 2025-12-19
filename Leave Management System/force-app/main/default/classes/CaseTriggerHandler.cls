/*******************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @ClassName:       CaseTriggerHandler
 * @Description:     This class calls the processActivaiton if OnLeave User gets cases.
 ****************************************************************************************************************/
public with sharing class CaseTriggerHandler{
/********************************************************************************************************************
 *@Author:          CRM Team Innovation
 *@methodName:      reassignCasesForUsersOnLeave
 *@param:         newCases-List of new/updated Case records to check for reassignment
 *@Description:     This method checks if the owners of the newly created/updated Case records are on active leave.
    *                  If they are,it invokes the LeaveTriggerHandler to handle the reassignment logic.
  **********************************************************************************************************************/
    public static void reassignCasesForUsersOnLeave(List<Case> newCases){
        Set<Id> ownerIds=new Set<Id>();
        for(Case c:newCases){
            if(c.OwnerId!=null&&String.valueOf(c.OwnerId).startsWith('005')){
                ownerIds.add(c.OwnerId);
            }
        }
        if(!ownerIds.isEmpty()){
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
                List<Case> casesToUpdate=new List<Case>();
                Map<Id,List<Case>> emailsForDelegates=new Map<Id,List<Case>>();
                CaseReassignment.processActivations(leaves,casesToUpdate,emailsForDelegates);
                if(!casesToUpdate.isEmpty()){
                    Map<Id,Case> finalCasesToUpdate=new Map<Id,Case>(casesToUpdate);
                    update finalCasesToUpdate.values();
                }
                if(emailsForDelegates!=null&&!emailsForDelegates.isEmpty()){
                    CaseReassignment.sendAllNotifications(emailsForDelegates,null,null);
                }
            }
        }
    }
}
