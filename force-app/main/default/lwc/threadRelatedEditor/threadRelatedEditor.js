import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ThreadRelatedEditor extends LightningElement {
    @api recordId;

    handleSuccess() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Saved',
            message: 'Thread related info updated',
            variant: 'success'
        }));
    }

    handleError(event) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: event.detail?.message || 'Update failed',
            variant: 'error'
        }));
    }
}

