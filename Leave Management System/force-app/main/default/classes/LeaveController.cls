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
        LeaveBalanceDTO dto=new LeaveBalanceDTO();
        dto.earned=(cs!=null&&cs.Earned_Leave__c!=null)?cs.Earned_Leave__c:0;
        dto.sick  =(cs!=null&&cs.Sick_Leave__c  !=null)?cs.Sick_Leave__c  :0;        
        List<Leave__c> userLeaves=[
            SELECT 
                Leave_Type__c,Days_Taken__c
            FROM 
                Leave__c 
            WHERE 
                OwnerId=:UserInfo.getUserId()
        ];
        dto.bookedEarned=0;
        dto.bookedSick=0;
        dto.bookedUnpaid=0;
        for(Leave__c leave:userLeaves){
            if(leave.Leave_Type__c=='Earned_Leave'&&leave.Days_Taken__c!=null){
                dto.bookedEarned+=leave.Days_Taken__c;
            }
            if(leave.Leave_Type__c=='Sick_Leave'&&leave.Days_Taken__c!=null){
                dto.bookedSick+=leave.Days_Taken__c;
            }
            if(leave.Leave_Type__c=='Unpaid_Leave'&&leave.Days_Taken__c!=null){
                dto.bookedUnpaid+=leave.Days_Taken__c;
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
            SELECT
                Id,Name,Start_Date__c,End_Date__c,Leave_Type__c,Status__c,Reason_To_Leave__c,Days_Taken__c
            FROM
                Leave__c
            WHERE
                OwnerId=:UserInfo.getUserId()
            ORDER BY
                Start_Date__c DESC,
                CreatedDate DESC
        ];
    }
/********************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @methodName:      getMyOpenCases
 * @Description:     Returns up to 'limitSize' open Cases owned by the current user, ordered by LastModifiedDate DESC
 *                   Open is defined as IsClosed=false
 **********************************************************************************************************************/
    @AuraEnabled(cacheable=true)
    public static List<Case> getMyOpenCases(Integer limitSize){
        Integer lim=20;
        Id uid=UserInfo.getUserId();
        String soql='SELECT Id, CaseNumber, Subject, Status, Priority, Type, LastModifiedDate '+
                      'FROM Case '+
                      'WHERE OwnerId=\''+String.escapeSingleQuotes(String.valueOf(uid))+'\' AND IsClosed=false '+
                      'ORDER BY LastModifiedDate DESC '+
                      'LIMIT '+String.valueOf(lim);
        return Database.query(soql);
    }
}
