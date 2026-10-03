# JSON composition acceptance for #182

This is an intermediate delivery of one ordinary JSON Program through the
public Host. It connects existing Source, Relation, installed Model, capture,
Effect Preview/approval and durable Run owners. The harness installs fixtures
and submits the Program once; it does not execute the operations separately.

## Reproducible input and independent expectations

- [Program template](../../scripts/fixtures/composed-infer-effect.program.template.json)
  contains both Source acquisitions, JOIN, two-row INFER, the existing KEEP
  lowering, conditional selection and the Effect in four ordinary stages.
- [Independent expectations](../../scripts/fixtures/composed-infer-effect.expected.json)
  fix Source rows, classified and selected rows, column order/contracts, Effect
  body and physical-call counts. These are authored fixture values retained
  from the existing acceptance; they are not computed from product output.
- [Fixture installation/binding](../../scripts/fixtures/composed-infer-effect-input.mjs)
  substitutes only the MappingRef issued by the current public Effect
  publication. Every other Program field is retained verbatim. The template's
  `__PUBLICATION_MAPPING_REF__` is a binding placeholder, not authorization.
- [Existing public acceptance](../../scripts/test-packed-salesforce-source.mjs)
  runs the ordinary Source case and this composition by default, on Local and
  HTTPS. `--composed-infer` remains a filter. The existing `client-packed` job
  reuses the exact-SHA producer's tarballs; no extra packing job is introduced.

The initial JOIN retains IDs 1 and 2. Classified rows are
`[{"id":1,"left_amount":10,"right_amount":100,"risk":"low"},
{"id":2,"left_amount":20,"right_amount":200,"risk":"high"}]`.
The selected Named Result is exactly:

```json
[{"id":2,"left_amount":20,"right_amount":200,"risk":"high","target_id":"a00000000000002","next_name":"review-required"}]
```

Its one Effect PATCH targets `a00000000000002` with
`{"Name":"review-required"}`. Both Named Results must retain the independent
column order, nullable types and literal UTF-8 bounds in the expectation file.
KEEP must retain the original JOIN amounts.

## Restart and physical-call observations

Each dedicated child owns the Host and the process executing the Run. It exits
abruptly with code 77, without graceful close, after durable capture while
approval is pending, and again after approval persistence. Termination stops
both owners together. The next child uses only durable state, looks up the
same request and attaches the same Run. Shared Hosts are not stopped.

For each transport, the independently expected observations are:

| Process boundary | Source read sessions | Cumulative Effect writes |
| --- | ---: | ---: |
| Submit; stop after capture/approval waiting | 2 | 0 |
| Restore; approve; stop after persistence | 0 | 0 |
| Restore; execute; read Named Results | 0 | 1 |
| Restore the completed Run again | 0 | 1 |

Model inputs are exactly `[100,200]`, each physically invoked once. Captured
Source and Model results are not reexecuted during restoration. A currently
valid saved approval is not requested again. The acceptance also retains its
current-authority refusal, stale target, unanswered expiry, cleanup-pending
and lost Effect response regressions; an unknown Effect response requires
reconciliation and is not resent or reported as success.

The ordinary acceptance prints `packed composition acceptance` JSON containing
the exact source SHA, submitted Program byte digest, request/Run identities,
physical Source/Model observations, cumulative write counts, expected write
body and both termination boundaries. `--keep-artifacts` preserves the isolated
consumer's `rce-program.json`, `composition-acceptance.jsonl` and durable state
for inspection. The Program file is also bound by its digest in the report.

After normal package production, the existing CI consumer command is:

```sh
node scripts/test-packed-salesforce-source.mjs
```

For a focused reproduction using the same verified package artifact:

```sh
ACTQL_PACKED_CLIENT_PACKAGES=/path/to/exact-sha-artifact \
  node scripts/test-packed-salesforce-source.mjs --composed-infer --keep-artifacts
```

The package helper verifies the artifact against the checkout. Without an
artifact it uses normal package prepack. The initial intermediate submission
did not rerun that preparation. Subsequent fixed-HEAD packed acceptance and
hosted CI must be reported against their own source revisions.

