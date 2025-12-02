import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLeaveBalances from '@salesforce/apex/LeaveController.getLeaveBalances';
import getMyLeaves from '@salesforce/apex/LeaveController.getMyLeaves';

const COLUMNS = [
    {
        label: 'Start Date',
        fieldName: 'Start_Date__c',
        type: 'date',
        typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' }
    },
    { label: 'Leave Type', fieldName: 'Leave_Type__c' },
    { label: 'Reason', fieldName: 'Reason_To_Leave__c' },
    { label: 'Days Taken', fieldName: 'Days_Taken__c', type: 'number' },
    { label: 'Status', fieldName: 'Status__c' }
];

export default class LeaveSummary extends NavigationMixin(LightningElement) {
    columns = COLUMNS;

    // balances
    earned = 0;
    sick = 0;
    bookedEarned = 0;
    bookedSick = 0;
    bookedUnpaid = 0;
    availableEarned = 0;
    availableSick = 0;

    // wire leave balances
    @wire(getLeaveBalances)
    wiredBalances({ error, data }) {
        if (data) {
            console.log('getLeaveBalances data => ', JSON.stringify(data));
            this.earned = data.earned ?? 0;
            this.sick = data.sick ?? 0;
            this.bookedEarned = data.bookedEarned ?? 0;
            this.bookedSick = data.bookedSick ?? 0;
            this.bookedUnpaid = data.bookedUnpaid ?? 0;
            this.availableEarned = data.availableEarned ?? 0;
            this.availableSick = data.availableSick ?? 0;
        } else if (error) {
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
