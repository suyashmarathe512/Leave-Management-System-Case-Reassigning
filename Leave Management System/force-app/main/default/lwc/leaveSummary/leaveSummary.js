import{ LightningElement,wire} from 'lwc';
import{ NavigationMixin} from 'lightning/navigation';
import getLeaveBalances from '@salesforce/apex/LeaveController.getLeaveBalances';
import getMyLeaves from '@salesforce/apex/LeaveController.getMyLeaves';
import getMyOpenCases from '@salesforce/apex/LeaveController.getMyOpenCases';
import getMyPastLeaves from '@salesforce/apex/LeaveController.getMyPastLeaves';
export default class LeaveSummary extends NavigationMixin(LightningElement){
    isSidebarOpen=false;
    earned=0;
    sick=0;
    bookedEarned=0;
    bookedSick=0;
    bookedUnpaid=0;
    availableEarned=0;
    availableSick=0;
    cases=[];
    casesError;
    pastLeaves=[];
    pastLeavesError;
    columns=[
    { label:'Start Date',fieldName:'_startDate',type:'text',sortable:true},
    { label:'Leave Type',fieldName:'Leave_Type__c',type:'text',sortable:true},
    { label:'Reason',fieldName:'Reason__c',type:'text'},
    { label:'Days Taken',fieldName:'Days_Taken__c',type:'number'},
    { label:'Status',fieldName:'Status__c',type:'text'}
    ];
get contentClass(){
    return this.isSidebarOpen?"content-wrap shifted" :"content-wrap";
}
    @wire(getLeaveBalances)
    wiredBalances({ error,data}){
        if(data){
            console.log('getLeaveBalances data => ',JSON.stringify(data));
            this.earned=data.earned??0;
            this.sick=data.sick??0;
            this.bookedEarned=data.bookedEarned??0;
            this.bookedSick=data.bookedSick??0;
            this.bookedUnpaid=data.bookedUnpaid??0;
            this.availableEarned=data.availableEarned??0;
            this.availableSick=data.availableSick??0;
    }else if(error){
            console.error('Error loading balances',error);
    }
}
    @wire(getMyLeaves)
    leaves;
    @wire(getMyOpenCases,{ limitSize:20})
    wiredCases({ error,data}){
        if (data){
            this.cases=data;
            this.casesError=undefined;
    } else if (error){
            this.cases=[];
            this.casesError=error;
    }
}
    @wire(getMyPastLeaves,{ limitSize:20})
    wiredPastLeaves({ error,data}){
        if (data){
            this.pastLeaves=data;
            this.pastLeavesError=undefined;
    } else if (error){
            this.pastLeaves=[];
            this.pastLeavesError=error;
    }
}
    get formattedLeaves(){
        const rows=this.leaves&&this.leaves.data?this.leaves.data :[];
        return rows.map((r,idx) => ({
            ...r,
            _rowClass:idx % 2 === 0?'row-even' :'row-odd',
            _startDate:this._formatDateSafe(r.Start_Date__c),
            _endDate:this._formatDateSafe(r.End_Date__c)
    }));
}
    get formattedCases(){
        return Array.isArray(this.cases)?this.cases.map(c => ({
            Id:c.Id,
            Subject:c.Subject||c.CaseNumber||'Case',
            CaseNumber:c.CaseNumber||'',
            Status:c.Status||''
    })) :[];
}
    get formattedPastLeaves(){
        return Array.isArray(this.pastLeaves)?this.pastLeaves.map(p => ({
            Id:p.Id,
            Name:p.Name||'Leave',
            _startDate:this._formatDateSafe(p.Start_Date__c),
            _endDate:this._formatDateSafe(p.End_Date__c),
            Status__c:p.Status__c||''
    })) :[];
}
    _formatDateSafe(dateIso){
        if (!dateIso) return '';
        try{
            const d=new Date(dateIso);
            if (isNaN(d)) return dateIso;
            return d.toLocaleDateString('en-GB',{ year:'numeric',month:'2-digit',day:'2-digit'});
    } catch (e){
            return dateIso;
    }
}
    toggleSidebar=() =>{
        this.isSidebarOpen=!this.isSidebarOpen;
};
    closeSidebar=() =>{
        this.isSidebarOpen=false;
};
    navigateToRecord(event){
        const recordId=event.currentTarget?.dataset?.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type:'standard__recordPage',
            attributes:{
                recordId,
                objectApiName:'Case',
                actionName:'view'
        }
    });
}
    handleApplyLeave(){
        this[NavigationMixin.Navigate]({
            type:'standard__objectPage',
            attributes:{
                objectApiName:'Leave__c',
                actionName:'new'
        }
    });
}
    openCases(){
        this.isSidebarOpen=true;
        this[NavigationMixin.Navigate]({
            type:'standard__objectPage',
            attributes:{
                objectApiName:'Case',
                actionName:'list'
        },
            state:{
                filterName:'Open'
        }
    });
}
}
