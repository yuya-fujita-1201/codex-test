import { LightningElement, track } from 'lwc';

export default class ChatWorkspace extends LightningElement {
    @track threadId;

    handleThreadSelect(e) {
        this.threadId = e.detail.threadId;
    }
}

