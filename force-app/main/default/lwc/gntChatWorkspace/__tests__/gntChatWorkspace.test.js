import { createElement } from 'lwc';
import GntChatWorkspace from 'c/gntChatWorkspace';
import getRecentThreads from '@salesforce/apex/GNT_ChatMessageController.getRecentThreads';
import getRecentThreadsForRecord from '@salesforce/apex/GNT_ChatMessageController.getRecentThreadsForRecord';
import getMessages from '@salesforce/apex/GNT_ChatMessageController.getMessages';
import getMessagesPage from '@salesforce/apex/GNT_ChatMessageController.getMessagesPage';
import createThreadApex from '@salesforce/apex/GNT_ChatMessageController.createThread';
import createThreadForRecord from '@salesforce/apex/GNT_ChatMessageController.createThreadForRecord';
import postMessage from '@salesforce/apex/GNT_ChatMessageController.postMessage';
import sendMessageApex from '@salesforce/apex/GNT_ChatMessageController.sendMessage';
import deleteMessageApex from '@salesforce/apex/GNT_ChatMessageController.deleteMessage';
import LightningConfirm from 'lightning/confirm';
import { registerLdsTestWireAdapter } from '@salesforce/wire-service-jest-util';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

jest.mock('@salesforce/apex/GNT_ChatMessageController.getRecentThreads', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/apex/GNT_ChatMessageController.getRecentThreadsForRecord', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/apex/GNT_ChatMessageController.getMessages', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/apex/GNT_ChatMessageController.getMessagesPage', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/apex/GNT_ChatMessageController.createThread', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/apex/GNT_ChatMessageController.createThreadForRecord', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/apex/GNT_ChatMessageController.postMessage', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/apex/GNT_ChatMessageController.sendMessage', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('@salesforce/apex/GNT_ChatMessageController.deleteMessage', () => ({
    default: jest.fn()
}), { virtual: true });

jest.mock('lightning/confirm', () => ({
    open: jest.fn()
}), { virtual: true });

const getObjectInfoAdapter = registerLdsTestWireAdapter(getObjectInfo);

const SAMPLE_THREADS = [
    {
        Id: 't1',
        Name: 'スレッド1',
        GNT_Status__c: 'Active',
        Status__c: 'Active'
    }
];

const SAMPLE_MESSAGES = [
    {
        Id: 'm1',
        GNT_Body__c: '本文',
        GNT_PostedAt__c: '2024-01-01T00:00:00.000Z',
        GNT_PostedBy__c: '投稿者',
        GNT_SyncStatus__c: 'Pending',
        CreatedDate: '2024-01-01T00:00:00.000Z'
    }
];

function flushPromises() {
    return new Promise((resolve) => setImmediate(resolve));
}

describe('c-gnt-chat-workspace', () => {
    beforeEach(() => {
        document.body.innerHTML = '';
        jest.clearAllMocks();
        getRecentThreads.mockResolvedValue([...SAMPLE_THREADS]);
        getRecentThreadsForRecord.mockResolvedValue([...SAMPLE_THREADS]);
        getMessages.mockResolvedValue([]);
        getMessagesPage.mockResolvedValue([...SAMPLE_MESSAGES]);
        createThreadApex.mockResolvedValue('a0T000000000001');
        createThreadForRecord.mockResolvedValue('a0T000000000002');
        postMessage.mockResolvedValue('mX');
        sendMessageApex.mockResolvedValue({});
        deleteMessageApex.mockResolvedValue({});
        LightningConfirm.open.mockResolvedValue(true);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('loads threads on initialization and computes card title', async () => {
        const element = createElement('c-gnt-chat-workspace', { is: GntChatWorkspace });
        document.body.appendChild(element);
        getObjectInfoAdapter.emit({ label: 'Account' });
        await flushPromises();

        expect(getRecentThreads).toHaveBeenCalled();
        expect(element.threads).toHaveLength(1);
        expect(element.cardTitle).toBe('Account チャット');
    });

    it('creates a new thread when confirmed', async () => {
        const element = createElement('c-gnt-chat-workspace', { is: GntChatWorkspace });
        document.body.appendChild(element);
        await flushPromises();

        element.newThreadTitle = '新しいスレッド';
        element.firstComment = '初回コメント';
        element.firstCommentCount = element.firstComment.length;

        await element.createThread();
        await flushPromises();

        expect(createThreadApex).toHaveBeenCalledTimes(1);
        expect(postMessage).toHaveBeenCalledWith({ threadId: 'a0T000000000001', body: '初回コメント' });
        expect(element.threads[0].Id).toBe('a0T000000000001');
    });

    it('decorates and toggles messages', async () => {
        const element = createElement('c-gnt-chat-workspace', { is: GntChatWorkspace });
        document.body.appendChild(element);
        await flushPromises();

        const decorated = element.decorateMessages(SAMPLE_MESSAGES);
        expect(decorated[0].displayAuthor).toBe('投稿者');
        expect(decorated[0].expandLabel).toBe('もっと見る');

        element.threads = [
            {
                Id: 't1',
                Name: 'スレッド',
                messages: decorated,
                messagesLoaded: true,
                isClosed: false,
                newComment: 'hello',
                commentCount: 5,
                disableComment: false,
                uiDisableComment: false
            }
        ];

        element.toggleExpand({
            currentTarget: {
                dataset: { threadId: 't1', id: 'm1' }
            }
        });
        expect(element.threads[0].messages[0].expanded).toBe(true);
    });

    it('posts comment and refreshes messages', async () => {
        const element = createElement('c-gnt-chat-workspace', { is: GntChatWorkspace });
        document.body.appendChild(element);
        await flushPromises();

        element.threads = [
            {
                Id: 't1',
                Name: 'スレッド',
                messages: [],
                messagesLoaded: true,
                isClosed: false,
                newComment: '追加コメント',
                commentCount: 5,
                disableComment: false,
                uiDisableComment: false
            }
        ];

        await element.confirmAndPostComment({
            currentTarget: { dataset: { id: 't1' } }
        });
        await flushPromises();

        expect(postMessage).toHaveBeenCalledWith({ threadId: 't1', body: '追加コメント' });
        expect(getMessages).toHaveBeenCalledWith({ threadId: 't1', limitSize: 100 });
        expect(element.threads[0].newComment).toBe('');
    });

    it('sends message after confirmation', async () => {
        const element = createElement('c-gnt-chat-workspace', { is: GntChatWorkspace });
        document.body.appendChild(element);
        await flushPromises();

        await element.sendMessage({
            currentTarget: { dataset: { threadId: 't1', id: 'm1' } }
        });
        await flushPromises();

        expect(LightningConfirm.open).toHaveBeenCalled();
        expect(sendMessageApex).toHaveBeenCalledWith({ messageId: 'm1' });
    });

    it('handles dedupeMessages edge cases', () => {
        const element = createElement('c-gnt-chat-workspace', { is: GntChatWorkspace });
        const list = element.dedupeMessages([
            { Id: 'x1', GNT_Body__c: 'A', GNT_PostedAt__c: '2024-01-01', CreatedDate: '2024-01-01' },
            { GNT_Body__c: 'A', GNT_PostedAt__c: '2024-01-01', CreatedDate: '2024-01-01' }
        ]);
        expect(list).toHaveLength(1);
    });
});
