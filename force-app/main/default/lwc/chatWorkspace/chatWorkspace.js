import { LightningElement, track } from 'lwc';

export default class ChatWorkspace extends LightningElement {
    @track threadId;
    @track threadName;

    handleThreadSelect(e) {
        this.threadId = e.detail.threadId;
        this.threadName = e.detail.threadName;
    }
}
