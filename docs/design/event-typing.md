# Event operation checking

The event checker supports `to_events`, `watermark_events` and `dedupe_events`; its normative owner is
[event bridges](../spec/language.md#event-bridges). It preserves semantic ID
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
