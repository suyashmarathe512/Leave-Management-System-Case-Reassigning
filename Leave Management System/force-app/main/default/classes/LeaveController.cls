/********************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @ClassName:        LeaveController
 * @Description:      Apex controller for Leave Management LWC components
 **********************************************************************************************************************/
public with sharing class LeaveController{
/********************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @ClassName:        LeaveBalanceDTO
 * @Description:      Data Transfer Object to hold leave balance details
 **********************************************************************************************************************/
    public class LeaveBalanceDTO{
        @AuraEnabled public Decimal earned;
        @AuraEnabled public Decimal sick;
        @AuraEnabled public Decimal bookedEarned;
        @AuraEnabled public Decimal bookedSick;
        @AuraEnabled public Decimal bookedUnpaid;
        @AuraEnabled public Decimal availableEarned;
        @AuraEnabled public Decimal availableSick;
    }
/********************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @methodName:        getLeaveBalances
 * @Description:     Get current user's leave balances from Leave_Balance__c custom setting
 **********************************************************************************************************************/
    @AuraEnabled(cacheable=true)
    public static LeaveBalanceDTO getLeaveBalances(){
       Leave_Balance__c cs;
        String uid=UserInfo.getUserId();
        cs=Leave_Balance__c.getInstance(uid);
        if (cs==null){
            cs=Leave_Balance__c.getInstance();
        }
LeaveBalanceDTO dto=new LeaveBalanceDTO();
dto.earned=(cs!=null && cs.Earned_Leave__c!=null)?cs.Earned_Leave__c:0;
dto.sick  =(cs!=null && cs.Sick_Leave__c  !=null)?cs.Sick_Leave__c  :0;        
        List<Leave__c> userLeaves=[
            SELECT 
                Booked_Earned_Leaves__c, 
                Booked_Sick_Leaves__c, 
                Booked_unpaid_leaves__c
            FROM 
                Leave__c 
            WHERE 
                OwnerId=:UserInfo.getUserId()
        ];
        dto.bookedEarned=0;
        dto.bookedSick=0;
        dto.bookedUnpaid=0;
        for(Leave__c leave:userLeaves){
            if(leave.Booked_Earned_Leaves__c!=null){
                dto.bookedEarned+=leave.Booked_Earned_Leaves__c;
            }
            if(leave.Booked_Sick_Leaves__c!=null){
                dto.bookedSick+=leave.Booked_Sick_Leaves__c;
            }
            if(leave.Booked_unpaid_leaves__c!=null){
                dto.bookedUnpaid+=leave.Booked_unpaid_leaves__c;
            }
        }
        dto.availableEarned=dto.earned-dto.bookedEarned;
        dto.availableSick=dto.sick-dto.bookedSick;
        return dto;
    }
/********************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @methodName:        getMyLeaves
 * @Description:     Get current user's leaves
 *  **********************************************************************************************************************/
    @AuraEnabled(cacheable=true)
    public static List<Leave__c> getMyLeaves(){
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
            WHERE OwnerId=:UserInfo.getUserId()
            ORDER BY Start_Date__c DESC, CreatedDate DESC
        ];
    }
}
