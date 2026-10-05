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

## Remaining acceptance

These are combined-source focused checks, not a fresh packed Host campaign.
The prior named-match Local/HTTPS campaign belongs to source `907e3af...`, and
the path branch's earlier reports belong to their recorded sources. Neither
is relabeled as acceptance of this union. Fresh combined packed Local/HTTPS,
normal required CI and the applicable cross-target coverage remain unverified.
No full Core, Wasm/native, proof, performance or manual CI rerun was performed.
The PR remains Draft; no PR was merged and main was not modified.
