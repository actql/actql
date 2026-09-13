# Event operation checking

The pipeline retains existing record-key witnesses through to_events, watermark,
session and dedupe, and the explicit events projection. It does not create an
intrinsic ID witness from Carrier roles alone. Window transfer preserves fixed
keys and adds a start component for sliding memberships; events projection must
not turn that composite back into ID-only uniqueness. These internal record
witnesses become public Relation keys only after an explicit Relation bridge.
As-of and nearest source dispatch still follows the actual Carrier, not the
presence of an internally carried key set. In particular, an unrelated retained
Relation key cannot replace Events' semantic identity role. Original validation,
binding, window and producer obligations remain prerequisites of the transfer.

The event checker supports `to_events`, `watermark_events`, `dedupe_events` and
`session`; their normative owners are the corresponding Language sections,
including [event bridges](../spec/language.md#event-bridges). It preserves semantic ID
and clock-source roles and partial payload contracts. UTC timestamp clock sources
retain a separate conversion obligation; their payload values are not replaced.
It requires proof that
generated columns are absent, not complete types for unrelated payload fields.
Classification, valid event values, uniqueness and profile/resource resolution
remain obligations; no event is evaluated by this static checker.

## Watermark output decision

The fixed Sketch reference describes the original schema for `drop`, whereas
the AoA executor adds `watermark_ms`, `late` and `watermark_decision` to every
surviving event for both policies. ActQL explicitly adopts the latter shape,
also consistent with the existing Relation watermark operation. Dropping rows
does not remove label columns. The source remains the existing finite literal
threshold and explicit policy, without importing the richer Relation threshold
and Parameter syntax. Equality at the threshold is not late.

The typed Carrier retains authored role names rather than inventing physical
`id` or `event_time_ms` columns. Generated-column collisions are rejected rather
than overwriting payload. Pipeline integration must preserve incoming window
boundary aliases because labeling/filtering does not change those values.

## Clock-source bridge

The bridge selects existing identity/time fields, preserving qualified provenance
and unrelated payload evidence. `ClockEncoding` distinguishes numeric milliseconds
from UTC timestamp conversion without publishing a synthetic time field. Clock
encoding is derived by the Carrier constructor from the validated source type,
not supplied as a caller assertion. Window checking and watermark obligations
retain that encoding; the explicit `events` projection still exposes the original
timestamp field. Bridge options cannot be mistaken for watermark options or expose
a fabricated threshold. The bridge does not claim that data conversion executed.

## Business-key deduplication

The checker reuses the shared OrderKey reader and type domains, with ordered,
owned partition references and order terms. Only referenced contracts must be
known; open payload field sets are retained. Empty and repeated partition keys
follow the language's explicit equivalence with `dedupe_rows`, differing from
the old reference compiler's nonempty restriction. No implicit keep/tie options
are accepted: first-in-order and failure on an unresolved top tie are the fixed
semantics. The checker retains the tie obligation and cannot infer that actual
event IDs were unique or that data was sorted from a successful static result.

## Sessions

Session checking preserves the input Carrier, unlike the older reference compiler
which always projects its result to Relation. Relation input supplies explicit
identity/time roles; Events uses intrinsic roles. Both retain unknown payload
types but require absence evidence for generated fields. The shared millisecond
reader charges its own scalar/declaration inspection after source preflight;
its usage is deducted from the same operation budget, never reset per argument.

Empty `by` uses one global partition, consistent with partition semantics
elsewhere; repeated keys remain authored occurrences. Both are explicit language
decisions beyond the reference compiler's nonempty restriction. Time arithmetic,
stable session identity construction, binding and execution bounds remain
obligations, not a claim that session assignment has executed.

## Owned execution requirements

The Program operation resolution index binds value admission, semantic identity
uniqueness and timestamp-clock conversion to the exact checked Event operation,
its original input occurrence and source obligation. These checks run before
input use; empty inputs and literal data do not waive them. Conversion retains
the authored payload field and its type rather than replacing it with the clock.

Watermark classification and dedupe representative selection are separately
bound before output. They retain the original threshold/policy and repeated
partition/order terms, respectively. Failure rejects the operation output; a
successful static binding neither attests unique IDs nor repairs duplicates.
Session boundary assignment and stable identity construction have separate
owned output checks. Both retain the positive millisecond gap and, for a
Parameter, the original scalar resolution from that exact stage, producer visit
and operation. Equivalent duration spellings resolve to the same milliseconds
without replacing their source or binding ownership. A different occurrence's
equal value cannot substitute for the selected binding. Searching the owned
requirement group consumes the shared work budget, including nonmatching slots.

The checks retain the operation's partition references and semantic identity/time
roles. Boundary assignment uses the strict gap comparison and exclusive end
specified by `session`; identity construction uses the key tuple, start and first
event identity. They do not attest assignment, deduplicate event IDs, or promote
a shared session label to a unique record key. Value/clock admission and duplicate
identity validation remain prerequisites before input use; failure of either
session check rejects output. Resource and profile resolution remain independent,
and these bindings cannot waive either requirement.
