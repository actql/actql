# Grouped navigation offsets: Frontend connection and acceptance

Status: this bounded Frontend connection has completed local public acceptance.
Required hosted CI remains separate. This does not complete the analytic profile.

## Counterexample and preserved contract

The query parser accepts `LAG(amount, (2))` and `LEAD(amount, ((@p)))`, but the
former lowerer inspected only the argument's root node. It rejected a grouped
literal or parameter with `UnsupportedAnalytic`. A complete independently
authored Program using numeric `offset` and `offset: {"$param":"p"}` passes the
ordinary checker. The pre-fix focused run passed that control and failed the
SQL/Pipe source comparison: 1/2.

The existing [analytic contract](../spec/language.md#row-preserving-analytics-analytic)
requires a literal or whole parameter reference, nonnegative safe-integer offsets,
default 1, typed NULL outside the partition, and the original input multiplicity.
It agrees with the selected GoogleSQL navigation signature's literal/parameter
restriction; see [LAG and LEAD](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/navigation_functions#lag)
and the pinned [reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/navigation_functions.md).
Removing grouping from these atoms preserves their role. It does not authorize
column-dependent offsets, arithmetic or arbitrary expression evaluation.

`query_analytic_offset.mbt` performs a bounded walk through parentheses, retains
the argument's source origin, and emits the existing numeric/parameter form.
Numeric digits also consume the expression work budget and retain the previous
safe-integer validation. Parameter declarations, binding and value constraints
remain with the ordinary checker. No parser, shared Owner, execution engine,
wire, schema, contract version or Grammar Manifest is changed. Previously
accepted ungrouped inputs retain their semantic Program representation.

For example, the public source can now contain:

```sql
SELECT id,
       LAG(amount, ((2))) OVER (ORDER BY id) AS previous,
       LEAD(amount, (@p)) OVER (ORDER BY id) AS next
FROM records WHERE id > 0 ORDER BY id
```

## Fixed sources and focused checks

- Base main including #421 and #434:
  `77ba71aa642d1081f047132e59ef18ebf17a787c`.
- Clean implementation and acceptance source used for normal pack:
  `3e8f105f98e853f64c3f1bfc99fa3a2a9724d0aa`.
- Post-fix JS: new regression file **4/4**, existing `*OVER*` caller selection
  **3/3**. Guards: `run-LT0Xpw`, `run-uG9PqO`; pre-fix `run-86Rpeb`.
- Pinned MoonBit `0.10.12+1634b282e` formatting, changed Node file syntax and
  `git diff --check` passed. One intermediate compile diagnostic was corrected
  before the passing checks; it is not evidence of a product failure.
- No full Core, Wasm, Native, proof, performance, full Client or full packed
  corpus was run locally. No manual Actions rerun was requested.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/grouped_analytic_offset_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/compile_test.mbt -f '*OVER*'
node scripts/test-packed-public-query.mjs --analytic-offset-only --keep-artifacts
```

The packed command ran under the shared serial heavy-check guard with a 720s
budget and 5s TERM grace. Its installed acceptance profile explicitly declares
analytic input/output/partition wire ceilings of 1,048,576 bytes each and 10,000
frame memberships. These are test installation limits, not observed-size
evidence or a change to production defaults. The 512 MiB execution budget stays
unchanged. The cases are also registered in the normal packed corpus.

## Real public acceptance

Evidence producer `public-query-evidence-KonfKc`, guard `run-SbByfn`, records
clean source, five successful ordinary prepack commands, exact tarball digests,
outside-checkout installation, package-boundary checks and complete command logs.
The producer summary reports `status: passed`, `complete: true`.

The same unmodified package installation completed **5 positive cases and 9
preparation refusals on each of Embedded Local and authenticated HTTPS**. The
positive cases include the independently written JSON control, authored SQL,
authored Pipe, zero-offset duplicates/NULLs, and empty typed output. Exact rows,
column order and `Result.describe().columns` agree with the independent fixture.
No private columns appear. Input id=0 detects a dropped WHERE; offset 2 differs
from the default; parameter zero detects loss of the parameter binding.

Each success checks one Source acquisition, Named Result stream completion,
reattach and same-request replay without new acceptance or acquisition. Each
refusal checks the existing typed input-error code, zero new Run admission,
zero provider I/O, and no request registration. Refusals cover undeclared/missing,
negative, fractional, NULL, unsafe and incorrectly typed parameters, plus
dynamic and arithmetic offsets. The test does not patch an emitted Program.

Independent machine control: [Program](fixtures/analytic-offset.expected.program.json).
Designed rows and column contracts: [results](fixtures/analytic-offset.expected.json).

| Package | SHA-256 |
|---|---|
| client-wire | `9dddd809931f810598bf6669ffd211b716c40bd34b9f169073b90d11cc014595` |
| sdk | `440cc4585c66840867f645708c6654435e7f111dc119f91f3bd4ccf117a11207` |
| run-host-core | `cdacf102e0615594dd7aafeb45612786f59235b900884ae40860eb71f48b9c99` |
| local-node | `7af1662740a29f56de18da62b87300471aded483afa98dff5d7cab3cfa38b051` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The subsequent evidence-document commit changes only this review and its two
independent JSON fixtures. The pack is explicitly evidence for `3e8f105f...`;
documentation changes are not a second execution run. There is no unmerged Git
dependency. The capacity boundary from #430 and common IN execution from #435
remain separate unresolved units; neither is claimed as fixed here.
