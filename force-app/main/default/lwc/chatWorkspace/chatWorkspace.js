import { LightningElement, track, api, wire } from 'lwc';
import getRecentThreads from '@salesforce/apex/ChatMessageController.getRecentThreads';
import getRecentThreadsForRecord from '@salesforce/apex/ChatMessageController.getRecentThreadsForRecord';
import getMessages from '@salesforce/apex/ChatMessageController.getMessages';
import getMessagesPage from '@salesforce/apex/ChatMessageController.getMessagesPage';
import createThreadApex from '@salesforce/apex/ChatMessageController.createThread';
import createThreadForRecord from '@salesforce/apex/ChatMessageController.createThreadForRecord';
import postMessage from '@salesforce/apex/ChatMessageController.postMessage';
import sendMessageApex from '@salesforce/apex/ChatMessageController.sendMessage';
import deleteMessageApex from '@salesforce/apex/ChatMessageController.deleteMessage';
import LightningConfirm from 'lightning/confirm';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

export default class ChatWorkspace extends LightningElement {
    @track threads = [];
    _recordId;
    _objectApiName;
    @track objectLabel;
    @api
    get recordId() { return this._recordId; }
    set recordId(v) {
        if (this._recordId !== v) {
            this._recordId = v;
            // refresh when context changes
            if (this._initialized) this.refreshAll();
        }
    }
    @api
    get objectApiName() { return this._objectApiName; }
    set objectApiName(v) {
        if (this._objectApiName !== v) {
            this._objectApiName = v;
        }
    }
    newThreadTitle = '';
    firstComment = '';
    firstCommentCount = 0;
    openSectionNames = [];

    connectedCallback() {
        this._initialized = true;
        this.refreshAll();
    }

    @wire(getObjectInfo, { objectApiName: '$_objectApiName' })
    wiredObjInfo({ data }) {
        if (data) this.objectLabel = data.label;
    }

    get cardTitle() {
        return this.objectLabel ? `${this.objectLabel} チャット` : 'チャット';
    }

