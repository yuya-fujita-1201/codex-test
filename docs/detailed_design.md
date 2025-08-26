# タスク管理アプリ 詳細設計書

## 1. データモデル
### Task
| フィールド | 型 | 備考 |
| --- | --- | --- |
| id | number | 主キー |
| title | string | タスク名 |
| description | string | 詳細 |
| dueDate | string (ISO) | 期限日 |
| priority | 'low' \| 'medium' \| 'high' | 優先度 |
| completed | boolean | 完了フラグ |

## 2. API 詳細
### GET /api/tasks
- レスポンス: Task[]

### POST /api/tasks
- リクエスト: Task (id を除く)
- レスポンス: 作成された Task

### PUT /api/tasks/:id
- リクエスト: 更新対象 Task
- レスポンス: 更新後 Task

### DELETE /api/tasks/:id
- レスポンス: 削除成功可否

## 3. エラーハンドリング
- バリデーションエラー時は 400 を返却
- サーバー内部エラー時は 500 を返却

