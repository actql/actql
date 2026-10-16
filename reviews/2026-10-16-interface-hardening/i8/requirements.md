# I8 independent interface acceptance map

This is a review/evidence index for the supplied 540-line review and `plan.md`,
not a new product contract, semantic specification or runtime inventory.
Entries point to the existing owners. Labels and matching handwritten tables
are not evidence of semantic or distribution coverage.

Baseline OSS `02f9e53f29b4913d5c6e8276d2ac248800fe8173`, tree `4a8d2c2a847b376d3110b811261c9ad87d52fb66`;
Cloud `fdaa1eca675dc89c74c8eec751e3c152265eef7c`, adopting OSS `285637aa`.
Old R8 results remain historical. New runtime tests executed: **0**.

## Implementation outcomes

| ID | Owner | Required independent evidence | Baseline read / current gap |
| --- | --- | --- | --- |
| I1 | D | All fixtures selected by each current runner match the reviewed ABI, actual artifact and asserted property; mismatch rejects at entry; historical cases retain historical artifact/digest. | Read-confirmed current74/current-selected42; all runner branches and early refusal remain unverified. |
| I2 | C | Preserve original request bytes/CIDs/ResourceRef/catalog and all restored Effect/request/config refusal conditions through one connector MoonBit authority, Node and Native. | Read-confirmed JS preimage/identity/catalog/recoverRequests; candidate independent gold and Node/Native evidence pending. |
| I3 | A | One generated managed binding; distributed wrappers do not directly interpret compiler internals; actual compiled success/refusal/malformed outcomes retain distinctions. | Read-confirmed separate Result and Option/payload interpretations; generated-shim coverage and real conversions pending. |
| I4 | A/D/F | Existing normative contracts plus MoonBit boundary declarations determine actions, named/unit/order/ownership-aware arguments/results, Python signatures, C declarations/calling convention and adopted Cloud types. | Handwritten action/ctypes/signature lists remain baseline. Prior Cloud adopted typing is present; no claim it needs rebuilding. |
| I5 | E | Normative expectations, generated/reused codec semantics, no Remote engine/Wasmtime requirement; execute independent JS/Python/Native vectors. | Read-confirmed integer negative-zero and string-unit branches. Normative resolution and actual language vector evidence pending. |
| I6 | B | Discover real package/wheel/CLI/Cloud production dependencies and exported operations, classify and fail unregistered additions; connect existing checks and meaningful mutations. | 13 npm manifests and3 Python pyprojects independently enumerated; this is a root snapshot, not completed closure discovery. |
| I7 | C/F/all producers | Close all additional boundary requirements, ten attributes and applicable real-owner normal/fault tests without another authority/scheduler/retry ledger. | All A-H explicit. Unexplained missing/unsupported interfaces remain gaps, not exclusions. |
| I8 | G/Root | Audit whole explicit review scope, then one normally generated adopted integrated artifact set and existing installed real business route at Root-frozen cut. | No new IF product execution or final cut yet. Previous R8/02f acceptance is historical only. |

## Additional interfaces A-H

| ID | Owner | Required contract / actual-owner evidence | Existing boundary references |
| --- | --- | --- | --- |
| A Core/connector/Compute | C/B | Connector-neutral Core; independent Source and Command extension with original scheduler/approval/recovery unchanged; preserve third-Compute acceptance. | scripts/check-connector-addition.mjs; scripts/check-connector-dispatch-boundary.mjs; scripts/backend-semantic-boundary.test.mjs |
| B Core/Store/Journal | F | Prepared transition and physical committed/conflict/outcome-unknown differ; lost commit reply reconciles the same original attempt; physical DB/fsync/corruption stay physical. | adapters/host-node/sqlite-checkpoint-journal.test.mjs; adapters/host-node/sqlite-effect-history-page.test.mjs; Cloud test/effect-run-custody.test.ts |
| C Control/data | C/E | Bounded DTOs distinct from buffers/data; schema, missing/NULL, numeric/encoding, order/chunk/EOS, ownership, maxima and copy accounting; no forced full materialization. | adapters/connectors/sheets; adapters/connectors/local/host/iceberg-process.mjs; adapters/connectors/local/iceberg/physical.py; packages/python-sdk/src/actql_sdk/_local_core.py |
| D Host/Credential | F | External authentication does not grant ActQL authority; all owner scope fields plus operation/time/revocation/limits; recheck after await at final irreversible operation. | src/remote_credential/credential.mbt; adapters/host-common/owned-invocation-context.mjs; adapters/site-node/https-credential-resource.mjs |
| E Coordinator/Site/Transfer | F | Admission/start/external outcome/publication/physical release distinct; authenticated durable identity covers lost/duplicate/reordered/stale generation/delayed ACK/failed cleanup. | adapters/host-common/remote-coordinator-abi.test.mjs; adapters/host-node/remote-site-coordinator.test.mjs; Cloud test/site-response-custody.test.ts |
| F Core/INFER Provider | F/A | Original request/prompt meaning, response interpretation, raw capture/retention and physical transport distinct; provider bytes issue no success/retry/completion/permission. | packages/provider-http/_internal/installed-http-chat.mjs; packages/provider-ai-sdk; adapters/host-node/infer-operation-approval.test.mjs |
| G Core/observation | F/E | Use owner projections; observer/UI faults cannot change confirmed state, permission or success; copied bounded observations retain no authority. | adapters/host-common/task-observation.mjs; adapters/host-common/observation.mjs; packages/sdk/internal/run-observation.mjs |
| H Source/binding/artifact | D/G/all producers | Adopt matching source, compiler, generator, contract, wrapper, public types and actual artifact; separate wire/private ABI/package/toolchain versions. | scripts/package-release.mjs; scripts/check-python-local-core.mjs; scripts/native-cli-release.mjs; Cloud vendor/oss-artifacts.json |