## Fixed source execution evidence

At `0f1bddbfbab87e52bb4a8933927aa83a968623fd`, with main
`25093479e16c40874701ae7f884ffcc7538d425b`, a focused source-prepared public
Local/HTTPS execution completed in 17.5 seconds. It checked the same Program,
independent rows/contracts/order, both abrupt termination boundaries, exact
request/Run restoration, Source observations `[2,0,0,0]`, Model inputs
`[100,200]`, zero unapproved writes and one write retained after another restart
per transport.

- [Exact submitted bytes](fixtures/pr182-source-0f1bddbf.program.json): SHA-256
  `2d4620eb3de66800f09373d9a292590db814a761c766132e7d46792fa83fe1fc`.
- [Observed results and restart identities](fixtures/pr182-source-0f1bddbf.observed.json)
  retain that historical SHA and the separate runtime payload digests.

This historical Program includes the MappingRef issued for its dedicated mock
installation. Fresh acceptance binds a new publication through the template;
the historical reference is not reused as current authorization. Source
execution evidence is not packed-distribution or required-CI success for a
later HEAD. Historical green SHAs remain separate evidence.

## Adopted owners and remaining units

A #223 is adopted at `61b0760d303d054b76f3444e9abab6181e3d52e4`.
D retains A's acquired input and Model execution ownership and adds only the
composition connections. G #222 is adopted at
`4116239f9527e4decffca1b63705dd0abfafd3c2`; #193 is now merged into main.
C #164's initial Graph scope is merged; this JSON acceptance
uses the existing Relation path and does not wait for full Graph completion.
G #227's additional actual managed-root release work is unadopted and separate;
zero accounting balances are not evidence of general physical heap bounds.

B #242's public unit `6f3439eb34b220de99c58003f1749d10cc913e60` is not adopted
in this intermediate PR. The observed DATA `ClientProgramInvalidInput`/400
is a pre-connection failure, not proof of a defect in B's implementation.
The next difference will adopt B's existing script lowerer and connect DATA to
this same Program path; D does not create another syntax processor. Old #174
receipts are historical evidence, not the current B connection status.

The shared dot/G foundation-history correction constrains final integration
and verification separately from this product acceptance. Existing history
and declarations remain immutable. This PR is Draft until its integrated
HEAD's external packed acceptance and required CI complete. Real Model/real
service acceptance, Cloud deployment and broader #182 coverage are separate
units; fixtures incur no external cost or real service writes.

Main containing #243 was adopted by a normal merge from
`4303f0681c7e7ae3544563fa9dd6d7e5c0eebd41`, without conflicts or removal of any
inherited declaration. The integration commit is
`b42b367afb280983d25b08cd621aac671582c7cc`. Forty focused CI scheduling,
fixture binding and mock runtime-builder checks passed in 6.2 seconds;
Node syntax and whitespace checks also passed. No full local CI, Core,
proof campaign, packed suite or performance measurement was added.

The initial Git-only history preflight first rejected
`Ambiguous foundation merge bases` at the retained integration
`19b0b464b983695c68df60d601016bb25a4fd06d`. Its ordered parents are
`4a4f4f10eb9723e3537c2b0fb444fca20dd28f33` and
`88fbcc95306abb4fc41f0d488bcc6d38ec19506d`; their two maximal bases are
`8b21ddd3f4a17fcecbb9bcf5878082148af0aa99` and
`8baa87fc6b6cb7d7caa981cef1692c9d73d88318`. This is distinct from the repaired
duplicate-introduction and missing main #225 declaration failures. The
then-current history contract required one base and rejected before it could assess
this merge's required resolution. D does not rewrite the retained merge,
select an arbitrary base or introduce a competing shared-validator repair.
At that submission, the Draft retained its unmerged #193 dependency.

