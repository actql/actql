# Property Graph Delta source connection

Status: frontend connection and the generic JSON literal dependency are
implemented; successful integrated text Delta execution remains unverified. This is not
completion of the Property Graph migration or the full frontend profile.

Fixed base: `7e337afa9e5a64035c5925aca1d93ba0ef787aaf` (main, including
#428, #431 and #442). The common application contract is documented in
[Property Graph Delta application](2026-10-05-property-graph-delta-application.md).

## Meaning and ownership

The existing named-operation syntax accepts
`FROM g |> apply_graph_delta(with: changes, field: 'delta')`.
The pipe receiver supplies the Graph input; `with` is a previously declared
Relation producer reference and `field` is a column-name string. The frontend
retains the admitted Graph definition and identity domain for subsequent DATA,
MATCH, node_rows and edge_rows use. It does not acquire, persist or apply a Delta
itself, change any wire contract, or use a legacy Graph conversion.

The new lowering helper emits the existing `apply_graph_delta` Program operation
and reuses the shared named-argument and producer resolver. The common checker
owns field presence and its non-null JSON type. The common execution owner owns
the single-row requirement, closed Delta shape, exact base/before/target checks,
capacity and cleanup. Malformed bodies are not accepted merely because their
column has JSON type.

Both Graph-prefix call sites are connected: DATA/MATCH prefixes and Graph-to-
Relation prefixes. A Graph operation after a Relation transition remains
unsupported, and string-valued producer references are not guessed as names.

## Independent evidence

- Before the change, focused JS run `run-ZJfvUc` passed the independently
  authored complete JSON Program check and rejected its source equivalent with
  `UnsupportedGraph` (1/2 tests).
- After the change, focused JS run `run-hRAD7Z` passed 5/5 tests: complete
  expected Program, ordinary checker, quoted DATA and MATCH continuation,
  common argument refusal, and exact scope/Carrier diagnostics.
- Existing Graph rows and Subgraph caller tests passed 11/11 in JS run
  `run-ghnOFn`. Node syntax checks and independent fixture loading also passed.
- The public fixture reuses the common owner's independently authored valid
  Delta application Program and expected node/edge rows. These are machine-input
  controls, not evidence of successful text Delta generation.
- Two text cases supply a typed identity JSON as an intentionally malformed
  Delta. They test semantic execution refusal. Seven text cases test preparation
  refusal and zero durable Run acceptance/provider I/O. Neither group is a
  successful text Delta acceptance test.
- The new generic JSON source case constructs one node with property `p=7`,
  supplies an independently authored Delta through `SELECT JSON r'''…'''`,
  and expects `[{"p":8,"node_key":1}]`. Its machine-input control uses the
  same independently authored complete Program. Definition provenance,
  contract and base/target snapshot CIDs are computed from those authored
  declarations; no product output supplies an expected CID or row.
- Focused run `run-uQT7Pf` passed 1/1: the complete source Program equals the
  independent expectation and both pass the ordinary checker. The explicit
  RESULT declaration has its own existing output projection. This is lowering
  and admission evidence, not public execution evidence.

Focused command (pinned MoonBit/Node PATH):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js src/query_program --filter '*Graph Delta source*'
```

Packed evidence will record the clean source SHA, normal-pack manifest/digests,
Local/HTTPS results and logs separately. No CI success is asserted here.

The first packed run (`run-SZmSsj`, source
`2b88e0c23fc3de86ef29c0f0ce4eca6ca2ca2bb0`) passed both JSON controls and
both semantic execution refusals in Local, then failed the aggregate Source-I/O
assertion before HTTPS. The source-free execution-refusal fixtures had omitted
their zero-read count, so the harness expected one external read per case.
That fixture accounting is corrected; rows, contracts and refusal expectations
are unchanged. This run is not full public acceptance evidence.

The second packed run (`run-sCzVlj`, source
`53386d620120e22dba24e58d1510e448d9366463`) passed the selected Local and
HTTPS corpus, including preparation refusals, but the driver then attempted
unrelated String restart acceptance without a String fixture. The new narrow
selection is now registered at the existing restart/native dispatch boundaries
as well. This run establishes its completed boundary cases, not overall driver
success.

## Separate JSON literal dependency

Normal source execution needs an ordinary JSON-producing expression. The common
parameter contract has no untyped JSON parameter, and the existing managed
DuckDB transfer profile only supports DOUBLE/VARCHAR. A Delta-only literal,
provider adapter or post-lowering Program mutation would hide that gap.

The follow-up is [common typed JSON #463](https://github.com/actql/actql/pull/463)
and [generic source #466](https://github.com/actql/actql/pull/466). This branch
integrates their pushed commits, without changing the Delta application owner.
The common contract defines precision, duplicate keys, JSON null versus SQL
NULL and preparation limits. JSON-valued row expectations use that contract's
typed-cell envelope; semantic Delta/identity bodies retain their owner format.
Successful authored source through `apply_graph_delta` to Named Result in
packed Local/HTTPS remains a required integration acceptance. Parser/checker
success and earlier machine controls do not establish it.

## Parent integration on 2026-10-06

Normally integrated generic JSON source
`9935c0581db1d91e3f5879b226e556c4f96cd3e7`, containing common typed JSON
`00521024e055471a00736c8a2c024166f35267af` and main
`eb74d7b65d0f338ef5862a7d9cd7397744a08eaa`. The two harness conflicts
retain Delta/JSON selections and all new main analytic/membership selections.
There is no new grammar or application-owner change in this child integration.

On the merge tree, selected source/independent-Program/checker regressions
passed 6/6 (`run-Ts0aKP`, `focused-test-L6t3xB`); independent Values identity
tests passed 2/2 (`run-9rCWhD`, `focused-test-seGhpn`). Harness syntax,
manifest, canonical vector, document-family and diff checks passed. The
independent normative preimage matches the JSON parent's current identity.
Integrated packed acceptance will use one clean source revision and one set
of normally packed tarballs for both JSON and Delta selections. Old packed
successes retain their original source SHAs and are not relabeled here.

### Shared-boundary handoff

B retains only the JSON literal/value/wire and text-to-Program connection.
The existing #463 boundary packet requests A/C review; those reviews are
not yet claimed. The combined expression law is
`sha256:800ab1eed12a3bcf98779493833081bc636c6ea108adbe1b57a57c01512b2f67`.
The dependent schema, registry, profile and generated pins were regenerated
in the common parent; historical declarations and independent vectors remain.
This pin integration needs dot and the relevant contract owners' review.

D/A should note one already existing #463 capture-restoration connection:
`model_execution/restored_capture.mbt::begin_restored_model_response` passes
`wire=true` to the common schema-directed canonical conversion of a persisted
checked response. JSON cells use `{"$json":payload}`; JSON null differs from
SQL NULL. This is not canonicalization of the provider's original Model wire,
a cancellation decision or a new recovery owner. B has not added another
fix to D's original-wire/cancellation work. Original wire custody and checked
response restoration must remain distinct. H's Effect value comparisons,
request identity, recovery hooks and Ledger cleanup are unchanged by this
child. No expression scheduling/work or retained-capacity adjustment is made.
