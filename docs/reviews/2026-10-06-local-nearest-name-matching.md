# Nearest input name matching

## Scope and implementation

Verified implementation SHA: `34918ca1efd20904e69d80185200f9a57b6313a3`.
The following documentation commit does not change runtime or test sources.
This unit depends on the Pool name-matching parent, PR #585, at
`feb175d059b17b0176106564f05f9157009a4db2`. It does not depend on the sibling
Ranking or Score/Normalize continuations.

Nearest already uses bounded key comparisons and the common admitted output
row cursor. Its remaining input-name boundary flattened the component name and
compared complete identity names in one poll. `local_veca/nearest.mbt` now
borrows the typed names and retains one offset. The existing shared
`compare_reference_fragment` inspects at most 64 raw UTF-16 pairs per poll.
Component matching keeps reference-spelling semantics; identity matching also
requires the original qualification role. `Unqualified("left.id")` cannot
substitute for `Qualified(Left, "id")`, despite equal reference spelling.
Fixed output roles are matched directly without flattening names.

The first component fragment shares the existing field-bind poll. Later
fragments consume separate cumulative control units. Short-name work totals
are unchanged. A cursor position adds one reserved workspace slot before reads.
There is no new provider, scheduler, output owner, ledger or atomic fallback.
The fixture-only `nearest_name_offset` reader grants no execution authority.

The Session still owns stop confirmation and cleanup. A cancellation request
does not release the pending field or either input. Cleanup before confirmed
stop returns `NotStopped`; afterward it clears the cursor once. Input binding,
identity validation, ordering, score arithmetic and completion remain under
their existing owners.

## Independent boundaries

| Shape | Control exact / one-short | Workspace exact / one-short |
| --- | --- | --- |
| One numeric record per Carrier port, short names | 52 / 51 | 32 / 31 |
| Same direct or fused Relation input, depth ten | 66 / 65 | 52 / 51 |
| One record per Carrier port, 513-unit role names | 84 / 83 | 32 / 31 |
| Same long names through Relation, depth two | 98 / 97 | 44 / 43 |
| Four long Text identities through Carrier | 1517 / 1516 | 45 / 44 |
| Relation input with an unused 257-item Array | 1104 / 1103 | 44 / 43 |

Each long role has 511 ASCII units followed by one supplementary character:
513 UTF-16 units, or nine 64-unit fragments. Two roles on each of two ports add
`2 * 2 * (9 - 1) = 32` control polls. The one-record structural workspace is
`6 record + 4 score + 3 scratch + 2 identity + 17 fixed = 32`. A shared
depth-two Relation recheck adds `8 + 2 + 2 = 12` slots. These limits are derived
from phases, not from a successful execution's reported usage.

The typed Relation entry fixture previously retained Carrier-only budgets. It
now includes the already-existing scalar/Vector admission: `52 + 2*(2+5)=66`
polls and depth-ten cursor: `32+8+10+2=52` slots. This is not a new work charge
for short names. Existing exact/one-short controls and typed limit assertions
are retained, not replaced by generous budgets.

Quanta 1, 7 and 256 produce the same expected values and cumulative control
totals. One-short work fails with `NearestWorkLimit`; insufficient workspace
fails before reads with `NearestWorkspaceLimit`. Both identity and component
name phases have cancellation/cleanup regressions. The qualification fixture
also guards the distinction between typed identity and spelling equality.

## Ordinary retained Host path

The existing public Nearest harness has one additional ordinary JSON Program:
two Values results with numeric IDs, a typed two-component Vector column and
513-unit identity/component names; direct Relation Nearest; two downstream
consumer tasks. No array-to-Vector inference or manually assembled task state
is used. Expected published rows, in order, are:

```json
[
  {"candidate_id":1,"query_id":1,"rank":1,"score":5},
  {"candidate_id":2,"query_id":1,"rank":2,"score":5},
  {"candidate_id":1,"query_id":2,"rank":1,"score":5},
  {"candidate_id":2,"query_id":2,"rank":2,"score":5}
]
```

The actual public result-name set must be exactly `published`, `consumed_a`
and `consumed_b`; each result is read and compared independently. The same
request is reused without another dispatch or Compute advance.

