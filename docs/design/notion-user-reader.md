# Notion user acquisition boundaries

The existing Notion Connector owns vendor response interpretation. Common
ValueContract and Value admission still own logical cells; Credential, Account,
RowRun, Resource and the installed Site retain their existing responsibilities.
No user-page constructor issues a workspace selection, token, grant, Reference,
KeySet, physical cleanup acknowledgement or complete acquisition.

## Original vendor page

`project_notion_user_list` consumes original response bytes with explicit byte,
source-node, decode-depth, row, cursor, identity and cell budgets. It validates
before hashing or producing a page. It accepts the documented user-list
`object`/`type` discriminants and checks the `has_more`/`next_cursor` pair.
A continued page requires a nonempty original opaque cursor; a terminal page
requires explicit null. Empty continued pages are not silently terminal. A page
cannot exceed the vendor's 100-user maximum or the caller's smaller row bound.
There is no sorting, cursor decoding, text normalization, truncation or retry.
Unknown vendor data remains bounded by whole-response admission and is not
interpreted as an ActQL column, transport option or permission.

Every row has the original nonempty user id. Name and user kind may be unavailable.
An actual person variant requires its person object; only that object supplies
email. A bot requires its bot object and never acquires an email from a stray
person-shaped field. A partial user does not acquire a type from object shape.
Unavailable nullable cells remain null, never fabricated names or booleans.
Every declared cell is checked before projection, including an unselected email.
Duplicate identities within the page refuse the whole page. These checks do not
prove that other pages have no duplicate or that a token can see all users.

## Checked projection and identity

The page retains checked cells privately. Selection preserves caller column order
and exact cell text; unknown or repeated selected names refuse. Column-name and
id-array accessors return new arrays, not mutable aliases to the checked backing.
The response hash describes original bytes; equal hashes do not establish the
same physical issuer, installation, response borrow or current authority.
Nullable String contracts describe the public columns without inventing grants
from an observed person/bot label. Metadata, schema and row output use the existing bounded
writers, and failure returns no partial wire result.

## Physical caller and retained resources

The private Node bridge forwards the same typed page through compiler-generated
exports. It does not select a workspace, access secrets, send HTTP, create a
RowRun or establish a numerical supplier. The physical reader must use its
original Site/Account/Credential operation and separately retain all raw response
borrows, current authorization and cleanup responsibility. A parsed page, hash,
Promise completion or Site close is not a physical-retirement acknowledgement.
Whole-paging identity/cursor checks and actual installed capture remain caller
obligations; the page is not a complete normally installed Source.

Whole raw bodies, parse/decode graphs, checked cells, id-map entries, cursors,
selected-column maps and output-writer storage may overlap. Value node/text limits
are structural work/admission limits, not byte reservations or free retention.
The consuming prepared acquisition/Run must retain those holdings through the
existing Resource/RowRun custody path until actual retirement. Cancellation and
response-loss handling remain with those original Owners. No new cleanup ledger
or automatic retry is introduced.

## Verification and vendor references

The focused Catalog cases exercise original person/bot/partial data, Unicode,
nullable absence, empty/continued pages, inconsistent cursors, duplicate ids,
malformed bytes/JSON, cell and output boundaries, and declared cells rejected
before selection. The actual private Node test consumes the normally compiled
Catalog bridge rather than a JavaScript reimplementation. Canonical APIs are
checked on JS, Wasm and Native; only executed targets establish runtime evidence.

Vendor meaning follows Notion's [list-users endpoint](https://developers.notion.com/reference/get-users),
[User object](https://developers.notion.com/reference/user) and
[pagination conventions](https://developers.notion.com/reference/intro#pagination).
The physical request must pin its reviewed Notion-Version; this catalog does not
claim that a version header or an authorization operation has already been sent.

## Credential-bound paging

The private physical user reader sends `GET /v1/users` with the reviewed
`Notion-Version: 2026-03-11` and bounded `page_size`. It passes the original
opaque `next_cursor` back as `start_cursor`; a short or empty continued page
is not terminal. The Catalog alone interprets the original response, validates
every declared cell before projection and emits its bounded metadata/rows.
Whole-acquisition checks reject repeated cursors, duplicate user identities,
incomplete final pages and exceeded total row/body limits without finishing
or capturing a partial Source. No page is sorted, normalized or retried.

The same original installed Credential binding retains token identity across
pages. Every request independently claims its own existing operation use and
rechecks current Account/authority before dispatch and after each await. A
replacement token, foreign invocation, nominally different grant or changed
current Account refuses. The user-list response is not an original workspace
issuer, permission proof or an email capability: the trusted installation must
bind the selected workspace/integration and information capabilities itself.
The reader does not infer those bindings from a user's name, id or bot fields.

Rejected and malformed responses are charged before projection and their exact
original raw bodies remain on the failure. A lost response retains the original
Credential Journal use as Unknown; another `read()` or reuse of that claim
cannot resend or resolve a replacement token. Cancellation also retains the
same failure, raw observations and cleanup responsibility. No retry queue,
additional authorization Owner or OAuth exchange is introduced.

## Reader graph and physical retirement

Before I/O the trusted caller must supply the complete simultaneous retained
and workspace envelope through the existing original acquisition/Resource
owner. Per-page limits, canonical RowRun transfer charge and an explicit
component reservation are not that complete numerical supplier. The graph
includes original options and callback/credential references, AbortController
and combined signal, frozen projection/limit/export tables, the reader state
and its three methods, original raw response/body aliases across all pages,
metadata and parsed Catalog/checked-cell graphs, complete id/cursor sets,
request target/query encoding, bounded row output/JSON parse and the escaped
success/failure observation arrays. Shared objects and cloned arrays still
have reference/layout costs; they do not make overlapping holdings free.
Pending I/O, signing/secret resolution, callback Promises and their handlers
may overlap this graph. Retention lasts through the original consuming
acquisition, not merely through the last physical socket read.

The same reader is single-use. Its private WeakMap rejects copied receivers;
`read`, `requestStop` and `observe` retain the original phase and stop handle.
`observe().cleanupConfirmed` remains false because raw, row, closure and error
aliases can escape. Transport close, fulfilled Promise, canonical RowRun close,
freezing or GC does not manufacture a retirement receipt. The existing
provider-reader caller must keep the same Resource/RowRun borrower pending
until a genuine transfer/retirement supplier exists. Normal installation,
complete reader funding, actual physical retirement and public Notion
read/write acceptance remain separate outstanding boundaries.

The actual physical counters use original Common SQL/AQL preparation, Account,
signed Credential grants, SQLite claims, loopback TLS and canonical RowRun.
Their independent component bounds do not qualify a normal reader supplier;
legacy RowRun close settles its own base account, not the unregistered whole
reader graph. These counters preserve original raw/journal/key/Unknown state.
No live Notion workspace or credential is used. Endpoint versioning follows
Notion's [version policy](https://developers.notion.com/reference/versioning);
request parameters and capabilities follow the existing list-users reference.
