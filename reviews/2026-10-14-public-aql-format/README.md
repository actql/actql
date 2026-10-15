# Explicit public AQL format

The adopted launch gap L1 requires `format: 'aql'`. This spelling selects the
existing Text compiler, with the same typed declarations and explanatory
check path as `aql-text`. The authored source format remains part of the
original request; existing spellings, helper defaults and stored identities
are not rewritten. No DATA fallback, parser or execution Owner is added.

The independent baseline at 2c62c2b3921df04e38f6d50709e6a2f4ed5d9d08 failed
Node 0/2 (`InvalidAqlDocument` and format admission) and JS 0/1 (`InvalidFormat`).
The initial Node import failure is separate environment evidence. Baselines
remain in run-jWQE9v, run-UqboyU and run-jQLHG5 under the author worktree.

The public cohort has four normal declarations (typed parameter, WITH/Pipe
ordered duplicates, SQL NULL, independent JSON Program) and two refusals
(retired DATA, undeclared parameter) per transport. Existing source-free
installation, authorization, I/O guard, Result assertions and same-request
attach/resend/lookup checks are reused. The original default cohort is unchanged.
The AQL-only check probe verifies typed parameter checking, authored syntax
location and zero Run admission. No fixture is generated from product output.

`prepared-checks.mjs <clean-sha> node|moon|callers|source|validation` uses the
existing nonzero test guard. The validation mode requires the worktree's
private Python 3.13 environment with httpx 0.28.1, rfc8785 0.1.4 and mypy 1.19.1,
and locked TypeScript 5.9.3. It checks Python public stubs, runtime wire, TS
consumers and ordinary Python/family metadata freshness.

`prepared-public.mjs --producer <clean-sha> <fresh-absolute-RC>` produces the
normal four release packages with unmodified prepack. After actual producer
termination, `--consumer <same-sha> <same-RC> <fresh-absolute-receipt>` installs
through the existing fixture registry in an empty directory. Each stage retains
the original 300-second budget and five-second termination grace. No overlay,
checkout NODE_PATH or supplied product runtime is permitted.

D owns the Native CLI's remaining external-declaration format gate connection.
E owns actual Python packaged Local acceptance; B includes the coordinated
format type/wire projection only. Their execution evidence is separate.
