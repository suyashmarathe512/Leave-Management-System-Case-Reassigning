@isTest
public class LeaveTriggerHandlerTest{
    @testSetup
    static void makeData(){
        Profile p=[SELECT 
                        Id 
                    FROM 
                        Profile 
                    WHERE 
                        Name='Standard User' LIMIT 1];
        // Create Manager User
        User manager=new User(
            Alias='mngr',
            Email='manager@testorg.com',
            EmailEncodingKey='UTF-8',
            LastName='Manager',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            ProfileId=p.Id,
            TimeZoneSidKey='America/Los_Angeles',
            UserName='manager_lms_test' + System.currentTimeMillis() + '@testorg.com'
        );
        insert manager;
        User u=new User(
            Alias='stdusr',
            Email='standarduser@testorg.com',
            EmailEncodingKey='UTF-8',
            LastName='Testing',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',
            ProfileId=p.Id,
            TimeZoneSidKey='America/Los_Angeles',
            UserName='standarduser_lms_test' + System.currentTimeMillis() + '@testorg.com',
            ManagerId=manager.Id
        );
        insert u;
        Leave_Balance__c balance=new Leave_Balance__c(
            SetupOwnerId=u.Id,
            Earned_Leave__c=10,
            Sick_Leave__c=10
        );
        insert balance;
        System.runAs(new User(Id=UserInfo.getUserId())){
            Group g=new Group(Type='Queue',Name='Case Queue');
            insert g;
            QueueSobject mappingObject=new QueueSobject(QueueId=g.Id,SobjectType='Case');
            insert mappingObject;
        }
    }
    @isTest
    static void testCalculateBusinessDays(){
        Date startDate=Date.today();
        Date endDate=startDate.addDays(5);
        Test.startTest();
        Integer days=LeaveTriggerHandler.calculateBusinessDays(startDate,endDate);
        Test.stopTest();
        System.assert(days >= 0,'Business days calculation should return a non-negative integer');
    }
    @isTest
    static void testInsertLeave_Success(){
        User u=[SELECT 
                    Id 
                FROM 
                    User 
                WHERE 
                    UserName 
                LIKE 'standarduser_lms_test%' LIMIT 1];
        Test.startTest();
        System.runAs(u){
            Leave__c leave=new Leave__c(
                OwnerId=u.Id,
                Start_Date__c=Date.today().addDays(1),
                End_Date__c=Date.today().addDays(2),
                Leave_Type__c='Earned_Leave',
                Status__c='Pending'
            );
            insert leave;
            Leave__c insertedLeave=[SELECT 
                                        Id,Status__c 
                                    FROM 
                                        Leave__c 
                                    WHERE 
                                        Id=:leave.Id];
            System.assertEquals('Pending',insertedLeave.Status__c);
        }
        Test.stopTest();
    }
    @isTest
    static void testInsertLeave_InsufficientEarnedBalance(){
        User u=[SELECT 
                    Id 
                FROM 
                    User 
                WHERE 
                    UserName 
                LIKE  
                    'standarduser_lms_test%' LIMIT 1];
        Test.startTest();
        System.runAs(u){
            Leave__c leave=new Leave__c(
                OwnerId=u.Id,
                Start_Date__c=Date.today().addDays(1),
                End_Date__c=Date.today().addDays(100),
                Leave_Type__c='Earned_Leave',
                Status__c='Pending'
            );
            try{
                insert leave;
                System.assert(false,'Should have thrown exception for insufficient balance');
            }catch(DmlException e){
                System.assert(e.getMessage().contains('insufficient Earned Leave balance'),'Expected insufficient balance error,got: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }
    @isTest
    static void testInsertLeave_InsufficientSickBalance(){
        User u=[SELECT 
                    Id 
                FROM 
                    User 
                WHERE 
                    UserName 
                LIKE 
                    'standarduser_lms_test%' LIMIT 1];
        Test.startTest();
        System.runAs(u){
            Leave__c leave=new Leave__c(
                OwnerId=u.Id,
                Start_Date__c=Date.today().addDays(1),
                End_Date__c=Date.today().addDays(100),
                Leave_Type__c='Sick_Leave',
                Status__c='Pending'
            );
            try{
                insert leave;
                System.assert(false,'Should have thrown exception for insufficient balance');
            }catch(DmlException e){
                System.assert(e.getMessage().contains('insufficient Sick Leave balance'),'Expected insufficient balance error,got: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }
    @isTest
    static void testInsertLeave_NoBalanceRecord(){
        // Create a new user without balance
        Profile p=[SELECT 
                        Id 
                    FROM 
                        Profile 
                    WHERE 
                        Name='Standard User' 
                    LIMIT 1];
        User u2=new User(
            Alias='u2',Email='u2@test.com',EmailEncodingKey='UTF-8',LastName='U2',
            LanguageLocaleKey='en_US',LocaleSidKey='en_US',ProfileId=p.Id,
            TimeZoneSidKey='America/Los_Angeles',UserName='u2_lms_test' + System.currentTimeMillis() + '@test.com'
        );
        insert u2;
        Test.startTest();
        System.runAs(u2){
            Leave__c leave=new Leave__c(
                OwnerId=u2.Id,
                Start_Date__c=Date.today().addDays(1),
                End_Date__c=Date.today().addDays(2),
                Leave_Type__c='Earned_Leave',
                Status__c='Pending'
            );
            try{
                insert leave;
                System.assert(false,'Should fail due to missing balance record');
            }catch(DmlException e){
                System.assert(e.getMessage().contains('Leave balance record not found'),'Expected missing balance error,got: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }
    @isTest
    static void testOverlappingLeaves(){
        User u=[SELECT 
                    Id 
                FROM 
                    User 
                WHERE 
                    UserName 
                LIKE 
                    'standarduser_lms_test%' LIMIT 1];
        // Create an existing approved leave
        Leave__c l1=new Leave__c(
            OwnerId=u.Id,
            Start_Date__c=Date.today().addDays(1),
            End_Date__c=Date.today().addDays(5),
            Leave_Type__c='Earned_Leave',
            Status__c='Pending'
        );
        insert l1;
        l1.Status__c='Approved';
        update l1;
        Test.startTest();
        System.runAs(u){
            Leave__c l2=new Leave__c(
                OwnerId=u.Id,
                Start_Date__c=Date.today().addDays(3),
                End_Date__c=Date.today().addDays(6),
                Leave_Type__c='Earned_Leave',
                Status__c='Pending'
            );
            try{
                insert l2;
                System.assert(false,'Should fail due to overlapping dates');
            }catch(DmlException e){
                System.assert(e.getMessage().contains('already have leave in this time period'),'Expected overlap error,got: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }
    @isTest
    static void testHandleAfterDelete_TriggersReassignment(){
        User u=[SELECT 
                    Id 
                FROM
                    User 
                WHERE 
                    UserName 
                LIKE 
                    'standarduser_lms_test%' LIMIT 1];
        Date today=Date.today();
        Leave__c leave=new Leave__c(
            OwnerId=u.Id,
            Start_Date__c=today.addDays(10),
            End_Date__c=today.addDays(15),
            Leave_Type__c='Earned_Leave',
            Status__c='Pending'
        );
        insert leave;
        leave.Start_Date__c=today.addDays(-1);
        leave.End_Date__c=today.addDays(5);
        leave.Status__c='Approved';
        update leave;
        Test.startTest();
        delete leave;
        Test.stopTest();
        List<Leave__c> deletedLeaves=[SELECT 
                                            Id 
                                        FROM 
                                            Leave__c 
                                        WHERE
                                            Id=:leave.Id];
        System.assertEquals(0,deletedLeaves.size());
    }
    @isTest
    static void testSubmitForApproval(){
        User u=[SELECT 
                    Id 
                FROM 
                    User 
                WHERE
                    UserName 
                LIKE 
                    'standarduser_lms_test%' LIMIT 1];
        Test.startTest();
        Leave__c leave=new Leave__c(
            OwnerId=u.Id,
            Start_Date__c=Date.today().addDays(10),
            End_Date__c=Date.today().addDays(12),
            Leave_Type__c='Earned_Leave',
            Status__c='Pending'
        );
        insert leave;
        Test.stopTest();
    }
}
