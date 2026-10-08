# Explicit local references on the ordinary Native Host

## Connection and dependency

This unit adopts #1014, merged to main as
`b693899a4c15e0cd30ba638d11a626556e30f141` (published parent
`fb38a8609693878ac586071b01f0398edd76abcf`). The earlier
`f028c848412fb2e5644262126f2c00949475f5df` measurements remain original evidence.
The working branch adopted main `80ca8ab23202cde18123e9a1a790bb7c5f308aa8`
by a normal merge (`6158440abbcb66b330a5feaf6dba3039be0407f2`).
After #1014 integration, it normally merged main
`fc0e48bfb` before publication.
It introduces the public library connection, not a CLI or a new execution owner.

The edited boundaries are `physical_strategy` (preserved conditions, bounded
immutable template validation and residual assignment correspondence),
`physical_host` and `duckdb/standard_host` (read-only ordinary offline proposal),
and `duckdb/host_native` (explicit settings, lazy local read, current input
binding, policy admission, optional bounded explanation and release custody).
The existing Native probe consumes the new typed failure. Workflow, CI
selectors, Effects, Model execution and common cancellation are unchanged.

## Behavior and trust

Absence of settings preserves the existing offline selection with no profile
read, input identity traversal, measurement or remote consultation. Diagnostic
reference mode never changes selection. Selection mode requires explicit
permission for uncontrolled external load; this permission does not bypass
input, Program, runtime, capture, trust, freshness or current request checks.
Load applicability, stable improvement, net benefit, calibrated ETA and p90
remain unknown.

The configuring application chooses a trusted local root, exact file digest
and original revision from its validated original. A payload cannot authenticate
itself. The Native reader admits at most 60 KiB, reads the file generation once,
validates the closed existing template and retains immutable bytes. Missing
files become unknown; changed digest, revision, malformed schema and read/close
errors fail admission. The cache contains no request, grant or previous commit.
Runtime/artifact/environment attestations come from trusted application settings;
the Host cannot independently attest the entire executable or external load.

An opaque input token must match this dispatch's actual captured Source and its
bounded logical Relation/schema identity. Conditions derive the checked Program
CID, actual row count and Native import/retention/execution limits; the profile
cannot supply these values. Input identity is computed over already captured
rows, without calling Source again, only when explicitly requested by the
application. Its preparation cost must be included in the caller's outer timer.

Each choice uses the ordinary pending request and candidate snapshot. Native
clock checks occur before and after optional work and before common admission.
A descriptive initial whole-Run median may propose one offered assignment;
subsequent choices match its task/registration/resident realization against
current residual feasible assignments. Current prices, resources and opaque
resident binding remain ordinary admission obligations. This correspondence
neither predicts a new residual time nor proves a globally optimal plan.
Missing/mismatched references use the configured offline policy only after
validating the same current request. Invalid or expired requests never do so.
Unsupported input/candidate paths remain unknown without manufacturing requests.

Explanations are bounded, read-only queries, with no arbitrary storage callback
in execution or cleanup. Their optional serialization failure does not change
Run outcome. The Host retains input binding through failed/pending cleanup and
clears its additional capture reference only after confirmed formal release.

## Current local checks and remaining acceptance

- JS: template/sidecar/ranking fixtures, **10/10**.
- JS: lazy configuration and optional diagnostic failure fixtures, **2/2**.
- Native: changed public Host and real probe consumer typechecks succeeded.
- Public interfaces were generated with the existing `moon info` tool.

Commands:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/physical_strategy/operational_profile_template_wbtest.mbt src/physical_strategy/operational_estimates_wbtest.mbt src/physical_strategy/empirical_ranking_wbtest.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/connectors/duckdb/host_native/performance_configuration_wbtest.mbt
moon check --target native src/connectors/duckdb/host_native
moon check --target native src/cmd/native_retained_case_probe
moon info src/physical_strategy src/physical_host src/connectors/duckdb/standard_host src/connectors/duckdb/host_native
```

Native checks/interface generation used the shared local supervisor with a
120-second limit. Toolchain: the checked-in MoonBit pin. Evidence directories
are `_build/focused-evidence/focused-test-9LPjNM`,
`_build/focused-evidence/focused-test-tsNVJu`, and
`_build/local-checks/attempts/run-cg5GhS`.

These are portable fixtures and compiler evidence, **not actual Native runtime
acceptance**. The complete ordinary caller example, Text/JOIN runtime acceptance,
restart, stale request, stop and cleanup retry, current-revision originals and
cost disclosure remain the next integrated unit. The parent measurements remain
unchanged originals; no earlier success is relabeled for this revision.
Hosted CI remains intentionally stopped and has not been requested.
