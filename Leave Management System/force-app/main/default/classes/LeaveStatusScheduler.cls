
public with sharing class LeaveStatusScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        try {
            List<Leave__c> leavesToUpdate = [
                SELECT
                    Id, Status__c, Start_Date__c
                FROM
                    Leave__c
                WHERE
                    Start_Date__c <= TODAY
                AND
                    Status__c = 'Approved'
            ];
            if (!leavesToUpdate.isEmpty()) {
                List<Leave__c> leavesToUpdateList = new List<Leave__c>();
                for (Leave__c leave : leavesToUpdate) {
                    leave.Status__c = 'Active';
                    leavesToUpdateList.add(leave);
                }
                if (!leavesToUpdateList.isEmpty()) {
                    Database.update(leavesToUpdateList, false);
                }
            }
        } catch (Exception e) {
            System.debug('Error in LeaveStatusScheduler: ' + e.getMessage());
        }
    }
}