## Ten attributes for each discovered operation

Each attribute must link to an existing owning declaration/contract and actual
verification. Explicit nonapplicability needs a reason. A blanket role label,
function arity or wire schema does not establish identity or cleanup custody.

| Attribute | Required content |
| --- | --- |
| responsibility | Semantic MoonBit owner and physical-operation owner |
| inputs_outputs | Named typed values, units, ranges, absence/NULL and encoding |
| identity | Instance, original Run/request and generation binding |
| ownership | Borrow/own, retention/release, copying and serialization |
| synchronization | Sync/async, reentry/concurrency and callback lifetime |
| failure | Typed refusal, physical failure, Unknown and contract mismatch |
| cancellation_cleanup | Cancel acceptance versus stopped versus physically released |
| resources | Maximum bytes/rows/work; reservation/accounting owner and time |
| extension | Required/optional capabilities, extension points and unknown variants |
| verification | Freshness, actual artifacts, independent vectors and fault tests |

## Four layers and six meaningful mutation controls

| Layer | Acceptance |
| --- | --- |
| L1 Discovery | Actual distributed roots/production closures/exports; outside-dir file/helper/export must fail unregistered. |
| L2 Correspondence | Read-only generation/types/actions/signatures/docs versus actual JS/Wasm/Native exports/imports/memory/calling convention; approved generated shim only. |
| L3 Meaning | Independent cross-language vectors and actual-owner copied/foreign/stale/lost/reentrant/partial/cancel/cleanup-pending cases. |
| L4 Detection | Mutations fail the intended assertion/gate; setup/import failures do not establish behavioral detection, except deliberate static contract/type probes. |

| Mutation | Owner | Intended detection |
| --- | --- | --- |
| M1 Swap action numbers | A/D/B | Generated correspondence plus actual semantic boundary |
| M2 Swap same-typed argument roles | A/D/B | Meaningful asymmetric independent input; scalar signature equality is insufficient |
| M3 Omit one scope field | F/B | Original owner refuses foreign/changed scope, including after await |
| M4 Turn Unknown into success or unsent | F/B | Lost reply/recovery retains original uncertain operation; no resend or false success |
| M5 Mix an old artifact | D/G/B | Adopted source/compiler/generator/contract/wrapper/type/artifact correspondence rejects stale member |
| M6 Add unregistered Python/other-language decision code | B/producers | Actual distributed discovery plus semantic-access/dependency checks rejects the new file/export/helper |

## Families, vectors and owner-fault coverage

The three representations remain separate:
- **Same-process opaque**: Typed operations and owner-bound opaque handles; private compiler shim; no forced JSON or extracted internals.
- **Local scalar ABI**: Wasm/Native buffers/handles/memory/thread/ownership; no foreign instance/process pointers or handles.
- **Remote wire**: Version/schema/correlation/closed variant/limits/capabilities; no wire local handle or SDK execution authority.

Independent vector categories: negative zero, bool versus int, integer/numeric bounds, Unicode and length units, NULL versus omission, unknown variant, correlated identifiers, stale revisions.

Changed-boundary fault categories: copied handle, foreign instance, stale generation, lost response, reentry, partial construction, cancellation, cleanup pending.

Retain third-Compute evidence and add independent Source and Command acceptance
without common scheduler, approval or recovery changes. Physical Arrow/Iceberg
field identity, missing/NULL and order/EOS must survive; do not force rows
through a new JSON/object-array bottleneck.

## Distribution and final execution plan

The separate baseline root snapshot enumerates source metadata, not a completed
distribution closure. B must derive the real modules/exports/operations from
normal package, wheel, Native CLI and Cloud roots, including outside-directory
helpers and generated runtime/platform entries. G will challenge that discovery
with omitted roots, newly distributed helpers/exports and unregistered decision
code; the two handwritten lists must never be their own oracle.

After Root freezes an integrated cut, bind actual source/compiler/generator/
contract/wrapper/type/artifact identities, normal prepack/install, and necessary
actual JS/Wasm/Native diagnostics. Reuse only proven unchanged inputs. Perform
the existing real DuckDB + bounded GCS read -> SQL/AQL JOIN with a declared
Named Result -> original sealed Preview approval -> Local Iceberg commit ->
public Named Result read -> fresh post-commit process same-Run attach/read,
with independent rows/schema and no Source/Effect replay. Before approval,
Named Result is declared/retained; its row body is not publicly readable.
This is a regression of the existing business, not new distinct business.

No per-PR full Core/all-target/pack repetition. No paid LLM, deployment, public
publication, Hosted CI or old Run/Unknown retry. Preserve the original 6GiB
producer floor and atomic shared pool; task-specific preparation and consumer
reservations keep their own existing bounds. CP977 and all raw/RC/DB/WAL/keys
remain protected. The historical Foundation d2f3 two-FAIL disposition is an
independent release blocker; this work changes no history or validator.

## Current communication and qualification

Concrete baseline gaps were sent directly to A (remaining Option/refusal paths),
B (all distribution families/new-helper coverage), D (all selected ABI fixtures),
E (negative zero and length-unit branches), C (unchanged identity/restore golds
and Node/Native), and F (complete scope after-await and real-owner fault cases).
Owner candidates, source-qualified test results and mutation evidence remain
pending and are reviewed independently as they arrive. No product hunk is owned
or edited by G.
