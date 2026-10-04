# Pure two-source acquisition connection

Issue: [#285](https://github.com/actql/actql/issues/285).
Inspected source: `adf43ce95eb833630140f619c0aefba266b056bd`.
Publication base: `ccd805fc0c852963c739adcf4efd7a90dc490e71`.
The intervening main change contains only lag/as-of tests and their review note;
all edited source and harness files are unchanged.

## Boundary

The installed pure plural route used a separate Native-first preparation and
passed Native-only configurations into capacity admission. The existing private
Local ledger owner already supports typed Native/Broad configurations for both
Pure and Effect owners. Expose that same connection for pure two-input execution;
keep the selected configuration and its original residual/retention capacities.
No acquisition scheduler, fallback estimate, additional ledger or general N-Source
support is introduced.

All counts now use the same authorization-gated common selection. A held read is
reprepared under its resumed occurrence-specific access before shared ledger
creation. That exact preparation is used for the later acquisition. Selection and
observations join the existing per-occurrence diagnostic events. Read authorization
is rechecked before provider access; Effect approval and write dispatch are untouched.

This is acquisition eligibility parity under equal source policy/authority/evidence,
not a claim that Pure and Effect whole-Program plans or reservations are identical.
Broad retains its original Local residual owner; existing capture, managed-input,
publication, cleanup and durable retained-Result protocols remain responsible.

## Focused executed evidence

The bounded/nonzero Node wrapper executed five connection tests on Node 24.19.0:

- Both Native and Broad selected payloads cross pure/Effect preparation at each
  of the two occurrence positions
- Held and denied reads cannot select or manufacture configurations
- Missing comparison evidence remains deferred, without a Native shortcut
- Resumed selections precede ledger construction; second-source failure preserves
  first-source cleanup, including failed cleanup and idempotent retry without reread

All five fail against the original two adapter files and pass with this repair.
These are adapter connection tests with a modeled MoonBit/provider boundary;
they are not real candidate, physical reservation or end-to-end acceptance.
The final run passed 5/5 after correcting two omissions in the new dispatch mock.
The 93 unchanged JavaScript import/wrapper inputs were verified against their
Git blob identities. Changed JavaScript files pass syntax checks; changed files
pass whitespace checks. The changed MoonBit source passes the pinned formatter.

Three interface declarations were updated to match the source signatures, and
the RelA mirror follows the existing connector generator's byte-copy rule.
Compiler/interface verification was not run locally: those declarations await
normal CI verification rather than being described as locally generated output.

## Authored real-provider acceptance, pending execution

The existing two-source fixture and public/packed harness carry the new cases;
there is no second public execution implementation or duplicated fault driver.
The unchanged independently authored Program, rows and output contracts are used.

- Local and HTTPS observe actual product Native/Broad choices under ordinary
  installed priority, with both candidates eligible
- Eight successful cases include the existing distinct/equal/unused controls
  and a Broad two-input JOIN on each transport
- Fresh-process attach, read, lookup and exact-request resubmission require the
  same Run and zero Source reads, including the Broad cases
- Broad variants reuse second-provider failure, cancellation before its open and
  pending/error cleanup-retry scenarios; assertions observe the same ledger,
  positive retained holdings, exactly one close and no repeated Source reads
- The live capture boundary test checks positive Broad retention, occurrence
  identity rejection, independent release and idempotent close

No local Core build, real-provider campaign, packed acceptance, proof, native or
performance suite was run. The current draft is not acceptance-complete until
these registered tests and required automatic CI execute successfully for its
submitted source. No manual workflow dispatch or rerun is requested.

## First hosted result and ingress correction

Automatic [run 37162132269](https://github.com/actql/actql/actions/runs/37162132269)
for source `7b63f9f3e53dd6b16c432132d729f8a64d0a87d7`, tested merge
`d1b1481e9e30d8ebe6b449078bb31dc755eef08e`, passed preflight including the
public-interface/compiler check, plus spec and Core JS. The live Broad capture
identity/positive-retention test passed. Public Native controls passed.

The public Broad cases failed before execution because `embedded-local.mjs` still
called the Native-only getter in `prepareAcquisitions`. This was a missed ingress
connection in the repair, not a CI-policy problem or a bad expected result. The
packed job's saved diagnostic artifact confirms the same cause. The follow-up
uses the typed Native/Broad getter for selected preparations and lets held reads
reach their existing approval/resumed-selection owner before ledger admission.

A specifically bounded follow-up diagnostic passed **3/3**: Broad public Local,
Broad public HTTPS, and the existing real second-acquisition-failure/cleanup
control. Both successes retain the independent rows/contracts, two actual source
sessions and product-selected Broad diagnostics; exact-request retry performs no
additional acquisition. The failure control confirms one completed source read
and settled physical-close custody.

That diagnostic used the unchanged compiled core from the normal CI package
artifact `11288067328`, run `37162132269`, attempt 1. Its tested merge has exactly
the source tree of the first submitted commit. Only the two reviewed ingress
adapter hunks were applied in a private extracted installation, retaining the
producer's package-import rewrite. This is **mixed adapter-source diagnostic
coverage, not pristine packed acceptance for the follow-up commit**. No repack,
Core build, full public campaign or manual CI run was performed.

Verified SHA-256 digests:

- Artifact ZIP: `0ae2711014d70ec5b9fad05353b6bfbb3d451c1d3d23365ec52b3d455bc59dea`
- client-wire: `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0`
- sdk: `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b`
- run-host-core: `9aed70336c43f226a693eeee7158e731dde9a8ae13c49a498aa05eef97e5fa78`
- local-node: `13e60ca77fc2ce635971fad1240b056f0bb7da09067c8dec5ff08cd5a86c7311`
- node: `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64`

The ingress correction remains subject to fresh automatic exact-source CI and
full registered public acceptance, including restart and pending cleanup cases.
## Optional terminal Effect comparison prepared on 2026-10-04

The next narrow acceptance unit starts from main
`ab049bd4e0eec06b48186a957abf2af308d44716`, then normally merges main
`fc3378ec65551edd7d5d52ca1d88ea15d6e690fa` (#325 included). It compares Native JSON and
Broad authored text, each with and without a terminal Effect, on Local and
HTTPS. These are two independent pairs, not a strategy/format cross product.
The six files named by `scripts/fixtures/two-source-optional-effect.mjs`
contain complete submitted Programs, exact text and independent expectations.
Only the newly published MappingRef is bound at submission. No lowered JSON
is amended and no Source or Effect is invoked separately by the harness.

Both members retain `id >= 0` on each Source, JOIN `max_output_rows: 100`,
the same six output columns and the single row with `id: 1`, NULL left amount,
right amount 100, literal risk `high` and target/name constants. Both acquire
each exact DuckDB once, invoke no Model, and restore the same submitted request
and Run without provider opens or SQL after process termination. The Effect
member requires signed approval and write counts `[0,0,1,1]`; the pure member
has no checkpoint or write and counts `[0,0,0]`. The existing driver stops the
dedicated Host and execution process at durable capture and persisted approval;
the pure control stops after completed publication.

The ordinary packed Salesforce composition consumer executes these pairs
without a new job or package producer. `--optional-effect-only` selects them
without the existing Source/INFER fault matrix. Existing focused flags retain
their prior selections. An additive diagnostic observer connection exposes the
actual completed acquisition selection in the existing Effect owner, as the
pure owner already does. It does not change selection, admission or cleanup.
Program and Run CIDs can differ across JSON/text structure or Effect presence;
only exact same-request replay identity is required. The pair compares actual
candidate eligibility and explicit priority, not unrelated requirement CIDs.

Before registration, the new focused fixture/scheduling regression failed
1/5 tests because ordinary packed execution did not run the pair. After the
connection, 29/29 selected Node tests passed (Client scheduling, acquisition
custody and DuckDB selection). Outer and generated driver syntax checks and
`git diff --check` passed. Fresh-packed public execution and automatic PR CI
are pending; these local checks are not execution acceptance.

This does not close the Source-free Graph Result Data Policy dependency or
prove active temporary holding inventory. Those common connections remain
with A; cumulative allocation counters and `client.close()` alone are not
physical release evidence. Existing failure/recovery matrices are reused,
not duplicated for this optional-Effect pair.

### Manifest and Session CI main integration

The next normal merge adopts main
`c4fc104d8a700794766dcee5114617b001f8a6f9`, including #334's existing
manifest-selected Effect installation and #326's current scoped Session CI
setting. No conflicts or product acceptance changes are needed. Client
scheduling, acquisition custody and the selected installation table pass
30/30 focused Node tests after this integration. The previous PR run
37180581517 passed preflight but had not started its packed consumer when
this integration was prepared. That older submitted SHA's results remain
separate from the new automatic PR run; no manual rerun is requested.