An unused 115-item Array precedes the role columns. Its recheck takes
`2*115+3=233` polls; initialization, read and identity mismatch reach 236.
The scalar read/recheck and nine identity-name fragments reach 248. Vector
read/recheck reaches 254 at name offset 64. The existing Host quantum of 256
therefore stops at component offset 192, proved by the companion core fixture.
The public observer pauses this actual advance boundary; no sleep chooses it.
Cancellation preserves retained snapshots while physical stop is unconfirmed,
publishes no partial Result, performs no additional dispatch, and reclaims the
snapshots after confirmed stop.

The original three public cases also pass: long identity validation,
output cancellation after one committed row, and unused Array admission.
The production-route manifest registers the new core, qualification and public
fixtures. Gate mutations remove required roles, remove the actual suite import,
or substitute flattened name matching; they must fail the completion check.
This gate is a regression connection check, not an arbitrary-program proof.

## Executed verification

The following checks ran on the clean implementation SHA above. Toolchain
selection follows AGENTS.md and the local verification skill. Evidence paths
are relative to this checkout and remain local, not published artifacts.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js \
  src/query_integration/nearest_name_matching_wbtest.mbt \
  src/query_integration/nearest_text_scanning_wbtest.mbt \
  src/query_integration/nearest_typed_entry_wbtest.mbt \
  src/query_integration/vector_input_recheck_wbtest.mbt \
  src/query_integration/nearest_composite_output_wbtest.mbt \
  src/local_veca/nearest_name_roles_wbtest.mbt \
  src/query_integration/local_carrier_vectors_wbtest.mbt --filter '*nearest*'
```

JS: **35/35**, `run-Zi3r4s`, `focused-test-LFffia`. The filter executes Nearest
cases only; unrelated Pool cases in the admission file are not counted.

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-name-pattern 'public retained nearest|nearest (requires|cannot|public key)' \
  adapters/host-node/public-nearest-key-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
```

Node: **8/8**, `run-vFgZ8w`, `focused-test-vdbQRG`: four real public Host
cases and four resource-gate regressions. Public tests use checkout exports and
real retained files, not packed distribution acceptance.

The selected three-target API generation, `moon info --target js,wasm,native
src/local_veca`, passed. Workers and Node Host generators passed their read-only
freshness checks without changing tracked fixtures. Changed MoonBit files were
formatted individually; `git diff --check` passed. The actual resource checker
still reports 69 operations, 62 mapped production routes and seven typed
pre-execution refusals, not whole-Local boundary completion.

Runtime preparation selected only `local-node run-host-core`, from the same
production sources later committed above. Both asset/package `--check` commands
passed at that SHA. No runtime source changed between preparation and tests.
Relevant SHA-256 payloads:

| Ignored payload | SHA-256 |
| --- | --- |
| `packages/local-node/_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js` | `610a6c53d2e1cc26e55d345f216d96012040211d580d704796fb2b39dd80779d` |
| `packages/local-node/_build/js/release/build/retained_host_bridge/retained_host_bridge.js` | `7d7d8cee953ac22d15e74df6dc3fc5f05b5b987ad281c2ebd41f43c3aefdfa5d` |
| `packages/run-host-core/dist/client_values_host_abi.js` | `afd59ea3984645a1e8112c0470133b80846bd10cb7d6a417e5abf88aabd2ad22` |

Candidate evidence is preserved separately: compile failure `run-vxQofL`;
fixture preparation and stale typed-entry budget failure `run-6RC4Ag`;
Moon timeout `run-xaRAKP`; incorrect provisional-progress fixture assertion
`run-3lBZpE`; and 90-second four-case Node timeout `run-KR0gDM`. None is a pass.
The corrected candidate passed 13/13 JS (`run-8jYr2Q`), 23/23 affected callers
(`run-JlrP5Y`) and the isolated new public case plus guards, 5/5
(`run-atqsPc`). The clean-SHA checks above supersede those candidate results.

## Residuals

This closes Nearest's algorithmic input-name matching. Preparation/schema
lookup, identifier admission, legacy synchronous drains, aggregate intermediate
bytes and whole-Run physical accounting are separate residuals. Full Core,
Wasm/Native execution, packed Local/HTTP and performance campaigns were not run.
Selected API compilation is not three-target semantic acceptance. CI status is
reported on the Draft PR for its exact published HEAD; local results are not CI
success. The final merge destination remains main, after the parent dependency.
