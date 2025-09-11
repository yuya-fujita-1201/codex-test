import { LightningElement, track } from 'lwc';
import getRecentThreads from '@salesforce/apex/ChatMessageController.getRecentThreads';
import getMessages from '@salesforce/apex/ChatMessageController.getMessages';
import getMessagesPage from '@salesforce/apex/ChatMessageController.getMessagesPage';
import createThreadApex from '@salesforce/apex/ChatMessageController.createThread';
import postMessage from '@salesforce/apex/ChatMessageController.postMessage';
import LightningConfirm from 'lightning/confirm';

export default class ChatWorkspace extends LightningElement {
    @track threads = [];
    newThreadTitle = '';
    firstComment = '';
    firstCommentCount = 0;
    openSectionNames = [];

    connectedCallback() {
        this.refreshAll();
    }

    async refreshAll() {
        const threads = await getRecentThreads({ limitSize: 25 });
        // Do not load messages now; lazy-load on expand
        this.threads = threads.map((t) => ({
            ...t,
            messages: [],
            messagesLoaded: false,
            loading: false,
            hasMore: true,
            oldestLoadedDate: null,
            newComment: '',
            commentCount: 0,
            disableComment: true
        }));
        this.openSectionNames = [];
    }

    // New thread creation
    handleTitleChange(e) {
        this.newThreadTitle = e.detail.value;
    }

    handleFirstCommentChange(e) {
        this.firstComment = e.detail.value;
        this.firstCommentCount = (this.firstComment || '').length;
    }

    get disableCreate() {
        const t = this.newThreadTitle && this.newThreadTitle.trim().length > 0;
        const c = this.firstComment && this.firstComment.trim().length > 0;
        return !(t && c);
    }

    async createThread() {
        const title = (this.newThreadTitle || '').trim();
        const body = (this.firstComment || '').trim();
        if (!title || !body) return;
        try {
            const ok = await LightningConfirm.open({
                message: 'スレッドを作成し、コメントを投稿します。よろしいですか？',
                label: '確認',
                theme: 'default'
            });
            if (!ok) return;

            const id = await createThreadApex({ title });
            await postMessage({ threadId: id, body });
            // Clear inputs
            this.newThreadTitle = '';
            this.firstComment = '';
            this.firstCommentCount = 0;
            // Load first page to show the posted comment
            const msgs = await getMessagesPage({ threadId: id, pageSize: 20, beforeCreatedDate: null });
            // Prepend new thread and open it
            this.threads = [
                {
                    Id: id,
                    Name: title,
                    messages: msgs,
                    messagesLoaded: true,
                    loading: false,
                    hasMore: msgs.length === 20,
                    oldestLoadedDate: msgs.length ? msgs[0].CreatedDate : null,
                    newComment: '',
                    commentCount: 0,
                    disableComment: true
                },
                ...this.threads
            ];
            this.openSectionNames = [id, ...this.openSectionNames];
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(e);
        }
    }

    // Comment handling per-thread
    handleCommentChange(e) {
        const id = e.currentTarget.dataset.id;
        const value = e.detail.value || '';
        this.threads = this.threads.map((t) =>
            t.Id === id
                ? { ...t, newComment: value, commentCount: (value || '').length, disableComment: value.trim().length === 0 }
                : t
        );
    }

    async confirmAndPostComment(e) {
        const id = e.currentTarget.dataset.id;
        const th = this.threads.find((t) => t.Id === id);
        if (!th || !th.newComment || th.newComment.trim().length === 0) return;

        const result = await LightningConfirm.open({
            message: 'コメントを投稿します。よろしいですか？',
            label: '確認',
            theme: 'default'
        });
        if (!result) return;

        try {
            await postMessage({ threadId: id, body: th.newComment });
            // Clear input and refresh messages for this thread
            const msgs = await getMessages({ threadId: id, limitSize: 100 });
            this.threads = this.threads.map((t) =>
                t.Id === id
                    ? {
                          ...t,
                          messages: msgs,
                          messagesLoaded: true,
                          newComment: '',
                          commentCount: 0,
                          disableComment: true,
                          oldestLoadedDate: (msgs && msgs.length ? msgs[0].CreatedDate : t.oldestLoadedDate)
                      }
                    : t
            );
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error(err);
        }
    }

    async handleToggle(e) {
        const open = e && e.detail && e.detail.openSections;
        const ids = Array.isArray(open) ? open : (open ? [open] : []);
        this.openSectionNames = ids;

        // Determine which sections need loading (and clear closed sections)
        const toLoad = ids.filter((id) => {
            const t = this.threads.find((x) => x.Id === id);
            return t && !t.messagesLoaded;
        });

        // Clear messages for closed sections to save memory
        this.threads = this.threads.map((t) =>
            ids.includes(t.Id)
                ? t
                : { ...t, messages: [], messagesLoaded: false, hasMore: true, oldestLoadedDate: null }
        );

        if (toLoad.length === 0) return;

        // Load in parallel then update
        await Promise.all(
            toLoad.map(async (id) => {
                try {
                    const msgs = await getMessagesPage({ threadId: id, pageSize: 20, beforeCreatedDate: null });
                    this.threads = this.threads.map((t) =>
                        t.Id === id
                            ? {
                                  ...t,
                                  messages: msgs,
                                  messagesLoaded: true,
                                  hasMore: msgs.length === 20,
                                  oldestLoadedDate: msgs.length ? msgs[0].CreatedDate : null
                              }
                            : t
                    );
                } catch (err) {
                    // eslint-disable-next-line no-console
                    console.error(err);
                }
            })
        );
    }

    async handleScrollMessages(e) {
        const id = e.currentTarget.dataset.id;
        const t = this.threads.find((x) => x.Id === id);
        if (!t || t.loading || !t.hasMore) return;
        // Load more when user scrolls near top
        if (e.currentTarget.scrollTop > 30) return;

        this.threads = this.threads.map((x) => (x.Id === id ? { ...x, loading: true } : x));
        try {
            const msgs = await getMessagesPage({ threadId: id, pageSize: 20, beforeCreatedDate: t.oldestLoadedDate });
            const combined = msgs.concat(t.messages || []);
            this.threads = this.threads.map((x) =>
                x.Id === id
                    ? {
                          ...x,
                          messages: combined,
                          loading: false,
                          hasMore: msgs.length === 20,
                          oldestLoadedDate: combined.length ? combined[0].CreatedDate : x.oldestLoadedDate
                      }
                    : x
            );
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error(err);
            this.threads = this.threads.map((x) => (x.Id === id ? { ...x, loading: false } : x));
        }
    }
}
