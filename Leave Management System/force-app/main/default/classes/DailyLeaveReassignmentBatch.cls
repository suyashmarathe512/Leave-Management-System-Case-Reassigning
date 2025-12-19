/********************************************************************************************************************
* @Author:        CRM Team Innovation
* @ClassName:     DailyLeaveReassignmentBatch
* @Description:   Batch+Schedulable Apex to reassign Cases based on Leave__c start/end dates without manual updates.
*                 Runs daily. It finds:
*                   - Activations: Approved leaves whose Start_Date__c is today (entering effective-active)
*                   - Inactivations: Approved leaves that were active yesterday but end before today (leaving active)
*********************************************************************************************************************/
public with sharing class DailyLeaveReassignmentBatch implements Database.Batchable<SObject>, Schedulable{
    public void execute(SchedulableContext sc){
        Database.executeBatch(new DailyLeaveReassignmentBatch(), 200);
    }
    public Database.QueryLocator start(Database.BatchableContext bc){
        Date today=Date.today();
        return Database.getQueryLocator([
            SELECT 
                Id, OwnerId, Status__c, Start_Date__c, End_Date__c
            FROM 
                Leave__c
            WHERE 
                Status__c='Approved']);
    }
    public void execute(Database.BatchableContext bc, List<Leave__c> scope){
        Date today=Date.today();
        List<Leave__c> activated=new List<Leave__c>();
        List<Leave__c> inactivated=new List<Leave__c>();
        for (Leave__c leave : scope){
            if (leave.Start_Date__c <= today && leave.End_Date__c>=today){
                activated.add(leave);
            }else{
                inactivated.add(leave);
            }
        }
        List<Case> casesToUpdate=new List<Case>();
        Map<Id,List<Case>> emailsForDelegates=new Map<Id,List<Case>>();
        Map<Id,List<Case>> emailsForReturnees=new Map<Id,List<Case>>();
        Map<Id,List<Case>> emailsForStoppedDelegates=new Map<Id,List<Case>>();
        if (!activated.isEmpty()){
            CaseReassignment.processActivations(activated,casesToUpdate,emailsForDelegates);
        }
        if (!inactivated.isEmpty()){
            CaseReassignment.processInactivations(inactivated,casesToUpdate,emailsForReturnees,emailsForStoppedDelegates,emailsForDelegates);
        }
        if (!casesToUpdate.isEmpty()){
            // Deduplicate cases to prevent "Duplicate id in list" exception if a case is touched by both processes.
            Map<Id,Case> casesMap=new Map<Id,Case>();
            for (Case c:casesToUpdate){
                casesMap.put(c.Id,c);
            }
            update casesMap.values();
        }
        // Send notifications outside the update block to ensure they are sent even if no cases were updated (e.g., user had no cases).
        CaseReassignment.sendAllNotifications(emailsForDelegates,emailsForReturnees,emailsForStoppedDelegates);
    }

    public void finish(Database.BatchableContext bc){
    }
}
