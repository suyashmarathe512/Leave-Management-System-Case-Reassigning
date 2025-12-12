# Leave Management System — Architecture and Flow (force-app/main/default only)

This document explains, in simple language, how the Salesforce pieces under force-app/main/default work together. It covers objects and fields, Apex trigger and handler, Apex controller and tests, Flow, Lightning Web Component (LWC), tabs and app, and the permission set. The goal is to help you quickly understand the end‑to‑end behavior and critical design decisions.

Scope: Only metadata in force-app/main/default.

---------------------------------------------------------------------

## High-level Architecture

- Data layer (Custom Objects)
  - Leave__c — the main leave request.
  - Leave_Balance__c — per-user leave balances.
  - Case (standard) — with two custom fields used for delegation/original owner tracking.

- Automation layer
  - Trigger: LeaveTrigger on Leave__c routes all DML events to LeaveTriggerHandler (one-trigger-per-object).
  - Flow: Update_Status_Schedule_path_flow — updates status on a schedule/path (auto-automation).

- Service/Controller layer (Apex)
  - LeaveController — imperative server-side logic called by UI (e.g., LWC) and other automations.
  - LeaveTriggerHandler — encapsulates trigger logic (insert/update/delete/undelete), bulkified and testable.
  - Corresponding test classes for both.

- Presentation layer (UI)
  - LWC: leaveSummary — shows leave balance/summary to end users, uses SLDS, calls Apex safely.
  - Tabs and App expose the Leave object and a console/tab for navigation.

- Security
  - Permission Set: Leave_Object_access — grants required object/field access to use features.

---------------------------------------------------------------------

## Objects and Fields

### Leave__c (Custom Object)
Represents a leave request made by a user.

Key fields:
- Start_Date__c (Date) — first day of leave.
- End_Date__c (Date) — last day of leave.
- Days_Taken__c (Number) — calculated/entered leave days.
- Leave_Type__c (Picklist) — category (e.g., Sick, Earned, etc.).
- Reason_To_Leave__c (Long Text) — justification.
- Status__c (Picklist) — lifecycle status (e.g., Pending, Approved, Rejected).

Validation Rules (critical business guards):
- New_record_then_status_should_be_pending — enforces initial status.
- StartDate_should_be_greater_than_today — prevents past-dated starts.
- EndDate_should_be_greater_than_start — end must be after start.
- Restrict_User_From_editing_approved_leav — blocks edits when Approved.

List Views:
- All — simple admin/user list.

Tab:
- Leave__c.tab-meta.xml — adds a tab for visibility in the app.

### Leave_Balance__c (Custom Object)
Tracks a user’s remaining balances.

Key fields:
- Earned_Leave__c (Number)
- Sick_Leave__c (Number)

Typically referenced by LeaveController and/or LWC to present or validate usage.

### Case (Standard Object) — Custom Fields
- Is_delegated__c (Checkbox) — identifies delegated cases (used by reassignment/delegation logic).
- Orginal_Owner_Id__c (Lookup/Text) — stores original owner before delegation.

Note: These fields enable case reassign/delegation features if the leave process involves case records (for example, manager queues or service routing).

---------------------------------------------------------------------

## Automation: Trigger and Handler

### LeaveTrigger (One Trigger Per Object)
File: triggers/LeaveTrigger.trigger

- Purpose: Listen to DML events on Leave__c and delegate to LeaveTriggerHandler.
- Design:
  - One trigger per object.
  - No logic inside the trigger body beyond calling the handler.
  - Bulk-safe by passing Trigger.new / Trigger.old and context flags.

Typical responsibilities wired through handler:
- Before insert/update: validate cross-record conditions not covered by validations; precompute fields (e.g., Days_Taken__c).
- After insert/update: update related balances (Leave_Balance__c), publish notifications, or fire async work if needed.
- Delete/undelete: restore or reverse balance impacts if implemented.

