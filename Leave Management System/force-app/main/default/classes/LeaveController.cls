public with sharing class LeaveController {

    public class LeaveBalanceDTO {
        @AuraEnabled public Decimal earned;
        @AuraEnabled public Decimal sick;
        @AuraEnabled public Decimal bookedEarned;
        @AuraEnabled public Decimal bookedSick;
        @AuraEnabled public Decimal bookedUnpaid;
        @AuraEnabled public Decimal availableEarned;
        @AuraEnabled public Decimal availableSick;
    }
    
    // 1) Get balances from hierarchical custom setting Leave_Balance__c
    @AuraEnabled(cacheable=true)
    public static LeaveBalanceDTO getLeaveBalances() {
        Leave_Balance__c cs;

        // Try user-level instance first, then org default
        cs = Leave_Balance__c.getInstance(UserInfo.getUserId());
        if (cs == null) {
            cs = Leave_Balance__c.getInstance();
        }

        LeaveBalanceDTO dto = new LeaveBalanceDTO();
        dto.earned = (cs != null && cs.Earned_Leave__c != null) ? cs.Earned_Leave__c : 0;
        dto.sick   = (cs != null && cs.Sick_Leave__c   != null) ? cs.Sick_Leave__c   : 0;
        
        // Calculate booked leaves from user's leave records
        List<Leave__c> userLeaves = [
            SELECT Booked_Earned_Leaves__c, 
                   Booked_Sick_Leaves__c, 
                   Booked_unpaid_leaves__c
            FROM Leave__c 
            WHERE OwnerId = :UserInfo.getUserId()
        ];
        
        dto.bookedEarned = 0;
        dto.bookedSick = 0;
        dto.bookedUnpaid = 0;
        
        for(Leave__c leave : userLeaves) {
            if(leave.Booked_Earned_Leaves__c != null) {
                dto.bookedEarned += leave.Booked_Earned_Leaves__c;
            }
            if(leave.Booked_Sick_Leaves__c != null) {
                dto.bookedSick += leave.Booked_Sick_Leaves__c;
            }
            if(leave.Booked_unpaid_leaves__c != null) {
                dto.bookedUnpaid += leave.Booked_unpaid_leaves__c;
            }
        }
        
        // Calculate available leaves by subtracting booked from total balance
        dto.availableEarned = dto.earned - dto.bookedEarned;
        dto.availableSick = dto.sick - dto.bookedSick;

        return dto;
    }

    // 2) Get current user's Leave__c records for the table
    @AuraEnabled(cacheable=true)
    public static List<Leave__c> getMyLeaves() {
        // Select all fields from Leave__c
        return [
            SELECT Id,
                   Name,
                   Start_Date__c,
                   End_Date__c,
                   Leave_Type__c,
                   Status__c,
                   Reason_To_Leave__c,
                   Booked_Earned_Leaves__c,
                   Booked_Sick_Leaves__c,
                   Booked_unpaid_leaves__c,
                   Days_Taken__c
            FROM Leave__c
            WHERE OwnerId = :UserInfo.getUserId()
            ORDER BY Start_Date__c DESC, CreatedDate DESC
        ];
    }
}
