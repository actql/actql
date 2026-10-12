# SourceView static request slots

`source_request_slots.collect` consumes a source-owned staged Program and opaque
Binding declarations from that exact Program. It enumerates all static request
fields on connector inputs across all stages, retaining stage/input/field
coordinates and the original immutable cursor. Parameter and Binding holes
resolve against their separate declaration namespaces even when names coincide.
No concrete values are read or substituted. A separately parsed, equal-looking
Binding owner is rejected.

## Value-role decision

The normative owner is [Connector SourceViews](../spec/language.md#sourceviews),
including the explicit static-request-value-slots rule. The earlier Parameter
section already required whole-value substitution and opaque nested business
data, but did not spell out the request slot boundary. It is now explicitly
each static request field: an exact singleton $param or $binding is a reference;
everything else is literal data. The literal key is not another quotation
operator in requests. This avoids interpreting an arbitrary nested business key
as executable syntax and permits a declared object/array to fill one complete
request role without becoming a recursive template.

Reference discovery therefore depends on authored source, not on whichever
Catalog schema happens to be selected. Letting a selected nested schema decide
whether a business object is a reference would change the Program's used-reference
projection with its environment. Under this decision, a nested reference-shaped
object is not an alternate spelling for a Host binding; a future nested-template
feature would need explicit source grammar, not an implicit recursive scan.

Sketch `87dc7144:src/actql-invocation-bindings.ts` recursively scans requests and
can interpret nested binding-shaped business data. That behavior is not carried
over: the clarified whole-value rule is authoritative. The embedded Program
request schema in actql-protocol-schemas remains a JSON object shape; role
interpretation, declaration resolution and contract-dependent type/coverage
checks are semantic checks, not a new JSON Schema type constraint. This changes
neither identity domains nor unrelated schema pins; source meaning now has an
explicit rule for the previously underspecified nested Binding case.

## Scope and limits

[SourceView input syntax](sourceview-input.md) now checks the closed authored
connector form separately. Final assembly must bind both passes to the same
prepared source; neither one alone establishes resolved Input admissibility.

Connector/resource selectors must be present nonempty strings, and connector
inputs cannot also author a local carrier. Request must be an object when
present. Only actual source request fields become slots; local inputs and
Result/receipt imports do not. Empty/absent requests contribute no slots here;
this does not establish their admissibility under the resolved contract or
complete Input syntax. In particular, this collector does not replace schema
checks for explicit empty request or imply that a missing required role is valid.

Collection retains the original source order, not canonical reference ordering.
The reference-index stage must construct escaped normalized pointers and sort
by canonical path/name, then combine these occurrences with operation/Effect
uses. It must not mark declarations unused from this partial inventory alone.
Missing declarations and malformed immediate holes fail atomically. Literal
descendants are traversed iteratively only for resource accounting, never for
reference interpretation. Work includes Binding preparation once plus stage,
input and retained request data traversal; Parameter/source parsing budgets
remain the enclosing integration's responsibility. Slot limits are cumulative
across inputs/stages. These are work limits, not a whole-heap bound.

SourceView selection/completion, complete input-field grammar, Catalog membership,
request-schema assignability, required static/correlation role coverage, concrete
Ref admission and current Host authority remain separate. A resolved declaration
does not prove any of those properties or grant network access. This package
does not construct executable requests, run acquisitions or emit Program CIDs.

## Checked Request materialization

After ordinary SourceView checking and parameter binding,
`sourceview_resolution.parameterized_request_wire` encodes the exact retained
Request fields through the existing typed-value wire encoder. It does not
rescan business objects for reference holes. An unresolved Host binding refuses
materialization; it is not emitted as caller-controlled data. Existing JSON
scalar markers remain part of this typed wire, and a physical driver interprets
the wire under its declared Request contract rather than treating every object
as a template. Ordinary string values retain their exact spelling.

The installed row Source obtains this wire from its selected acquisition owner
and passes it to the Site driver as `requestWire`. Encoding is bounded by the
owner's byte/node/depth limits. The accounted RowRun reserves the wire before
generation and includes its overlap with completion records; encoding failure
uses the same failure/cleanup path before issuing a physical read grant. The
wire does not establish read authority, completed pagination or captured content.

Full Relation row declarations may supply an admitted nonnullable object Request
schema and an object of Catalog facts. The common declaration generator seals
their envelopes and identities together with the exact output schema. An
ordinary view without those declarations still has an empty Request and facts;
that is not an implicit file-list capability. File profiles and actual physical
limits are checked by their existing Catalog and acquisition owners.

## Reference admission at row acquisition

The common row acquisition owner may receive a trusted Host-bound
`ReferenceIssuer` when admission begins. It retains that capability on the
same read attempt and admits returned cells through the existing Host value
admission path. Reference validation uses the attempt's finite page byte,
node and depth bounds. Without an issuer, ordinary value admission remains
in force: a reference-shaped provider envelope is not authority.

The issuer validates provenance and current authorization; it is not supplied
by a Program, inferred from a declared field type or constructed from provider
JSON. Retained reference values keep the issuer's authorization handle, so
later revocation does not become available content merely because row capture
completed. Ordinary field presence, omission, NULL and input ownership remain
the same. This admission boundary neither proves completed listing nor creates
byte custody or a content reference.

## Strict file-content SourceView profile

The installed Relation declaration accepts an optional closed
`acquisition_wire` object containing `kind`, `authority` and, when supplied,
`correlation`. The common declaration Owner supplies the Request envelope
reference and finite snapshot mode, validates against the existing generated
SourceView grammar, and seals the resulting Catalog. Connectors cannot supply a
replacement Request reference, default mode or contract CID through this
object. Correlation arrays retain their authored role order. Omission retains
the ordinary scan declaration; it does not infer fetch authority from facts.
The Program Checker still owns role typing, mode coherence and strict content
profile validation. Declaration or wire admission alone is not that check,
physical capture, read authorization or trusted ContentRef issuance.

The SourceView's own Catalog facts contain a closed `file_content` component:
`version: actql-file-content/0.1`, `kind: file_content`,
`admitted_scope_contract_cid`, `content_schema_contract_cid`,
`version_capability: {contract_cid, required_nonnull: true}` and
`representation: exact_stored_bytes`. The schema CID matches this exact view's
admitted output schema. This profile is separate from `file_listing`; names or
resource suffixes never imply it.

The Request owner checks `acquisition.kind=fetch`, declared `read_content` or
`read_binary` authority (never metadata permission), exactly two correlated roles
`resource` and `version` on both sides, cardinality `one`, and their response
identity. Both keys are nonnullable; the Resource kind matches the SourceView.
The response schema guarantees both roles and a nonnullable `content_ref`
`content` column. MIME narrowing belongs to that admitted value contract, not
a filename or a preceding metadata filter. The same facts body carries the
existing lookup-capacity component with `complete_per_requested_key` and
`max_rows_per_key=1`. Unknown facts components cannot become a fully admitted
body merely because these known components passed.

These checks establish a declaration and its Catalog ownership, not successful
I/O or byte custody. The keyed acquisition still validates each actual response,
the requested immutable version, exact stored bytes, current authority and
strict completeness. Its capture issuer alone can publish a usable ContentRef.
The capture observation is selected by the existing acquisition owner; this
profile does not install a second lookup, capture or authority state machine.
