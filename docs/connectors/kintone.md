# kintone

The kintone Connector reads records, subtables and attachments from kintone
apps, and writes records, attachments and process statuses back. A Program
uses it to classify inquiries, keep an app in step with a CRM or warehouse,
and move records through an app's workflow.

## Sources

- `kintone.<app>` — each app in the connection is a source, named by the
  alias you give it (`kintone.inquiries`). Columns are the app's fields by
  their field code, plus the record number (`$id`), `$revision`, creator,
  modifier and their times. The key is `$id`; a field the app marks "prohibit
  duplicate values" can also serve as the key for `UPSERT`. Subtables are
  read as arrays of objects, one object per subtable row.
- `kintone.attachments` — files in attachment fields: `resource`, `version`
  (the file key), `record_id`, `app`, `field`, `name`, `media_type`, `size`.
- `kintone.contents` — the bytes of an attachment as a `content_ref`:
  `resource`, `version`, `media_type`, `content`. Join it on `resource` and
  `version` from `kintone.attachments`; the Connector downloads only the
  files the join names.

### Installed record reads

The ordinary installed record Source uses the existing managed Source reader
for both checked Query and authored whole-input acquisition. It preserves the
original declaration and typed values; it does not reconstruct an acquisition
from a provider response or a matching schema identifier.

Form metadata has its own authorized read Resource and credential binding.
Record permission does not grant Form permission. The reader checks the
original Form before reading records and again after each page, including the
last page. Both bindings and their currentness checks remain owned until the
same reader confirms cleanup. A changed Form or denied current read stops the
acquisition rather than publishing partially accepted rows.

`maxRequests` counts Form and record responses together; `maxPages` still bounds
record pages. The configured byte, row, parser and value limits are unchanged.
Actual received bytes are charged before a native construction-capacity check
and decoding; insufficient capacity can refuse a permitted-size response
without silently reducing those limits. Repeated Result reads and reopening a
Saved Result use the captured values, not another provider read.

## Types

| kintone field | ActQL | Notes |
| --- | --- | --- |
| SINGLE_LINE_TEXT, MULTI_LINE_TEXT, RICH_TEXT, LINK | `string` | Rich text is HTML; it is read as the HTML string, not flattened. |
| NUMBER | `decimal` | Scale as the field displays; kintone stores numbers as strings, so no precision is lost. |
| CALC | `decimal` or `string` | By the field's display format. Read only. |
| DATE | `date` | |
| TIME | `time` | Minute precision. |
| DATETIME, CREATED_TIME, UPDATED_TIME | `timestamp` | UTC with the offset kintone returns. |
| CHECK_BOX, MULTI_SELECT | `array<string>` | |
| RADIO_BUTTON, DROP_DOWN, STATUS | `string` | |
| USER_SELECT, ORGANIZATION_SELECT, GROUP_SELECT, CREATOR, MODIFIER | `array<string>` / `string` | Codes; names come from the user API. |
| FILE | `array<content_ref>` | Each file is readable through `kintone.contents`. |
| SUBTABLE | `array<object>` | Each object has the subtable's fields and its row `id`. |
| RECORD_NUMBER (`$id`), `$revision` | `string`, `int64` | `$id` includes the app code when one is set. |
| LOOKUP, REFERENCE_TABLE | the looked-up type / not a column | Reference tables are joins the Program writes itself. |

## Effects and operations

Record Effects write records of an app by key:

- **insert** — `EFFECT INSERT kintone.inquiries (subject, body, assignee) VALUES (…)`.
- **update** — ``EFFECT UPDATE kintone.inquiries ID `$id` SET (category = …)``.
- **upsert** — `EFFECT UPSERT kintone.customers ID customer_code SET (…)`,
  keyed by a field the app prohibits duplicates on; kintone's update-by-key
  API applies it.
- **delete** — ``EFFECT DELETE kintone.inquiries ID `$id` ``.

The key named by `ID` must identify exactly one record. `$id` always does; a
unique field does because kintone enforces the constraint. Subtable rows are
written as part of their record: an update that sets a SUBTABLE field replaces
the subtable with the array given.

An UPSERT Mapping binds the original observed unique field as its target key,
with a non-null key value. This does not replace the record's native `$id`.
The selector supplies the key on the create branch; it need not also appear in
`SET`. Other required create fields must still be supplied.

The complete UPSERT requires both add-record and edit-record permissions, plus
the applicable record and field rights. Its Mapping has one exact permission
rule for that operation and write-field set. Observing a present or absent record
does not narrow those requirements. Lookup read permission, currentness, approval
and the selected conditional write remain separate obligations.

Content:

- **store** — ``EFFECT STORE kintone.attachments SET (record = `$id`, field = 'attachments', content = content)``
  uploads the row's `content` (a `content_ref` from `SERIALIZE` or a
  `contents` source) and attaches it to the record's field.

Operations:

- **update_status** — ``EFFECT COMMAND kintone.update_status TARGET `$id` ID `$id` INPUT (action = 'Resolve', assignee = owner)``
  runs a process-management action on the record, moving it to the action's
  next status.

