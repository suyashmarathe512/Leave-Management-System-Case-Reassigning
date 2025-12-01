# Leave-Management-System-Case-Reassigning
Users must create a Leave record before their leave period, specifying the dates,  status, and cases with the delegated user.
# Problem Statement
Leave Management and Case Reassignment System
1) Users must create a Leave record before their leave period, specifying the dates, 
status, and cases with the delegated user.
2) The system must enforce only one Active Leave record per user at any time.
On the Start Date, the Leave record automatically becomes Active.
3) All open (non-closed) cases owned by the user should be reassigned to the Delegated 
User when the leave starts. The Delegated User should receive an email summarising 
the reassigned cases.
4) When the End Date is reached, the Leave record should automatically become 
Inactive. All still-open (non-closed) cases that were reassigned should be returned to 
the original owner when the leave ends.
5) Both the original user and the Delegated User should receive a confirmation email 
about the case reassignment at the end of the leave period.
6) Implement automation using Salesforce flows, triggers, or Apex to handle record 
status changes, case reassignments, and notifications.
7) Create a user-friendly interface for users to create, view, and manage Leave records 
and associated cases.
8) Ensure only authorised users can create or modify Leave records and view/reassign 
cases based on their role.
9) Create a report and a dashboard to display the cases with their respective owners.
Note: Use Standard Objects and Create New Custom Object if needed
