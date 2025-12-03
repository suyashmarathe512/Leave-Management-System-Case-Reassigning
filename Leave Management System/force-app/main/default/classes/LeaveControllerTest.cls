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
        // Insert Users (setup objects) via System.runAs of an existing user to avoid mixed DML with non-setup
        // Approach: create setup objects first, then perform all non-setup DML in a separate transaction.
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // 1) Setup DML only: Create User WITHOUT assigning a role to avoid Mixed DML with non-setup later
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
            for (Integer i = 0; i < 3; i++) {
                Leave__c lv = new Leave__c();
                lv.Start_Date__c = Date.today().addDays(i);
                lv.End_Date__c   = Date.today().addDays(i + 3);
                lv.Leave_Type__c = 'Earned_Leave';
                lv.Status__c     = 'Pending';
                lv.Reason_To_Leave__c = 'Test run ' + i;
                testUserLeaves.add(lv);
            }
            insert testUserLeaves;
            LeaveController.LeaveBalanceDTO dto = LeaveController.getLeaveBalances();
            System.assertNotEquals(null, dto, 'DTO should not be null');
            System.assertEquals(20, dto.earned);
            System.assertEquals(8, dto.sick);
            System.assertEquals(2, dto.bookedEarned);
            System.assertEquals(1, dto.bookedSick);
            System.assertEquals(0.5, dto.bookedUnpaid);
            System.assertEquals(18, dto.availableEarned);
            System.assertEquals(7, dto.availableSick);
        }
        Test.stopTest();
    }
    @IsTest
    static void test_getMyLeaves_filtersByOwner() {
        // Insert setup Users once here (NO roles assigned to avoid Mixed DML)
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

        // Non-setup DML after: create records
        System.runAs(u) {
            List<Leave__c> mine = new List<Leave__c>();
            for (Integer i = 1; i < 3; i++) {
                Leave__c lv = new Leave__c(
                    Start_Date__c = Date.today().addDays(i),
                    End_Date__c = Date.today().addDays(i+2),
                    Leave_Type__c = 'Earned_Leave',
                    Status__c = 'Pending',
                    Reason_To_Leave__c = 'Mine ' + i
                );
                mine.add(lv);
            }
            insert mine;
        }
        System.runAs(other) {
            List<Leave__c> notMine = new List<Leave__c>();
            for (Integer j = 1; j < 2; j++) {
                Leave__c lv = new Leave__c(
                    Start_Date__c = Date.today().addDays(j+8),
                    End_Date__c = Date.today().addDays(j+11),
                    Leave_Type__c = 'Sick_Leave',
                    Status__c = 'Pending',
                    Reason_To_Leave__c = 'Not mine ' + j
                );
                notMine.add(lv);
            }
            insert notMine;
        }
        System.runAs(u) {
            Test.startTest();
            List<Leave__c> myLeaves = LeaveController.getMyLeaves();
            Test.stopTest();
            System.assertNotEquals(null, myLeaves, 'Result should not be null');
            System.assertEquals(2, myLeaves.size(), 'Should return only leaves owned by running user');
        }
    }
}
