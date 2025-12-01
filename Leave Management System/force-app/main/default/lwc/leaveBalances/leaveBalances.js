import { LightningElement, wire } from "lwc";
import getLeaveBalance from "@salesforce/apex/LeaveApplicationController.getLeaveBalance";
import getDefaultLeaveBalanceSetting from "@salesforce/apex/LeaveApplicationController.getDefaultLeaveBalanceSetting";

export default class LeaveBalances extends LightningElement {
    balance = {};
    setting = {};
    hasError = false;

    @wire(getLeaveBalance)
    wiredLeaveBalance({ data, error }) {
        if (data) {
            this.balance = data;
            this.hasError = false;
        } else if (error) {
            this.balance = {};
            this.hasError = true;
            // optional: surface toast in parent if needed
        }
    }

    @wire(getDefaultLeaveBalanceSetting)
    wiredSetting({ data, error }) {
        if (data) {
            this.setting = data;
        } else {
            this.setting = {};
        }
    }

    get earnedCasualHours() {
        return this.balance?.annualLeaveHours ?? 0;
    }

    get sickHours() {
        return this.balance?.sickLeaveHours ?? 0;
    }

    get settingEarnedCasual() {
        return this.setting?.earnedCasualLeave ?? 0;
    }

    get settingSick() {
        return this.setting?.sickLeave ?? 0;
    }
}
