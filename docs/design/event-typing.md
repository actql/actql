# Event operation checking

The event checker begins with `watermark_events`; its normative owner is
[event bridges](../spec/language.md#event-bridges). It preserves semantic ID
and numeric-time roles and partial payload contracts. It requires proof that
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
