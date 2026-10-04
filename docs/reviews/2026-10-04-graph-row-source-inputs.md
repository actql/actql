# Graph row source inputs: implementation and evidence

## Baseline and scope

Baseline: `7b064f617216ead8c1784e0ce898b9dcdc31227a` (main). The common
Property Graph row Bridge is already present, including the #275 finite,
presence-aware row contract. This unit connects existing named calls to it;
it does not replace the constructor, checker, Bridge or execution owner.

| Path | Baseline | This unit / remaining boundary |
|---|---|---|
| Machine Program `node_rows: true` / `edge_rows: true` | Common checking and public execution available | Retained; independent JSON controls execute alongside text |
| Text `FROM g \|> node_rows()` / `edge_rows()` | Parser recognizes calls; script lowering rejects the Carrier transition | Existing operations lower into a normal Relation suffix and Named Result |
| DATA bound to a row Bridge | Rejected by Graph-preserving lowering | Binds the existing step producer as a Relation; no copy or reacquisition |
| Conditional row properties | Common checker requires presence, distinct from nullable | Ordinary references still rejected, including after `IS NOT NULL` |
| Definition selection arguments | Separate common/profile dependency | Explicitly unsupported here; no inferred selection |
| Traverse node output | C's #289 publishes a separate consumer/contract unit | Not adopted or claimed by this unit; no replacement traversal |
| Other Graph consumers | Syntax and adapted execution are separate | Existing unsupported diagnostics retained; no legacy fallback |

C's #289 reference inspected for scope is
`ce28f088167e6b2b94353ef508864068e46956cf`. It is not an adopted dependency
or evidence of public traversal execution here. D retains CTE, Source
predicate, assertion and Effect changes. B's Graph-to-Relation dispatch is
separated in commit `29458ed7b5b31572d853d6f64e77c6305c78f7fe` for integration
with D's script changes. The shared boundary was posted on
[the composition PR](https://github.com/actql/actql/pull/273#issuecomment-5975061264).

## Meaning preservation

The lowering module emits the existing boolean Bridge operation and passes its
producer to ordinary Relation lowering. It resolves visible names from the
constructor and declared input schemas; it does not sample rows, invent types,
presence, uniqueness or order evidence. The common checker remains responsible
for Graph roles, property/key collisions and Conditional presence. Name display
order follows the common canonical UTF-16 definition order.

The source suffix can project, filter, order and declare a Result. Quoted DATA
references and uppercase operation spelling use existing name rules. A DATA
binding itself creates no Named Result, sort, capture or physical boundary.
The result schema is read through public `Result.describe()` and compared with
independent declared columns, rather than inferred from output rows.

The full Program in `src/query_program/graph_rows_test.mbt` is hand-authored.
The separate machine controls in
`scripts/fixtures/property-graph-row-source-input.mjs` use direct Values;
text uses ordinary SELECT/UNION producers. Their structural CIDs may differ,
but rows, column contracts and explicit order must agree. Neither fixture
calls a lowerer to generate expectations or patches a generated Program.

## Identity impact

No API, wire version, Graph identity law or Host budget changes. Updating the
query normative text changes its grammar manifest pin and dependent
compilation/Plan/Run identities. Values Program, Unit and Result Plan bodies
are unchanged. Historical vectors keep their previous pins.

- Grammar: `sha256:dc6a79192190098180af67a8726ecad1519d0c93037e43ad41d45cc288d0ef09`.
- Independent fixed Values Run: `sha256:97c4dacbf36c4d15cd0b936c07a24d75b1d033d92d587e376c2c50ee598ea918`.

The Run vector assembles contract preimages independently of the product issuer.
The corresponding focused MoonBit issuer test confirms the fixed expectation.
Generated runtime bundles remain untracked. Fixture generators were run in
Workers → Node order and required no generated fixture changes.

## Executed evidence

Product/fixture verification SHA:
`8074f08e4954e87f1b1f37471bbc3d9fb0003dfd`. Any subsequent change adding only
this report is not represented as a new packed verification SHA.

Pinned Node 22.23.2 and MoonBit 0.10.12+1634b282e were used.

| Command / selection | Result |
|---|---|
| `node scripts/local-checks.mjs test moon -- --target js src/query_program --filter 'Graph row*'` | 5/5 |
| Same wrapper, `src/query_program --filter 'SGA*'` | 4/4 |
| Same wrapper, `src/run_publication_host --filter 'run materials rebuild exactly*'` | 1/1 |
| Node wrapper: SGA grammar and independent Run vector tests | 3/3 |
| Node wrapper: frontend profile and public-query case tests | 10/10 |
| Workers/Node fixture freshness; compilation manifests; spec family; canonical JSON | Passed; 366 canonical identities checked |
| `node scripts/test-packed-public-query.mjs --graph-rows-only` | Local and HTTP each: 5 normal cases + 5 pre-admission refusals |

The packed driver normally packs all five distribution packages with prepack,
installs outside the checkout, and uses the existing bounded public harness.
The new narrow flag skips unrelated planner, two-source, snapshot/native and
cancellation suites. README Local/HTTPS and missing-asset controls still ran.

Normal cases: nullable node property and two static labels; composite keyed
parallel self-loop edges; quoted edge-row DATA binding; typed empty node rows;
and two independent JSON controls. The existing harness checks ordered rows,
full column types/nullability/order, stream termination, same-request Run reuse,
and attach/read behavior. Five refusal cases check unsupported selection,
Conditional property access, Conditional `IS NOT NULL`, wrong Carrier and an
unknown property. All refuse before durable Run admission and provider I/O.

Local evidence invocation: `public-query-evidence-OFWooH`, completed/passed.
The evidence records source SHA, command status, timing, stdout/stderr and these
tarball SHA-256 values. Its owned temporary installation was removed after
evidence preservation (`artifactsRemoved: true`).

| Package | SHA-256 |
|---|---|
| client-wire | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| sdk | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| run-host-core | `eb5076cfd9fc55d728bf7af03209a06614742794a7b7629ce12c9ea1bb197a98` |
| local-node | `a04bdd1209226cf75efa14202389b248bfaa3ee2798f4a55a3e7b03af063d686` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

No full Core, all-target, proof, performance or full packed suite was run locally.
Exact submitted-HEAD CI is separate from this selected evidence. This does not
claim completion of traversal, remaining SGA consumers, snapshot acceptance or
Frontend r1. #287 remains separately blocked on #295's main integration and
remaining packed acceptance; neither its 512 MiB limit nor expectations change.

## Main integration follow-up

Main `5caeccc79dacc758afa5d87c2cee6be024e32565` includes #273's Effect
continuation loop, #286's scoped-order selector and #295's selected-fragment
capacity repair. The Graph-row dispatch is integrated into the current-query
branch of that loop; D's continuation and Effect ownership remain unchanged.
Both packed selectors are preserved. The merged normative source regenerates
all dependent pins, retaining independent vectors for both parents:

- Integrated grammar: `sha256:bd3b6c7767656a531df52628453cbff90762a8d6013af432ced62d241d8fdb0a`.
- Integrated independent Values Run: `sha256:cb619661631f118d81c0ae5fdfe60240ccde214ca7dd0b6f8c50719adbec95b1`.

The packed evidence above still belongs to `8074f08e...`, not this integrated
source. Integration checks and exact-HEAD CI must be reported separately.