The stacked parent was subsequently incorporated through normal merge
`b8a4c682f90babf0f35edf00eed41ab0365e7c16` at its actual public HEAD
`ec27ef0e9091d20d53e6d1064afe8848b9a24ede`. This keeps #193 as an ancestor
and the Draft's base, while preserving its custody-order fixtures and restored
Graph generation ownership. Thirty-two focused fixture/scheduling and synthetic
capacity-orchestration checks passed in 2.1 seconds; formatting of the two
inherited MoonBit files and whitespace checks passed. These synthetic checks
do not execute a proof campaign or revalidate the product's public packed path.
The historical source success above remains bound to its original SHA.

## Main integration and independent CI repairs

Main `79ac7f83ca8cac8fe5ca3eea6a03d659dd979f99` contains #248 at
`4b9d597eb623c95f485c53135b2616c85ed59ae8` and #244 at
`7a85ff83c38505f1997c044596dfdde167a831d6`. Normal merges
`3724e9d90848861ee15b6db97443d2e63c96b23b` and
`4e2791761714fab3fb14c331997db5c2e44787d0` preserve existing declarations,
the current CI cost controls and shared Source/Run dispatch owners. #193's
public head is an ancestor of this main, so this PR can now use base `main`.

The shared validator from #248 derives all maximal-base obligations. New
append-only declarations bind the actual retained merges: 19b0's bases require
5 and 20 paths with a 21-path union; b8a4's bases require 23 and 0 paths with a
23-path union. The zero-obligation base remains recorded. The #244 integration
also declares its one protected package registration overlap. Every record
binds ordered real parents, exact blob digests/modes and retained supporting
declaration groups. No shared-validator workaround or historical edit is used.
Full Git history passed at `f585157323c6281870d357ce8644dc1f50d5057e`
(51 declarations, 18 integrations), followed by 165 focused foundation,
generator, assembly freshness and scoped Workers interface checks. This is
Git provenance validation and focused regression, not a proof campaign.

The previous PR run at `92240a7912f8064a12f9ffcf52b0bd09aba6bedd`,
[37108088415](https://github.com/actql/actql/actions/runs/37108088415), failed.
Its successful packed job is historical evidence only. Three independent
non-history failures were reproduced after main integration and repaired:

- Workers had stale tracked bridge projections. Both assemblies and their
  interfaces are regenerated with the existing generators, preserving typed
  managed-start failures.
- The INFER compilation regression referenced an intermediate alias as an
  Effect Result. It now declares and consumes the final Named Result with
  its original string key, retains A's preceding filter, and checks explicit
  prefix/barrier node identities rather than searching arbitrary names.
  Foreign equal-body preparations remain rejected by the original owner.
- The reference Effect Site omitted its Preview-input release hook. It now
  returns the same exact pin release hook as the installed Salesforce Site.
  Public HTTP restart, transformed Result, unknown response, cancellation
  and rejection regressions pass without ignoring cleanup failures or changing
  the production cleanup owner.

The next validation uses this integrated checkout's normal prepack producer
once, then reuses those SHA/digest-verified tarballs for the existing
`--composed-infer` Local/HTTPS consumer. Its exact SHA, retained external
acceptance report and natural PR CI run are reported separately after the
commit. No full local packed suite, Core campaign or manual CI rerun is added.

During this integration, main advanced again. Normal merge
`736ec05845de80f124878017e269511a5644589c` adopts #247's maintenance-family
selection from `a9f6f2507f13f8e4708e7b71517761599353ddac`. Its only textual
conflict was the adjacent `client-salesforce.needs` expectation in
`scripts/client-ci.test.mjs`: retain main's `select-targets` dependency and the
composition assertion preventing a duplicate packed Host acceptance.
Normal merge `b9b07b0228e3d5cbe10bbf7b0d2182759714b397` then adopts fetched
main `da13b789552dd6ea62ee09506c34e6d4f4ff0217`, including #233/#235/#237/#240
and #250. The frontend comes from its existing owner; the next DATA composition
acceptance remains separate. Append-only declarations bind the actual CI and
package registration overlaps in these merges. Fixed-HEAD packed evidence
before these updates remains separate; the submitted HEAD is validated again
using normal prepack and the existing focused consumer.
