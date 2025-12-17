import{ LightningElement,wire} from 'lwc';
import{ NavigationMixin} from 'lightning/navigation';
import getLeaveBalances from '@salesforce/apex/LeaveController.getLeaveBalances';
import getMyLeaves from '@salesforce/apex/LeaveController.getMyLeaves';
import getMyOpenCases from '@salesforce/apex/LeaveController.getMyOpenCases';

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
    
get contentClass(){
    return this.isSidebarOpen?"content-wrap shifted" :"content-wrap";
}
    @wire(getLeaveBalances)
    wiredBalances({ error,data}){
        if(data){
            console.log('getLeaveBalances data=>',JSON.stringify(data));
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
    
    _formatLeave(record) {
        // 1."25 Dec 2025,Thursday"
        let finalDate=record.Start_Date__c;
        if (record.Start_Date__c) {
            try {
                const d=new Date(record.Start_Date__c);
                const datePart=d.toLocaleDateString('en-GB',{ day: 'numeric',month: 'short',year: 'numeric' });
                const dayPart=d.toLocaleDateString('en-GB',{ weekday: 'long' });
                finalDate=`${datePart},${dayPart}`;
            } catch (e) {
                console.error('Date format error',e);
            }
        }
        // 2. Leave Type & Dot Styling
        const type=record.Leave_Type__c?record.Leave_Type__c.replace(/_/g,' '):'Leave';
        const isSick=type.toLowerCase().includes('sick');
        const dotClass=isSick?'status-dot sick':'status-dot casual';
        // 3. Status Text Styling
        let statusClass='status-text';
        if (record.Status__c==='Approved') statusClass+=' status-approved';
        else if (record.Status__c==='Rejected') statusClass+=' status-rejected';
        else statusClass+=' status-pending';
        return {
            ...record,
            formattedDate: finalDate,
            typeLabel: type,
            durationLabel: `• ${record.Days_Taken__c || 0} ${record.Days_Taken__c===1?'day':'days'}`,
            dotClass: dotClass,
            statusClass: statusClass
        };
    }
    get upcomingLeaves() {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
    
        const rows = this.leaves?.data || [];
    
        return rows
            .filter(r => {
                const endDate = new Date(r.End_Date__c);
                return endDate >= today;
            })
            .map(r => this._formatLeave(r));
    }
    
    get pastLeaves() {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
    
        const rows = this.leaves?.data || [];
    
        return rows
            .filter(r => {
                const endDate = new Date(r.End_Date__c);
                return endDate < today;
            })
            .map(r => this._formatLeave(r));
    }
    
    get formattedCases(){
        return Array.isArray(this.cases)?this.cases.map(c=>({
            Id:c.Id,
            Subject:c.Subject||c.CaseNumber||'Case',
            CaseNumber:c.CaseNumber||'',
            Status:c.Status||''
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