    async refreshAll() {
        let threads;
        if (this._recordId) {
            threads = await getRecentThreadsForRecord({ recordId: this._recordId, limitSize: 25 });
        } else {
            threads = await getRecentThreads({ limitSize: 25 });
        }
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
            isClosed: t.Status__c === 'Closed',
            disableComment: true,
            uiDisableComment: true
        }));
        // auto-open latest 3 threads
        this.openSectionNames = this.getDefaultOpenIds();
        await this.setOpenSections(this.openSectionNames);
    }

    getDefaultOpenIds() {
        return (this.threads || []).slice(0, 1).map((t) => t.Id);
    }

    decorateMessages(list) {
        const truncate = (s, expanded) => {
            if (!s) return '';
            if (expanded || s.length <= 255) return s;
            return s.substring(0, 255) + '…';
        };
        const formatJst = (iso) => {
            if (!iso) return '';
            try {
                const d = new Date(iso);
                const parts = new Intl.DateTimeFormat('en-US', {
                    timeZone: 'Asia/Tokyo',
                    year: 'numeric', month: '2-digit', day: '2-digit',
                    hour: '2-digit', minute: '2-digit', second: '2-digit',
                    hour12: false
                }).formatToParts(d).reduce((acc, p) => { acc[p.type] = p.value; return acc; }, {});
                const y = parts.year;
                const mo = parts.month;
                const da = parts.day;
                const h = parts.hour;
                const mi = parts.minute;
                const s = parts.second;
                return `${y}-${mo}-${da} ${h}:${mi}:${s}`;
            } catch (e) { return iso; }
        };
        return (list || []).map((m) => {
            const s = m.SyncStatus__c;
            const isSynced = s === 'Synced';
            const isPending = s === 'Pending';
            const isFailed = s === 'Failed';
            const statusTitle = isFailed
                ? (m.ErrorMessage__c || '連携失敗')
                : (isSynced ? '同期済み' : (isPending ? '連携保留' : s));
            const ts = m.PostedAt__c || m.CreatedDate;
            return {
                ...m,
                expanded: false,
                canExpand: (m.Body__c || '').length > 255,
                displayBody: truncate(m.Body__c, false),
                expandLabel: 'もっと見る',
                isSynced,
                isPending,
                isFailed,
                statusTitle,
                displayTime: formatJst(ts)
            };
        });
    }

    hasUnsent(messages) {
        return (messages || []).some((m) => m && m.SyncStatus__c !== 'Synced');
    }

    withCommentUiState(thread, messages) {
        const msgs = messages !== undefined ? messages : thread.messages;
        const hasUnsent = this.hasUnsent(msgs);
        const value = (thread.newComment || '');
        const disableByValue = value.trim().length === 0;
        const uiDisableComment = disableByValue || !!thread.isClosed || hasUnsent;
        return {
            ...thread,
            messages: msgs !== undefined ? msgs : thread.messages,
            hasUnsent,
            uiDisableComment,
            disableComment: disableByValue
        };
    }

    // Utility: ensure messages are unique by Id and ordered by CreatedDate ASC
    dedupeMessages(list) {
        const seen = new Set();
        const out = [];
        (list || []).forEach((m) => {
            const key = m && m.Id ? m.Id : JSON.stringify({
                b: m && m.Body__c,
                p: m && m.PostedAt__c,
                u: m && m.PostedBy__c
            });
            if (!seen.has(key)) {
                seen.add(key);
                out.push(m);
            }
        });
        // sort oldest -> newest for stable rendering
        out.sort((a, b) => {
            const da = (a && a.CreatedDate) || (a && a.PostedAt__c) || '';
            const db = (b && b.CreatedDate) || (b && b.PostedAt__c) || '';
            return da < db ? -1 : da > db ? 1 : 0;
        });
        return out;
    }

    // New thread creation
    handleTitleChange(e) {
        this.newThreadTitle = e.detail.value;
        const el = this.template.querySelector('lightning-input[data-name="title"]');
        if (el) { el.setCustomValidity(''); el.reportValidity(); }
    }

    handleFirstCommentChange(e) {
        this.firstComment = e.detail.value;
        this.firstCommentCount = (this.firstComment || '').length;
        const el = this.template.querySelector('lightning-textarea[data-name="firstComment"]');
        if (el) { el.setCustomValidity(''); el.reportValidity(); }
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

            const id = this._recordId
                ? await createThreadForRecord({ title, recordId: this._recordId, objectApiName: this._objectApiName })
                : await createThreadApex({ title });
            await postMessage({ threadId: id, body });
            // Clear inputs
            this.newThreadTitle = '';
            this.firstComment = '';
            this.firstCommentCount = 0;
            this.clearComposerErrors();
            // Load first page to show the posted comment
            const msgs = this.dedupeMessages(
                this.decorateMessages(
                    await getMessagesPage({ threadId: id, pageSize: 20, beforeCreatedDate: null })
                )
            );
            // Prepend new thread and open it
        const newHasUnsent = this.hasUnsent(msgs);
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
                disableComment: true,
                isClosed: false,
                hasUnsent: newHasUnsent,
                uiDisableComment: true
            },
            ...this.threads
        ];
            // Keep latest 3 (includes new thread at top)
            // Ensure the new thread is opened first and de-duplicate
            const ids = [id].concat(this.openSectionNames || []).filter((v, i, a) => a.indexOf(v) === i);
            this.openSectionNames = ids;
            await this.setOpenSections(this.openSectionNames);
            // In some cases the accordion needs a tick to recognize the new section
            setTimeout(() => {
                const acc = this.template.querySelector('lightning-accordion');
                if (acc) acc.activeSectionName = this.openSectionNames;
            }, 0);
        } catch (e) {
            const msg = this.normalizeError(e);
            if (msg && msg.indexOf('タイトル') >= 0) {
                this.setComposerFieldError('title', msg);
            } else {
                this.setComposerFieldError('firstComment', msg);
            }
        }
    }

    // Comment handling per-thread
    handleCommentChange(e) {
        const id = e.currentTarget.dataset.id;
        const value = e.detail.value || '';
        const target = this.threads.find((t) => t.Id === id);
        if (target && target.isClosed) {
            return; // Closed threads cannot be edited
        }
        this.threads = this.threads.map((t) =>
            t.Id === id
                ? this.withCommentUiState({ ...t, newComment: value, commentCount: (value || '').length }, undefined)
                : t
        );
        // clear field error while typing
        const el = this.template.querySelector(`lightning-textarea[data-id="${id}"]`);
        if (el) { el.setCustomValidity(''); el.reportValidity(); }
    }

    async confirmAndPostComment(e) {
        const id = e.currentTarget.dataset.id;
        const th = this.threads.find((t) => t.Id === id);
        if (!th || th.isClosed || !th.newComment || th.newComment.trim().length === 0) return;

        try {
            await postMessage({ threadId: id, body: th.newComment });
            // Clear input and refresh messages for this thread (status will be Pending)
            const msgs = this.dedupeMessages(
                this.decorateMessages(
                    await getMessages({ threadId: id, limitSize: 100 })
                )
            );
            this.threads = this.threads.map((t) =>
                t.Id === id
                    ? this.withCommentUiState(
                          {
                              ...t,
                              messagesLoaded: true,
                              newComment: '',
                              commentCount: 0,
                              oldestLoadedDate: (msgs && msgs.length ? msgs[0].CreatedDate : t.oldestLoadedDate)
                          },
                          msgs
                      )
                    : t
            );
        } catch (err) {
            const msg = this.normalizeError(err);
            const el = this.template.querySelector(`lightning-textarea[data-id="${id}"]`);
            if (el) { el.setCustomValidity(msg || '投稿に失敗しました'); el.reportValidity(); }
        }
    }

    // Send a saved (Pending) message to external
    async sendMessage(e) {
        const threadId = e.currentTarget.dataset.threadId;
        const messageId = e.currentTarget.dataset.id;
        try {
            const ok = await LightningConfirm.open({
                message: 'このメッセージを外部に送信します。よろしいですか？',
                label: '確認',
                theme: 'default'
            });
            if (!ok) return;
            await sendMessageApex({ messageId });
            const msgs = this.dedupeMessages(
                this.decorateMessages(
                    await getMessages({ threadId: threadId, limitSize: 100 })
                )
            );
            this.threads = this.threads.map((t) =>
                t.Id === threadId
                    ? this.withCommentUiState({ ...t, messagesLoaded: true }, msgs)
                    : t
            );
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error(err);
        }
    }

    // Delete a message
    async deleteMessage(e) {
        const threadId = e.currentTarget.dataset.threadId;
        const messageId = e.currentTarget.dataset.id;
        try {
            const ok = await LightningConfirm.open({
                message: 'このメッセージを削除します。よろしいですか？',
                label: '確認',
                theme: 'warning'
            });
            if (!ok) return;
            await deleteMessageApex({ messageId });
            const msgs = this.dedupeMessages(
                this.decorateMessages(
                    await getMessages({ threadId: threadId, limitSize: 100 })
                )
            );
            this.threads = this.threads.map((t) =>
                t.Id === threadId
                    ? this.withCommentUiState({ ...t, messagesLoaded: true }, msgs)
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
        await this.setOpenSections(ids);
    }

    async setOpenSections(ids) {
        this.openSectionNames = ids || [];

        // Determine which sections need loading (and clear closed sections)
        const toLoad = this.openSectionNames.filter((id) => {
            const t = this.threads.find((x) => x.Id === id);
            return t && !t.messagesLoaded;
        });

        // Clear messages for closed sections to save memory
        this.threads = this.threads.map((t) =>
            this.openSectionNames.includes(t.Id)
                ? t
                : { ...t, messages: [], messagesLoaded: false, hasMore: true, oldestLoadedDate: null }
        );

        if (toLoad.length === 0) return;

        // Load in parallel then update
        await Promise.all(
            toLoad.map(async (id) => {
                try {
                    const msgs = this.dedupeMessages(
                        this.decorateMessages(
                            await getMessagesPage({ threadId: id, pageSize: 20, beforeCreatedDate: null })
                        )
                    );
                    this.threads = this.threads.map((t) =>
                        t.Id === id
                            ? this.withCommentUiState(
                                  {
                                      ...t,
                                      messagesLoaded: true,
                                      hasMore: msgs.length === 20,
                                      oldestLoadedDate: msgs.length ? msgs[0].CreatedDate : null
                                  },
                                  msgs
                              )
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
            const msgs = this.dedupeMessages(
                this.decorateMessages(
                    await getMessagesPage({ threadId: id, pageSize: 20, beforeCreatedDate: t.oldestLoadedDate })
                )
            );
            const combined = this.dedupeMessages(msgs.concat(t.messages || []));
            this.threads = this.threads.map((x) =>
                x.Id === id
                    ? this.withCommentUiState(
                          {
                              ...x,
                              loading: false,
                              hasMore: msgs.length === 20,
                              oldestLoadedDate: combined.length ? combined[0].CreatedDate : x.oldestLoadedDate
                          },
                          combined
                      )
                    : x
            );
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error(err);
            this.threads = this.threads.map((x) => (x.Id === id ? { ...x, loading: false } : x));
        }
    }

    toggleExpand(e) {
        const threadId = e.currentTarget.dataset.threadId;
        const msgId = e.currentTarget.dataset.id;
        const update = (m) => {
            const expanded = !m.expanded;
            const full = m.Body__c || '';
            return {
                ...m,
                expanded,
                displayBody: expanded ? full : (full.length > 255 ? full.substring(0, 255) + '…' : full),
                expandLabel: expanded ? '閉じる' : 'もっと見る'
            };
        };
        this.threads = this.threads.map((t) =>
            t.Id === threadId
                ? { ...t, messages: (t.messages || []).map((m) => (m.Id === msgId ? update(m) : m)) }
                : t
        );
    }

    // Error helpers
    normalizeError(err) {
        try {
            if (err && err.body && typeof err.body.message === 'string') return err.body.message;
            if (Array.isArray(err && err.body)) return err.body.map((x) => x.message).join(', ');
            if (typeof err === 'string') return err;
            if (err && err.message) return err.message;
        } catch (ignore) {}
        return 'エラーが発生しました';
    }

    setComposerFieldError(fieldName, message) {
        const el = this.template.querySelector(
            fieldName === 'title' ? 'lightning-input[data-name="title"]' : 'lightning-textarea[data-name="firstComment"]'
        );
        if (el) {
            el.setCustomValidity(message || 'エラーが発生しました');
            el.reportValidity();
        }
    }

    clearComposerErrors() {
        ['title', 'firstComment'].forEach((f) => {
            const el = this.template.querySelector(
                f === 'title' ? 'lightning-input[data-name="title"]' : 'lightning-textarea[data-name="firstComment"]'
            );
            if (el) { el.setCustomValidity(''); el.reportValidity(); }
        });
    }
}
