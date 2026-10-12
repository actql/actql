# WITH JOIN topology and installed Values repair

## Fixed sources and scope

The immutable full-Core failure source is
`d62f4de55f98badeb37af933f6fdb0e5dbfeae22`. This unit repairs eleven original
`compile_test.mbt` cases and one `full_using_scope_test.mbt` case. The separate
Graph refusal case comes from #1625, whose authentic branch was merged here;
its fix and six-case scope are not counted again.

The initial baseline `7653570639695deae48b7dd0fff8d48081f1018b` ran
`run-vEhoZn`: 51/64 passed, including the separate pending Graph refusal.
Latest adopted main is `41dca6e71a7ffffaaa48d0eab0932a3f4ab34ed4`.
The product/test source verified below is
`36e97d10e2be4837cc3d4657485bf8925404c2f9`.
A later documentation-only commit is the submitted HEAD; it is not assigned
new runtime evidence.

## Independent requirements and the actual defect

`docs/spec/query-text.md`, “WITH producer bindings”, specifies that naming a
producer adds no acquisition or Stage boundary, that earlier/outer producers
remain visible, and that valid unused bindings are statically checked and then
pruned. Original SQL/Pipe source strings, Values data/schema, declared keys,
predicates, JOIN arguments and ceilings, ordered exported fields and common
checker assertions remain intact.

Old fixture expectations instead required a Stage per named binding and old
standalone JOIN helper names. They now verify one shared logical pipeline,
actual pre/post-JOIN predicates, evaluated SELECT inputs, output-only fields,
LIMIT, and one installed Values producer. DISTINCT's selected row is followed
only through explicit same-column identity projections to the published Result;
the assertion does not accept an arbitrary downstream transform.

The outer-`orders` JOIN, previously refused by the old CTE route, is valid under
the adopted scope. The independent one-installed-Values assertion exposed a
real defect: `bind_script_input` memoized Captured inputs but not installed
GeneratedValues. `run-ZBMU0n` passed 70/71, with this case emitting two Values
steps. The fix reuses the existing `ScriptSources.bound` entry for installed
Context inputs. Synthetic source-free SELECT Unit producers remain local to
their body. There is no new execution Owner, acquisition, evaluator, identity,
contract, schema, pin, limit or fallback.

The original full FULL USING Program is preserved both as a checked staged
control in the test and in `original-full-using-program.json`. The current
complete Program was independently recomposed from those original operation
bodies and the adopted WITH contract: one Values seed, ASSERT UNIQUE BY x,
the same keyed producer on both JOIN ports, FULL ON x with ceiling 10,
coalesced key, original ascending order and x/a/b projection. Private names were
worked out from the existing reserved-length allocator, not copied from a
product result. The staged control is not claimed to be the current lowering.

A JOIN budget of zero remains refused by its original single-JOIN
`UnsupportedCte` construction boundary. The chain JOIN path has a different
existing refusal; this unit does not change either product contract.

## Executed checks

All checks use the tracked `prepared-checks.mjs`, the repository pinned MoonBit
and Node, and the unchanged 60-second / 5-second grace / non-Heavy guard.

- `run-6AYNDm`, source `36e97d10e2be4837cc3d4657485bf8925404c2f9`:
  **JS 84/84**, selecting `compile_test.mbt`, `full_using_scope_test.mbt`,
  `with_join_test.mbt`, `full_select_scope_test.mbt`,
  `with_binding_demand_test.mbt`, `with_binding_preparation_test.mbt`, and
  `source_free_test.mbt` under `src/query_program`.
- `run-q8qlYg`, same source: read-only pinned formatter passed for the three
  changed MoonBit files. `git diff --check` passed.
- Both guards report complete exit 0 and lock release. The runtime Owner 47713
  was directly observed absent after completion; the final own lock is absent.

Preserved intermediate failures: `run-d1Wzqm` compiled zero tests because this
unit's new helper incorrectly used Option instead of Result; `run-YXD3Cx`
66/71 identified independently authored slot expectations that used the chain
allocator on the single-JOIN path, plus obsolete outer-scope rejection and the
separate Graph refusal. These failures were corrected by inspecting the actual
existing allocator/route and adopted scope. They remain failures, not successes.
`run-RTDglz`, `run-3VWJBJ`, `run-WbkTsg` are formatter runs only.

Original logs/receipts remain in `_build` and are copied byte-identically with
SHA-256 verification to
`/Users/t14i/workspace/20260822/reviews/2026-10-12-b-frontend-core-repair-evidence`.
`evidence-hashes.json` publishes hashes only, not raw logs.

## Boundaries

Twelve additional original failures have repair evidence in this unit. Across
#1610, #1617, #1623, #1625, #1628 and this unit, 47/55 assigned original failures
have bounded repair evidence; the remaining eight are not declared fixed.
This is not public Host/packed Local/HTTPS acceptance, Native/Wasm execution,
full-Core conformance or Hosted CI success. None was run. Merge target is main;
#1625 is an authentic unmerged dependency if it has not yet reached main.
