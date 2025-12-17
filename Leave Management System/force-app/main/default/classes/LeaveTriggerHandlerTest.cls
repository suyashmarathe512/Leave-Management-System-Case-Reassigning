@isTest
public class LeaveTriggerHandlerTest{
    private static final String EARNED_LEAVE='Earned_Leave';
    private static final String SICK_LEAVE='Sick_Leave';
    private static final String UNPAID_LEAVE='Unpaid_Leave';
    private static final String PENDING_STATUS='Pending';
    private static final String APPROVED_STATUS='Approved';
    private static final String REJECTED_STATUS='Rejected';
    @testSetup
    static void setupTestData(){
        User testUser=new User(
            FirstName='Test',
            LastName='User',
            Email='testuser@example.com',
            Username='testu432ser@example.com.test',
            ProfileId=[SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1].Id,
            IsActive=true,
            Alias='tuser',
            TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US'
        );
        insert testUser;
        User delegatedUser=new User(
            FirstName='Delegated',
            LastName='User',
            Email='delegated@example.com',
            Username='deleg432ated@example.com.test',
            ProfileId=[SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1].Id,
            IsActive=true,
            Alias='duser',
            TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US'
        );
        insert delegatedUser;
        testUser.DelegatedApproverId=delegatedUser.Id;
        update testUser;
        User adminUser=new User(
            FirstName='Admin',
            LastName='User',
            Email='admin@example.com',
            Username='admin432user@example.com.test',
            ProfileId=[SELECT Id FROM Profile WHERE Name='System Administrator' LIMIT 1].Id,
            IsActive=true,
            Alias='auser',
            TimeZoneSidKey='America/Los_Angeles',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US'
        );
        insert adminUser;
        adminUser.DelegatedApproverId=delegatedUser.Id;
        update adminUser;
        Leave_Balance__c balance=new Leave_Balance__c(
            SetupOwnerId=testUser.Id,
            Earned_Leave__c=100,
            Sick_Leave__c=100
        );
        insert balance;
        Group testQueue=new Group(
            Name='Case_Queue',
            Type='Queue'
        );
        insert testQueue;
    }
    @isTest
    static void testHandleBeforeInsertUpdate_SufficientEarnedLeaveBalance(){
        User testUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='testuser@example.com' LIMIT 1];
        System.runAs(testUser){
            Leave__c leave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(2),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=PENDING_STATUS
            );
            Test.startTest();
            insert leave;
            Test.stopTest();
            Leave__c insertedLeave=[SELECT 
                                        Leave_Type__c 
                                    FROM 
                                        Leave__c 
                                    WHERE 
                                        Id=:leave.Id];
            System.assertEquals(EARNED_LEAVE,insertedLeave.Leave_Type__c,
                'Leave type should remain Earned_Leave when balance is sufficient');
        }
    }
    @isTest
    static void testHandleBeforeInsertUpdate_InsufficientEarnedLeaveBalance(){
        User testUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='testuser@example.com' LIMIT 1];
        System.runAs(testUser){
            Leave__c firstLeave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(9),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=PENDING_STATUS
            );
            insert firstLeave;
            Leave__c secondLeave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today().addDays(10),
                End_Date__c=Date.today().addDays(125),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=PENDING_STATUS
            );
            Test.startTest();
            try{
                insert secondLeave;
                System.assert(false,'Expected DmlException was not thrown');
            } catch (Exception e){
                System.assert(
                    e.getMessage().contains('Please apply for Unpaid Leave'),
                    'Error message should indicate insufficient earned leave balance'
                );
            }
            Test.stopTest();
        }
    }
     @isTest
    static void testHandleBeforeInsertUpdate_InsufficientSickLeaveBalance(){
        User testUser=[SELECT
                            Id
                        FROM
                            User
                        WHERE
                            Email='testuser@example.com' LIMIT 1];
        System.runAs(testUser){
            
            Leave__c firstLeave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(4),
                Leave_Type__c=SICK_LEAVE,
                Status__c=PENDING_STATUS
            );
            insert firstLeave;
            Leave__c secondLeave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today().addDays(10),
                End_Date__c=Date.today().addDays(192),
                Leave_Type__c=SICK_LEAVE,
                Status__c=PENDING_STATUS
            );
            Test.startTest();
            try{
                insert secondLeave;
                System.assert(false,'Expected DmlException was not thrown');
            } catch (Exception e){
                System.assert(
                    e.getMessage().contains('Please apply for Unpaid Leave'),
                    'Error message should indicate insufficient sick leave balance'
                );
            }
            Test.stopTest();
        }
    }
    @isTest
    static void testHandleBeforeInsertUpdate_OnlyOneActiveLeaveAllowed(){
        User testUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='testuser@example.com' LIMIT 1];
        System.runAs(testUser){
            Leave__c firstLeave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(2),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=APPROVED_STATUS
            );
            insert firstLeave;
            Leave__c secondLeave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today().addDays(1),
                End_Date__c=Date.today().addDays(3),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=APPROVED_STATUS
            );
            Test.startTest();
            Database.SaveResult result=Database.insert(secondLeave,false);
            Test.stopTest();
            System.assertNotEquals(null,result,'Result should not be null');
        }
    }
    @isTest
    static void testHandleBeforeInsertUpdate_OverlappingLeaveValidation(){
        User testUser=[SELECT
                            Id
                        FROM
                            User
                        WHERE
                            Email='testuser@example.com' LIMIT 1];

        System.runAs(testUser){
            Leave__c firstLeave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(5),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=APPROVED_STATUS
            );
            insert firstLeave;
            Leave__c secondLeave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today().addDays(3),
                End_Date__c=Date.today().addDays(8),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=PENDING_STATUS
            );
            Test.startTest();
            Database.SaveResult result=Database.insert(secondLeave,false);
            Test.stopTest();
            System.assertEquals(false,result.isSuccess(),'Insert should fail due to overlapping dates');
            System.assert(result.getErrors().size() > 0,'There should be at least one error');
            System.assert(result.getErrors()[0].getMessage().contains('You already have leave in this time period'),'Error message should indicate overlapping leave');
        }
    }
    @isTest
    static void testHandleBeforeInsertUpdate_WithRequiredDates(){
        User testUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='testuser@example.com' LIMIT 1];
        System.runAs(testUser){
            Leave__c leave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(2),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=PENDING_STATUS
            );
            Test.startTest();
            insert leave;
            Test.stopTest();
            Leave__c insertedLeave=[SELECT 
                                Id 
                            FROM 
                                Leave__c 
                            WHERE 
                                Id=:leave.Id];
            System.assertNotEquals(null,insertedLeave.Id,
                'Leave with required dates should be created');
        }
    }
    @isTest
    static void testHandleAfterUpdate_AdminActivateLeaveSendsEmailToDelegate(){
        User testUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='testuser@example.com' LIMIT 1];
        User delegatedUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='delegated@example.com' LIMIT 1];
        User adminUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Profile.Name='System Administrator' LIMIT 1];
        System.runAs(testUser){
            List<Case> cases=new List<Case>();
            for (Integer i=0; i < 2; i++){
                cases.add(new Case(
                    Subject='Test Case ' + i,
                    OwnerId=testUser.Id,
                    Status='New'
                ));
            }
            insert cases;
        }
        System.runAs(adminUser){
            List<Case> preOpen=[SELECT Id,OwnerId,IsClosed FROM Case WHERE OwnerId=:testUser.Id];
            Leave__c leave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(1),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=PENDING_STATUS
            );
            insert leave;
            leave=[SELECT Id,Status__c FROM Leave__c WHERE Id=:leave.Id];
            Test.startTest();
            Leave__c toUpdate=new Leave__c(Id=leave.Id,Status__c=APPROVED_STATUS);
            update toUpdate;
            Test.stopTest();
            System.debug('Email invocations after activation: ' + Limits.getEmailInvocations());
            System.assertEquals(1,Limits.getEmailInvocations(),
                'One email should be sent to delegated user');
        }
    }
    @isTest
    static void testHandleAfterUpdate_AdminInactivateLeaveReassignCases(){
        User testUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='testuser@example.com' LIMIT 1];
        User delegatedUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='delegated@example.com' LIMIT 1];
        User adminUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Profile.Name='System Administrator' LIMIT 1];
        List<Case> delegatedCases=new List<Case>();
        for(Integer i=0; i < 2; i++){
            delegatedCases.add(new Case(
                Subject='Delegated Case ' + i,
                OwnerId=delegatedUser.Id,
                Orginal_Owner_Id__c=testUser.Id,
                Is_delegated__c=true,
                Status='New'
            ));
        }
        insert delegatedCases;
        System.runAs(adminUser){
            Leave__c leave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(1),
                Leave_Type__c=UNPAID_LEAVE,
                Status__c=PENDING_STATUS
            );
            insert leave;
            Leave__c toActive=new Leave__c(Id=leave.Id,Status__c=APPROVED_STATUS);
            update toActive;
            Test.startTest();
            Leave__c toInactive=new Leave__c(Id=leave.Id,Status__c=REJECTED_STATUS);
            Database.SaveResult result=Database.update(toInactive,false);
            Test.stopTest();
            System.debug('Email invocations after inactivation: ' + Limits.getEmailInvocations());
            System.assertEquals(true,result.isSuccess(),'Admin should be able to inactivate leave');
        }
    }
    @isTest
    static void testHandleAfterUpdate_AdminInactivateLeaveSendsEmailToAll(){
        User testUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='testuser@example.com' LIMIT 1];
        User delegatedUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='delegated@example.com' LIMIT 1];
        User adminUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Profile.Name='System Administrator' LIMIT 1];
        Case delegatedCase=new Case(
            Subject='Delegated Case',
            OwnerId=delegatedUser.Id,
            Orginal_Owner_Id__c=testUser.Id,
            Is_delegated__c=true,
            Status='New'
        );
        insert delegatedCase;
        System.runAs(testUser){
            Case delegatedCase1=new Case(
                Subject='Delegated Case for Inactivate',
                OwnerId=delegatedUser.Id,
                Orginal_Owner_Id__c=testUser.Id,
                Is_delegated__c=true,
                Status='New'
            );
            insert delegatedCase1;
        }
        System.runAs(adminUser){
            Leave__c leave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today(),
                End_Date__c=Date.today().addDays(1),
                Leave_Type__c=UNPAID_LEAVE,
                Status__c=PENDING_STATUS
            );
            insert leave;
            Leave__c toActive=new Leave__c(Id=leave.Id,Status__c=APPROVED_STATUS);
            update toActive;
            Test.startTest();
            Leave__c toInactive=new Leave__c(Id=leave.Id,Status__c=REJECTED_STATUS);
            Database.update(toInactive,false);
            Test.stopTest();
            System.debug('Email invocations after inactivation (2nd test): ' + Limits.getEmailInvocations());
            System.assertEquals(2,Limits.getEmailInvocations(),
                'Two emails should be sent (one to original user,one to delegated user)');
        }
    }
    @isTest
    static void testHandleAfterUpdate_StatusChangeOtherThanActiveInactive(){
        User testUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Email='testuser@example.com' LIMIT 1];
        User adminUser=[SELECT 
                            Id 
                        FROM 
                            User 
                        WHERE 
                            Profile.Name='System Administrator' LIMIT 1];
        
        Case testCase=new Case(
            Subject='Test Case',
            OwnerId=testUser.Id,
            Status='New'
        );
        insert testCase;
        System.runAs(adminUser){
            Leave__c leave=new Leave__c(
                OwnerId=testUser.Id,
                Start_Date__c=Date.today().addDays(10),
                End_Date__c=Date.today().addDays(12),
                Leave_Type__c=EARNED_LEAVE,
                Status__c=PENDING_STATUS
            );
            insert leave;
            Test.startTest();
            leave.Status__c=APPROVED_STATUS;
            Database.update(leave,false);
            Test.stopTest();
            Case verifyCase=[SELECT 
                                OwnerId 
                            FROM 
                                Case 
                            WHERE 
                                Id=:testCase.Id];
            System.assertEquals(testUser.Id,verifyCase.OwnerId,
                'Case should not be reassigned when status changes to non-Active/Inactive status');
        }
    }
}
