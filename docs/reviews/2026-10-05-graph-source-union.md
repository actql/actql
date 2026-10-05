# Graph source integration: named matches and traversal paths

## Adopted inputs and scope

This follow-up combines the existing named-match and path-emission Frontend
connections on repaired main. It preserves normal Git parents: first merge
main into the named-match branch, then merge the traversal-path branch. The
named-match PR is explicitly stacked on the traversal-path PR for review.

- Named matches: `bf3eb419f482b5ccb806e68410e2a957ac61b52d` (#420)
- Traversal paths: `1626a805242f652dd94885aa622ee3a8d89287bc` (#409)
- Repaired main: `3d21f2c8ccbe055aa792bdffdaab2b85770cf0c4`
- Common source baseline: `4a63d0e699674df519c9d35a990080026000e560`

The production lowerers compose without a conflicting hunk. Match routing and
authored fields remain with their existing owner; traversal uses the renamed
shared path/node lowering entry. Both corpus registrations, focused flags,
positive cases and refusal cases are retained. No Host policy, capacity,
execution algorithm, contract version or saved identity is changed.

The new combined regression has one independently authored complete Program:
named `match_nodes` selects an identity, a DATA binding becomes the selector,
and `traverse(emit: 'paths')` produces the five path fields. Both the independent
Program and authored source pass the common checker. Missing selector columns
remain a common-checker refusal; node-only output fields remain a Frontend
scope refusal.

## Union identities

The manifest is regenerated from the combined query-text document, not chosen
from either feature branch.

- Query-text rules SHA-256: `6e19ee2d70f3c97104b0faff22b8f5d8e37ab021bff6555555bb018bac0f564a`
- Grammar Manifest CID: `sha256:88b3e10e85fa88630900251773eb7b2fe5eb00e0714f3668843145fd82e68a8c`
- Complete manifest import CID: `sha256:0f1b47e4ce235a781d421ed8f2085f88f4192467e90581686c44fd7e45d3fb2e`
- Independent fixed Values Run CID: `sha256:51ecc5fb9c556efbca40505459a5432303d0bc368879a6859bda4098d38b9166`

The existing independent hand-assembled Values preimage oracle supplies the
Run expectation without importing the product compiler or issuer. Its complete
template, executable-plan, compiled-plan and Run bodies were independently
rehashed with Python's sorted compact JSON and SHA-256. Both feature parents'
grammar and Run vectors remain fixed historical expectations.

The first focused Node run found a stale SGA grammar expectation inherited from
the path branch's pre-main source. This follow-up binds the current test to the
combined normative document, retains that old expectation as an explicit
historical vector, and also retains both actual feature-parent vectors. The
failed 13/14 attempt is not counted as a successful check.

## Verification of this combined source

Executed with pinned Node 24.21.0 and the existing MoonBit toolchain through
the repository's bounded, nonzero-test wrappers:

- Four Node files: `compilation-manifests.test.mjs`,
  `client-values-run-materials-vector.test.mjs`, `canonical-json.test.mjs`, and
  `sga-query-call-contract.test.mjs`: **14/14**
- `src/query_program`, JS: **307/307**, including the two combined regressions
- `src/source_frontend`, JS: **17/17**
- `src/canonical_json/identity_vectors.generated_test.mbt`, JS: **368/368**
- `src/run_publication_host/client_values_run_materials_wbtest.mbt`, JS: **1/1**
- Compilation manifests, document metadata, spec-family and canonical-vector
  read-only freshness checks pass; spec-family contains 10 documents, 1,329
  requirements, 23 document imports and 255 machine imports
- Changed MoonBit formatting, packed-driver JavaScript syntax and whitespace
  checks pass

Regeneration commands, in order:

1. `node scripts/compilation-manifests.mjs --write`
2. `node scripts/update-document-metadata.mjs --write`
3. `node scripts/check-actql-spec-family.mjs --write`
4. `node scripts/check-canonical-json.mjs --write`

The independent Run and SGA expectations are separately authored/rehashed;
these commands do not infer expected behavior from runtime output.

## Packed acceptance of the combined source

Verified clean source: `093107685a8cbcbffeb05c6e63de003e6539a509`.
This adds one public named-match → DATA selector → traversal-path case and two
corresponding preparation refusals to the existing path corpus. The existing
independent constructor definition preimage supplies its identity domain; the
expected TRAIL output contains the two permutations of the distinct self-loop
edge identities. No product output supplies this oracle.

The earlier named-match campaign at `907e3af...` and the path branch's earlier
reports remain evidence for their own recorded sources. They are not relabeled
as acceptance of the combined source.

Both commands ran serially through `runLocalCheck` with the shared heavy-check
lock, pinned MoonBit `0.10.12+1634b282e`, and Node `22.23.2` (the supported
Node >=22 profile). These were scoped campaigns, not the complete packed suite:

```sh
node scripts/test-packed-public-query.mjs --graph-traverse-paths-only --keep-artifacts
node ../.codex-scratch/b-graph-union-retained-acceptance.mjs ../.codex-scratch/public-query-evidence-Evoqhi
```

| Campaign, on each of Embedded Local and public HTTPS | Successful inputs | Preparation refusals |
| --- | ---: | ---: |
| Traversal nodes | 5 | 7 |
| Traversal paths, including the composed named match | 9 | 13 |
| Named matches | 10 | 14 |
| Total per transport | 24 | 34 |

Every successful input reached Named Result rows and `Result.describe()` with
the complete independently authored ordered column/type/nullability contracts.
Expectations retain parallel-edge multiplicity, ordered path identity arrays,
WALK/TRAIL/ACYCLIC distinctions, NULL properties, typed empty Results, explicit
parameters and authored column order. Relations without an authored ORDER BY
are compared as multisets. Resend, attach and repeat Result reads preserve Run
identity without extra admission or Source I/O. Every preparation refusal
preserves the observed admission/provider-I/O counters. No transformed Program,
replacement checker, executor, capacity increase or legacy Graph is used.

The first campaign performed ordinary `npm pack`/prepack and a new installation
outside the repository. Its receipt has clean source, all successful commands,
complete output and no evidence errors. The second campaign verifies that exact
source and the retained tarball SHA-256 digests, copies the same installed
packages into a private external root, and runs the unchanged `acceptance.mjs`
with `ACTQL_TEST_GRAPH_MATCH_ONLY=1` and a fresh Store. It does not pack/build
again or change the library/test bytes. The package boundary audit still runs.

Retained evidence (under `/Users/t14i/workspace/20260822/worktrees`):

- `.codex-scratch/public-query-evidence-Evoqhi`: normal pack/install, traversal
  Local/HTTPS, README Local/HTTPS, public-check boundaries and expected missing
  generated-asset refusal; command receipt **passed**, **complete**, source
  **clean**. Guard: `actql-frontend-graph-match-rows/_build/local-checks/attempts/run-TkDRIu`.
- `.codex-scratch/public-query-evidence-8oqs8K`: unchanged named-match corpus,
  copied retained installation and fresh Store; receipt **passed**, **complete**,
  source **clean**. Guard: `actql-frontend-graph-match-rows/_build/local-checks/attempts/run-jjqkY9`.
  `artifacts/reuse.json` records the producer and installation used. The exact
  scratch runner remains at `.codex-scratch/b-graph-union-retained-acceptance.mjs`.

Both receipts bind the following tarballs to the same clean source:

| Package | SHA-256 |
| --- | --- |
| `@actql/client-wire` | `a8d1f2a63ed08d3378765fbee905fb72233d19e66e8ce77d6f1398ae45dbe8b7` |
| `@actql/sdk` | `a42baf2456b366d3a761f01cce27292ae1dcee13c8ce6113a3b70896bedd4e97` |
| `@actql/run-host-core` | `c656633e8c8963c89ab0c62780f571ec68470904f2130c71679661f2c85aa887` |
| `@actql/local-node` | `f41cf31b8ee0d19dfaebbd6cfe978c9295dd222f992ac4c9d0ef090709f56559` |
| `@actql/node` | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The two existing combined lowering/checker regressions passed **2/2** through
`node scripts/local-checks.mjs test moon -- --target js src/query_program/graph_match_paths_integration_test.mbt`.
This focused run preceded the fixture commit and is recorded as a dirty-tree
run, not relabeled a clean-commit run. Its evidence is
`actql-frontend-graph-match-rows/_build/focused-evidence/focused-test-rwfXS5`
(guard `run-nimUlA`). JavaScript syntax and whitespace checks pass.

Two unsuccessful setup attempts remain separate from product verification:
the initial filename was mistakenly passed as a test-name filter; the nonzero
test guard rejected the zero-test run (`run-Lde1rc`). The first retained-install
attempt used an external node_modules link; the unchanged package boundary
audit refused it before running a product case (`public-query-evidence-ZvHEFs`,
`run-aKEyWW`). Copying the verified installation into the consumer root resolved
that setup error; the audit was not disabled. Neither attempt is counted as a
successful campaign.

## Remaining review and CI

The named-match PR remains stacked on the unmerged traversal-path PR #409.
These scoped JS/public Host results do not establish fresh acceptance of #409's
different HEAD, full Core, Wasm/native, proof/performance or the full packed
corpus. Normal required CI remains unverified. Evidence-only documentation
after the verified source does not constitute another runtime campaign.
The PR remains Draft; no manual CI rerun, PR merge or main modification was made.
