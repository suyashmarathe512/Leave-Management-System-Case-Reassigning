# Leave Management and Case Reassignment System

This document explains the architecture of the Leave Management and Case Reassignment system, focusing on the metadata within the `force-app/main/default` directory. It is designed to help developers and administrators understand the objects, automation, and logic that drive the application.

## High-level Architecture

The system is built on a standard Salesforce declarative and programmatic model:

-   **Data Layer (Custom Objects)**: `Leave__c` for requests, `Leave_Balance__c` for balances, and custom fields on the standard `Case` object for delegation.
-   **Automation Layer (Triggers & Flows)**:
    -   An Apex trigger on `Leave__c` (`LeaveTrigger`) manages leave-related logic.
    -   An Apex trigger on `Case` (`CaseTrigger`) handles automatic case reassignment for users on leave.
-   **Service Layer (Apex Classes)**: Handler classes (`LeaveTriggerHandler`, `CaseTriggerHandler`) contain the core logic, and a controller (`LeaveController`) provides methods for the UI.
-   **Presentation Layer (UI)**: A Lightning Web Component (`leaveSummary`) displays leave information to users.
-   **Security Layer (Permission Set)**: A permission set (`Leave_Object_access`) grants access to the system's features.

---

## Objects and Fields

### Leave__c (Custom Object)

Represents a single leave request made by a user.

-   **Key Fields**: `Start_Date__c`, `End_Date__c`, `Leave_Type__c`, `Status__c` (Pending, Approved, Rejected), `Reason_To_Leave__c`.
-   **Validation Rules**:
    -   Ensures status is 'Pending' on creation.
    -   Start Date cannot be in the past.
    -   End Date must be after Start Date.
    -   Approved leave records are locked from editing.

### Leave_Balance__c (Custom Object)

Tracks a user’s available leave balances (e.g., `Earned_Leave__c`, `Sick_Leave__c`). This is typically referenced by the `LeaveTriggerHandler` to validate requests.

### Case (Standard Object) - Customizations

The standard Case object is customized to support automatic reassignment.

-   **Key Fields**:
    -   `Is_delegated__c` (Checkbox): A flag indicating that the case has been automatically reassigned because the original owner is on leave.
    -   `Orginal_Owner_Id__c` (Text/Lookup): Stores the ID of the owner to whom the case was originally assigned before delegation. This ensures the case can be returned to the original owner after their leave ends.
    -   `Previous_Owner_Id__c` (Text/Lookup): Tracks the immediately previous owner when a case is manually reassigned.

---

## Automation

### Leave Automation

#### LeaveTrigger and LeaveTriggerHandler

-   **Purpose**: Manages all business logic for the `Leave__c` object, following a one-trigger-per-object pattern.
-   **`LeaveTrigger.trigger`**: A simple trigger that delegates all `before` and `after` events (insert, update, delete) to the `LeaveTriggerHandler`.
-   **`LeaveTriggerHandler.cls`**:
    -   **Before Save**: Validates that the user has a sufficient leave balance for the request.
    -   **After Save**: When a leave is 'Approved', this handler reassigns all of the user's open cases to their manager. It also handles returning delegated cases to a user when they are no longer on leave (e.g., leave is cancelled or rejected).

### Case Reassignment Automation

#### CaseTrigger and CaseTriggerHandler

-   **Purpose**: Automatically reassigns cases that are created for or assigned to a user who is currently on an approved leave.
-   **`CaseTrigger.trigger`**: Fires on `after insert` and `after update` to check if the case owner is on leave. It also fires on `before update` to track ownership changes.
-   **`CaseTriggerHandler.cls`**:
    -   `trackPreviousOwner`: Before a case is updated, it records the previous owner in `Previous_Owner_Id__c` if the owner is being changed.
    -   `reassignCasesForUsersOnLeave`: After a case is created or updated, it checks if the owner is on an active, approved leave. If so, it cleverly re-uses the `LeaveTriggerHandler`'s reassignment logic to delegate the case to the user's manager, marking the case as delegated.

## Presentation Layer (LWC)

### leaveSummary

A simple Lightning Web Component that calls the `LeaveController` to display the current user's leave balances and potentially a summary of their requests.

---

## Security

### Leave_Object_access (Permission Set)

Grants users the necessary CRUD permissions for `Leave__c`, `Leave_Balance__c`, and the custom fields on `Case` to use the application.

---

## End-to-End Flow Example

1.  **User on Leave**: A User (e.g., 'User A') submits a `Leave__c` request for next week. Their manager approves it. The `Status__c` becomes 'Approved'.
2.  **Case Reassignment on Approval**: The `LeaveTriggerHandler` immediately queries for all open Cases owned by 'User A' and reassigns them to User A's manager. It sets `Is_delegated__c` to `true` and populates `Orginal_Owner_Id__c` with User A's ID.
3.  **New Case Arrives**: The next day, a new `Case` is created and assigned to 'User A'.
4.  **Automatic Delegation**: The `CaseTrigger` fires. The `CaseTriggerHandler` checks if 'User A' is on an approved leave. Since they are, it reassigns this new case to User A's manager and flags it as delegated.
5.  **User Returns**: User A's leave is cancelled or ends. The `LeaveTriggerHandler` finds all cases where `Orginal_Owner_Id__c` is User A and reassigns them back.

---

## Project Structure (`force-app/main/default`)

```
├── applications/
│   └── Leave_Application.app-meta.xml
├── classes/
│   ├── CaseTriggerHandler.cls
│   ├── LeaveController.cls (+ Test)
│   └── LeaveTriggerHandler.cls (+ Test)
├── lwc/
│   └── leaveSummary/
├── objects/
│   ├── Case/ (Custom Fields)
│   ├── Leave__c/ (Fields, Validations)
│   └── Leave_Balance__c/ (Fields)
├── permissionsets/
│   └── Leave_Object_access.permissionset-meta.xml
├── tabs/
│   ├── Leave__c.tab-meta.xml
│   └── Leave_Portal.tab-meta.xml
└── triggers/
    ├── CaseTrigger.trigger
    └── LeaveTrigger.trigger
```
