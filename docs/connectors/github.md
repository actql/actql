# GitHub

The GitHub Connector reads issues, pull requests, comments, commits and files
from a repository, writes issues and comments back, commits files, and merges,
closes, labels and requests reviews. A Program uses it to triage issues with a
model, keep a repository's issues in step with another system, and publish
generated files.

## Sources

- `github.issues` — the repository's issues: `number`, `node_id`, `title`,
  `state`, `state_reason`, `body`, `author`, `assignees` and `labels` (arrays),
  `milestone`, `comments` (the count), `created_at`, `updated_at`,
  `closed_at`, `url`. Key `number`.
- `github.pull_requests` — pull requests with the same shape plus `base`,
  `head`, `draft`, `mergeable`, `merged_at`, `merged_by`, `review_decision`.
  Key `number`.
- `github.issue_comments` — comments on issues and pull requests: `id`,
  `subject_number`, `author`, `body`, `created_at`, `updated_at`. Key `id`.
- `github.repositories` — the bound repository's metadata, or the organisation's
  repository listing under an explicitly admitted organisation read scope:
  `name`, `full_name`,
  `default_branch`, `visibility`, `pushed_at`, `open_issues`. Key `full_name`.
- `github.commits` — commits on a branch: `sha`, `message`, `author`,
  `committed_at`, `parents`, `files` (an array of path and change kind).
  Filter by branch and time range. Key `sha`.
- `github.files` — files at a ref: `resource`, `version` (the blob sha),
  `path`, `size`, `media_type`, `ref`. `LIST_FILES(github, glob => r'docs/**/*.md')`
  is the same listing for the default branch.
- `github.contents` — a file's bytes as a `content_ref`: `resource`,
  `version`, `media_type`, `content`. Join it on `resource` and `version`
  from `github.files`; the Connector fetches only the blobs the join names.

### Connection scope

A repository connection is scoped to one original repository (`owner`/`repo`
and its admitted stable identity). Its `github.repositories` Source reads that
repository's metadata. A token that can access other repositories does not
enlarge this connection's scope. Use another repository connection for
repository-specific Sources, Content or Effects in another repository.

Organisation repository enumeration requires a separately admitted
organisation-scoped Source connection that explicitly identifies the
organisation through the explicit `organization` connection field; `owner` and
`repo` are forbidden on that connection. It publishes only `github.repositories`.
Its separate publication, Account and Site must retain that same original
organisation and the authority for the bounded repository-listing read. The
token's type, accessible repositories or ownership of the configured repository
cannot select this scope implicitly. The `owner`/`repo` setup below selects
repository scope only.

The organisation Source lists metadata for repositories owned by that
organisation and visible through its admitted current Account and Credential.
Publication observes the original Organisation ID and login. Later pages resolve
that same ID, check the unchanged login, and verify every repository owner's
type, ID and login against it. The GraphQL request explicitly uses
`ownerAffiliations: [OWNER]`; the provider default also includes collaborators,
and `affiliations` filters the viewer instead of the organisation's ownership.
Those rows do not grant permission to read
each repository's issues, files or content, or to perform Effects there. Provider
visibility is not proof that inaccessible repositories do not exist. Exhausting
validated bounded pagination completes this credential-visible listing, not an
all-repositories or atomic snapshot claim. It requires no independent proof of
whole-organisation visibility. A stronger whole-organisation coverage claim
requires a separately admitted coverage original and Source contract; token
type, `totalCount` or an empty page cannot supply it. Pagination,
current checks and bounded-read obligations still apply; a failed or incomplete
listing is not a complete empty result. An implementation without the admitted
organisation scope must refuse that selection, rather than return only the
configured repository as if it had enumerated the organisation. Organisation
enumeration remains part of the connector's target behaviour.

## Types

| GitHub value | ActQL | Notes |
| --- | --- | --- |
| `number`, `id`, `comments`, `size` | `int64` | |
| `node_id`, `sha`, logins, `url` | `string` | |
| `state`, `state_reason`, `visibility`, `review_decision` | `string` | GitHub's enumerations as strings (`open`, `closed`, `completed`, `not_planned`, …). |
| `title`, `body`, `message` | `string` | Bodies are Markdown; Programs write plain strings and GitHub renders them. |
| `labels`, `assignees`, `parents` | `array<string>` | Label names, logins, parent shas. |
| `created_at`, `updated_at`, `closed_at`, `merged_at`, `pushed_at`, `committed_at` | `timestamp` | UTC. |
| `draft`, `mergeable` | `bool` | `mergeable` is NULL while GitHub is still computing it. |
| `files` (on a commit) | `array<object>` | `path`, `status`, `additions`, `deletions`. |
| file content | `content_ref` | Through `github.contents`; `media_type` from the path's extension. |

