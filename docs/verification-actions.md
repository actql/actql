# Read-only verification scheduling report

Before reducing verification work, inspect repeated **declarations**:

```sh
node scripts/verification-actions.mjs
node scripts/verification-actions.mjs --json > /tmp/verification-actions.json
node --test scripts/verification-actions.test.mjs
```

This is a report, not a selector, execution log, action-key system or cache.
It never executes inspected commands, imports inspected JavaScript, writes
repository files, skips a check or supplies old evidence. This report does not change
workflow jobs or assertions. The fixtures also run through the existing
`ci-evidence.test.mjs` CI reporting gate; retain its other imported fixtures
when integrating reporting changes.

## Declared actions and selected CI jobs

This inventory describes workflow declarations; it does not evaluate the
run's CI selection plan. Consult the selector and final-check summaries to
distinguish executed jobs from explicitly **NOT APPLICABLE** families.

For pull requests containing only ordinary edits to existing regular files in
the [reviewed maintenance inventory](../scripts/ci-targets.mjs), CI runs the
selector, complete lint, complete spec and final check. Unrelated runtime and
proof families are skipped as whole families. N/A is neither a test pass nor
reuse of an older execution receipt. Selected proof campaigns still require
their complete JS, Wasm and native evidence.

New, removed, renamed, mode/type-changed or unclassified files do not qualify.
Main retains full verification; other PRs retain their normal job-family
coverage and existing core-target selection. A new runtime, build or proof
caller of a registered reporting tool requires re-review of that registration.

## Sources and candidate workflows

The default sources are `.github/workflows/ci.yml`, `package.json`,
`toolchain.json` and `scripts/local-checks.mjs` under the repository root.
A different checkout or an explicitly chosen candidate workflow is read-only:

```sh
node scripts/verification-actions.mjs --root /path/to/checkout --json
node scripts/verification-actions.mjs --workflow /path/to/candidate/ci.yml --json
```

`--workflow` changes only the workflow input. Package scripts, toolchain pin
and local-runner text still come from `--root`. Use a complete candidate root
when those inputs changed too. There is no automatic PR fetch or implicit
import of unmerged code. Split Client jobs are discovered from the supplied
workflow without a second job registry or changed verification commands.
The tool does not certify Git revision, clean checkout or an atomic snapshot.
Report provenance must identify the actual source checkout separately.

Each occurrence retains job, matrix case, step index, declared purpose,
conditions, prior step commands and ordered predecessor occurrence references,
runner/setup declarations, working directory,
shell, explicit environment assignments and complete ordered argv. Locations
identify the YAML step (not an asserted exact shell-token column), followed by
any nested `package.json` script/hook locations. `commandLineOffset` is relative
to that source's command string. Inputs/selectors and flags are descriptive;
complete argv remains authoritative. Selectors are **not file-content identity**.

The local npm definitions are callable entrypoints, not claimed extra executions
in a CI run. Nested `npm run NAME` lists the checked package's `preNAME`,
`NAME` and `postNAME` declarations in order. Their actual execution depends on
unobserved npm configuration (including `ignore-scripts`); this is not evidence
that any lifecycle hook ran. The local runner is inspected as text,
with workflow-reference line numbers. Its JavaScript filtering/substitution,
installed tools and inherited shell environment are not executed or certified.
Use the existing local runner for verification; this report never replaces it.

## Interpretation

JSON comparisons keep two separate fields:

- `invocationEquality: proven` means only identical normalized literal argv
- `equivalence: suspected` means literal argv and observed declared context
  match, warranting investigation; unresolved dependency closure still exists
- `equivalence: different` identifies a known difference in argv, selectors,
  target, flags, explicit environment, compiler/setup declarations, directory,
  shell or matrix context
- `equivalence: unknown` includes opaque/dynamic declarations, different
  purposes/conditions, prior command histories and local-versus-CI entrypoints

**No action equivalence is proven and every record is ineligible for reuse.**
Matching command text or test names never establishes semantic redundancy.
Separate targets, crash states, restoration checks and execution observations
must remain independent. Missing dependency evidence cannot become equality.
A successful exit means reporting succeeded, not that verification passed.

For example, current scheduling can contain the same bounded-session runner
before mutations and again for final restoration. Its literal invocation
matches; its purpose and preceding execution state do not establish equivalent
actions. Repeated Host `moon build` declarations likewise occur after different
commands and unknown filesystem effects. The fixed Run-materials vector runs
under separate matrix targets; those observations must not be collapsed.
Root `check:spec` includes scripts also available through separate local npm
commands. Their availability alone is not a second scheduled CI execution.

## Conservative normalization and omissions

Only literal words, single/double quotes, spaces, backslash-newline
continuations, comments, `&&` and newlines are understood. Ordered arguments
are never sorted. A single quoted `$NAME` is literal; double quoted expansion
is dynamic. Unsupported shell syntax makes the **whole block opaque**, rather
than extracting a command that may actually be conditional. Variables,
substitutions, pipes, redirects, globs, loops, `cd`, `export`, shell functions
and stateful builtins are not interpreted. Unknown executables and unsupported
npm arguments remain opaque. No nested Node/Python/shell program is inspected.

Only simple literal matrix axes are expanded, capped at 64 cases. Dynamic
matrices, include/exclude and unsafe substitution values stay unknown. YAML
duplicate keys and aliases are rejected. Remote/local `uses:` actions and
reusable workflows are retained as explicit omissions; their internals and
state effects are not guessed. Their declared refs/inputs remain part of the
observed setup context. Dynamic environment/directory/runner/action inputs and
unsupported shell selections prevent a comparison. The reporter does not
collect inherited environment values, secrets or resolved executable bytes.

Input files must be regular, non-symlink final entries, bounded to 2 MiB and
valid UTF-8. Descriptor reads reject observed changes and special files, but
are not an atomic multi-file snapshot. Inventory and pair limits fail with a
nonzero exit rather than silently truncate. Pair discovery uses the understood
command family plus subject (script, first test selector or Moon operation),
not all possible pairs. The full occurrence list remains available even when
no pair is emitted. Shared names or subsets of a multi-test command are not
split into claimed independent actions.

## Action-input evidence owner

[#195](https://github.com/actql/actql/issues/195) and
[#214](https://github.com/actql/actql/pull/214) own the bounded Lean input manifest
and comparator in `proofs/bounded-session/action-inputs.mjs`. This independent
scheduling report, based on main before that integration, explicitly reports
`actionIdentity.status: unavailable`. It does not copy the module, mint another
key or assume an unmerged dependency. Once integrated, use that owner's
`readManifestFile` and `compareManifests` on **two explicitly supplied manifests**
for the bounded Lean action. Even equal observed inputs retain unresolved
runtime/distribution/environment boundaries and never permit skipping or reuse.

The fixtures use independently authored commands and expected differences,
including negative input/target/flag/environment/fault cases, compiler and
runner changes, mutation/restoration, unknown shell, npm lifecycle/cycles,
matrix separation, source locations and read-only CLI behavior.
