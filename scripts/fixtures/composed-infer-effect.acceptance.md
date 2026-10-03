# Public composition fixture

`composed-infer-effect.aql.template` is an independently authored, complete
text request. Bind only `__PUBLICATION_MAPPING_REF__` to the installed mapping,
then submit its exact bytes through `client.aql(document, {format: 'aql-text'})`.
The harness does not append an Effect or edit the lowered Program.

The JSON comparison is `composed-infer-effect.program.template.json`.
`composed-infer-effect.expected.json` supplies the independent rows, column
contracts and order, Source/Model observations, write counts and restart points
for both inputs. In particular, the source predicates remain `id = id`, the
authored JOIN bound remains 10, and the Model task's item limit remains 2.
`ITEM KEY (id)` selects the key; the preceding `ASSERT UNIQUE BY (id)` invokes
the existing checked assertion and physical row owner. It is not unconditional
proof or duplicate elimination.

The common Program may use different generated identifiers and step aliases.
Text lowering captures each single-use source once, places DATA producers and
INFER/KEEP in one computation Stage, and imports its retained classified Result
through an ordinary Stage Result edge for the terminal Effect continuation.
Both text and JSON therefore use four Stages; generated identifiers, projection
steps and KEEP correspondence plumbing can differ. The classified and updates
Results each use their producing Stage's terminal port. Operators, contracts, arguments, literal values,
result types/columns/order and physical execution counts must retain the JSON
semantics. Source provenance and these identity-bearing Stage/step references
may differ; Program and Run CIDs need not match between JSON and text. Repeating
the same text request, including after both dedicated processes stop, must
retrieve the original Run.

This first connection retains one complete public Relation after INFER before
the Effect continuation. Additional retained roots in the Model Unit, or hidden
immutable range snapshots that would require separate carrier/output ports,
remain implementation limits; they must not be dropped or treated as invalid
language. The shared Model component and execution owners are not replaced.

The ordinary `scripts/test-packed-salesforce-source.mjs` consumer includes both
inputs and reuses its existing approval/restart/failure/cleanup matrix. The
`--composed-text` flag selects only text composition for local diagnosis. Pack
from a clean fixed SHA with the ordinary package producer and use
`ACTQL_PACKED_CLIENT_PACKAGES` to reuse those five tarballs. Keep artifacts when
capturing evidence. The consumer installs outside the checkout and runs both
Local and HTTPS without a MoonBit toolchain.

The duplicate counterexample uses the normal full text and separate databases
with two matching rows keyed by id 1. The NULL counterexample uses the complete
`composed-infer-effect-null-assert.aql.template` and a matching row whose
right_amount is NULL. This nullable assertion is checked before INFER; a NULL
source id filtered by `id = id` or JOIN would not test assertion rejection.
Both requests must fail without a Model call, checkpoint or Effect write. The
physical assertion's typed duplicate/NULL cases remain covered by the existing
bounded row-owner regressions.
