# Adopted WITH P2-T Lag source connection

Status: implementation and limited local evidence; installed public acceptance
has not run. Newly passed external E2E scenarios: **0**.

This closes the missing named `lag` source adapter in the already adopted WITH
revision, LANGUAGE_CHANGES operation signature and acceptance T12. It does not
expand scalar `LAG OVER`, add another execution owner, or change the RelA
navigation contract. #1645 is merged; the original 55 Frontend repair unit is
closed separately. The original fixed full-Core 92 failures remain historical
failures, not a new all-Core pass.

## Connection and independent control

```aql
WITH rows AS (
  SELECT 1 AS id, 10 AS amount
  UNION ALL SELECT 2, 30
  UNION ALL SELECT 3, CAST(NULL AS FLOAT64)
), keyed AS (FROM rows |> ASSERT UNIQUE BY (id)),
lagged AS (
  FROM keyed AS r
  |> lag(partition_by: [],
         order_by: [{field: r.AMOUNT, dir: 'desc', nulls: 'last'}],
         field: r.amount, output: previous)
)
SELECT id, amount, previous FROM lagged ORDER BY id
```

Designed rows are `[{id:1,amount:10,previous:30},
{id:2,amount:30,previous:null},{id:3,amount:null,previous:10}]`.
Ordered columns are `id: number NOT NULL`, `amount: nullable number`, and
`previous: nullable number`. Calculation order is amount descending NULLS LAST;
published order is id ascending. Candidate-key completion comes from the common
ASSERT UNIQUE owner, not an assumption about inline rows.

The independent complete JSON Programs and rows/schema are authored in
`scripts/fixtures/lag-source-input.mjs`. The source adapter passes partition
fields, shared OrderKeys, field/output roles and an optional literal or whole
Parameter offset into the existing `lag` operation. It preserves repeated and
empty partition lists, authored direction/null placement and omitted offset.
The checker decides counts, collisions, calculation order and nullable output.
Frontend tests compare actual lowering arguments and ASSERT bodies to a separate
complete JSON Program and check both through the common owner.

## Evidence by fixed source

- `65839f7f508410f2d0625b11648a62d0e1fe2f42`: independent JSON passed;
  three positive text controls failed at the missing source entrance. JS 2/5.
- `57991607696106dca15b7216a7dc43044c818b5f`: roles connected; JS 15/17,
  two source controls still failed before Lag. Typed diagnosis at `6fc049ba2`
  identified `Operation(Expression(NullTypeUnresolved))` in the preceding set
  query. The bare-NULL variant remains a separate unresolved boundary.
- `5aa59d750e799f70e09811911a173ff3bcf1bc42`: explicitly typed NULL matches
  the original nullable Float oracle without changing values; JS 17/17 including
  shared dedupe callers. No untyped-NULL fix is claimed.
- `881971cb5d2fdf2ded6bc03170d82d576c3b2762`: a broader selection including
  existing common Lag packages timed out at 60 seconds, exit 124; not PASS.
- `0aa1b110aa9c7de6557d76121e2e3b6ce440c974`: focused source/role JS 7/7;
  independent Node 128/128. Empty order, offset 0/-1/1.5 and output collision
  assert precise common causes; dropped fields/old aliases assert UnknownColumn.
- `da3601f29b53999d2b9f863a7cd0d87e49490a89`: after normal adoption of main
  `f6632bd6fa2941a1988c3a4de0c38afd2b449c71`, JS 9/9 including the real
  Values Run-CID consumer; Node 128/128 including final observation hooks;
  affected query_syntax/query_program/source_frontend Wasm and Native compile
  succeeded. No Wasm/Native runtime is claimed. Prior JS info at `e8924ba954`
  generated no interface changes.

Commands use pinned toolchain and `prepared-checks.mjs`, 60 seconds/grace 5,
nonHeavy. Evidence hashes and exact commands are retained in `evidence-hashes.json`;
raw logs remain outside Git in the workspace evidence path recorded there.
Compilation is not runtime acceptance. A formatter invocation initially touched
an unrelated, previously clean Model capture file; that formatting-only mutation
was restored from its tracked HEAD. The wrapper now uses pinned `moonfmt` on each
explicit changed file and preserves other owners' source.

## Identity and inventory

Only the authored query grammar/rules inputs change grammar identity. Frozen
`pre-lag-*` bytes and the complete submitted watermark Values preimages remain.
`lag-identity-oracle.mjs` independently reseals the complete template, executable,
compiled and Run bodies; it imports no product compiler, canonicalizer or runtime
output. Program, Unit, ResultPlan, dependency and limit bodies are unchanged.
Current generated pins and the real consuming Run assertion follow this oracle.

Public registration adds exactly 8 successes and 6 refusals: inventory 4032 to
4046, SHA-256 `edad94cbc20403137cf7c569cd224fde2b44e74d40ab554c4ce66ec99a0124bd`.
The independent enumerator reads declared fixture data. This count is prepared
coverage, not an executed public result.

## Original installed acceptance, still pending

Use only the existing shared Heavy window assigned by the coordinator. From one
fixed clean SHA, run normal five-package production, then the same-source
`--lag-only` public consumer in a fresh external installation. Each original
guard remains 300 seconds/grace 5:

```sh
node reviews/2026-10-12-frontend-lag-source/prepared-public.mjs --producer FULL_SHA /private/tmp/actql-b-lag-FULL_SHA-pack
node reviews/2026-10-12-frontend-lag-source/prepared-public.mjs --consumer FULL_SHA /private/tmp/actql-b-lag-FULL_SHA-pack
```

Each Local/HTTPS transport must complete the same eight JSON/text positives
(default offset, offset two, repeated partition, typed empty) and six refusals
(empty order, zero offset, collision, missing field, String field and reserved
output). Existing public comparisons check values, full ordered schema, source
read count zero, attach, identical-request resend, lookup and unchanged counters.
The existing verified-case receipt collector saves actual Run/value/schema after
those comparisons without generating expectations or adding Client reads.

Preserve all five tarballs, manifest/source/digests, independent and completed
inventories, both transport receipts and terminal/worker/group/lock evidence.
Do not relax limits or discard a failing case. No five-package producer, installed
Local/HTTPS execution, Provider or Hosted CI has yet run for this unit. Shared
Heavy allocation is pending behind D/G. Other WITH P2 coverage is not implied.
