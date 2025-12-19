@isTest
public class CaseReassignmentTest{
    @testSetup
    static void makeData(){
        // Create a Standard User Profile
        Profile p=[SELECT
                        Id 
                    FROM 
                        Profile 
                    WHERE 
                        Name='Standard User' LIMIT 1];
        // Create 3 Users: A -> B -> C (Chain of command)
        User userC=new User(
            Alias='usrC',Email='userc@test.com',
            EmailEncodingKey='UTF-8',LastName='UserC',LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',ProfileId=p.Id,
            TimeZoneSidKey='America/Los_Angeles',UserName='userc_lms_'+System.currentTimeMillis()+'test@test.com'
        );
        insert userC;
        User userB=new User(
            Alias='usrB',Email='userb@test.com',
            EmailEncodingKey='UTF-8',LastName='UserB',LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',ProfileId=p.Id,
            TimeZoneSidKey='America/Los_Angeles',UserName='userb_lms_test'+System.currentTimeMillis()+'@test.com',
            DelegatedApproverId=userC.Id
        );
        insert userB;
        User userA=new User(
            Alias='usrA',Email='usera@test.com',
            EmailEncodingKey='UTF-8',LastName='UserA',LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',ProfileId=p.Id,
            TimeZoneSidKey='America/Los_Angeles',UserName='usera_lms_t'+System.currentTimeMillis()+'est@test.com',
            DelegatedApproverId=userB.Id
        );
        insert userA;
        // Create Case Queue (Required by CaseReassignment)
        System.runAs(new User(Id=UserInfo.getUserId())){
            Group g=new Group(Type='Queue',Name='Case Queue');
            insert g;
            QueueSobject mappingObject=new QueueSobject(QueueId=g.Id,SobjectType='Case');
            insert mappingObject;
        }
        // Create Leave Balances (Required by LeaveTriggerHandler validation)
        List<Leave_Balance__c> balances=new List<Leave_Balance__c>();
        balances.add(new Leave_Balance__c(SetupOwnerId=userA.Id,Earned_Leave__c=20,Sick_Leave__c=20));
        balances.add(new Leave_Balance__c(SetupOwnerId=userB.Id,Earned_Leave__c=20,Sick_Leave__c=20));
        balances.add(new Leave_Balance__c(SetupOwnerId=userC.Id,Earned_Leave__c=20,Sick_Leave__c=20));
        insert balances;
        // Create Cases for User A
        List<Case> cases=new List<Case>();
        for(Integer i=0; i<5; i++){
            cases.add(new Case(Subject='Test Case ' + i,OwnerId=userA.Id,Status='New',Priority='Medium',Type='Other'));
        }
        insert cases;
    }
    @isTest
    static void testProcessActivations_DelegationToB(){
        User userA=[SELECT
                            Id 
                        FROM 
                            User 
                        WHERE 
                            UserName LIKE 'usera_lms_%' LIMIT 1];
        User userB=[SELECT
                        Id 
                    FROM    
                        User 
                    WHERE 
                        UserName LIKE 'userb_lms_%' LIMIT 1];
        Date today=Date.today();
        // Create Leave for A (Insert as Pending first to satisfy validation rule)
        Leave__c leave=new Leave__c(
            OwnerId=userA.Id,
            Start_Date__c=today,
            End_Date__c=today.addDays(5),
            Status__c='Pending',
            Leave_Type__c='Earned_Leave'
        );
        insert leave;
        Test.startTest();
        leave.Status__c='Approved';
        update leave;
        Database.executeBatch(new DailyLeaveReassignmentBatch(),20);
        Test.stopTest();
        // Verify cases moved to B
        List<Case> cases=[SELECT
                                OwnerId,Is_delegated__c,Orginal_Owner_Id__c 
                            FROM 
                                Case 
                            WHERE 
                                Subject 
                            LIKE 
                                'Test Case%'];
        for(Case c:cases){
            System.assertEquals(userB.Id,c.OwnerId,'Case should be reassigned to User B');
            System.assertEquals(true,c.Is_delegated__c,'Case should be marked as delegated');
            System.assertEquals(userA.Id,c.Orginal_Owner_Id__c,'Original owner should be User A');
        }
    }

