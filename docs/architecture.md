# 架构

pigi 没有服务器。App 内的 `LocalEngine`(Swift actor)负责同步,界面通过 `ArchiveClient` 门面与引擎交互。

```
SwiftUI 界面 ── AppState ── ArchiveClient ── LocalEngine ─┬─ GmailSession (REST, OAuth PKCE, history 增量)
                                                          ├─ ImapConnection (Network.framework TLS)
                                                          └─ Store (系统 SQLite3, WAL, FTS5 trigram)
```

## 数据

- 数据库:`~/Library/Application Support/pigi/mail.db`;列表头缓存:`.../pigi/mail-headers.json`。
- 表:`accounts`、`messages`(含 `seq` 变更序号)、`attachments`、`muted`、FTS5 虚表。
- 变更流:每次写入递增 `seq`;界面用 `changes(after:)` 增量拉取,`events()` 推送唤醒。
- 状态:`inbox / archived / trash / spam / deleted`;标签沿用 Gmail 词汇 `INBOX / UNREAD / STARRED / TRASH / SPAM`。

## Gmail

- 用户自备 OAuth 客户端(iOS 类型,无 secret),PKCE,scope `gmail.modify`。客户端 ID 存 UserDefaults `gmailClientID`。
- 首次回填默认 30 天;之后用 `history.list` 增量。请求限速 8/s,遇 401/配额/5xx 重试。
- 刷新令牌存钥匙串。

## IMAP

- 自实现的 TLS IMAP 客户端:LOGIN、LIST、SELECT、UID SEARCH/FETCH/STORE/MOVE/COPY、EXPUNGE。
- 每 60 秒轮询;UIDVALIDITY 变化时旧行标记删除。归档移到 `\Archive`(缺失则创建),删除移到 `\Trash`。
- 密码存钥匙串(`imap-<email>`)。

## 解析

`MIME` 解析 RFC 2047 编码词、quoted-printable、base64、multipart、字符集与 RFC 2231 文件名。`Detect` 提取验证码、退订信息(one-click / link / mailto,仅公网 URL)与地址。

## 测试

调试构建设置环境变量 `PIGI_INSECURE_TLS=1` 可连接自签名证书的本地 IMAP 测试服务器(仅 DEBUG)。

## 目录

```
Pigi/            App 源码(界面、AppState、更新)
Pigi/Engine/     同步引擎:Store、MIME、Detect、Imap、Gmail
landing/         官网(Cloudflare Workers Static Assets)
docs/            文档
```
