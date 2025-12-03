public with sharing class LeaveTriggerHandler {
    public static void handleBeforeInsertUpdate(List<Leave__c> newLeaves) {
        Set<Id> ownerIds = new Set<Id>();
        for(Leave__c leave : newLeaves) {
            if(leave.OwnerId != null) {
                ownerIds.add(leave.OwnerId);
            }
        }
        if(ownerIds.isEmpty()) {
            return;
        }
        Map<Id, Leave_Balance__c> balanceMap = new Map<Id, Leave_Balance__c>();
        List<Leave_Balance__c> balances = [
            SELECT 
                Id, SetupOwnerId, Earned_Leave__c, Sick_Leave__c 
            FROM 
                Leave_Balance__c 
            WHERE 
                SetupOwnerId IN :ownerIds 
        ];
        
        for(Leave_Balance__c balance : balances) {
            balanceMap.put(balance.SetupOwnerId, balance);
        }
        Map<Id, Decimal> earnedBookedMap = new Map<Id, Decimal>();
        Map<Id, Decimal> sickBookedMap = new Map<Id, Decimal>();
        List<AggregateResult> bookedLeaves = [
            SELECT 
                OwnerId, 
                SUM(Booked_Earned_Leaves__c) earnedSum, 
                SUM(Booked_Sick_Leaves__c) sickSum
            FROM 
                Leave__c 
            WHERE 
                OwnerId IN :ownerIds
            GROUP BY 
                OwnerId
        ];
        for(AggregateResult ar : bookedLeaves) {
            Id ownerId = (Id)ar.get('OwnerId');
            Decimal earnedSum = (Decimal)ar.get('earnedSum');
            Decimal sickSum = (Decimal)ar.get('sickSum');
            earnedBookedMap.put(ownerId, earnedSum != null ? earnedSum : 0);
            sickBookedMap.put(ownerId, sickSum != null ? sickSum : 0);
        }
        // Ensure every ownerId has a default of 0 to avoid NullPointer on map.get
        for (Id oid : ownerIds) {
            if (!earnedBookedMap.containsKey(oid)) {
                earnedBookedMap.put(oid, 0);
            }
            if (!sickBookedMap.containsKey(oid)) {
                sickBookedMap.put(oid, 0);
            }
        }
        for(Leave__c leave : newLeaves) {
            if(leave.OwnerId != null && leave.Start_Date__c != null && leave.End_Date__c != null) {
                Integer numberOfDays = leave.End_Date__c.daysBetween(leave.Start_Date__c) + 1;
                if(leave.Leave_Type__c == 'Earned_Leave' || leave.Leave_Type__c == 'Sick_Leave') {
                    Leave_Balance__c balance = balanceMap.get(leave.OwnerId);
                    Boolean isBalanceSufficient = true;
                    if(balance != null) {  
                        Decimal availableBalance = 0;
                        if(leave.Leave_Type__c == 'Earned_Leave') {
                            availableBalance = balance.Earned_Leave__c - (earnedBookedMap.containsKey(leave.OwnerId) ? earnedBookedMap.get(leave.OwnerId) : 0);
                            if(numberOfDays > availableBalance) {
                                isBalanceSufficient = false;
                            }
                        } else if(leave.Leave_Type__c == 'Sick_Leave') {
                            availableBalance = balance.Sick_Leave__c - (sickBookedMap.containsKey(leave.OwnerId) ? sickBookedMap.get(leave.OwnerId) : 0);
                            if(numberOfDays > availableBalance) {
                                isBalanceSufficient = false;
                            }
                        }
                    }else {
                        isBalanceSufficient = false;
                    }
                    if(!isBalanceSufficient) {
                        leave.Leave_Type__c = 'Unpaid_Leave';
                    }
                }
            }
        }
        List<Leave__c> existingLeaves = [
            SELECT 
                Id, OwnerId, Status__c 
            FROM 
                Leave__c 
            WHERE 
                OwnerId IN :ownerIds 
        ];
        Map<Id, List<Leave__c>> ownerToLeavesMap = new Map<Id, List<Leave__c>>();
        for(Leave__c existingLeave : existingLeaves) {
            if(!ownerToLeavesMap.containsKey(existingLeave.OwnerId)) {
                ownerToLeavesMap.put(existingLeave.OwnerId, new List<Leave__c>());
            }
            ownerToLeavesMap.get(existingLeave.OwnerId).add(existingLeave);
        }
        for(Leave__c leave : newLeaves) {
            if(leave.OwnerId != null) {
                List<Leave__c> ownerLeaves = ownerToLeavesMap.get(leave.OwnerId);
                Boolean isActiveLeave = (leave.Status__c != null && leave.Status__c == 'Active');
                if(Trigger.isInsert) {
                        if(isActiveLeave) {
                        if(ownerLeaves != null) {
                            for(Leave__c existingLeave : ownerLeaves) {
                                if(existingLeave.Status__c != null && existingLeave.Status__c == 'Active') {
                                    leave.addError('Only one active leave record is allowed per employee.');
                                    break;
                                }
                            }
                        }
                    }
                        }
                if(Trigger.isUpdate) {
                        if(isActiveLeave) {
                        if(ownerLeaves != null) {
                            Integer activeCount = 0;
                            for(Leave__c existingLeave : ownerLeaves) {
                                if(existingLeave.Status__c != null && existingLeave.Status__c == 'Active') {
                                    if(existingLeave.Id != leave.Id) {
                                        activeCount++;
                                    }
                                }
                            }
                            if(activeCount > 0) {
                                leave.addError('Only one active leave record is allowed per employee.');
                            }
                        }
                    }
                }
            }
        }
        populateDelegatedApproverIds(newLeaves);
    }
    private static void populateDelegatedApproverIds(List<Leave__c> leaves) {
        Set<Id> ownerIds = new Set<Id>();
        for(Leave__c leave : leaves) {
            if(leave.OwnerId != null) {
                ownerIds.add(leave.OwnerId);
            }
        }
        if(ownerIds.isEmpty()) {
            return;
        }
        List<User> users = [
            SELECT Id, ManagerId 
            FROM User 
            WHERE Id IN :ownerIds
            WITH USER_MODE
        ];
        Map<Id, Id> userIdToManagerIdMap = new Map<Id, Id>();
        for(User user : users) {
            userIdToManagerIdMap.put(user.Id, user.ManagerId);
        }
        for(Leave__c leave : leaves) {
            if(leave.OwnerId != null && leave.DelegatedApproverId__c == null) {
                if (userIdToManagerIdMap.containsKey(leave.OwnerId) && userIdToManagerIdMap.get(leave.OwnerId) != null) {
                    leave.DelegatedApproverId__c = userIdToManagerIdMap.get(leave.OwnerId);
                }
            }
        }
    }
    private static Boolean isAlreadyRunning = false;
    public static void submitNewLeavesForApproval(List<Leave__c> newLeaves) {
        if (isAlreadyRunning) return;
        isAlreadyRunning = true;
        for (Leave__c leave : newLeaves) {
            if (leave.Status__c == 'Pending') {
                Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(leave.Id);
                req.setComments('New leave record submitted for approval.');
                req.setProcessDefinitionNameOrId('Leave_Approval_Process');
                Approval.ProcessResult result = Approval.process(req);
                if (!result.isSuccess()) {
                    System.debug('Approval failed for ' + leave.Id + ': '
                        + result.getErrors());
                }
            }
        }
    }

    public static void handleAfterUpdate(List<Leave__c> newLeaves, Map<Id, Leave__c> oldMap) {
        List<Leave__c> activatedLeaves = new List<Leave__c>();
        List<Leave__c> inactivatedLeaves = new List<Leave__c>();
        for (Leave__c leave : newLeaves) {
            Leave__c oldLeave = oldMap.get(leave.Id);
            if (leave.Status__c == 'Active' && oldLeave.Status__c != 'Active') {
                activatedLeaves.add(leave);
            }
            if (leave.Status__c == 'Inactive' && oldLeave.Status__c != 'Inactive') {
                inactivatedLeaves.add(leave);
            }
        }
        // Handle activation
        if (!activatedLeaves.isEmpty()) {
            Set<Id> ownerIds = new Set<Id>();
            for (Leave__c leave : activatedLeaves) {
                ownerIds.add(leave.OwnerId);
            }

            // Query open cases owned by these users
            List<Case> openCases = [
                SELECT
                    Id, CaseNumber, OwnerId, Orginal_Owner_Id__c
                FROM
                    Case
                WHERE
                    OwnerId IN :ownerIds AND IsClosed = false
            ];
            Map<Id, List<Case>> ownerToCasesMap = new Map<Id, List<Case>>();
            for (Case c : openCases) {
                if (!ownerToCasesMap.containsKey(c.OwnerId)) {
                    ownerToCasesMap.put(c.OwnerId, new List<Case>());
                }
                ownerToCasesMap.get(c.OwnerId).add(c);
            }
            List<Case> casesToUpdate = new List<Case>();
            Map<Id, List<Case>> delegatedToCasesMap = new Map<Id, List<Case>>();
            for (Leave__c leave : activatedLeaves) {
                List<Case> userCases = ownerToCasesMap.get(leave.OwnerId);
                if (userCases != null && leave.DelegatedApproverId__c != null) {
                    for (Case c : userCases) {
                        c.OwnerId = leave.DelegatedApproverId__c;
                        c.Orginal_Owner_Id__c = leave.OwnerId; // Store original owner
                        c.Is_delegated__c = true;
                        casesToUpdate.add(c);
                        if (!delegatedToCasesMap.containsKey(leave.DelegatedApproverId__c)) {
                            delegatedToCasesMap.put(leave.DelegatedApproverId__c, new List<Case>());
                        }
                        delegatedToCasesMap.get(leave.DelegatedApproverId__c).add(c);
                    }
                }
            }
            if (!casesToUpdate.isEmpty()) {
                Database.update(casesToUpdate, false);
            }
            // Send emails to delegated users
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            Set<Id> delegatedIds = delegatedToCasesMap.keySet();
            Map<Id, User> userMap = new Map<Id, User>([
                SELECT Id, Email, Name
                FROM User
                WHERE Id IN :delegatedIds
            ]);

            for (Id delegatedId : delegatedIds) {
                User delegatedUser = userMap.get(delegatedId);
                if (delegatedUser != null && delegatedUser.Email != null) {
                    List<Case> reassignedCases = delegatedToCasesMap.get(delegatedId);
                    String subject = 'Reassigned Cases Summary';
                    String body = 'Dear ' + delegatedUser.Name + ',\n\nThe following cases have been reassigned to you as the delegated user for an employee on leave:\n\n';
                    for (Case c : reassignedCases) {
                        body += 'Case Number: ' + c.CaseNumber + '\n';
                    }
                    body += '\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setToAddresses(new String[]{delegatedUser.Email});
                    email.setSubject(subject);
                    email.setPlainTextBody(body);
                    emails.add(email);
                }
            }
            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails);
            }
        }
        // Handle inactivation
        if (!inactivatedLeaves.isEmpty()) {
            Set<Id> delegatedIds = new Set<Id>();
            for (Leave__c leave : inactivatedLeaves) {
                if (leave.DelegatedApproverId__c != null) {
                    delegatedIds.add(leave.DelegatedApproverId__c);
                }
            }
            // Query open delegated cases owned by delegated users
            List<Case> delegatedCases = [
                SELECT
                    Id, CaseNumber, OwnerId, Orginal_Owner_Id__c
                FROM
                    Case
                WHERE
                    OwnerId IN :delegatedIds AND Is_delegated__c = true AND IsClosed = false
            ];
            Map<Id, List<Case>> delegatedToCasesMap = new Map<Id, List<Case>>();
            for (Case c : delegatedCases) {
                if (!delegatedToCasesMap.containsKey(c.OwnerId)) {
                    delegatedToCasesMap.put(c.OwnerId, new List<Case>());
                }
                delegatedToCasesMap.get(c.OwnerId).add(c);
            }
            List<Case> casesToReassign = new List<Case>();
            Map<Id, List<Case>> originalToCasesMap = new Map<Id, List<Case>>();
            for (Leave__c leave : inactivatedLeaves) {
                List<Case> userCases = delegatedToCasesMap.get(leave.DelegatedApproverId__c);
                if (userCases != null) {
                    for (Case c : userCases) {
                        if (c.Orginal_Owner_Id__c == leave.OwnerId) { // Ensure it's for this leave
                            c.OwnerId = c.Orginal_Owner_Id__c;
                            c.Is_delegated__c = false;
                            c.Orginal_Owner_Id__c = null;
                            casesToReassign.add(c);
                            if (!originalToCasesMap.containsKey(c.OwnerId)) {
                                originalToCasesMap.put(c.OwnerId, new List<Case>());
                            }
                            originalToCasesMap.get(c.OwnerId).add(c);
                        }
                    }
                }
            }
            if (!casesToReassign.isEmpty()) {
                Database.update(casesToReassign, false);
            }
            // Send confirmation emails to both original owners and delegated users
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            Set<Id> allUserIds = new Set<Id>();
            for (Leave__c leave : inactivatedLeaves) {
                allUserIds.add(leave.OwnerId);
                if (leave.DelegatedApproverId__c != null) {
                    allUserIds.add(leave.DelegatedApproverId__c);
                }
            }
            Map<Id, User> userMap = new Map<Id, User>([
                SELECT Id, Email, Name
                FROM User
                WHERE Id IN :allUserIds
            ]);

            for (Leave__c leave : inactivatedLeaves) {
                User originalUser = userMap.get(leave.OwnerId);
                User delegatedUser = userMap.get(leave.DelegatedApproverId__c);
                List<Case> reassignedCases = originalToCasesMap.get(leave.OwnerId);
                if (reassignedCases != null && !reassignedCases.isEmpty()) {
                    // Email to original owner
                    if (originalUser != null && originalUser.Email != null) {
                        String subject = 'Cases Reassigned Back to You';
                        String body = 'Dear ' + originalUser.Name + ',\n\nYour leave has ended, and the following cases have been reassigned back to you:\n\n';
                        for (Case c : reassignedCases) {
                            body += 'Case Number: ' + c.CaseNumber + '\n';
                        }
                        body += '\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';
                        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                        email.setToAddresses(new String[]{originalUser.Email});
                        email.setSubject(subject);
                        email.setPlainTextBody(body);
                        emails.add(email);
                    }
                    // Email to delegated user
                    if (delegatedUser != null && delegatedUser.Email != null) {
                        String subject = 'Cases Reassigned Back to Original Owner';
                        String body = 'Dear ' + delegatedUser.Name + ',\n\nThe leave period has ended, and the following cases have been reassigned back to the original owner:\n\n';
                        for (Case c : reassignedCases) {
                            body += 'Case Number: ' + c.CaseNumber + '\n';
                        }
                        body += '\nBest regards,\nLeave Management System';
                        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                        email.setToAddresses(new String[]{delegatedUser.Email});
                        email.setSubject(subject);
                        email.setPlainTextBody(body);
                        emails.add(email);
                    }
                }
            }
            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails);
            }
        }
    }
}
