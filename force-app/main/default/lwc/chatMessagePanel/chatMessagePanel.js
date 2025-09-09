import { LightningElement, api, track, wire } from 'lwc';
import getMessages from '@salesforce/apex/ChatMessageController.getMessages';
import postMessage from '@salesforce/apex/ChatMessageController.postMessage';

export default class ChatMessagePanel extends LightningElement {
    @api threadId;
    @track messages = [];
    newBody = '';

    @wire(getMessages, { threadId: '$threadId', limitSize: 100 })
    wiredMessages({ error, data }) {
        if (data) {
            this.messages = data.map(m => ({
                ...m,
                isSynced: m.SyncStatus__c === 'Synced',
                isPending: m.SyncStatus__c === 'Pending',
                isFailed: m.SyncStatus__c === 'Failed'
            }));
        }
        // else ignore error for brevity
    }

    handleBodyChange(e) {
        this.newBody = e.detail.value;
    }

    get disableSend() {
        return !this.threadId || !this.newBody || this.newBody.length === 0;
    }

    // flags moved into each message for template usage

    async send() {
        try {
            await postMessage({ threadId: this.threadId, body: this.newBody });
            this.newBody = '';
            // Requery messages by forcing wire to refresh (simple approach: change threadId temporarily)
            const cur = this.threadId;
            this.threadId = null;
            setTimeout(() => { this.threadId = cur; }, 0);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(e);
        }
    }
}
