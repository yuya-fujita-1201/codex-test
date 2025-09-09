import { LightningElement, track } from 'lwc';
import getRecentThreads from '@salesforce/apex/ChatMessageController.getRecentThreads';
import createThreadApex from '@salesforce/apex/ChatMessageController.createThread';

export default class ChatThreadList extends LightningElement {
    @track threads = [];
    newTitle = '';

    connectedCallback() {
        this.refresh();
    }

    async refresh() {
        this.threads = await getRecentThreads({ limitSize: 25 });
    }

    handleTitleChange(e) {
        this.newTitle = e.detail.value;
    }

    get disableCreate() {
        return !this.newTitle || this.newTitle.length === 0;
    }

    async createThread() {
        try {
            const id = await createThreadApex({ title: this.newTitle });
            this.newTitle = '';
            await this.refresh();
            this.dispatchEvent(new CustomEvent('threadselect', { detail: { threadId: id } }));
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(e);
        }
    }

    selectThread(e) {
        const id = e.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('threadselect', { detail: { threadId: id } }));
    }
}