## Effects and operations

Record Effects write issues, pull requests and comments by key:

- **insert** — `EFFECT INSERT github.issues (title, body, labels, assignees) VALUES (…)`
  opens an issue; `EFFECT INSERT github.pull_requests (title, body, head, base) VALUES (…)`
  opens a pull request; `EFFECT INSERT github.issue_comments (subject_number, body) VALUES (…)`
  comments on an issue or pull request.
- **update** — `EFFECT UPDATE github.issues ID number SET (title = …, body = …, labels = …, state = 'closed')`;
  the same on `github.pull_requests` (title, body, base, draft) and
  `github.issue_comments ID id SET (body = …)`.
- **delete** — `EFFECT DELETE github.issue_comments ID id` deletes a comment;
  `EFFECT DELETE github.issues ID number` deletes an issue through the GraphQL
  `deleteIssue` mutation, which needs repository admin permission. A pull
  request has no delete in GitHub; `EFFECT DELETE github.pull_requests ID
  number` closes it and deletes its head branch, and the Preview says so.

The key must identify exactly one item: `number` within the repository for
issues and pull requests, `id` for comments.

Content:

- **store** — `EFFECT STORE github.files SET (path = …, branch = …, message = …, content = content)`
  commits the row's `content` (a `content_ref` from `SERIALIZE` or a
  `contents` source) to the path on the branch, creating or replacing the
  file. One Effect produces one commit per path.

Operations:

- **merge** — `EFFECT COMMAND github.merge TARGET number ID key INPUT (method = 'squash', commit_title = …)`.
- **close** — `EFFECT COMMAND github.close TARGET number ID key INPUT (reason = 'not_planned')`
  closes an issue or pull request with a state reason.
- **request_review** — `EFFECT COMMAND github.request_review TARGET number ID key INPUT (reviewers = ['kim'])`.
- **add_labels** — `EFFECT COMMAND github.add_labels TARGET number ID key INPUT (labels = ['triage'])`
  adds labels without replacing the existing ones (an `update` of `labels`
  replaces the set).

`TARGET` is the issue or pull request the operation acts on; `ID` is the
row's key and identifies the operation in the Preview and the status.

## Setup

```json
"github": {
  "connector": "github",
  "owner": "acme",
  "repo": "platform",
  "credentials": {"token": {"env": "GITHUB_TOKEN"}}
}
```

For organisation-owned repository metadata, use a separate connection:

```json
"github_org": {
  "connector": "github",
  "organization": "acme",
  "credentials": {"token": {"env": "GITHUB_TOKEN"}}
}
```

The two selector forms are mutually exclusive. An organisation connection does
not publish repository-specific Sources, Content or Effects; configure those
through separately admitted `owner`/`repo` connections. A consumer without the
organisation profile and its actual admission must refuse it, not silently use
repository scope or return an empty result.

Use a fine-grained personal access token or a GitHub App installation token.
Reading needs `issues: read`, `pull_requests: read`, `contents: read` and
`metadata: read`; writing needs `issues: write` (issues, comments, labels),
`pull_requests: write` (opening, updating, merging, requesting review) and
`contents: write` (committing files). GitHub Enterprise Server works with an
`api_origin` field. On ActQL Cloud the Connector is installed as a GitHub App
on the repositories you choose; a Local Host uses the token directly.

## Capabilities and pushdown

| Operation | Pushed down when |
| --- | --- |
| Projection | Reduces what the engine keeps; the REST API returns whole objects. |
| `WHERE` | On issues and pull requests: `state`, a label (`'bug' IN UNNEST(labels)`), `assignee`, `author`, `milestone`, and `updated_at >= …` (the `since` parameter); on comments: `since`; on commits: branch and `committed_at` range (`since`/`until`); on files: `ref` and path prefix. Other predicates, including anything on `body` or `title`, run on the Host — GitHub's search API is not used for them. |
| `ORDER BY` | `created_at`, `updated_at` or `comments` on issues and pull requests, in either direction. |
| `LIMIT` | Always, through page size and page number. |
| `GROUP BY`, `JOIN` | Never; they run on the Host. |

## Preview and reconciliation