    @isTest
    static void testProcessActivations_ChainToC(){
        User userA=[SELECT
                        Id FROM User WHERE UserName LIKE 'usera_lms_%' LIMIT 1];
        User userB=[SELECT
                        Id FROM User WHERE UserName LIKE 'userb_lms_%' LIMIT 1];
        User userC=[SELECT
                        Id FROM User WHERE UserName LIKE 'userc_lms_%' LIMIT 1];
        Date today=Date.today();
        // Create Leave for A and B (Both on leave today)
        List<Leave__c> leaves=new List<Leave__c>();
        leaves.add(new Leave__c(OwnerId=userA.Id,Start_Date__c=today,End_Date__c=today.addDays(5),Status__c='Pending',Leave_Type__c='Earned_Leave'));
        leaves.add(new Leave__c(OwnerId=userB.Id,Start_Date__c=today,End_Date__c=today.addDays(5),Status__c='Pending',Leave_Type__c='Earned_Leave'));
        insert leaves;
        Test.startTest();
        for(Leave__c l:leaves){
            l.Status__c='Approved';
        }
        update leaves; 
        Database.executeBatch(new DailyLeaveReassignmentBatch(),20);
        Test.stopTest();
        // Verify cases moved to C (A -> B[on leave] -> C)
        List<Case> cases=[SELECT
                                OwnerId 
                            FROM 
                                Case 
                            WHERE 
                                Subject 
                            LIKE 
                                'Test Case%'];
        for(Case c:cases){
            System.assertEquals(userC.Id,c.OwnerId,'Case should be reassigned to User C due to chain of command');
        }
    }   
    @isTest
    static void testProcessActivations_ToQueue(){
        User userC=[SELECT
                            Id 
                        FROM 
                            User 
                        WHERE UserName LIKE 'userc_lms_%' LIMIT 1];
        Group queue=[SELECT
                            Id 
                        FROM
                            Group 
                        WHERE
                            Name='Case Queue'
                        AND
                            Type='Queue' LIMIT 1];
        
        // Create case for C
        Case c=new Case(Subject='Case C',OwnerId=userC.Id,Status='New');
        insert c;
        Date today=Date.today();
        Leave__c leave=new Leave__c(OwnerId=userC.Id,Start_Date__c=today,End_Date__c=today.addDays(5),Status__c='Pending',Leave_Type__c='Earned_Leave');
        insert leave;
        Test.startTest();
        leave.Status__c='Approved';
        update leave;
        Database.executeBatch(new DailyLeaveReassignmentBatch(),20);
        Test.stopTest();
        Case res=[SELECT
                        OwnerId
                    FROM
                        Case
                    WHERE
                        Id=:c.Id];
        System.assertEquals(queue.Id,res.OwnerId,'Case should be reassigned to Queue as C has no delegate');
    }
    @isTest
    static void testProcessInactivations_ReturnToA(){
        User userA=[SELECT
                            Id
                        FROM
                            User
                        WHERE
                            UserName LIKE 'usera_lms_%' LIMIT 1];
        User userB=[SELECT
                            Id
                        FROM
                            User
                        WHERE
                            UserName LIKE 'userb_lms_%' LIMIT 1];
        // Setup: Case currently with B,delegated from A
        Case c=new Case(Subject='Delegated Case',OwnerId=userB.Id,Orginal_Owner_Id__c=userA.Id,Is_delegated__c=true,Status='New');
        insert c;
        Date yesterday=Date.today().addDays(-1);
        // Create past leave: Insert with future dates to bypass "Start Date < Today" validation,then update to past
        Leave__c leaveA=new Leave__c(OwnerId=userA.Id,Start_Date__c=Date.today().addDays(10),End_Date__c=Date.today().addDays(12),Status__c='Pending',Leave_Type__c='Earned_Leave');
        insert leaveA;
        leaveA.Start_Date__c=yesterday.addDays(-2);
        leaveA.End_Date__c=yesterday;
        leaveA.Status__c='Approved';
        update leaveA;
        List<Leave__c> inactivated=new List<Leave__c>{leaveA};
        List<Case> casesToUpdate=new List<Case>();
        Map<Id,List<Case>> mapReturnees=new Map<Id,List<Case>>();
        Map<Id,List<Case>> mapStopped=new Map<Id,List<Case>>();
        Map<Id,List<Case>> mapDelegates=new Map<Id,List<Case>>();
        Test.startTest();
        // Manually call processInactivations (simulating Batch job)
        CaseReassignment.processInactivations(inactivated,casesToUpdate,mapReturnees,mapStopped,mapDelegates);
        if(!casesToUpdate.isEmpty()) update casesToUpdate;
        Test.stopTest();
        Case res=[SELECT
                        OwnerId,Is_delegated__c 
                    FROM 
                        Case 
                    WHERE 
                        Id=:c.Id];
        System.assertEquals(userA.Id,res.OwnerId,'Case should return to original owner A');
        System.assertEquals(false,res.Is_delegated__c,'Is_delegated should be false');
        System.assert(mapReturnees.containsKey(userA.Id),'User A should be in returnees email map');
    }
    @isTest
    static void testProcessInactivations_BReturns_AStillAway(){
        User userA=[SELECT
                        Id 
                    FROM 
                        User 
                    WHERE 
                        UserName LIKE 'usera_lms_%' LIMIT 1];
        User userB=[SELECT
                        Id 
                    FROM 
                        User
                    WHERE 
                        UserName LIKE 'userb_lms_%' LIMIT 1];
        User userC=[SELECT
                        Id 
                    FROM 
                        User 
                    WHERE 
                        UserName LIKE 'userc_lms_%' LIMIT 1];
        Date today=Date.today();
        // A is still on leave (Active)
        Leave__c leaveA=new Leave__c(OwnerId=userA.Id,Start_Date__c=today.addDays(10),End_Date__c=today.addDays(15),Status__c='Pending',Leave_Type__c='Earned_Leave');
        insert leaveA;
        leaveA.Start_Date__c=today.addDays(-2);
        leaveA.End_Date__c=today.addDays(5);
        leaveA.Status__c='Approved';
        update leaveA;
        // B's leave ended yesterday (Inactive)
        Leave__c leaveB=new Leave__c(OwnerId=userB.Id,Start_Date__c=today.addDays(20),End_Date__c=today.addDays(25),Status__c='Pending',Leave_Type__c='Earned_Leave');
        insert leaveB;
        leaveB.Start_Date__c=today.addDays(-5);
        leaveB.End_Date__c=today.addDays(-1);
        leaveB.Status__c='Approved';
        update leaveB;
        // Case is currently with C (delegated from A -> B -> C)
        Case c=new Case(Subject='Chain Case',OwnerId=userC.Id,Orginal_Owner_Id__c=userA.Id,Is_delegated__c=true,Status='New');
        insert c;
        List<Leave__c> inactivated=new List<Leave__c>{leaveB};
        List<Case> casesToUpdate=new List<Case>();
        Map<Id,List<Case>> mapReturnees=new Map<Id,List<Case>>();
        Map<Id,List<Case>> mapStopped=new Map<Id,List<Case>>();
        Map<Id,List<Case>> mapDelegates=new Map<Id,List<Case>>();
        Test.startTest();
        CaseReassignment.processInactivations(inactivated,casesToUpdate,mapReturnees,mapStopped,mapDelegates);
        if(!casesToUpdate.isEmpty()) update casesToUpdate;
        Test.stopTest();
        Case res=[SELECT
                        OwnerId 
                    FROM 
                        Case 
                    WHERE 
                        Id=:c.Id];
        System.assertEquals(userB.Id,res.OwnerId,'Case should move to B because B returned but A is still away');
        System.assert(mapDelegates.containsKey(userB.Id),'B should be in delegates email map');
    }
    @isTest
    static void testSendAllNotifications(){
        User userA=[SELECT
                            Id,Email 
                        FROM 
                            User 
                        WHERE 
                            UserName LIKE 'usera_lms_%' LIMIT 1];
        Map<Id,List<Case>> mapCases=new Map<Id,List<Case>>();
        mapCases.put(userA.Id,new List<Case>{ new Case(Subject='Test') });
        Test.startTest();
        CaseReassignment.sendAllNotifications(mapCases,mapCases,mapCases);
        Test.stopTest();
    }
}