## Setup

```json
"kintone": {
  "connector": "kintone",
  "domain": "acme.cybozu.com",
  "apps": {
    "customers": {"id": 12, "unique": "customer_code"},
    "inquiries": 27
  },
  "credentials": {"api_token": {"env": "KINTONE_API_TOKEN"}}
}
```

Generate an API token per app with the permissions a Program needs: view
records to read; add, edit and delete records to write; manage app for
process management actions. When Programs use several apps, list one token
per app under `credentials.api_tokens` keyed by the app alias; the Connector
sends the tokens of every app a request touches. The `apps` map gives each
app id a name to use in Programs and, optionally, the unique field for
`UPSERT`. Password authentication for a user account works the same way with
`credentials.username` and `credentials.password`. On ActQL Cloud the same
tokens are stored in the Cloud's secret store.

## Capabilities and pushdown

| Operation | Pushed down when |
| --- | --- |
| Projection | Always; the `fields` parameter asks kintone for only the referenced fields. |
| `WHERE` | The predicate is on one app's fields with operators kintone's query language supports exactly: `=`, `!=`, `<`, `>`, `<=`, `>=`, `IN`, `NOT IN`, `LIKE` (kintone's `like` is a word search, so only `LIKE '%word%'` on text fields is pushed down), `IS NULL` / `IS NOT NULL`. Date functions such as `TODAY()` are evaluated by the Host before the query is sent. |
| `ORDER BY` | On fields kintone can sort; text sorts are code-point order, which matches ActQL's binary collation. |
| `LIMIT`, `OFFSET` | Always, within kintone's 10,000-record offset ceiling; beyond it the Connector pages by `$id` ranges. |
| `GROUP BY`, `JOIN` | Never; they run on the Host. |

## Preview and reconciliation

**Preview.** Updates, upserts, deletes and `update_status` are `full_diff`:
the Connector reads each target record, records its values and `$revision`,
and the Preview shows current and new values per field (for `update_status`,
the current and next status). The write is sent with that revision; kintone
rejects a request whose revision no longer matches, so a record edited after
the Preview makes the item `failed` with `conflict` rather than applying the
change blindly. Inserts and attachment uploads are `targeted`: the Preview
lists every record or file that would be created and where.

**Reconciliation.** Inserts and uploads carry a request marker. For an app
that declares a marker field in its connection entry (`"marker": "actql_request"`),
the marker is written into that field and a lost reply is reconciled by
querying the app for it. Without a declared marker field the item stays `unknown` and nothing is
resent. Updates and upserts write the same marker into the declared marker
field in the same request and are reconciled by reading the record for that
marker; a higher `$revision` or the approved values alone are not evidence. A
delete leaves no marker kintone keeps, so a lost reply to a delete stays
`unknown`. Nothing is resent.

For `update_status`, the synchronous revision response is retained provider
evidence, not an `accepted` EffectOutcome or a terminal Outcome Receipt. The
Connector records `applied` only after an actual authorized read-back of the
same app and record confirms the returned revision and the declared next status.
The saved response must belong to that same original request; a later status or
higher revision alone is insufficient. Process eligibility, filters and assignee
rules do not prove that the transition has completed. Missing confirmation keeps
the evidence and uncertainty pending; a lost response remains `unknown`, with
no automatic resend. A revision number is not an OperationRef and does not
supply an asynchronous poll or cancellation capability.

## Limits and cost

- kintone reads at most 500 records per request and limits requests per
  domain per day by plan; large apps are read in pages within the Program's
  row limit, and a read that would exceed it stops with an error.
- Writes are sent 100 records per request; each request is one item of the
  Effect ledger, and every record in it keeps its own outcome.
- Attachments are limited by kintone's file size cap; the Program's byte
  limit applies to downloads.
- Guest spaces are separate domains; configure a connection per guest
  space.

## Example

Inquiries waiting for more than three days:

```sql
FROM kintone.inquiries
|> WHERE status = 'Open' AND created_time < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 DAY)
|> SELECT `$id` AS record, subject, assignee
|> ORDER BY created_time;
```

Classify each inquiry and set its category:

```sql
FROM kintone.inquiries
|> WHERE category IS NULL
|> INFER `model-task:inquiry-category.v1` INPUT (subject, body) AS c
|> WHERE c.outcome = 'ok'
|> EFFECT UPDATE kintone.inquiries
     ID `$id` SET (category = c.value.category);
```

Resolve the inquiries a model judged answered, moving them through the
app's workflow:

```sql
FROM kintone.inquiries AS i
|> WHERE i.status = 'Answered'
|> JOIN kintone.attachments AS a ON a.record_id = i.`$id`
|> JOIN kintone.contents AS c ON a.resource = c.resource AND a.version = c.version
|> INFER `model-task:inquiry-closed.v1` INPUT (body = i.body, attachment = c.content) AS r
|> WHERE r.outcome = 'ok' AND r.value.closed
|> EFFECT COMMAND kintone.update_status TARGET i.`$id` ID i.`$id`
     INPUT (action = 'Resolve');
```
