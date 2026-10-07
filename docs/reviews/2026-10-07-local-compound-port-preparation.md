# Resumable compound completion-port preparation

## Completion unit

Verified implementation SHA: `e6493c39e22e6881a9e41746a74a2b854d9c78cd`.
The dependency is unary preparation #769. Main
`7525ab1434903e106fb663b44ae1bd0f0b9246fe` was normally merged as
`dcc02ce4fa52671c9d141a818424c1120c3300c2`, preserving both the unary and
Values/binary fixtures, resource roles and guards. The four conflict resolutions
were in the Host fixture, gap report and two resource-gate files, not kernel
algorithms. The parent's worktree was fast-forwarded to that same merge commit;
no commit was rewritten and no main worktree was changed.

| Existing provider | Preparation resumes into |
| --- | --- |
| Equality Join | `ChargeInput` |
| Nest | `ChargeInput` |
| Interval Join | `ReadLeftClocks` |
| As-of Join | `ValidateIdentity` |
| Sequence Match | `LoadInputNames` |

Each provider previously synchronously prepared its completion target and all
schema names inside start. It now uses the existing `TrustedOutputPreparation`
cursor in `PrepareCompletionPort`. Each transition advances one scalar or
identity code unit, with the existing stop and input-availability checks between
transitions. Logical algorithm work and workspace limits are unchanged; physical
poll work includes preparation and stays within the requested quantum.

The existing owner validates exact ordered inputs. A port is issued only after
preparation completes. Its verifier captures the existing live and rows refs,
not the whole execution state. Cleanup closes pending preparation before clearing
scratch or borrowed input views. Accepted output keeps its transferred names
after provider cleanup. No scheduler, ledger, algorithm or fallback is added.
Public APIs, schemas, CIDs, Graph identities and stored formats are unchanged.

## Independent and public evidence

The compound fixture uses real checker/lowerer entrypoints and existing input
owners. Literal name-byte formulas count two target spellings and one copy of
each schema name: Join 15, Nest 22, Interval 51, As-of 31 and Sequence 87 bytes.
Each exact limit succeeds and one less fails specifically with `Completion(Limit)`.
Quanta 1, 7 and 256 produce the same independently written ordered rows, total
physical work, remaining logical work and peak workspace. Cancellation is tested
inside each of the four name phases for every provider, with no issued output,
borrowed inputs still live, cleared cursor names and exactly-once cleanup.
A separate Join fixture uses 32 U+00E9/U+1F600 pairs, a 206-byte exact budget and
the independently written expected row; names survive accepted-output cleanup.

Normal JSON Programs exercise Join, Nest, Interval, As-of and Sequence through
`connectEmbeddedLocal`, the standard Host and a real retained Store. The long
generated column is projected into a public result with two downstream consumers.
All three result names and their full ordered contents are compared with literal
expectations. Result schema, idempotent resubmission, a positive-work cancellation
barrier, unconfirmed versus confirmed physical stop, nonpublication and final
snapshot reclamation are checked. These are checkout runtime tests, not packed
Local/HTTP or Native acceptance.

Twenty role-removal mutations require per-operation limit, quantum, stop and
public fixtures. Twenty source mutations remove each production start, advance,
finish or cancel connection and require gate rejection. The five production files
are captured in the gate's immutable source snapshot. The unmodified compound
connection baseline is checked before mutation, so another missing source cannot
make a mutation appear effective. Existing algorithm/resource evidence is retained.

## Executed checks

At the clean implementation SHA above:

- Six affected JS fixture files: **56/56 passed**.
  `run-IzWnW6`, `focused-test-2fsNHV`.
- Five public retained Host cases, two gate cases and two inventory cases:
  **9/9 passed**. `run-HMf8Wd`, `focused-test-MZxR42`.

The exact commands were:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 2 \
  src/execution_relation/bounded_join_wbtest.mbt \
  src/execution_relation/bounded_nest_wbtest.mbt \
  src/execution_relation/bounded_interval_join_wbtest.mbt \
  src/execution_relation/bounded_asof_join_wbtest.mbt \
  src/execution_relation/bounded_sequence_match_wbtest.mbt \
  src/execution_relation/bounded_compound_port_preparation_wbtest.mbt

node scripts/local-checks.mjs test node --timeout-seconds 150 -- \
  --test-name-pattern 'public retained .* compound completion names|compound output ports|acceptance evidence index|evidence paths exist' \
  adapters/host-node/public-property-name-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs
```

Receipts remain under `_build/local-checks/attempts/` and
`_build/focused-evidence/`. Runtime preparation selected the seven JS roots used
by the Host, with `--release --jobs 2`, and passed (`run-2CHFB7`). The Local Node
asset and Run Host core generators and their read-only checks passed. Preparation
occurred before committing identical production sources; the final public tests
ran with clean HEAD. Ignored bundles were not committed. Existing pinned
dependencies were borrowed without installation or modification.

Earlier development failures are retained separately: the exhaustive Nest fixture
phase mapping needed the new phase; three Sequence assertions had to enter their
original algorithm phase after preparation, without raising logical work limits;
and the initial public As-of fixture used zero tolerance, rejected by the existing
`PositiveMilliseconds` contract. It was corrected to a legal positive tolerance,
not by weakening acceptance. The first gate mutation test also exposed a missing
production file in its source snapshot; the source inventory was fixed rather
than bypassed. None of those failed runs is counted as success.

## Remaining obligations

This closes completion-port preparation for these five providers, not all Local
retention or all provider initialization. Nest still creates input name arrays
inside start; Interval and As-of resolve other metadata before their first resume.
Downstream name resolution, installed availability callbacks, and Native allocation
or callback correspondence remain separate work. Existing Store failure and
cleanup-retry fixtures were not all rerun in this unit. Wasm, Native, full Core,
packed Local/HTTP, proof campaigns and performance measurements were not executed.
Draft CI is preparation only; no required CI success is asserted here.