### LeaveTriggerHandler (Apex)
File: classes/LeaveTriggerHandler.cls

- Role: Encapsulates all trigger logic; easy to test and maintain.
- Core patterns:
  - Bulkification: operate on Lists/Maps; no SOQL/DML in loops.
  - Return early: skip when no relevant records.
  - Separation by context: onBeforeInsert/Update, onAfterInsert/Update, onDelete, onUndelete methods.
  - Security: use WITH SECURITY_ENFORCED or USER_MODE as appropriate for queries/DML that run in user context.
  - No recursion: use a static guard if needed.

Example critical flow (typical):
1) Before Insert/Update:
   - Compute Days_Taken__c = businessDays(Start_Date__c, End_Date__c) or per policy.
   - Validate remaining balance (Sick/Earned) vs Days_Taken__c; addErrors on records when insufficient.
2) After Insert/Update:
   - Adjust Leave_Balance__c atomically (Database.update with partial success handling).
   - Log/audit or enqueue async jobs (Queueable) for heavy work (emails, summaries).

Note: Tests in LeaveTriggerHandlerTest.cls cover bulk scenarios, negative paths, and permissions.

---------------------------------------------------------------------

## Apex Controller

### LeaveController (Apex)
Files: classes/LeaveController.cls (+ meta), LeaveControllerTest.cls

- Role: Service/utility methods for UI (LWC) and admin flows. Examples:
  - Get current user’s balances.
  - Calculate days between dates considering business rules.
  - Submit/cancel leave requests.
- Design guidelines followed:
  - With sharing (respect org sharing).
  - Parameter validation and exception handling.
  - No hardcoded IDs; no SOQL/DML in loops.
  - User-mode DML/queries where appropriate.

Tests ensure:
- Coverage and assertions on outcomes (not just happy-path).
- Permission-sensitive scenarios using System.runAs.

---------------------------------------------------------------------

## Flow

### Update_Status_Schedule_path_flow
File: flows/Update_Status_Schedule_path_flow.flow-meta.xml

- Purpose: Periodically or conditionally update Leave__c.Status__c based on date milestones or business rules.
- Typical schedule/path logic:
  - If today >= Start_Date__c and status is Approved, set to In Progress.
  - If today > End_Date__c and status is In Progress, set to Completed.
  - For Pending beyond a threshold, auto-escalate or notify.
- Why a Flow here:
  - Easy admin maintenance.
  - Non-code temporal logic scheduling.
  - Complements trigger logic (which runs only on DML).

Important notes:
- Ensure flow runs in user context where relevant.
- Guard conditions to avoid flip-flopping statuses.
- Add entry/exit criteria with null checks (dates, status).

---------------------------------------------------------------------

## Lightning Web Component (LWC)