**Preview.** Updates, deletes, `merge`, `close`, `request_review` and
`add_labels` are `full_diff`: the Connector reads the target with its
`updated_at` and ETag, and the Preview shows current and new values (for a
merge, the head sha that would be merged; for labels, the resulting set). At
apply time the request is conditioned on the ETag (`If-Match`) and, for a
merge, on the previewed head `sha`; a target changed in between makes the
item `failed` with `conflict` and nothing is sent. Inserts and file commits
are `targeted`: the Preview shows the repository, the exact title, body,
labels or path and content identity, and for a commit the branch head it
would follow.

**Reconciliation.** Creating an issue, a pull request or a comment is not
idempotent on GitHub's side, so every body the Connector writes ends with an
HTML comment carrying the request marker (`<!-- actql:effect:… -->`, which
GitHub does not render). The physical body preserves the original logical body
and appends two LF characters followed by
`<!-- actql:effect:<original-request-tag> -->`. An absent body uses only the
marker; an explicitly empty body retains the two LF characters. The tag is the
exact CID text of the original Common-issued row `DispatchKey`, bound to the
logical request scope, complete approved Preview and canonical item identity.
It is not the recovery locator, a physical Run/attempt ID or a separate binding
hash. The Preview binds the logical body and stamp derivation recipe; after
key derivation the Host supplies only that original tag DATA to the provider
and binds the final marked request before dispatch. Business-payload identity
and final transport identity remain separate. Recovery retains the same key,
marked bytes and original provider request CID; it never generates another tag
or reuses an unmarked request CID for different bytes. The logical row remains
separate from the physical body. A lost reply is reconciled by listing recent issues,
pull requests or comments for that marker; a body with the same text but no
marker is not evidence. File commits are reconciled by reading the branch
head: a commit whose message carries the marker and whose tree holds the
approved blob sha settles the outcome. Updates, closes, label changes and
review requests are reconciled through the issue's timeline events, which
record the actor and time of each change: an event by this installation in
the request window that produced the approved state settles the outcome,
while the item merely being in that state does not. A merge is settled by
the pull request's `merged` timeline event by this installation in the
request window; a merge commit alone is not. Without evidence the item stays
`unknown` and nothing is sent again. A successful mutation response is retained
as provider evidence pending the confirming read-back; HTTP 2xx alone does not
establish a successful mutation. A synchronous operation ends `applied` only
once the read-back confirms the required original state and evidence above.
Until that confirmation is admitted, retain the evidence and uncertainty.
The common [Effect outcome contract](../spec/execution.md#reconciliation)
reserves `accepted` for a pending provider operation with a genuine OperationRef
and its status, result, cancellation and reconciliation contracts. An issue,
pull request or comment ID, `clientMutationId`, or request marker is not such
an operation handle.

## Limits and cost

- The REST API allows 5,000 requests per hour per token (15,000 for GitHub
  App installations on Enterprise Cloud) and a secondary limit on concurrent
  writes; the Connector paces within both and pages 100 items at a time.
- Writes are sent one request per item — GitHub has no batch endpoint — and
  the Connector observes the one-second spacing GitHub asks for between
  content-creating requests.
- Blob reads are bounded by the Program's byte limit; files above GitHub's
  100 MB blob limit cannot be committed.
- GitHub's API has no usage fee for repositories you have access to.

## Example

Open issues that have had no comment for two weeks:

```sql
FROM github.issues
|> WHERE state = 'open' AND comments = 0
     AND created_at < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 14 DAY)
|> SELECT number, title, author
|> ORDER BY created_at;
```

Draft a first reply to each of them with a model, post it as a comment and
label the issue:

```sql
FROM github.issues
|> WHERE state = 'open' AND comments = 0
|> INFER `model-task:issue-first-reply.v1` INPUT (title, body) AS reply
|> WHERE reply.outcome = 'ok'
|> EFFECT INSERT github.issue_comments (subject_number, body)
     VALUES (number, reply.value.text);
```

```sql
FROM github.issues
|> WHERE state = 'open' AND 'triage' NOT IN UNNEST(labels)
|> INFER `model-task:issue-category.v1` INPUT (title, body) AS c
|> WHERE c.outcome = 'ok'
|> EFFECT COMMAND github.add_labels TARGET number ID number
     INPUT (labels = [c.value.category]);
```

Publish a generated CSV to the repository:

```sql
FROM snowflake.usage_30d
|> SELECT account_id, active_users, trend
|> SERIALIZE FORMAT CSV ORDER BY account_id
     OPTIONS (name = 'usage-30d.csv', header = TRUE, null_marker = '')
|> EFFECT STORE github.files
     SET (path = 'reports/' || name, branch = 'main', message = 'Update usage report', content = content);
```
