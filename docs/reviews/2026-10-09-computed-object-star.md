# Computed closed object receiver stars

## Scope and dependency

This unit follows #1060's named object-column star connection. It starts from
`595a822a4240681f4ed22c38df0dc76b724fd72e`, integrates main
`1e1dd7fd6fbe16dc91a035128f43fd6fb3bb2817` normally, and adopts the parent's
grammar-pin repair `4952f42c9293ec7636c0d7b240ee9be4a3bc1a54`.
The parent remains an unmerged dependency; the final merge destination is main.

The selected [GoogleSQL expression-star reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#select_expression)
allows a value with fields as a SELECT star receiver. This unit connects existing
closed object scalar expressions, including COALESCE, CASE, parentheses and typed
parameters, to that surface. It preserves the common canonical named-object
field order. It does not claim GoogleSQL ordered/anonymous STRUCT completion.

The minimal counterexample is:

```sql
SELECT id, (CASE WHEN id = 2 THEN other ELSE payload END).* FROM objects
```

An independently authored JSON Program evaluates the receiver once, projects its
two fields using ordinary property expressions and passes the normal checker.
The original parser rejects the source. Red `run-zueJuK` /
`focused-test-IO4BBn` runs 1/2 successfully: the control passes and the parser
unwrap fails. This proves a source-entry gap, not a published Run failure.

## Connection and invariants

- The query-owned scalar parser leaves a dot-star suffix to the SELECT owner.
  The existing expression parser's default behavior is unchanged; standalone
  expression dot-star remains invalid. Existing stars share one EXCEPT/REPLACE
  parser. Authored receiver nodes and source locations are retained.
- Expansion consults the actual lowered prefix through the existing metadata
  probe and common expression/type owners. It does not inspect rows or invent
  presence, identity or key evidence.
- Each computed receiver becomes an ordinary private derive before its retained
  field projections. Field projections consume the evaluated receiver rather
  than copying a complete evaluation into each field. Private names avoid input,
  output and authored reference collisions; traversal/copying retains work bounds.
- Already evaluated GROUP/QUALIFY fields retain their existing slots. SELECT's
  expression table retains original receiver expressions for ORDER name/scope
  resolution. Private evaluation names do not become public aliases.
- SET's current value and its original range remain distinct. Removed ranges
  stay inaccessible. EXCEPT/REPLACE read the same SELECT input snapshot.
- The ordinary SELECT removes private receiver and field slots before Result.
  Common checking owns nullable receivers, field types and GROUP validity. There
  is no new execution owner, physical strategy, transport, save format or fallback.

## Independent preparation evidence

`computed_object_star_test.mbt` contains a complete authored JSON control with
one receiver derive and two property reads. Expected source Program is compared
as a full semantic tree, not generated from a compiler result. Additional checked
cases cover SQL/Pipe, GROUP, DISTINCT, repeated ORDER expressions, current/old
slots, exclusions/replacements and bounded work. Scalar, missing-exclusion,
duplicate-replacement and displaced-range cases assert their exact typed causes.

- Existing plus new compiler star cases: 58/58, `run-NQgKuJ` /
  `focused-test-Wv4vuQ`, before the later exact-refusal assertions and pin update.
- New syntax cases: 2/2, `run-dr3d52` / `focused-test-LRr9M8`.
  An initial black-box test used an abstract type's private field and failed
  compilation (`run-gBjFFD` / `focused-test-fKAGHp`); it now uses the public node
  count. An initial malformed-input fixture was also corrected: `. FROM objects`
  can be parsed as a property and implicit alias, so the actual missing-property
  example ends immediately after the dot. `run-G03Wll` / `focused-test-aIRIMi`
  was 1/2 before that fixture correction. No new keyword restriction was added.
- New lowering and exact-refusal cases: 4/4, `run-CvkE8r` /
  `focused-test-NQCeod`.
- Two public-fixture/profile Node files: 16/16, `run-2dKtlO` /
  `focused-test-NYclr3`.
- Compilation manifest, SGA grammar and Values Run-vector Node files: 11/11,
  `run-im6tVz` / `focused-test-GoldVq`.
- Real Values Run issuance/rebuild: 1/1, `run-rHaDOj` /
  `focused-test-bEEJZA`; the existing mismatch checks remain.
- Existing generators update grammar manifests, document imports and canonical
  fixtures. Read-only manifest, metadata, specification-family and 380 canonical
  vector checks pass. The specification check remains `conformance:false`.

These are preparation-state results; no final-SHA CI success is inferred.
Only focused JS and Node selections run, not full Core or all backends.

## Identity closure

Grammar hash is `1f305f648cef0e06a22e42d2ad95a09b00596e84344f4c5899f4d72c71e068db`;
query-rule hash is `aadc03925405e78e008a50e3c84b66e8735e11f851b2e3a15ac1146a85e7b35e`.
The grammar manifest is
`sha256:5e830a0888c0b5d8f3d1d65dbfb84825c50da8071bb697f97df667c27cadc979`.
The independent Values preimage oracle derives Run CID
`sha256:258d5e590237fc06d812a6ca075f620e6cd5220a5e21b14b949e376462a58838`.
The parent's complete grammar/Run vector remains separately pinned; Values
Unit/proof/ResultPlan identities do not change. No saved Run is relabeled.

Before/after independent bodies are retained at
`/private/tmp/actql-b-computed-object-star-manifest-vector-audit-20261009.json`.

## Public acceptance obligations

Ten authored successes and four exact preparation refusals join the existing
computed-object public corpus and its ordinary packed route. Its full selected
inventory is now 37 positives, 16 preparation refusals and one expected execution
failure per boundary; original cases and expectations are retained.

The new control uses ordinary JSON Program inputs; source cases use full authored
DATA plus SQL/Pipe, without test-side Program correction. Independent rows/types
cover NULL versus fallback, duplicate rows, empty typed input, current values,
GROUP, DISTINCT, ORDER and exclusions/replacements. The existing public consumer
must verify Named Result rows and describe columns, full nullability, canonical
field/SELECT order, internal-column absence, one Source acquisition, attach and
unchanged request replay, and refusal before admission/provider I/O.

Initial failed campaigns and corrected clean five-package execution are recorded
below. The corrected Local/HTTPS cohort completes at `e28f1755dec14dfa2ddee5f7855665e9775dfc18`.
The parent's source/package success does not prove computed-star execution.
Required submitted-HEAD CI, Wasm/native, broad packed campaigns and ordered
STRUCT support remain unverified. Draft is required; no merge is performed.

## Initial clean packed attempt and CASE fixture correction

Normal five-package production and independent digest verification pass at
`4102d823a358bd9b736cf236c225c8f938b3d99a`. Selected consumer attempt `run-6E5NSP`
stops during Local `computed-object-star-pipe-case` with a describe-column
nullability mismatch; this is not a successful public campaign. Receipt
`public-query-evidence-TLDK17` retains complete stdout/stderr for failed command
010 and its clean source identity. The 27 original Local positives, new JSON
control and SQL COALESCE star pass before that point. Remaining new positives,
preparation refusals and HTTPS are unreached in this attempt.

The fixture had treated `CASE WHEN payload IS NULL THEN other ELSE payload END`
as statically non-null. The existing [value-contract join rule](../spec/language.md)
uses nullable OR across conditional result branches; COALESCE separately refines
nullability when one input is proven non-null. The common checker in
`expression_typing/signatures.mbt` applies exactly those independent rules. CASE
does not turn the nullable payload branch non-null from its condition.

The fixture now expects the nullable CASE receiver's property contract while
retaining all expected rows, names/order and the non-null COALESCE control.
This corrects an independent type expectation; it does not weaken or change
the implementation, common contract, limits, row expectations or acceptance
assertions. Fresh corrected-source Local/HTTPS remains pending.

After the fixture correction, the affected Node fixture file passes 7/7 in
`run-K6KuHX` / `focused-test-owOxOq`. This is fixture preparation evidence,
not completed public execution.

## Corrected CASE campaign and scalar refusal classification

Fresh normal five-package production at
`a513d4f606d851452f30e2fd22bb4e4541ec4574` passes, and all 37 selected Local
positive cases reach their expected Named Results. Attempt `run-JumZfj`, receipt
`public-query-evidence-O8QTxB`, then stops at the computed scalar-star refusal:
the public code is `ClientProgramImplementationLimit`, while the fixture had
incorrectly required `ClientProgramInvalidInput`. HTTPS and later refusals are
not established by this failed campaign.

The exact lowering regression already requires `UnsupportedProjection` for a
computed scalar receiver. `client_source_preparation.mbt` maps that cause to
`source_unsupported`, separately from invalid names/replacements; its existing
white-box test fixes that distinction. The audience-visible check then exposes
an implementation limit through `client-program-preparation.mjs`. The scalar
fixture now requires that existing exact public classification. The other three
computed-star refusals continue to require invalid input. No diagnostic owner,
lowerer, limits or row/type expectation changes, and every refusal still checks
zero admission and Source I/O. A complete corrected Local/HTTPS campaign remains
pending.

The corrected exact-code fixture file passes 7/7 through
`node scripts/local-checks.mjs test node -- scripts/computed-object-property-source-input.test.mjs`,
attempt `run-0jREiQ` / `focused-test-8oRfrQ`. This does not substitute for the
remaining public campaign.

## Completed corrected-source public cohort

Normal five-package production, independent tarball rehash and the unchanged
selected public consumer pass at clean source
`e28f1755dec14dfa2ddee5f7855665e9775dfc18`. Commands:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-computed-object-star-e28f1755d-pack
node scripts/test-packed-public-query.mjs --computed-object-property-only
```

The existing bounded wrapper uses pinned Node 22.22.0 and MoonBit
0.10.12+1634b282e, the shared heavy slot, a 1200-second budget and five-second
TERM grace. Attempt `run-rD1sjO` passes with exit zero, complete output and
released locks. Receipt `public-query-evidence-tyW3Q2` records ten complete
commands, each with the same clean source SHA and raw/verification exit zero;
there are no evidence errors. Successful temporary installations are removed.

Embedded Local and real HTTPS each complete **37 positives, 16 preparation
refusals and one expected execution failure**. All original cases remain.
Eleven exact-code refusals are individually logged per boundary; the five
original unlogged refusals are established by the unchanged common assertion
loop and completed consumer. The scalar-star refusal requires the established
implementation-limit code; the other new refusals require invalid input.
All refusals preserve zero admission and Source I/O assertions.

Named Result rows and full `describe().columns` contracts match independent
values, nullability, field/SELECT order, empty input, duplicates and current
versus original range values. Private receiver/sort columns are absent. Positives
acquire the Source once; attach and unchanged same-request replay do not acquire,
execute or admit a second Run. The CASE type correction preserves the existing
branch-join law, while the COALESCE control retains its non-null refinement.

| Package | Independently verified SHA-256 |
| --- | --- |
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `5e28c1fabbf8acbb5a00ea2d77a8ce8e3b5aefc04ed849d767b25ac477e29acf` |
| run-host-core | `11347952d713e286f65ac1518623b8e2a22d614abc1eb59c42023e1723e2e039` |
| local-node | `c0b27635f04cbcf09ae53196086e7dcefd8136a21c4e2f24745bf254c139ef9d` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

Exact wrapper source and stdout are retained in
`/private/tmp/actql-b-computed-object-star-e28f1755d-packed-20261009.mjs` and
its adjacent `.stdout.log`; independent artifact/log inventory is
`/private/tmp/actql-b-computed-object-star-e28f1755d-acceptance-audit-20261009.json`.
The review-record update after this campaign is documentation only, not a newly
packed source identity. Prior failed receipts are retained as failed attempts.

Required submitted-HEAD CI, Wasm/native, broad packed coverage and ordered or
anonymous STRUCT remain unverified. #1060 remains an unmerged parent dependency;
this is a completed local public cohort, not a merge approval. Draft is retained,
and neither a manual CI retry nor a merge is performed.
