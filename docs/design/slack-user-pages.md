# Slack user pages

The Slack Catalog owns the `slack.users` field declaration and vendor-page
projection. It reuses source-value parsing, decode admission, ValueContract,
CheckedValue and the bounded wire writer. Node only forwards typed calls to
that owner; it does not interpret compiler fields or infer a second schema.

The page is a bounded observation, not a selected workspace, Credential grant,
complete Source, planner/Ledger declaration or raw-custody retirement receipt.
Physical acquisition must retain the original workspace/token/request and
response correspondence, check the complete sequence of cursors and user ids,
and refuse repeated cursors, duplicate ids, limits and incomplete acquisition.
An empty page with a nonempty cursor is not end-of-input. Nothing in the page
projector dispatches, authorizes, retries or ACKs cleanup.

The declared key is the original `id` within the selected workspace. Names,
display names and email are values, not keys or authority. `real_name` comes
from `profile.real_name`; the top-level legacy copy is not an inferred
fallback. The other declared fields may be absent or null in Slack's varying
user objects, so this new declaration makes them nullable. An absent boolean
remains null rather than fabricated false. Empty supplied strings remain empty.
Email presence or absence is not evidence of a `users:read.email` grant.

Every declared cell and same-page id is checked before projection. Unknown
vendor fields are still included in the bounded parsed original, but do not
become columns, permissions or ActQL contracts. `ok` must be true, `members`
must be an array, and an error envelope cannot be relabelled an empty page.
The original nonempty opaque cursor is preserved. Slack's
[pagination contract](https://docs.slack.dev/apis/web-api/pagination/) defines
absent, empty and null `next_cursor` as terminal, including when member rows
are present. This does not admit a null `response_metadata` object, an error
envelope or other malformed/oversized cursor values. Supplied field values pass
the existing typed validator without string/number/boolean coercion. Value and
row/cursor/output bounds fail instead
of returning a partial page or silently deduplicating ids.

The implementation follows the existing public
[Slack Connector](../connectors/slack.md) target and Slack's
[users.list](https://docs.slack.dev/reference/methods/users.list/) and
[user object](https://docs.slack.dev/reference/objects/user-object/) contracts.
Slack documents profile values as absent, null or empty, user-object variation,
and cursor-based pagination. The source parser retains duplicate-key and UTF-8
refusal. Original API response bytes, parsed trees, checked cells, ids, cursor,
wire output and aliases require physical holding and release accounting; this
pure projection does not supply normal quantities or transfer that custody.

## Credential-bound acquisition

The private user-list reader uses the existing Credential binding for both
`POST /api/auth.test` and each `GET /api/users.list`. The trusted caller supplies
separate original grants and uses for these declared operations within the same
original invocation. The binding retains the secret returned by its original
trusted resolver and refuses changed bytes before later sends. Byte equality
and a shared callback are not proof of an original physical secret generation;
normal Site material membership and current generation remain independent.
Neither a token string nor a `team_id` query
argument proves workspace membership: Slack ignores that argument for workspace
tokens. The Catalog checks the actual bounded
[auth.test response](https://docs.slack.dev/reference/methods/auth.test/), and
the observed team must equal the originally selected workspace before any
user-page request. The private-constructor observation is not a grant, Ref,
permission, or evidence about a different binding. User and response digest are
read-only observation data; they never expose credential material.

Each operation independently rechecks current Account and Credential authority
after awaits and at the physical send fence. The identity result does not grant
`users:read` or `users:read.email`. An organization-token workspace selection is
not inferred from a compatible response, display name or callback. Installed
publication and the trusted original Site/token/workspace selection must provide
their own correspondence; the low-level reader is not their issuer.

The reader requires explicit page, total-row, per-response and aggregate-response
bounds, and an explicit page size below 1000 following the method contract.
Only a terminal cursor ends acquisition, including on an empty page. Every id
is checked across the complete sequence before the corresponding page is
delivered, even if projection omits it. A repeated cursor, duplicate id, incomplete
page limit or row/byte excess fails acquisition; no final capture or partial
success is returned. There is no hidden retry, cursor repair, token refresh or
second reader. Rate rejection is retained for the original request rather than
replayed. Normal admission/pacing remains with the installed caller.

The original RowRun caller charges each actual response before interpretation.
The identity response consumes its exact non-row observation charge; data pages
consume their own charged-page tickets. The reader returns observed rows and
completion, while the original caller owns finish/capture. It does not start or
finish another Run. A lost response remains the original journal use's Unknown,
and the same use cannot resolve another token or resend. Original handle methods
use the same receiver; copied handles and a second read are refused.

## Retained inventory and retirement

Before I/O the trusted caller must reserve the entire simultaneous reader graph
through the existing planner/Ledger/RowRun owner. Page and byte ceilings alone
are not such a declaration or a normal numerical supplier. The graph includes
the original Credential binding, grants/uses and retained secret; preparation
context, callbacks and original methods/receiver; signals and read/stop/current
Promises; the auth response, parsed identity and team/user/digest; all received
raw responses and error/result aliases; page parse trees, checked cells, metadata,
id and cursor strings and their sets; full/selected wire strings, decoded rows,
and escaped canonical capture. Parser, hashing, wire output and asynchronous
callback workspace overlap with these holdings, including on failure. Reference
sharing is not zero retained cost, and total byte/row/page bounds include the
identity observation where applicable.

Success totals are not peak simultaneous holdings. Aggregate refusal can retain
the previously accepted raw history plus the last per-response-bounded body that
causes failure. Admission must cover that extra response and its transport
workspace, not merely `maxTotalResponseBytes`. A current decoded page can likewise
overlap the previously accepted rows before a total-row refusal. Cursor target
encoding workspace follows the bounded cursor's encoded size before the final
target ceiling check. Shape/length checks precede set allocation and Unicode
scanning of the bounded original selection and workspace id.

The reader always reports `cleanupConfirmed: false`: raw observations escape to
the result, failure and callbacks. Socket close, a settled Promise, cancellation,
freezing, dropping a reference or GC cannot acknowledge their retirement. The
existing trusted custody-transfer/retirement owner must close that responsibility
before normal reservations can be released. Legacy canonical-RowRun component
reservations do not fund this complete graph or prove its retirement. Missing
normal supply or original installed correspondence remains unavailable; this
module does not substitute constants, a new ledger or a cleanup assertion.


## Installed users Source

The connector-owned Host declaration selects the existing users Catalog and
private installed Source adapter. It does not replace the public Connector
configuration reader or add another schema evaluator. The selected workspace
bytes, Account configuration, Site generation, runtime and selected TLS
certificate are part of the original physical binding. Closed profile and Site
readers snapshot own data properties without invoking accessors; Unicode is
neither normalized nor used to infer a workspace identifier.

The adapter borrows the original acquisition, RowRun and declared reader
capacity after Common begins the same session. Its synchronous factory performs
no I/O. It captures each provider, Site and Host callback with its original
receiver, then admits one read only. Before network work it rechecks the
original current Account decision. The same Site issues a separate workspace
identity grant for the original invocation; the users grant is never retargeted.
The exact identity response consumes its original observation charge, while
each data page consumes its own ticket in that same RowRun. The aggregate raw
byte ceiling must fit the generic Source's declared finite transfer budget;
this consistency check does not issue a capacity reservation or permission.

The wrapper retains the actual reader before method capture or awaits, along
with its original binding, separate grants, read/stop Promises, provider and
callback receivers, signal graph and error/result aliases. The configuration,
workspace and TLS original bytes, decoded declaration, request/target wires,
canonical binding hash workspace and those reader holdings overlap. A current
failure or stop closes the transport without preparing another reader or
replaying a request. Escaped observations still keep cleanup unconfirmed, and
the existing recovery Owner retains the same Run and reservation on failure.
Site close, Promise settlement and weak-reference collection do not retire
those aliases. Missing original reader capacity remains unavailable at the
normal Host entrance; neither profile bounds nor startup-only capacity fills
that independent supplier responsibility.

## Channels Source

The existing Slack Catalog projects `conversations.list` pages into `id`,
`name`, `topic`, `purpose`, `member_count`, `is_private`, `is_archived` and
`created`. Nested topic/purpose values remain exact text. Missing observations
remain nullable; they never become empty text, zero counts or false flags.
Counts use the distinct Signed64 contract. Their exact original numeric token
is normalized as an integral decimal and checked before conversion; the JSON
parser's binary64 placeholder is not the value. Creation seconds use checked
integer multiplication and the existing canonical UTC Timestamp owner.

The physical reader selects public/private channels and includes archived
channels. It rejects observed IM/MPIM discriminants, duplicate channel ids and
repeated cursors. An empty page with a continuation is not terminal. Every
returned column is checked before projection. No identifier prefix, channel
name or one-page result supplies workspace identity or whole-input proof.

The installed Source exposes separate users and channels views through the
existing Resource-to-operation binding. Each actual RowRun uses its own
`slack:users:list` or `slack:channels:list` grant and the same Site's separate
workspace-identity grant on the original token. Account/current/abort checks
remain per original read. The plural Source binding identifies a new installed
generation; no saved Run or predecessor publication is rewritten.

Channel response bytes, parse/decode trees, exact numeric-token text, normalized
integer/UTC text, checked values and rows-wire workspace overlap. The page,
identifier/cursor sets, original callbacks, reader failures, returned responses
and escaped aliases remain retained. The installation also retains its two
reader factories, acquisition memberships and declaration callbacks. Declared
bounds are not a Resource supplier. Missing normal reader capacity refuses;
transport closure, Journal success and GC never establish raw retirement or
return the original reservation. Cleanup remains unconfirmed until its actual
owner can prove those duties complete.

## Original Command request encoding

The same Slack Catalog encodes the closed post, reply, reaction and archive
inputs from an original CheckedValue. Its private request retains that original
value and contract; an equal rechecked value is not the retained input. Every
declared field and supplied value is checked before emission. Text constraints,
including enumeration and extents, remain with the original contract. There is
no JSON-to-CheckedValue adapter, implicit optional field or scalar coercion.

Message `ts` and `thread_ts` are exact String identities. They never pass through
binary64, a Host Date, or the derived Timestamp domain. The bounded writer
preserves Unicode and mrkdwn text without normalization. The post/reply text
limit follows Slack's documented 40,000-character truncation boundary: the
codec refuses a larger scalar sequence rather than changing approved text or
creating an implicit upload. Writer and input-recheck bounds remain separate
from that vendor write-request bound.

Post and reply require an explicit item marker, emitted as metadata with
`event_type: actql_effect` and `event_payload.effect_item_id`. Reaction and
archive requests forbid that marker because Slack does not return equivalent
reconciliation evidence for them. The marker String is DATA: only the existing
Effect/Preview owner can bind it to the original item. A request codec or
matching text cannot create that identity, a current target, approval, a
Credential use, an authenticated outcome or permission to resend.

The retained request, original checked object and child contracts, channel and
marker Strings, recheck frames, encoded document and escaped body can coexist.
Their bounds do not fund these holdings. Existing installed Effect, Site,
Journal and Resource owners retain currentness, exact request binding, claim,
Unknown resolution, response evidence and physical cleanup responsibilities.
A successful codec does not supply those originals or close the public Command
execution and recovery boundary.

## Original messages history projection

The messages Catalog retains exact `channel:ts` identity and the independent
original `ts` and `thread_ts` Strings. `posted_at` is the same instant in the
existing exact UTC Timestamp domain; physical epoch text is parsed with integer
seconds and nanoseconds, never a Host Date or binary64 conversion.

A pending history request belongs to one original history control. Its admitted
page retains that nominal occurrence and consumes the pending request before
response parsing. Cursor and exact time pagination preserve separate vendor
signals, reject repeated/non-progressing continuations, and leave inaccessible
history unavailable. Protocol termination is not proof of full Source coverage,
current authorization, physical cleanup or capacity. Replies require their own
original operation, grants, pagination and observation lifetime; a recent
history window cannot prove coverage of replies to older parents.

The adopted missing-count projection applies only to complete ordinary records
with both count and thread keys absent. Generic page DATA has no such original
history occurrence and retains unknown count. Explicit zero, positive count and
null preserve their meanings, including a positive count without thread
metadata. Event, partial or retained-thread ambiguity never becomes zero.
The known ordinary `bot_message` subtype is eligible under those same original
history and absence conditions; its subtype alone is not a partial/thread hint.
Unknown subtypes, event envelopes and changed/deleted/replied/broadcast cases do
not gain this inference. A bot message with retained thread hints stays unknown.
Other retained thread hints, such as `reply_users`, `latest_reply`, `root` or
`parent_user_id`, keep a missing count unknown even when the two primary keys
are absent; their contents are not evidence of an ordinary non-thread record.
Reactions and files keep their independent nullable/retained value rules.

The public `thread_ts IS NULL AND reply_count = 0` predicate uses the common
comparison-context rule: its existing Number zero is losslessly admitted under
the original `int64` column contract. The column is never promoted to Number,
and a different frontend or cold read cannot reinterpret a lost raw integer.
Original checked input, bounded RowRun capture and the same expression owner
retain this correspondence; none issues a physical Source or Resource grant.


## Original history transport

The private history reader projects each HTTP channel/cursor/time argument from
its original Common pending request. The captured provider callbacks retain
their original receiver; provider replacement after a token await cannot change
the protocol. The column list captures each original indexed value once and
validates that owned snapshot. Index getters keep their ordinary responsibility;
caller Array methods, iterators and species cannot replace the retained fields.
Account and currentness are checked around every await, including
identity observation and row consumption, before any next Common request is
constructed. The same retained credential binding observes `auth.test` with a
separate workspace-identity use; the history operation keeps its own grant/use.

Each raw response is retained and charged before decoding. Identity consumes
its non-row ticket before history starts. Each history page passes its exact
ticket to the original RowRun consumer before a dependent request can be made;
its last ticket is accounting, not evidence for an unrelated response prefix.
Unknown transport outcomes remain with the original journal use, with no retry
or replacement token. A terminal Catalog control does not prove complete
thread acquisition, current physical Source publication, cleanup or funding.

The live reader retains its method/callback receivers, workspace/channel/column
Strings, immutable limits and authorization, Common history/request/page values,
response envelopes and bodies, output wire and parsed rows, charge tokens,
observations and failed-result aliases, cancellation signal and in-flight
Promises together. Common closing and a closed transport do not acknowledge
retirement of escaped aliases or return a ReaderLoan. The actual Host supplier
must cover that simultaneous graph before this private reader is admitted.

### Original message reply pages

The Catalog reply protocol selects one exact row of an admitted ordinary-history
page. Its retained page and row occurrence, rather than equal JSON, identify the
selection. A reply that already names its parent uses that exact `thread_ts`;
otherwise the actual replies response must establish the parent. Terminal
completion requires both the actual parent and the selected message. Generic
message-page admission does not acquire ordinary-history completeness or infer a
missing reply count.

Each reply exchange has one nominal pending request. The protocol retains the
entire admitted response-page prefix, exact cursor and timestamp tokens, and all
original checked rows. Repeated IDs emit once only after bounded complete
CheckedValue equality; a changed row refuses completion. Equality has explicit
Value comparison limits independent from single-value admission limits, since
comparing two valid values retains and charges both. Page, aggregate byte, row,
comparison and work bounds remain separate. Exhaustion consumes the pending
request and does not authorize replay.

Cursor continuation is preferred. Ascending time continuation advances the
exclusive `oldest` token using exact instant ordering, with no Number or Host Date
conversion. Empty or nonprogressing continuation refuses completion. The physical
caller must separately retain original responses, operation-specific uses,
observation tickets and cleanup custody, and consume each prior response ticket
before a dependent exchange. This DATA protocol supplies no transport authority,
normal ReaderLoan or complete workspace coverage. Closing its control keeps
retained aliases and is not a physical cleanup acknowledgment.

The private physical reader exposes an opaque original-page token only through
the history consumer's page metadata. The exact history reader retains its
Common page/request, actual exchange and raw response, operation authorization,
charge and workspace identity. A token is eligible only after consumption and
the subsequent original-current check, and the history read must have completed
successfully. Copies, a token from another reader, an invalid row occurrence or
a second selection of that occurrence do not start another reply reader.

The reply reader captures the original provider callbacks before history I/O,
retains their receiver and checks the same credential binding/control/journal/
resolver references and Run/Account context. Its `slack:messages:replies` grant
and uses are separate from history and workspace identity. Before each exchange
and after awaited callbacks it rechecks the original history current callback
and any distinct reply current callback. A previous `auth.test` observation is
retained identity evidence, never a permission for a different operation.

Both controls retain full exchange records, including pending requests,
authorizations, actual responses and charges, even when later projection fails.
Escaped result and failure objects keep that same original prefix through
private outcome membership. The reply reader keeps the closed Common control
and its typed page prefix as well as raw response aliases. These records,
callbacks, maps, selection sets, parsed output and concurrent workspaces belong
to the actual Host resource inventory; bounds, weak maps, closure settlement
and garbage collection are not capacity or physical acknowledgments.

Combining reply output with already captured history rows requires the original
Source owner's coalescence and capture boundary. This private reader does not
silently overwrite an earlier captured row, establish complete channel history
or supply a normal business ReaderLoan. Its finite terminal result alone is not
an installed complete Slack Source.

### First-original history and reply coalescence

Cross-acquisition message coalescence retains each original completed history
page and each selected completed reply prefix. The selection must refer to the
same original history page and row; matching JSON, identifiers or projected
cells cannot reconstruct that selection. Closing a completed protocol preserves
its completion fact and its original references; closing an unfinished protocol
does not make it complete. Neither operation acknowledges physical cleanup.

For a duplicate `channel:ts`, the output is the exact first history CheckedValue
row. Private presence metadata is captured alongside that row from the original
bounded parser occurrence, including presence of `users` inside each reaction.
Vendor omission establishes no value. Explicit null and independently justified
ordinary-history count zero remain established facts. All overlapping facts
across retained observations must agree, including facts first established only
by a later response. Later supplied fields never fill or replace earlier cells.
New keys retain their original reply CheckedValue rows. The existing full-row
equality requirement for repeated IDs within reply pagination remains intact.

An established parent count cannot be smaller than the distinct selected child
keys. This prevents a derived parent zero from surviving incorporation of an
actual child. These checks establish consistency of the selected original
observations, not an atomic or latest-value snapshot, complete workspace or
thread coverage, current authorization, or permission to retry an original Run.

The projection retains history and reply controls, original pages and checked
rows, per-row presence vectors, nested reaction presence, per-key occurrence
lists, child-key maps and the output row-reference array. Comparison controls,
subvalue recheck workspace and bounded output encoding overlap those retained
originals. Page, occurrence, row, node, text and work limits bound computation;
they do not provide resource reservations. Escaped rows and wire strings retain
their own lifetimes after protocol close and are not reclaimed by a physical
response or Store acknowledgement.

### Original message projection receiver

The Node receiver obtains the completed history control only from its original
history reader state and each reply control only from a completed reply reader
bound to that same state. The three Catalog callbacks are captured once with
the original provider receiver, before the history acquisition awaits. Partial
callback groups refuse admission. Caller arrays and bounds are copied once;
copied reader handles, matching response JSON and foreign history selections
cannot choose the retained controls.

Before Common coalescence, the receiver checks the existing history and reply
current callbacks and checks their combined stop signal after every await.
Projection performs no additional request, secret resolution, grant claim or
response charge. Its returned JSON is DATA; the original Common projection and
all raw, typed, request, ticket and outcome prefixes stay in private custody.
An escaped success or failure retains that graph, not a physical cleanup claim.

The receiver additionally retains the source/reply handles and states, copied
control and column arrays, captured callbacks, bounded limit record and combined
signal. The Common projection, bounded canonical wire and parsed output overlap
those retained originals. Caller-visible output does not issue a Source capture
or prove complete thread coverage. Connecting the existing actual RowRun and
normal resource supplier remains a separate responsibility; a final ticket is
accounting rather than evidence for an otherwise missing original prefix.

### Original history time windows

The history protocol can retain an explicit open interval of original Slack
`oldest` and `latest` decimal epoch tokens. Both tokens preserve their exact
String bytes; their derived instants use the existing exact Timestamp owner.
The original lower bound remains fixed across cursor and time pagination. A
time-pagination upper bound may only tighten to the last original message
token, and cursor pagination retains the preceding upper bound. Endpoints and
out-of-window rows refuse the consumed pending occurrence. Known message
fields are admitted before that extent check, without skipping unused fields.
The existing unbounded constructor keeps its original no-window behavior.

This protocol describes a physical interval, not a derivation from WHERE or a
proof that a broader original Source request has been preserved. A checked
QueryRequirement, original bound Parameters and the declared request still
own the selected scan. Provider filtering cannot hide invalid known fields in
that extent; retaining a residual filter cannot restore their failures. The
projection-only declaration does not advertise filter preservation. Inclusive
query predicates, thread coverage and ordinary Source capture need their
actual existing-owner connections rather than reinterpretation of these tokens.

The retained lower/upper token references, normalized lower instant and each
request's current upper token overlap the original page and protocol prefix.
Timestamp parsing/comparison workspace is bounded by the token and page limits;
those limits are not Resource capacity or a physical cleanup acknowledgement.

### Node history-window projection

The private Node history reader captures explicit `requestWindow` DATA once;
Common validates the exact boundary tokens and interval order. The caller must
bind those DATA to the original selected request. A residual `WHERE` does not
allow a broader original request to be relabelled as a narrower scan. This
projection does not publish an installed Source or advertise filter pushdown.

The same retained Common history issues every cursor and time-continuation
request. Its original lower bound is retained throughout; only Common selects
a later upper bound. Node forwards those tokens without Number or Date
conversion, with `inclusive=false` once whenever either bound is present.
Absent lower bounds retain the old private request JSON representation.
Malformed bounds fail before secret resolution or HTTP; a response outside the
original window is refused rather than filtered away. The response and its
charge remain in the original failure custody.

The current [vendor method contract](https://docs.slack.dev/reference/methods/conversations.history/)
caps a dispatched page at 999. Dispatch takes the smaller of that cap and the
original Host page ceiling; it does not lower the Program's total row ceiling
or add read authority. The public documentation's older maximum-page wording
is a separate documentation clarification, not a global Array or row limit.

A windowed Common history control is retained before workspace identity I/O,
but its first pending request is issued only after the original identity and
current checks. The captured callback/receiver, two bound String references,
control, every page/response/charge and escaped result/error may overlap.
Closing the protocol does not prove physical retirement of any of them.

### Original channel-to-history preparation

A channel page is one admitted occurrence in an actual channel-list reader,
not a workspace grant or a complete messages Source. The explicit
`createSlackChannelListReaderForHistory` entrance retains the original reader,
request/grant/use/response/charge prefix and checked pages, including a failed
or pending exchange. A page token becomes selectable only
after its consumer and current check return, and only after the whole reader
succeeds. `selectSlackOriginalChannel` selects one original page/index once;
copied tokens, equal rows and another reader cannot substitute for that pair.
The ordinary channel reader keeps its existing charge-only callback metadata
and does not retain this additional page/selection inventory.

The dedicated history entrance requires that selection, the same provider
receiver, workspace, credential binding and invocation subject. Common creates
history from the checked channel row and retains the original page/index;
matching channel text does not establish that membership. Both the history's
current callback and its original channel reader's captured current callback
are checked before subsequent work. Stopping the original reader prevents new
identity or history exchanges. Each operation still needs its own actual
Credential grant/use; neither the old identity observation nor the selection
issues permission.

Selection preparation is one-use. A failed typed history preparation keeps its
original selection and is not rebound with larger limits. Direct history
constructors remain independent DATA entrances and cannot claim channel-page
origin. The channel-derived entrance does not accept a caller channel override
or a WHERE-derived time window. A complete messages Source must separately
realize the full selected request, including required conversation kinds and
threads, under its actual bounds; the observed channel pair alone proves none
of that coverage.

The explicit reader additionally retains its page map, per-page records and
selected-index sets, copied id references, every original request/authorization,
pending or failed exchange, success/failure prefix, selection
WeakMap keys/records, original callback/receiver and downstream history control.
The Common history's optional page/index field has layout cost even when None.
These overlap the page rows, checked contracts, raw responses, charges and
encoding workspace. The provider method wrappers retain their original methods
and receiver in both reader forms. Bounds and weak reachability do not fund or
retire these holdings; protocol closure is not a physical acknowledgement.

### History conversation enumeration

The ordinary channel reader requests `public_channel,private_channel` and its
Common projector continues to reject IM/MPIM discriminants. History discovery
has a separate `createSlackConversationListReaderForHistory` entrance with the
fixed `public_channel,private_channel,mpim,im` request and archived records
included. These are the conversation kinds of the existing
[Slack method](https://docs.slack.dev/reference/methods/conversations.list/);
the token's actual scopes and visibility remain separate requirements.

`project_slack_history_conversation_list` admits that broader response through
the same bounded Common decoding and checked-field construction. Present
`is_im` and `is_mpim` must be booleans; ordinary channel admission still requires
them to be false when present. Missing conversation-specific fields remain
nullable, without an inferred name, member count, kind or identifier prefix.
All known fields in every returned record are checked before selection, even
when a later projection omits them. Exact count tokens, duplicate identities,
cursor history and cumulative bounds retain their existing checks.

The broader reader retains the same original response/charge/page/index graph
used by history selection and cannot fall back to a narrower projector when
its captured Common port is absent. Its fixed request is not inferred from a
residual filter, nor is terminal pagination proof of a complete workspace or
thread population. It does not change the public channels declaration, saved
wire, operation grant or Source authority. The additional projector closure
and fixed request discriminator overlap the existing reader graph and typed
decoding workspace; their presence is not resource admission or cleanup ACK.
