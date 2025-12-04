/********************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @ClassName:       LeaveControllerTest
 * @Description:     Unit tests for LeaveController Apex class
 *                   - Covers getLeaveBalances and getMyLeaves
 *                   - Uses proper test setup, assertions, and bulk scenarios
 ********************************************************************************************************************/
@IsTest
public with sharing class LeaveControllerTest {
    @TestSetup
    static void setupData() {
        // Seed only non-setup data here to avoid Mixed DML in test methods
        Leave_Balance__c orgDefault = new Leave_Balance__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Earned_Leave__c = 10,
            Sick_Leave__c   = 5
        );
        insert orgDefault;
    }
    @IsTest
    static void test_getLeaveBalances_userSpecific() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Leave',
            LastName  = 'ControllerTester',
            Alias     = 'lctst',
            Email     = 'leave.controller.tester@example.com',
            Username  = 'leave.controller.tester.' + System.currentTimeMillis() + '@example.com',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey   = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
        Test.startTest();
        Leave_Balance__c userBalance = new Leave_Balance__c(
            SetupOwnerId = u.Id,
            Earned_Leave__c = 20,
            Sick_Leave__c   = 8
        );
        insert userBalance;

        System.runAs(u) {
            List<Leave__c> testUserLeaves = new List<Leave__c>();
            Leave__c lv1 = new Leave__c();
            lv1.Start_Date__c = Date.today();
            lv1.End_Date__c   = Date.today().addDays(2);
            lv1.Leave_Type__c = 'Earned_Leave';
            lv1.Status__c     = 'Pending';
            lv1.Reason_To_Leave__c = 'Test run 1';
            testUserLeaves.add(lv1);
            
            Leave__c lv2 = new Leave__c();
            lv2.Start_Date__c = Date.today().addDays(5);
            lv2.End_Date__c   = Date.today().addDays(7);
            lv2.Leave_Type__c = 'Earned_Leave';
            lv2.Status__c     = 'Pending';
            lv2.Reason_To_Leave__c = 'Test run 2';
            testUserLeaves.add(lv2);
            
            Leave__c lv3 = new Leave__c();
            lv3.Start_Date__c = Date.today().addDays(10);
            lv3.End_Date__c   = Date.today().addDays(12);
            lv3.Leave_Type__c = 'Sick_Leave';
            lv3.Status__c     = 'Pending';
            lv3.Reason_To_Leave__c = 'Test run 3';
            testUserLeaves.add(lv3);
            insert testUserLeaves;
            LeaveController.LeaveBalanceDTO dto = LeaveController.getLeaveBalances();
            System.assertNotEquals(null, dto, 'DTO should not be null');
            System.assertEquals(20, dto.earned);
            System.assertEquals(8, dto.sick);
            System.assertEquals(6, dto.bookedEarned);
            System.assertEquals(3, dto.bookedSick);
            System.assertEquals(0, dto.bookedUnpaid);
            System.assertEquals(14, dto.availableEarned);
            System.assertEquals(5, dto.availableSick);
        }
        Test.stopTest();
    }
    @IsTest
    static void test_getMyLeaves_filtersByOwner() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Owner',
            LastName  = 'Primary',
            Alias     = 'ownpr',
            Email     = 'owner.primary@example.com',
            Username  = 'owner.primary.' + System.currentTimeMillis() + '@example.com',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey   = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        User other = new User(
            FirstName = 'Owner',
            LastName  = 'Secondary',
            Alias     = 'ownsc',
            Email     = 'owner.secondary@example.com',
            Username  = 'owner.secondary.' + System.currentTimeMillis() + '@example.com',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey   = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert new List<User>{ u, other };
        System.runAs(u) {
            List<Leave__c> mine = new List<Leave__c>();
             Leave__c lv1 = new Leave__c();
            lv1.Start_Date__c = Date.today();
            lv1.End_Date__c   = Date.today().addDays(2);
            lv1.Leave_Type__c = 'Earned_Leave';
            lv1.Status__c     = 'Pending';
            lv1.Reason_To_Leave__c = 'Test run 1';
            mine.add(lv1);
            Leave__c lv2 = new Leave__c();
            lv2.Start_Date__c = Date.today().addDays(5);
            lv2.End_Date__c   = Date.today().addDays(7);
            lv2.Leave_Type__c = 'Earned_Leave';
            lv2.Status__c     = 'Pending';
            lv2.Reason_To_Leave__c = 'Test run 2';
            mine.add(lv2);
            Leave__c lv3 = new Leave__c();
            lv3.Start_Date__c = Date.today().addDays(10);
            lv3.End_Date__c   = Date.today().addDays(12);
            lv3.Leave_Type__c = 'Sick_Leave';
            lv3.Status__c     = 'Pending';
            lv3.Reason_To_Leave__c = 'Test run 3';
            mine.add(lv3);
            insert mine;
        }
        System.runAs(other) {
            List<Leave__c> notMine = new List<Leave__c>();
             Leave__c lv2 = new Leave__c();
            lv2.Start_Date__c = Date.today().addDays(5);
            lv2.End_Date__c   = Date.today().addDays(7);
            lv2.Leave_Type__c = 'Earned_Leave';
            lv2.Status__c     = 'Pending';
            lv2.Reason_To_Leave__c = 'Test run 2';
            notMine.add(lv2);
            Leave__c lv3 = new Leave__c();
            lv3.Start_Date__c = Date.today().addDays(10);
            lv3.End_Date__c   = Date.today().addDays(12);
            lv3.Leave_Type__c = 'Sick_Leave';
            lv3.Status__c     = 'Pending';
            lv3.Reason_To_Leave__c = 'Test run 3';
            notMine.add(lv3);
            insert notMine;
        }
        System.runAs(u) {
            Test.startTest();
            List<Leave__c> myLeaves = LeaveController.getMyLeaves();
            Test.stopTest();
            System.assertNotEquals(null, myLeaves, 'Result should not be null');
            System.assertEquals(3, myLeaves.size(), 'Should return only leaves owned by running user');
        }
    }
}
