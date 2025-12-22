/******************************************************************************************************************
 * @Author:          CRM Team Innovation
 * @ClassName:       CaseReassignment
 * @Description:     Reassigns cases for users based on their leave and sends email notifications.
 **************************************************************************************************************/
public without sharing class CaseReassignment{
    private static Id caseQueueId;
    private static Map<Id, User> allActiveUsersMap;
    /************************************************************************************************************************
    *@Author:          CRM Team Innovation
    *@methodName:      getCaseQueueId
    *@Description:     Helper method to get and cache the 'Case Queue' Id to avoid repeated SOQL queries.
     **************************************************************************************************************************/
    private static Id getCaseQueueId() {
        if(caseQueueId == null) {  
            caseQueueId=[SELECT 
                                Id 
                            FROM 
                                Group 
                            WHERE 
                                Name='Case Queue' 
                            AND 
                                Type='Queue' LIMIT 1].Id;
        } 
        return caseQueueId;
    }
    /************************************************************************************************************************
    *@Author:          CRM Team Innovation
    *@methodName:      getAllActiveUsers
    *@Description:     Helper method to get and cache all active users to avoid repeated SOQL queries.
     **************************************************************************************************************************/
    private static Map<Id, User> getAllActiveUsers() {
        if(allActiveUsersMap == null) {
            allActiveUsersMap=new Map<Id, User>([
                SELECT 
                    Id, Name, Email, DelegatedApproverId 
                FROM 
                    User 
                WHERE 
                    IsActive=true
            ]);
        }
        return allActiveUsersMap;
    }
    /************************************************************************************************************************
    *@Author:      CRM Team Innovation
    *@methodName:  buildCaseSummaryLines
    *@Description: Common helper to build "case details" text block for emails
     **************************************************************************************************************************/
    private static String buildCaseSummaryLines(List<Case> casesList){
        String body='';
        String baseUrl=URL.getOrgDomainUrl().toExternalForm();
        if(casesList==null){
            return body;
        }
        for(Case c:casesList){
            body+= 'Case Number: '+c.CaseNumber+'\n';
            body+= 'Subject: '+c.Subject+'\n';
            body+= 'Status: '+c.Status+'\n';
            body+= 'Priority: '+c.Priority+'\n';
            body+= 'Type: '+c.Type+'\n';
            body+= 'View Case: '+baseUrl+'/'+c.Id+'\n\n';
        }
        return body;
    }
    /************************************************************************************************************************
    *@Author:      CRM Team Innovation
    *@methodName:  getUsersOnLeave
    *@param:       userIds-Set of User Ids to check for active leave
    *@Description: Helper method to determine which users from a given set are currently on an active leave.
    *              Returns a map of UserId -> IsOnLeave(Boolean).
     **************************************************************************************************************************/
    private static Map<Id,Boolean> getUsersOnLeave(Set<Id> userIds){
        Map<Id,Boolean> userOnLeaveMap=new Map<Id,Boolean>();
        for(Id userId:userIds){
            userOnLeaveMap.put(userId,false);
        }
        Date today=Date.today();
        List<Leave__c> activeLeaves=[
            SELECT 
                OwnerId
            FROM 
                Leave__c
            WHERE 
                OwnerId IN :userIds
            AND 
                Status__c='Approved'
            AND 
                Start_Date__c <= :today
            AND 
                End_Date__c >= :today
        ];
        for(Leave__c leave:activeLeaves){
            userOnLeaveMap.put(leave.OwnerId,true);
        }
        return userOnLeaveMap;
    }
    /************************************************************************************************************************
    *@Author:      CRM Team Innovation
    *@methodName:  processActivations(Chain of Command - FORWARD)
    *@Description: Reassigns cases for users who are now on active leave.
    **************************************************************************************************************************/ 
    public static void processActivations(List<Leave__c> activatedLeaves,List<Case> casesToUpdate,Map<Id,List<Case>> emailsForDelegates){
        Set<Id> ownerIdsOnLeave=new Set<Id>();
        for(Leave__c leave:activatedLeaves){
            ownerIdsOnLeave.add(leave.OwnerId);
        }
        // 1. Fetch All Active Users
        Map<Id,User> allUsersMap=getAllActiveUsers();
        // 2. Optimization: Identify ONLY the users involved in the chain of command for these leaves
        Set<Id> involvedUserIds=getChainOfCommandUsers(ownerIdsOnLeave,allUsersMap);
        // 3. Query Leave Status ONLY for involved users 
        Map<Id,Boolean> usersOnLeaveStatus=getUsersOnLeave(involvedUserIds);
        Id queueId=getCaseQueueId();
        List<Case> casesToProcess=[
            SELECT 
                Id,OwnerId,Original_Owner__c,Is_delegated__c,CaseNumber,Subject,Status,Priority,Type 
            FROM 
                Case 
            WHERE 
                OwnerId IN :ownerIdsOnLeave 
            AND 
                IsClosed=false
        ];
        for(Case c:casesToProcess){
            // Calculate where the case should go based on the chain of command
            Id currentOwnerId=c.OwnerId;
            Id targetOwnerId=calculateTargetOwner(currentOwnerId,allUsersMap,usersOnLeaveStatus,queueId);
            if(targetOwnerId!=currentOwnerId){
                c.OwnerId=targetOwnerId;
                // If target is not the original owner,it is delegated
                c.Is_delegated__c=(targetOwnerId!=queueId); 
                if(c.Original_Owner__c==null){
                    c.Original_Owner__c=currentOwnerId;
                }
                casesToUpdate.add(c);
                if(c.Is_delegated__c&&String.valueOf(targetOwnerId.getSObjectType())=='User'){
                    if(!emailsForDelegates.containsKey(targetOwnerId)){
                        emailsForDelegates.put(targetOwnerId,new List<Case>());
                    }
                    emailsForDelegates.get(targetOwnerId).add(c);
                }
            }
        }
    }
    /************************************************************************************************************************
     * @Author:      CRM Team Innovation
     * @methodName:  calculateTargetOwner
     * @param1:      Id startUserId
     * @param2:      Map<Id,User> allUsersMap
     * @param3:      Map<Id,Boolean> usersOnLeaveStatus
     * @param4:      Id queueId
    *@Description: Core logic to traverse the chain of command and find the first available user.
    **************************************************************************************************************************/ 
    private static Id calculateTargetOwner(Id startUserId,Map<Id,User> allUsersMap,Map<Id,Boolean> usersOnLeaveStatus,Id queueId){
        Id currentId=startUserId;
        Set<Id> visitedIds=new Set<Id>();
        for(Integer i=0; i < 10; i++){
            if(visitedIds.contains(currentId)){
                break;
            }
            visitedIds.add(currentId);
            // If user is NOT on leave(and is not null),they are the target
            if(currentId!=null&&usersOnLeaveStatus.get(currentId)!=true){
                return currentId;
            }
            // If on leave,move to delegate
            User u=allUsersMap.get(currentId);
            if(u!=null&&u.DelegatedApproverId!=null){
                currentId=u.DelegatedApproverId;
            }else{
                // End of chain
                break;
            }
        }
        // Fallback to queue 
        return queueId;
    }
    /************************************************************************************************************************
     * @Author:      CRM Team Innovation
     * @methodName:  getChainOfCommandUsers
     * @param1:      Set<Id> startUserIds
     * @param2:      Map<Id,User> allUsersMap  
    *@Description: Helper to trace the delegation chain and return a Set of all involved User Ids.
    *              Used to filter the Leave__c query.
    **************************************************************************************************************************/ 
    private static Set<Id> getChainOfCommandUsers(Set<Id> startUserIds,Map<Id,User> allUsersMap){
        Set<Id> involvedUsers=new Set<Id>();
        for(Id startId:startUserIds){
            Id currentId=startId;
            for(Integer i=0; i < 10; i++){
                if(currentId==null || involvedUsers.contains(currentId)) break;
                involvedUsers.add(currentId);
                User u=allUsersMap.get(currentId);
                if(u==null) break;
                currentId=u.DelegatedApproverId;
            }
        }
        return involvedUsers;
    }
    /************************************************************************************************************************
    *@Author:      CRM Team Innovation
    *@methodName:  processInactivations(Chain of Command - RETURN)
    *@param1:      List<Leave__c> inactivatedLeaves
    *@param2:      List<Case> casesToUpdate
    *@param3:      Map<Id,List<Case>> emailsForReturnees
    *@param4:      Map<Id,List<Case>> emailsForStoppedDelegates
    *@Description: Reassigns cases back to their original owners who have returned from leave.
    **************************************************************************************************************************/ 
    public static void processInactivations(List<Leave__c> inactivatedLeaves,List<Case> casesToUpdate,Map<Id,List<Case>> emailsForReturnees,Map<Id,List<Case>> emailsForStoppedDelegates,Map<Id,List<Case>> emailsForDelegates){
        Set<Id> returneeIds=new Set<Id>();
        for(Leave__c leave:inactivatedLeaves){
            returneeIds.add(leave.OwnerId);
        }
        // 1. Build Upstream Map(Delegate -> List of Delegators) to find who delegates to these returnees
        Map<Id,User> allUsersMap=getAllActiveUsers();
        Map<Id,Set<Id>> delegateToDelegators=new Map<Id,Set<Id>>();
        for(User u:allUsersMap.values()){
            if(u.DelegatedApproverId!=null){
                if(!delegateToDelegators.containsKey(u.DelegatedApproverId)){
                    delegateToDelegators.put(u.DelegatedApproverId,new Set<Id>());
                }
                delegateToDelegators.get(u.DelegatedApproverId).add(u.Id);
            }
        }
        // 2. Identify "Impacted Original Owners"
        // If Charlie returns,we need to check cases for A and B if they delegate to C.
        Set<Id> impactedOriginalOwners=new Set<Id>();
        impactedOriginalOwners.addAll(returneeIds); // The returnees themselves
        // Traverse UP the chain(BFS) to find everyone who eventually delegates to a returnee
        // Ye loop check karta hai ki agar koi wapas aaya, toh uske upar waale logon ke cases pe kya asar padega.
        List<Id> queue=new List<Id>(returneeIds);
        Set<Id> visited=new Set<Id>(returneeIds);
        while(!queue.isEmpty()){
            Id current=queue.remove(0);
            if(delegateToDelegators.containsKey(current)){
                for(Id delegator:delegateToDelegators.get(current)){
                    if(!visited.contains(delegator)){
                        visited.add(delegator);
                        impactedOriginalOwners.add(delegator);
                        queue.add(delegator);
                    }
                }
            }
        }
        // 3. Prepare Downstream Logic(Availability Check) for the impacted owners
        Set<Id> involvedUsers=getChainOfCommandUsers(impactedOriginalOwners,allUsersMap);
        Map<Id,Boolean> usersOnLeaveStatus=getUsersOnLeave(involvedUsers);
        Id queueId=getCaseQueueId();
        // 4. Query Cases for ALL impacted original owners
        // Wo saare cases uthao jo delegated hain ya queue mein pade hain, taaki unhe sahi owner ke paas bhej sakein.
        List<Case> casesToReturn=[
            SELECT 
                Id,OwnerId,Original_Owner__c,Is_delegated__c,CaseNumber,Subject,Status,Priority,Type 
            FROM 
                Case 
            WHERE 
                Original_Owner__c 
            IN 
                :impactedOriginalOwners 
            AND 
                (Is_delegated__c=true OR OwnerId=:queueId) 
            AND 
                IsClosed=false
        ];
        // 5. Re-evaluate Chain of Command for each case
        // Har case ko check karte hain ki ab uska asli maalik kaun hona chahiye, kyunki log wapas aa gaye hain.
        for(Case c:casesToReturn){
            Id originalOwnerId=c.Original_Owner__c;
            Id currentOwnerId=c.OwnerId;
            // Recalculate who should own this case NOW
            Id targetOwnerId=calculateTargetOwner(originalOwnerId,allUsersMap,usersOnLeaveStatus,queueId);
            // If the calculated owner is different from the current owner,update it
            if(targetOwnerId!=currentOwnerId){
                c.OwnerId=targetOwnerId;
                if(targetOwnerId==queueId){
                    // Agar case Queue mein ja raha hai, toh use delegated mat maano, bas simple queue assignment hai.
                    c.Is_delegated__c=false;
                }else{
                    c.Is_delegated__c=(targetOwnerId!=originalOwnerId);
                }
                casesToUpdate.add(c);
                // Notification Logic
                if(targetOwnerId==originalOwnerId){
                    // Case returned to Original Owner
                    if(!emailsForReturnees.containsKey(targetOwnerId)){
                        emailsForReturnees.put(targetOwnerId,new List<Case>());
                    }
                    emailsForReturnees.get(targetOwnerId).add(c);
                }else if(String.valueOf(targetOwnerId.getSObjectType())=='User'){
                    // Case moved to a different Delegate(e.g.,Queue -> Charlie)
                    if(!emailsForDelegates.containsKey(targetOwnerId)){
                        emailsForDelegates.put(targetOwnerId,new List<Case>());
                    }
                    emailsForDelegates.get(targetOwnerId).add(c);
                }
                // Notify the person losing the case(Stopped Delegate)
                if(currentOwnerId!=null&&String.valueOf(currentOwnerId.getSObjectType())=='User'){
                    if(!emailsForStoppedDelegates.containsKey(currentOwnerId)){
                        emailsForStoppedDelegates.put(currentOwnerId,new List<Case>());
                    }
                    emailsForStoppedDelegates.get(currentOwnerId).add(c);
                }
            }
        }
    }
    /************************************************************************************************************************
    *@Author:      CRM Team Innovation
    *@methodName:  sendAllNotifications
    *@Description: Sends email notifications for delegated and returned cases.
    **************************************************************************************************************************/ 
    public static void sendAllNotifications(Map<Id,List<Case>> emailsForDelegates,Map<Id,List<Case>> emailsForReturnees,Map<Id,List<Case>> emailsForStoppedDelegates){
        Set<Id> allUserIds=new Set<Id>();
        if(emailsForDelegates!=null) allUserIds.addAll(emailsForDelegates.keySet());
        if(emailsForReturnees!=null) allUserIds.addAll(emailsForReturnees.keySet());
        if(emailsForStoppedDelegates!=null) allUserIds.addAll(emailsForStoppedDelegates.keySet());
        if(allUserIds.isEmpty()) return;
        Map<Id,User> allUserMap=new Map<Id,User>([SELECT 
                                                        Id,Name,Email 
                                                FROM 
                                                    User 
                                                WHERE 
                                                    Id 
                                                IN 
                                                    :allUserIds]);
        List<Messaging.SingleEmailMessage> emailList=new List<Messaging.SingleEmailMessage>();
        // 1. Emails to delegates for newly assigned cases(Active)
        if(emailsForDelegates!=null){
            for(Id delegateId:emailsForDelegates.keySet()){
                User delegatedUser=allUserMap.get(delegateId);
                if(delegatedUser==null||String.isBlank(delegatedUser.Email)){
                    continue;
                }
                List<Case> casesForDelegate=emailsForDelegates.get(delegateId);
                if(casesForDelegate==null||casesForDelegate.isEmpty()){
                    continue;
                }
                String subject='Reassigned Cases Summary';
                String body=
                    'Dear '+delegatedUser.Name+',\n\n'+
                    'The following cases have been reassigned to you as the delegated user for an employee on leave:\n\n'+
                    buildCaseSummaryLines(casesForDelegate)+
                    '\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';
                Messaging.SingleEmailMessage email=new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{delegatedUser.Email });
                email.setSubject(subject);
                email.setPlainTextBody(body);
                emailList.add(email);
            }
        }
        // 2. Emails to original owners for returned cases(Inactive)
        if(emailsForReturnees!=null){
            for(Id originalOwnerId:emailsForReturnees.keySet()){
                List<Case> returnedCases=emailsForReturnees.get(originalOwnerId);
                if(returnedCases==null||returnedCases.isEmpty()){
                    continue;
                }
                User originalUser=allUserMap.get(originalOwnerId);
                if(originalUser!=null&&!String.isBlank(originalUser.Email)){
                    String subjectOwner='Cases Reassigned Back to You';
                    String bodyOwner=
                        'Dear '+originalUser.Name+',\n\n'+
                        'Your leave has ended,and the following cases have been reassigned back to you:\n\n'+
                        buildCaseSummaryLines(returnedCases)+
                        '\nPlease review and handle accordingly.\n\nBest regards,\nLeave Management System';
                    Messaging.SingleEmailMessage email=new Messaging.SingleEmailMessage();
                    email.setToAddresses(new List<String>{originalUser.Email });
                    email.setSubject(subjectOwner);
                    email.setPlainTextBody(bodyOwner);
                    emailList.add(email);
                }
            }
        }
        // 3. Emails to delegates for returned cases(Inactive - Stopped Delegates)
        if(emailsForStoppedDelegates!=null){
            for(Id delegateId:emailsForStoppedDelegates.keySet()){
                List<Case> returnedCases=emailsForStoppedDelegates.get(delegateId);
                if(returnedCases==null||returnedCases.isEmpty()){
                    continue;
                }
                User delegatedUser=allUserMap.get(delegateId);
                if(delegatedUser!=null&&!String.isBlank(delegatedUser.Email)){
                    String subjectDelegate='Cases Reassigned Back to Original Owner';
                    String bodyDelegate=
                        'Dear '+delegatedUser.Name+',\n\n'+
                        'The leave period has ended,and the following cases have been reassigned back to the original owner:\n\n'+
                        buildCaseSummaryLines(returnedCases)+
                        '\nBest regards,\nLeave Management System';
                    Messaging.SingleEmailMessage email=new Messaging.SingleEmailMessage();
                    email.setToAddresses(new List<String>{delegatedUser.Email });
                    email.setSubject(subjectDelegate);
                    email.setPlainTextBody(bodyDelegate);
                    emailList.add(email);
                }
            }
        }
        if(!emailList.isEmpty()){
            try{
                Messaging.sendEmail(emailList,false);
            }catch(Exception ex){
                System.debug('Failed to send emails. Error: ' + ex.getMessage());
            }
        }
    }
}