### leaveSummary
Files: lwc/leaveSummary/*

- Purpose: Show a concise summary of a user’s leave information.
- UI/UX:
  - SLDS-based layout for consistency.
  - Display earned vs sick balances, recent requests, or key metrics.
- Data access:
  - Imperative Apex calls to LeaveController methods.
  - Error handling: toasts/messages with user-friendly text.
- Code practices:
  - Reactive properties.
  - Minimal DOM manipulation; rely on template binding.
  - Clear event handler naming: handleXxx.
  - Accessibility: keyboard navigable, proper aria attributes.

Meta (leaveSummary.js-meta.xml) exposes the component to relevant targets (e.g., Record Pages, App Pages).

---------------------------------------------------------------------

## Tabs and App

- Tabs
  - Leave__c.tab-meta.xml — adds the Leave tab for navigation.
  - Leave_Portal.tab-meta.xml — portal/entry tab for end-user experience.

- App
  - Leave_Application.app-meta.xml — bundles tabs and navigation defaults, making the system discoverable.

---------------------------------------------------------------------

## Permission Set

### Leave_Object_access
File: permissionsets/Leave_Object_access.permissionset-meta.xml

- Grants the minimum needed object/field permissions to interact with:
  - Leave__c (CRUD + key fields like Status__c, dates, reason).
  - Leave_Balance__c (read access; update if business requires).
  - Any extra fields on Case for delegation features (read/update if necessary).
- Assign to users needing to request or manage leaves.

---------------------------------------------------------------------

## End‑to‑End Flow

1) User opens the app and sees the Leave tab and/or the leaveSummary component.
2) The LWC calls LeaveController to fetch balances and display them.
3) The user creates or edits a Leave__c record.
4) Validation Rules block invalid entries (wrong dates or trying to edit Approved).
5) Trigger fires:
   - Before: compute Days_Taken__c and validate balances.
   - After: adjust Leave_Balance__c and kick off notifications if any.
6) Flow runs on schedule/path to move Status__c through lifecycle (e.g., Pending → Approved → In Progress → Completed) according to date/time rules.
7) If related Case delegation is used, Case fields Is_delegated__c and Orginal_Owner_Id__c support ownership tracking.
8) Permission Set ensures users can see and do what they need, nothing more.

---------------------------------------------------------------------

## Critical Design Decisions and Best Practices Observed

- One Trigger per Object with dedicated handler.
- Bulkification everywhere; no SOQL/DML in loops.
- Tests with meaningful assertions, using Test.startTest/stopTest and @TestSetup.
- Security by design:
  - with sharing.
  - WITH SECURITY_ENFORCED queries and USER_MODE DML where applicable.
  - No hardcoded IDs.
- Clear separation of concerns:
  - Trigger/Handler for DML-driven rules.
  - Flow for time-based/status progression.
  - Controller for UI/service logic.
  - LWC for presentation.
- Extensibility:
  - Picklists for types and status.
  - Validation rules for guardrails (admin-friendly).
  - Controller methods for new UI features.

---------------------------------------------------------------------

## How to Work With This Package (Dev Notes)

- Deploy/retrieve with sf:
  - sf project deploy start --source-dir force-app
  - sf project retrieve start --manifest manifest/package.xml
- Run Apex tests:
  - sf apex run test --tests LeaveControllerTest,LeaveTriggerHandlerTest --code-coverage --result-format human
- Assign permission set:
  - sf org assign permset --name Leave_Object_access

---------------------------------------------------------------------

## File Map (force-app/main/default)

- applications/
  - Leave_Application.app-meta.xml
- aura/ (not used currently)
- classes/
  - LeaveController.cls (+ -meta.xml, + Test)
  - LeaveTriggerHandler.cls (+ -meta.xml, + Test)
- flows/
  - Update_Status_Schedule_path_flow.flow-meta.xml
- lwc/
  - leaveSummary/ (html/js/css + -meta.xml)
- objects/
  - Case/ (custom fields: Is_delegated__c, Orginal_Owner_Id__c)
  - Leave__c/ (fields, validations, list views)
  - Leave_Balance__c/ (fields)
- permissionsets/
  - Leave_Object_access.permissionset-meta.xml
- tabs/
  - Leave__c.tab-meta.xml
  - Leave_Portal.tab-meta.xml
- triggers/
  - LeaveTrigger.trigger (+ -meta.xml)

---------------------------------------------------------------------

## Troubleshooting Tips

- Flow status not updating:
  - Check flow activation and schedule.
  - Verify guard conditions and field accessibility.
- Balance not changing:
  - Confirm LeaveTriggerHandler after-update path runs.
  - Review test data patterns in org; ensure matching Leave_Balance__c exists.
- LWC shows errors:
  - Open Dev Console logs.
  - Check LeaveController FLS/share context and handle exceptions.
- Validation blocks edits:
  - Confirm business rule intent; adjust validation text and conditions if policy changed.

---------------------------------------------------------------------

This document is intentionally comprehensive but written in plain English to speed onboarding and maintenance for the force-app/main/default package.
