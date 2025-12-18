/********************************************************************************************************************
* @Author:        CRM Team Innovation
* @ClassName:     DailyLeaveReassignmentBatch
* @Description:   Batch+Schedulable Apex to reassign Cases based on Leave__c start/end dates without manual updates.
*                 Runs daily. It finds:
*                   - Activations: Approved leaves whose Start_Date__c is today (entering effective-active)
*                   - Inactivations: Approved leaves that were active yesterday but end before today (leaving active)
*********************************************************************************************************************/
public with sharing class DailyLeaveReassignmentBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    public class BatchScope {
        public Date runDate;
        public BatchScope(Date d) { this.runDate = d; }
    }
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new DailyLeaveReassignmentBatch(), 20);
    }
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM Leave__c');
    }
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> scopeIds = (new Map<Id, SObject>(scope)).keySet();
        Date today = Date.today();
        List<Leave__c> activated = [
            SELECT 
                Id, OwnerId, Status__c, Start_Date__c, End_Date__c
            FROM 
                Leave__c
            WHERE 
                Id IN :scopeIds
            AND 
                Status__c = 'Approved'
              AND 
                Start_Date__c <= :today
              AND 
                End_Date__c >= :today
        ];
        List<Leave__c> inactivated = [
            SELECT 
                Id, OwnerId, Status__c, Start_Date__c, End_Date__c
            FROM 
                Leave__c
            WHERE 
                Id IN :scopeIds
            AND 
                Status__c = 'Approved'
            AND 
                End_Date__c < :today
        ];
        List<Case> casesToUpdate = new List<Case>();
        Map<Id, List<Case>> emailsForDelegates = new Map<Id, List<Case>>();
        Map<Id, List<Case>> emailsForReturnees = new Map<Id, List<Case>>();
        Map<Id, List<Case>> emailsForStoppedDelegates = new Map<Id, List<Case>>();
        if (!activated.isEmpty()) {
            CaseReassignment.processActivations(activated, casesToUpdate, emailsForDelegates);
        }
        if (!inactivated.isEmpty()) {
            CaseReassignment.processInactivations(inactivated, casesToUpdate, emailsForReturnees, emailsForStoppedDelegates, emailsForDelegates);
        }
        if (!casesToUpdate.isEmpty()) {
            // Dedup cases to prevent "Duplicate id in list" exception
            Map<Id, Case> casesMap = new Map<Id, Case>();
            for (Case c : casesToUpdate) {
                casesMap.put(c.Id, c);
            }
            update casesMap.values();
            CaseReassignment.sendAllNotifications(emailsForDelegates, emailsForReturnees, emailsForStoppedDelegates);
        }
    }
    public void finish(Database.BatchableContext bc) {
    }
}
