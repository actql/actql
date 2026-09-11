# Text-time Host policy admission

The normative owner is the text-time request policy in
[expression fragment execution](../spec/language.md).
The existing machine schema is
`spec/contracts/actql-expressions.json#/schemas/fragment/properties/request/properties/text_time_policy`.
Its predicate-consumer copies are checked for equality; this implementation does
not introduce a second wire schema or change their pinned identities.

`text_time_policy.admit` accepts canonical bytes and an independently selected
expected CID. The closed body has version `actql-text-time-host-policy/0.1` and
five required positive safe-integer fields: `max_input_codepoints`,
`max_input_utf8_bytes`, `max_pattern_bytes`, `max_output_bytes`, `max_replacements`.
Unknown members, missing values, coercions and noncanonical spelling are rejected.
The opaque Policy and Ceiling retain the full-body CID and field provenance.
`emit` writes the same canonical component to an existing bounded writer.

The shape agrees with the profile component at Sketch `87dc7144` in
`src/actql-portability.ts`. Its reference values are examples, not defaults.
The shared library does not select the reference profile implicitly. The reader
reuses the existing capacity-policy admission pattern without conflating their
distinct fields, identity domains or units. Independent Node identity and schema
checks accompany MoonBit boundary and canonical-wire tests on all three targets.

This is policy integrity and shape only. Check Environment membership, profile
selection, envelope/argument-bound derivation and static obligation discharge
remain separate. Actual text/date/regex evaluation and enforcement belong to the
execution implementation; no evaluator or lowerer is added here. Successful
admission does not authenticate the Host or grant execution permission.
