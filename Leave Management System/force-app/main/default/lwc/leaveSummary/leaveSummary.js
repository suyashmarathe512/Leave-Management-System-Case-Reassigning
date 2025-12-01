import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLeaveBalances from '@salesforce/apex/LeaveController.getLeaveBalances';
import getMyLeaves from '@salesforce/apex/LeaveController.getMyLeaves';

const COLUMNS = [
    { label: 'Request Id', fieldName: 'Name' },
    {
        label: 'Start Date',
        fieldName: 'Start_Date__c',
        type: 'date',
        typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' }
    },
    {
        label: 'End Date',
        fieldName: 'End_Date__c',
        type: 'date',
        typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' }
    },
    { label: 'Leave Type', fieldName: 'Leave_Type__c' },
    { label: 'Status', fieldName: 'Status__c' },
    { label: 'Reason', fieldName: 'Reason_To_Leave__c' },
    { label: 'Days Taken', fieldName: 'Days_Taken__c', type: 'number' },
    { label: 'Available Earned', fieldName: 'Available_earned_leaves__c', type: 'number' },
    { label: 'Available Sick', fieldName: 'Available_sick_leaves__c', type: 'number' },
    { label: 'Booked Earned', fieldName: 'Booked_Earned_Leaves__c', type: 'number' },
    { label: 'Booked Sick', fieldName: 'Booked_sick_leaves__c', type: 'number' },
    { label: 'Booked Unpaid', fieldName: 'Booked_unpaid_leave__c', type: 'number' }
];

export default class LeaveManagementApp extends NavigationMixin(LightningElement) {
    columns = COLUMNS;

    // balances
    earned = 0;
    sick = 0;

    // wire leave balances
    @wire(getLeaveBalances)
    wiredBalances({ error, data }) {
        if (data) {
            this.earned = data.earned || 0;
            this.sick = data.sick || 0;
        } else if (error) {
            // Keep UI simple; if needed, add toast
            console.error('Error loading balances', error);
        }
    }

    // wire leave records
    @wire(getMyLeaves)
    leaves;

    get tableError() {
        return this.leaves && this.leaves.error
            ? (this.leaves.error.body && this.leaves.error.body.message)
            : 'Error loading leave records';
    }

    // Open standard New Leave__c record page (New Record Form)
    handleApplyLeave() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Leave__c',
                actionName: 'new'
            }
        });
    }
}
