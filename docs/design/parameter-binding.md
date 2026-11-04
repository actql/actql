# Parameter declarations and binding

`parameter_binding` implements the pure declaration and invocation-value part of
[Parameters and binding](../spec/language.md#parameters). It does not establish
whole-Program use proofs, substitute expressions, admit
opaque `bindings`, publish protocol envelopes or start a Plan/Run.

## Declaration grammar

`read_declarations` accepts an optional owned Cursor for the Program's `params`
map. Absence means no declarations; a present map is nonempty. Names use
`[A-Za-z_][A-Za-z0-9_]*`, remain case-sensitive and are stored in UTF-16 order.
Source parsing and owned-tree admission precede this boundary.

`value_contract.read_parameter_syntax` is the trusted type adapter. It constructs
the same private, immutable Contract representation as the general readers while
retaining Parameter-only constraints. It is deliberately a syntax result, not
proof that its preserved `default` or `meta` cursors are valid. Only
`read_declarations` performs the complete declaration/default admission.

Parameter types are string, number, int64, decimal, boolean, timestamp, date, closed
object and homogeneous recursive array. `nullable` defaults to false throughout
this Parameter grammar. General authored and checked value contracts still require
explicit nullability. Number integer/minimum/maximum, string duration format and
array length/max_items constraints apply at their respective recursive positions.
`integer: false` imposes no integer restriction. `integer: true` does not introduce
a safe-integer ceiling. Both numeric bounds are inclusive and finite; their
intersection is checked against values without adding general satisfiability
inference to declaration admission. `length` is positive and safe; `max_items`
is nonnegative and safe. Consumer-specific bounds remain separate.

`take` (SQL/Pipe `LIMIT` and `OFFSET`) accepts a Number or int64 Parameter
declaration and resolves the original typed value in Common. Its count remains
in `1..9007199254740991`, and its offset in `0..9007199254740991`; nullable
declarations do not permit a null count or offset. An int64 binding is read
directly as an integer, without conversion to Number or reparsing its wire
string. The checked declaration, binding identity and bound-value provenance
remain distinct from the normalized `REL.limit` count body. Existing Number
and literal bodies are unchanged. This admission does not extend other
operation-parameter types, arithmetic or operational clocks, and a selection
limit does not narrow the original Source scan's admission extent.

An invalid bound `take` count can be rejected during row-capacity derivation
before the general operation-scalar closure. That rejection retains the exact
parsed Program and checked Parameter name. The public check projection uses
the existing positive-safe-integer reason only for that same Program, then
uses its already admitted binding origin to locate either the supplied value
or its declaration default. Equal Program bytes are not original membership;
no input value, generated SQL location or execution authority is inferred.

Source-free template checking connects Sort and literal Take obligations to the
same pipeline's existing checked producer orders. Each requirement retains its
original operation owner and the selected contextual resolution; the complete
Program still closes publication, capacity and interpretation contracts. No
execution Parameter is substituted to manufacture an order. Parameterized Take
bounds retain their unresolved consumer conditions until those are connected;
a literal-only order connection does not discharge them or authorize a Run.

`default` and annotation `meta` belong only to named declarations, not nested
type contracts. Metadata is nonempty canonical JSON-model data with reserved
top-level `actql_` keys rejected; it never participates in binding decisions.
A field named `meta` is ordinary object data. Neither default values nor supplied
business objects are searched for `$param` holes or recursively substituted.

Every default is validated at declaration admission, even if a caller will later
supply an override. Defaults satisfy both the base value contract and recursive
Parameter constraints. Decimal uses canonical fixed-scale wire strings and exact
coefficients, dates use the Language calendar, and nullable fields remain required.

## Semantic declaration projection

`emit_declaration` emits the annotation-free declaration required by the
[stage/Program semantic envelopes](../spec/language.md#local-approval), including
the `type` member of a canonical Parameter reference. It takes an admitted
Declaration, whose original owned source is retained privately. It removes only
that declaration's top-level `meta`, preserving defaults, authored optional type
fields, recursive constraints, and business fields named `meta`. It does not
expand a checked contract, insert omitted `nullable: false`, substitute a default,
or apply the typed-value identity projection to a default's wire spelling.
Changing a default remains a semantic declaration change; presentation annotation
changes do not affect these bytes.

Keys are emitted in canonical UTF-16 order, using text validated by declaration
admission. Explicit continuation frames avoid recursive traversal and a second
full value tree. Arrays use indexed reads; objects retain sorted field handles
while being emitted. The original admission limits bound source size, and the
shared Writer bounds emitted bytes, value nodes and open-container depth with
the same text/measurement/hash behavior. Output limits are not sorting-work or
heap-memory quotas, and the declaration keeps its source arena alive.

This is an internal identity-preimage API, not public explain: the output can
contain literal default values. It emits one declaration, not a Program/stage
envelope, used-name proof, canonical reference index or authorized Invocation.
The reference implementation's older `$.field[index]` paths are not reused;
the current reference contract requires RFC 6901 pointers and explicit sorting.

## Binding result

`bind` takes admitted declarations and an optional supplied-value object. Unknown
supplied names fail before resolution. A missing supplied value uses its complete
default if present, otherwise contributes a missing name. Explicit null never
selects a default. There is no deep merge or implicit value conversion.

All selected values are checked before returning a result, so a missing value
cannot hide an invalid supplied value. `Ready` contains an immutable complete
set; `NeedsBindings` exposes only the sorted missing-name list, not partially
ready values. Both accessors return detached arrays. Each bound value records
`Supplied` or `Default` separately from its checked typed value. These origins
are not typed identity inputs. `Ready` privately retains the admitted Parameter
types alongside the values; callers cannot pair the values with another declaration
set when computing identity.

BoundValues also retains the exact Declarations owner, exposed by
`bound_declarations` for internal composition checks. `bound_value_count` and
`bound_value_at` provide bounded indexed access without copying the full array.
Owner identity is not emitted or hashed and changes no Parameter identity bytes.
Consumers such as author-guard binding can reject values admitted under a
different declaration set before resolving usage-specific constraints.

Duration validation parses `[0-9]+(ms|s|m|h|d)` with ASCII case-insensitive units,
including leading-zero digit sequences. Exact integer conversion to milliseconds
must be positive and no larger than 9007199254740991. No binary64 parsing,
fractional tokens or zero duration are accepted. The checked value remains a
string with its source-normalized spelling; duration operand lowering consumes
the millisecond interpretation. Parameter identity emission applies that same
interpretation without replacing the stored string.

## Parameter Values identity

`emit_values` emits the exact version/values preimage defined by the
[Parameter identity wire contract](../spec/protocols/contracts.md#parameter-value-projection).
`stringify_values`, `measure_values` and `parameter_values_cid` use the same
emitter with text, measurement and incremental hash sinks. Their input is the
opaque `BoundValues` from `Ready`, not `NeedsBindings` or an independently supplied
declaration/value pair. The output is the hash preimage, not the wire envelope
including `parameter_values_cid`. External artifact admission and whole-Program
or extracted-unit used-name proofs remain separate.

Decimal uses the versioned coefficient/precision/scale preimage. Duration uses
positive safe integer milliseconds. Business objects containing `$actql_value`
are escaped into sorted name/value pairs; ordinary values are not universally
wrapped with their declarations. Origin, metadata and admission-only constraints
do not enter the value preimage. All values come from trusted binding; tags are
never interpreted from arbitrary input JSON.

Emission is nonrecursive and uses read-only indexed access to owned values and
type fields, scheduling one child at a time. It creates no second projected tree.
The hash sink does not materialize a serialized String or byte array. Bytes,
nodes and depth limits cover the complete emitted preimage, including version,
maps, tags, decimal bodies, escaped pair containers and pair-name strings. These
are output budgets, separate from binding's input budgets. Object keys are not
nodes; escaped pair names are string values and are nodes. Text and hash paths
make the same admission decisions. Writer failure prevents finalization or reuse;
no partial body or CID is returned. Retained input, writer key tracking and
traversal state still use memory, so output limits are not total-heap limits.

The result is immutable, but enforcing one retained set across attempts/resume is
the later Run boundary's responsibility. Usage across stages and prohibition of
structural-selector substitution require semantic traversal; scanning raw JSON
for `$param` is not a substitute. Public explain projections and privacy policy
also remain outside this value-bearing API; results do not derive debug printers
that automatically expose bound values.

## Resource limits and diagnostics

Declaration limits bound parameter count and the complete raw declaration tree:
nodes include map/declaration/constraint/default/meta values, keys consume UTF-8
text bytes, and depth counts containers with a scalar root at zero. Full-tree
preflight bounds the sum before per-declaration type/default validation. Each
subtree pass has the same caps but cannot admit more total source material than
the whole-tree preflight permitted; this is not a separate allowance per default.

Binding limits bound all selected value trees together. Nodes count each selected
root and descendant; the outer supplied map is not a value node. Text includes
each selected parameter name plus all string values and object keys. Missing names
are bounded by the admitted declaration set. Default and supplied values consume
the same allowance. Each selected root has independent root depth zero, with the
same depth ceiling. No partial result escapes on budget failure.

`declaration_usage` reports the existing source-tree preflight node and UTF-8
text-byte charges, including declaration keys, defaults and metadata.
`binding_usage` reports the selected-value preflight charges, including selected
Parameter names and reused defaults, for both Ready and NeedsBindings. Missing
values cost no value nodes; the supplied outer map is not itself a selected
value. NeedsBindings exposes no partially ready values. These counts let the
Program constructor subtract admission usage from an aggregate allowance before
the next phase without changing the established acceptance rules. They are not
CPU-work measurements, serialized lengths, heap bounds or new identity members.

Traversals are iterative, child frontiers reserve node budget, and maps are
opened once per collection rather than per field. Exact boundaries pass, negative
limits fail, and budgets are input/work limits rather than total-heap guarantees.
Errors preserve original paths and spans, including default locations. Preflight
failures can precede domain diagnostics. Declarations and effective values are
visited in canonical name order; nested constraints use field/index order.
These are package issues, not final CLI codes.

## Verification

[Fixed cases](../../portability/corpus/parameters.json) cover declarations,
recursive constraints, defaults, explicit null, missing values and rejection.
`generate:parameters` emits tests from fixed expectations; `check:parameters`
checks freshness, schema consistency and tooling regressions. The two embedded
Program schemas share the generated recursive Parameter type definition.
`generate:parameter-schemas` updates those definitions and their artifact pins;
document metadata and identity fixtures are updated with their existing commands.
Decimal schemas enforce scale <= precision at both declaration and recursive type
positions. Schema shape checking does not replace duration conversion or the
validation of complete typed defaults.

The [identity corpus](../../portability/corpus/parameter-identities.json) fixes
canonical text and CIDs independently of MoonBit output. `check:parameter-identities`
verifies those expectations with an independent projection and SHA-256, generated
test freshness and schema regressions. `generate:parameter-identities` regenerates
tests without rewriting expectations. `generate:parameter-identity-schema` updates
the projected-value schema and artifact pins; use the metadata and canonical
identity generators afterward. Product tests check exact output budgets and
text/hash parity in addition to these fixed identities.

Product tests additionally exercise whole-set budgets, metadata, source locations,
ownership, wide maps and deep recursive declarations on JS, Wasm and native.
They do not establish full compiler, Run or reference conformance.


## Same-parent declaration preflight

The split declaration reader has one preflight implementation. Its admitted
Cursor supplies immutable indexed children, key spans and scalar views. Container
length and depth refusals precede child construction; keys are charged in original
source order before descendants. A key refusal retains its original child path
and selects that child's original key span. It does not reconstruct a detached
object, field map or second path to recover the same location. Type, default,
metadata and binding rules remain with their existing semantic owners.

`begin_parameter_declaration_preflight` retains the original input, Cursor and
DeclarationLimits over the same `PreparationCapacity`. It reads the actual
outside retained/execution debits and adds its fixed constructor packet once.
The entering caller must already back the borrowed source, limits and the
getter/current/resize call frame; the packet is neither prepaid entrance credit
nor proof that a backend has supplied that backing.

Preparation observes only the selected subtree's constructor metadata and its
original ancestry, closes the existing phase-work receipt, then grows that same
reservation before calling the original declaration preflight. Pending children
are bounded by the original node budget, refusal paths by the selected root's
actual ancestry and original depth limit, and key normalization by the same raw
text guard. The Decode, collection, normalization and Resource owners supply
their own representation quantities; this domain adds only its constructor and
quotation controls through the existing representation tariff.

A failed grow retains the original metadata and quotation. Retrying that grow
does not repeat the observation or reclaim spent work. Success retains the same
original declaration-read continuation and partial usage tuple. Finishing the
original type/default/metadata body still requires that next phase's complete
reservation; preflight success alone is not a complete Program check.

Only after a successful synchronous preflight returns may reconciliation retire
its temporary traversal and normalization backing. A refusal retains its full
original diagnostic location. Clearing this continuation drops its references;
it does not settle the parent, release escaped source/outcome aliases, refund
attempts or acknowledge physical stop. Actual backend entrance funding and the
remaining type/default/metadata constructors must consume this same parent.

### Type facts before default construction

`DeclarationReadInput` drives the same reader through header, type and value
constructor boundaries. Ordinary `finish_declaration_read` drives those steps
to completion; a funded caller may advance one step at a time. Neither path
has a second implementation of name, type, metadata, default or constraint
admission. The input retains either its private traversal or its completed
original Result, and repeated finishing returns that Result unchanged.

The header retains the actual object, canonical name order and selected
original Cursor. It performs no non-null admission before that entry's name
check. The type step applies Decode's original non-null requirement and the
existing Parameter syntax reader once. Before the value step,
`declaration_read_pending_syntax` borrows that same completed syntax, including
its checked ParameterType and original metadata/default Cursors. The caller
can therefore request the existing Value constructor inventory using the
actual admitted type, without interpreting type names or default contents to
reconstruct a contract.

The value step keeps metadata validation before default admission and the next
entry's name/type work. It forwards the same ParameterType into the final
Declaration. Finishing a partly advanced reader resumes those original facts;
it does not reread the type. Phase and original-data accessors perform no
current callback, Map lookup or resource mutation. Phase DATA supplied by a
caller is never accepted as a proof or transition input.

These semantic boundaries do not supply their own resources. Header/type,
metadata, default Value, refusal and retained-result coexistence must all be
funded on the same preparation before advancing. The preflight packet still
covers only the initial four-reference read input; its state field replaces
the former optional-result field without adding a parallel owner. Backend
entrance frames and full later-phase funding remain the actual consumer's
responsibility, rather than implied by a successful pure reader step.

### Funded Header on the original preparation

After successful preflight scratch has returned and reconciled,
`prepare_parameter_declaration_header` grows the same original reservation
before advancing that read input's Header. The Header constructs its actual
ObjectView Map and name vector before the semantic parameter-count guard.
Their storage therefore uses the complete original field count, including a
count that will subsequently refuse; it cannot use the configured count as a
shortcut for already required construction.

The original empty/count rule also selects whether the Header can reach its
name sort. It remains one semantic definition in Parameter binding. Actual
sorting frames use the existing pinned builtin sort constructor inventory;
Maps, Arrays, indexed lookup and failure paths use their existing owners.
Header and sort storage are priced once each by the same representation tariff.
The independent quotation-control inventories share only their source-proved
sequential maximum after earlier synchronous quotes have returned. Neither a
previous quote nor a free byte observation is construction credit.

A failed Header grow retains its exact quote and leaves the semantic input at
Header. A successful retry advances that same input once. Resource currentness
may call out, so the driver checks the same read phase again after growth;
that is a cheap internal state check without another current callback. Header
success still means either its original typed refusal/completion or readiness
for Type, never a completed type/default check. Preflight reconciliation cannot
shrink a now-live Header, and clearing local references does not return its
parent debit or acknowledge physical cleanup.

The shared indexed-read quantities include the original boxed Option tags,
consistent with the existing logical representation model. The child carrier
owns an Int payload, Cursor index and two tags; the field carrier owns its
Cursor index and two tags. This corrects representation quantities at their
Decode owner without changing tariffs, semantic bounds or backend allocation
claims. Type, metadata, default, retained-result and actual backend entrance
funding remain subsequent obligations on this same parent.

### Original declaration quantities before Type

After Header, one fixed phase observes constructor quantities for all original
declarations before their Type/default bodies are constructed. The caller first
funds the complete original-Cursor work stack and retained fact vector on the
same reservation. The selected admitted subtree's node count bounds that stack;
the actual Header declaration count bounds retained observations. This is a
structural construction bound, not a wire-byte guess or per-field allowance.

The Parameter syntax owner supplies its original type-role geometry and the
actual root default/meta Cursors using the same role constants as its reader.
Default/meta descendants do not become type constructors. Parameter binding
retains their own quantity observations in Header's canonical declaration order.
Only its private current ordinal selects a retained fact. No caller ordinal,
equal record, path or CID can replace that association. Work and fact projections
return the same stored optional records; absence is not reported as zero.

One existing phase-work receipt bounds the complete quantity walk, with actual
metadata visits reported once. Per source node, type/control selection, indexed
field reads and default-tree observations have a source-derived bound of32
visits. This is not CPU time or a count of full validations. A failed initial
grow performs no observation; retry retains the original quote. Once observed,
repeated access forwards the same facts and cumulative work without rescanning
or obtaining another receipt. Semantic null/name/type/metadata/default refusal
ordering remains in the original reader, separate from these DATA observations.

Only after the synchronous walk and its original receipt returned may
reconciliation remove its Cursor-stack scratch. The same Header, original
Source, fact vector and outside debits remain funded. The Header's completed
sort scratch can be reused only after that Header invocation returned; it is
not retained as another logical owner. The preparation's extra retained-body
scalar and Header's fact-reference slot are included in their respective
constructor inventories. Neither clearing references nor retaining facts
settles the parent or proves physical cleanup.

The Type phase uses these original facts; the later default phase must use the
actual admitted ParameterType and complete constructor coexistence. Observing quantities
does not prepare a type, validate a default, admit a Program, fund a backend
entrance frame or authorize execution.


### Funded original Type construction

After the quantity traversal returns and reconciles, the Type continuation
quotes the complete original Parameter syntax constructor from that reader's
retained current facts. ValueContract owns the returned type graph, recursive
work, current ObjectViews, key-check path, refusal locations and identifier
normalization quantities. Existing collection, indexed-path, normalization and
pinned builtin sort owners describe their own backing. The Host composes those
quantities through the same representation tariff; it does not infer a type or
copy the syntax rules into a resource recipe.

The continuation grows the same preparation reservation before advancing the
original reader once. A failed grow retains the original quote, selected Cursor
and fact record. Retry neither repeats the quantity walk nor reads another
parameter's type. After the resource current callback returns, both the same
read phase and those original associations must still hold. These are internal
identity checks, without another callback. The original reader retains the
completed ParameterSyntax for the subsequent metadata/default phase; a resource
step's success can also hold the original typed refusal, rather than Program
acceptance.

An invalid declaration name uses that same Header-selected child's original
key span and path. The immutable Header already established its own complete
field inventory; reconstructing a filtered allowed-name list and rechecking
the same object does not add semantic evidence. Name-before-null ordering,
non-null admission and the actual Parameter type reader remain unchanged.
Nested field refusals retain their existing ValueContract location path.

Sequential quotation constructors share only their source-derived control
maximum. The current Type quote also retains its two original-association
references in the existing continuation. This is domain construction DATA,
not spare capacity, a minimum, RSS or a numerical physical-entry supplier.
Type scratch is not reconciled yet: the later metadata/default constructor
still requires its complete coexistence quote. The same syntax retains the
Decimal fact needed by Value quantity projection, so that selected route does
not traverse the admitted type again. Clearing
local references keeps the parent's charge; it neither refunds work/attempts
nor acknowledges cleanup. The Value continuation below funds the next
metadata/default and final declaration constructors. Actual backend entrance
backing remains an obligation of the original caller.


### Completed type facts in the default quantity projection

The original Parameter syntax reader retains the maximum Decimal precision as
it admits the same recursive type. The scalar is updated only after that
Decimal's existing precision/scale guards, and is returned only with a complete
ParameterSyntax. Default and metadata contents cannot supply this fact. The
original private syntax holds it alongside the same ParameterType and source
Cursors; no caller-provided precision, equal wrapper or global table is read.
Its extra scalar word belongs to the Type return inventory under the existing
representation tariff.

The syntax-based Value construction inventory consumes that completed fact
without another Contract traversal. Its quantity arithmetic and malformed
geometry rule remain shared with the existing direct checked-Type entry. A
consumer possessing only a checked ParameterType still funds that entry's
actual metadata walk; the syntax-based route needs none. Neither route admits
a default, reconstructs its type or grants capacity. The same original syntax
can therefore supply the complete later default quotation without an unfunded
pre-quotation type graph walk. Metadata checks, actual Value admission and
Parameter constraints remain their existing semantic owners and ordering.
Their full same-parent construction envelope and backend adoption are still
required before the funded reader can advance that Value phase.


### Funded metadata, defaults and completed declarations

`prepare_parameter_declaration_value` selects the same reader's completed
ParameterSyntax and retained current construction facts. The original syntax
supplies the already admitted type and Decimal quantity. The original default
subtree supplies its own geometry; absent and wrong-kind metadata remain
separately observable facts. Neither a caller ordinal nor a copied quantity
record can select another declaration in this continuation.

Value admission owns its returned Value/CheckedValue and complete traversal,
scalar, indexed-child, normalization and refusal construction families. Its
body inventory retains the collection extents it already computed; the full
phase forwards those extents instead of expanding the same Arrays/Maps again.
Parameter binding adds its own Value Limits and outer refusal carriers while
that call is active. Those caller records cannot be charged only to a later
phase or treated as already backed by the callee. Parameter binding also owns
its unchanged metadata reader, subsequent constraints, declaration records and
incremental slots in Header's original entries Array.

The original semantic step runs metadata before Value admission before
Parameter constraints. Each synchronous family has returned before the next
begins, so the quotation selects the maximum of their complete temporary
families. Already constructed types/defaults and the next returned declaration
coexist with that maximum. The initial control packet funds the source-derived
sequential quotation maximum, including its original association references;
it is not an additional grant or an assumption of spare capacity.

The same preparation grows before the semantic Value step advances once.
A failed grow retains its exact quote, original syntax and facts. Retry makes
no second quantity scan or type read. Original associations and the read phase
must still hold after resource currentness returns; these comparisons call no
second external current callback. Repeated declarations reuse the same retained
fact inventory and original work receipt. New Type/Value peaks preserve the
larger already charged peak until an explicit final reconciliation, rather
than silently shrinking a previous phase or refunding its work.

`reconcile_parameter_declarations` accepts only the original reader's complete
successful cached result, including absent declarations completed at Header.
All synchronous constructor scratch has returned, while original source and
escaped output aliases remain in the retained envelope. An original refusal
keeps its full diagnostic backing and cannot take this success-only shrink.
Repeated finishing returns the same semantic result. Clearing the continuation
drops only its references; it neither settles the parent nor reports physical
cleanup. Binding supplied/default values into a later binding result, Program
and Context consumers, actual backend entrance frames and physical preparation
supply remain distinct original-owner obligations.


### One binding reader for ordinary and funded callers

`BindingReadInput` retains the original declarations, supplied Cursor and Value
limits. Its Header, Selection, Preflight and Value boundaries belong to the
existing semantic binder. Ordinary `bind` drives that same reader to its
cached result; a fixed resource caller can fund and advance one constructor at
a time. There is no alternate interpretation of supplied shape, default
selection, nullability, constraints, missing values or binding budgets.

Header closes the supplied object before any selected-value work. Each
Selection retains its original Declaration and source Cursor once. Missing
entries are accumulated while later supplied values are still checked; a
missing field cannot mask a subsequent invalid value. Explicit NULL remains
supplied, rather than selecting a default. The selected origin is recorded
before name/source budget admission, so failures preserve their actual domain
and original location. Preflight charges the same cumulative binding budget;
Value admission uses the same original type and constraints only for supplied
values. Defaults forward their already admitted original CheckedValue.

Each Declaration also retains its original ParameterSyntax. The provided-value
step uses that same syntax's ParameterType; the existing public type projection
remains the identical original. A later constructor quotation can use the
syntax's completed Decimal fact without reconstructing a type or scanning its
graph. The extra reference belongs to the declaration's return inventory, not
a capacity grant or new authority.

Original selection getters forward their stored optional records without
lookups, allocation, IO or current callbacks. Only a complete result exposes
Ready BoundValues or the original missing declarations. Repeated finishing
returns that same Result and does no binding work. Semantic boundaries alone
do not fund construction: Header, selected-source preflight, supplied Value,
output/diagnostic coexistence and actual Program/Context/backend consumers
still require their corresponding original-parent resource connection.

Completed successful binding also retains the actual per-value node/text
admission maxima from that same admission pass. Reuse compares both these
maxima and the cumulative selected-source preflight usage with the requested
node/text ceilings. A fitting smaller ceiling forwards the same Result without
new admission. Depth must remain equal or relaxed; failure reuse still requires
identical limits because successful usage does not prove a failed prefix.
The two retained scalar maxima are included in the original Header reservation.


## Original binding Header reservation

The binding continuation uses the same existing preparation reservation. Its
initial immutable control packet is added once to the actual outside debit;
the entering caller separately owns borrowed declarations, input and limits,
and the frame used to read/current-check/resize that reservation. The Header
ancestry observer claims one original work phase, spends its actual parent-node
visits and closes the receipt before any later resize; it does not refill work
for each field. Invalid original fixed limits retain their direct refusal
without starting that metadata walk.

Header construction accounts for the actual supplied object width, including
invalid unknown fields, rather than clipping it to the declaration count. The
Decoder owns the composite `closed_object` Map, key-check, pair-array and refusal
path construction. Its key-check quantities come from the same structural owner
that chooses the actual key-check implementation. ParameterBinding adds only
its names, original reader/Budget, empty entry/missing arrays and result carriers.
No second key threshold, semantic verdict or byte tariff is introduced.

The fixed Host continuation retains one original reader and quote. It grows the
same parent before advancing Header, retains both on refusal to grow, and checks
the original reader boundary after the resource call can reenter. Completion of
that reservation call is distinct from the reader's original semantic result.
Clearing local references does not settle the parent or acknowledge physical
cleanup. Selected-source preflight, provided Value and final binding inventories
require their own later construction backing; Header is not their allowance.


## Original selected bindings and construction lifetime

A construction-observed binding retains one private inventory of its actual
original declaration, selected Cursor, provided/default choice, subtree geometry
and path depth. The existing source-selection helper supplies both ordinary
binding and this inventory. Later semantic selection forwards the retained
original instead of repeating a Map lookup. The inventory carries construction
DATA only; it does not admit a value, authorize access or replace an original.

The complete fact vector is funded before its one work-metered metadata walk.
A single original phase covers all entries; cached work is not a per-entry work
allowance. The same parent keeps Header, facts and already constructed outputs.
Confirmed metadata scratch retirement changes the live quote base, so later
constructors do not regrow that completed scratch merely from an old peak.

Each selected name/source preflight uses the remaining original binding Budget.
It shares its constructor recipe with declaration preflight. Provided values
use the original declaration Syntax and the existing full Value and Parameter
constraints owners. Cached defaults keep their original CheckedValue and do not
repeat those admissions, but their selected source still spends the current
binding Budget. The binding-specific Origin error carrier remains included.
Missing names cannot mask a later invalid supplied value or expose partial
BoundValues as Ready.

A retry preserves the same original fact and quote. After the Resource boundary
can reenter, both phase and original fact must still match before one semantic
advance. Only the original cached Complete Ok can reconcile synchronous scratch;
failed source/location backing remains charged. Clearing drops only local
references, leaving original aliases, the parent and consumed work with their
existing owners. It does not acknowledge physical stop or make a new Run grant.
