# NEAREST member binding across typed producer transitions

Date: 2026-10-08. B owns this Frontend connection. Implementation and focused
checking are complete for the cases below; public Local/HTTPS acceptance is not
established. The complete source-to-common-Program objective remains open.

## Counterexample and independent control

```aql
FROM queries AS q
|> NEAREST candidates AS c
   QUERY KEY (q.request_id) VECTOR q.embedding
   CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2
   KEEP (q.note, c.label) AS neighbor
|> SELECT label, neighbor.SCORE AS score
```

The common NEAREST output and ordinary object projection declare `score`.
Frontend object members resolve case-insensitively against that declaration;
ordinary machine property lookup remains exact. Before this change, the member
pass retained only Relation schemas. `to_vectors` discarded those facts and
`nearest` did not restore its output. The authored `SCORE` reached final checking
unchanged and was refused, although the independently authored complete Program
with exact `score` checked successfully.

`nearest_member_test.mbt` contains the complete independent Program, including
Values, input roles, ToVectors, two many-to-one KEEP joins, named key objects,
member derivation and Result columns. It also covers quoted mixed spelling,
nested `QUERY_KEY.REQUEST_ID`, and exact ordinary UnknownField refusal for a
missing member. One query still has two matches; query identity alone never
becomes an output uniqueness witness.

The first fixture attempt used the ordinary SELECT expression-slot spelling
rather than Pipe's slot 3 after three visible KEEP/result slots. Its comparison
failed; this was a fixture slot-name error. The expectation was corrected from
the existing slot allocation rule before changing the implementation. The
corrected control then passed while the uppercase source failed (1/2,
`run-p7VX90`). No expected value, contract, order or execution limit changed.

## Connection and ownership

The private member pass now retains common typed Carrier values for producer
bindings. Existing Relation probes still supply their schemas. ToVectors,
NormalizeVectors and ScoreVectors use `vector_typing.check`; NEAREST uses
`vector_typing.check_nearest` with the actual named query producer. The common
output Carrier supplies the subsequent Relation/object contracts. No NEAREST
field list or score contract is manufactured by the Frontend.

Successful probe work and Relation-to-Carrier field construction are charged.
A refused vector probe retains the remaining allowance and stops continuation,
just like the existing member probes. A missing producer fact is not a proof
of failure. Pending value, key, dimension, profile, capacity and execution
obligations remain with the ordinary checker and runtime owners. This does not
admit a provider, re-evaluate SELECT, sample rows, or create a fallback.

The change depends on the member-resolution implementation in PR #942 at
`16df32532bcd58b9919318bc194fb2b8e705a629`. The final merge target is main; while
that parent is unmerged, the child PR keeps its parent branch as its base.
No shared Owner, public contract, wire, identity pin or snapshot format changes.
`moon info src/query_program` produced no public-interface difference.

## Limited verification

Pinned toolchain, repository nonzero wrapper and serialized local guard:

- `run-th9v1E`: 29/29 JS across NEAREST lowering/shared checks, the initial
  member counterexample, existing member cases and probe budgets.
- `run-cl6tKP`: the expanded nested/refusal selection timed out after 120s;
  terminal SIGTERM, guard exit 124, locks released. No completed test result is
  claimed for that attempt. Its incomplete focused receipt remains retained.
- `run-ZTV7Cl`: 12/12 JS across `nearest_member_test.mbt` and
  `member_probe_budget_wbtest.mbt`, including nested members and vector probe
  continuation; 2/2 Node in `scripts/nearest-member-source-input.test.mjs`.
  Guard passed/complete, exit 0, output complete and locks released.
- Existing `moon info src/query_program`, selected formatting and
  `git diff --check` completed.

These checks were executed on the working change over the parent SHA above.
They are not exact-child-HEAD execution, public Host or CI evidence.
No full Core, cross-target, proof/performance or full packed campaign ran.

## Prepared public acceptance and remaining work

The existing `scripts/fixtures/nearest-public-input.mjs` consumer now includes
two independent ordered JSON projection controls, a source `neighbor.SCORE`
projection, nested quoted/mixed key members and a missing-member refusal.
There are nine positives and five refusals. Existing nullable KEEP, empty input,
omitted KEEP, Result.describe, column order, stream completion, re-read/retry
and rejection counter assertions remain. Expected dot scores are 1 and 0;
query q1 matches candidate a at rank 1 and b at rank 2.

Fixture preparation is not execution evidence. This consumer requires genuine
published typed `queries` and `candidates` sources with dimension-2 embeddings;
the JS compiler's Values test context is not a public Source installation. No
adapter, schema override, array-to-vector coercion or test-time Program repair
is added to fill that requirement. The current ordinary Host declares VecA
checking support; the historical profile-disabled report is not evidence of a
current refusal.

Next close these same controls through a normal clean-HEAD five-package
producer and the existing public Local/HTTPS installation/consumer. Preserve
rows, full column contracts, order, acquisition counts and Run-admission/I/O-zero
refusal checks. Attribute tarballs and receipts to the actual child SHA.
Graph and INFER producer facts, wider NEAREST source composition and complete
public acceptance remain separate unfinished parts of the full objective.
