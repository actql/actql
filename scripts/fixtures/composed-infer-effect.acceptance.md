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
Text lowering captures each single-use source once, then places DATA producers,
INFER/KEEP, both named Results and the Effect in one computation Stage. The JSON
fixture uses separate classify/apply Stages. The retained classified Result
therefore has a generated nonterminal port in text, while the Effect references
the terminal updates port. Operators, contracts, arguments, literal values,
result types/columns/order and physical execution counts must retain the JSON
semantics. Source provenance and these identity-bearing Stage/step references
may differ; Program and Run CIDs need not match between JSON and text. Repeating
the same text request, including after both dedicated processes stop, must
retrieve the original Run.

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
