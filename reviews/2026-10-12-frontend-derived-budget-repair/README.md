# Frontend Core repair: WITH producer composition and bounded checking

Base main: `b0ae22c042efc04f90c7c279e2cc51aadc4651cf`. This fixture-only
unit closes nine original failures: optional-derived alias (1), its budget
controls (2), nested queries (3), and Pipe CTEs (3). Product/contract/pin changes
are zero. No original source, Values rows, Source declarations, predicate,
projection column order, UNION multiplicity, or runtime limit changes.

## Independent complete Program oracles

The adopted WITH contract says naming a binding neither acquires/copies data nor
requests placement or a task/Stage boundary. Complete independently authored
Program comparisons remain; their obsolete per-binding Stage shells are composed
into the existing pipeline instead. Every original independent Program is
preserved in `original-independent-programs.json`, with its exact base SHA. The integration
review restored these six historical literals directly from Git at that base;
the submitted archive had inadvertently contained the new composed expectations.
Original author ancestry and the actual test expectations remain unchanged.

Expected programs are authored from those original declarations/rows and the
selected producer semantics, not parsed out of actual compiler output. Private
slot allocation is checked separately against the installed allocator: two
installed inputs reserve two names, binding allocation reserves cte_2, then the
Values leaf reserves seed_3. The expression/predicate/schema/row oracle does not
come from that allocator. Full Program comparisons still detect missing or
wrong filters, fields, imports, branch reads and append inputs.

- Values projection: one Values leaf, `a > 0`, current `[a,b]`, final `[b,a]`,
  one main Stage. Original duplicate and NULL rows remain unchanged.
- Captured projection: the original capture Stage/declaration/predicate/full
  schema remains byte-equivalent as a JSON value; one retained Result supplies
  the main Stage. A transparent derived range retains an identity projection;
  ordinary WITH naming alone adds none. Explicit Pipe AS seals the new range
  snapshot using the current full column projection. Each source form has its
  independently authored complete expected Program.
- Shared captured UNION ALL: one unfiltered original capture, separate
  `amount > 10` and `amount < 5` consumer filters, their `[id]` projections,
  append with both producer references, final `[id]`. No implicit Stage per arm.
- Named/unnamed derived budget controls: preserve predicate, NULL/duplicate
  source and LIMIT 3, and the original 20-step budget. Fused composition is
  accepted by the ordinary checker. A separate one-step structural limit is
  rejected with CompileLimit, proving that admission was not relaxed.

Existing demand/static checks also run. The independently authored simple
optional-derived Values control remains unchanged. This unit does not establish
runtime rows/Host/publication or execute an external Source.

## Exact evidence and unsuccessful iterations

- `a0a42d8b122621780bf8051d77c33872aecca49f`: run-6keTig JS0/2 (old presumed
  23-step rejection); run-pc82VB JS11/18 (seven old topology expectations).
- `a325b491cf92e9130db1f6298e6443730904c8ba`: run-nuUz2k JS18/20. My first
  new oracle omitted transparent range projections. Source inspection of
  binding carry_ranges and explicit AS scope identified the distinction.
- `852d10f6bd595f890b510b9f52d2a68c8e0fb281`: run-9t4LYN JS19/20; I had
  overgeneralized derived transparency to plain WITH naming. It remains a
  failed oracle iteration, not product completion.
- `60e9c68062ff00e3d7041723442950b32bf42e27`: run-JeL8ez JS3/3 after explicitly
  separating AS rebinding from WITH naming. run-NCwvnn pinned formatter-write
  is retained separately.
- `a414a9b3c2d408c477ba0802910b3789d96f1d10`: run-AeMqjE JS **28/28**, the
  four changed fixture files plus with_binding_demand/preparation controls;
  run-27cdBh read-only pinned formatting of the four changed files. Both
  complete exit 0. Owners 19513/22016 were directly observed absent and run
  locks released. Later documentation HEAD is not substituted for this source.

Every guard used 60 seconds / grace 5, nonHeavy. Run
`prepared-checks.mjs` with those six explicit files under the pinned Node/MoonBit
environment; `--format` is read-only. No full Core, Local/HTTPS, package producer,
Provider, Native/Wasm execution, or Hosted CI. Raw receipts/logs are verified
copies at `/Users/t14i/workspace/20260822/reviews/2026-10-12-b-frontend-core-repair-evidence`;
only verified hashes are published in `evidence-hashes.json`.

Together with #1610/#1617/#1623/#1625, bounded repair evidence covers **35/55**
original assigned frontend failures; **20** remain. Capture/order and actual
Catalog gaps, remaining JOIN/PIVOT/UNPIVOT topology and Graph checking remain
separate. #1608 is frozen and private lag/typed preparation diagnostics preserved.
