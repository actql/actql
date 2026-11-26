# Repository conventions

- Write all code comments, documentation, and GitHub communication in English.
  This includes issue and pull request titles, bodies, comments, and reviews.
- Follow Conventional Commits for commit messages and pull request titles:
  `<type>[optional scope][!]: <description>`. Write descriptions and commit
  bodies in English, and use the appropriate type and scope for the change.

- Keep `docs/design` focused on architecture, semantic decisions and contract
  boundaries. Do not put branch handoffs, cherry-pick instructions, delivery
  status or test-run reports there. Report those in the working conversation
  and commit history instead.

- The public documentation under `docs/` (getting started, concepts, guides,
  connectors, reference) defines the v0.1 target; the specification and pinned
  machine contracts define the same behaviour normatively and are aligned to
  it. Reference implementations are implementation material, not an immutable
  version authority.
- Before proposing acceptance changes or resolving an unspecified edge case,
  follow [Semantic decision criteria](docs/design/semantic-decisions.md).
  Separate existing requirements, conflicting evidence and new decisions. Do
  not turn a reference implementation limitation or a lint preference into a
  language restriction. When the user delegates specification decisions, resolve
  ambiguities using these criteria, document the rationale and compatibility
  impact, and proceed with the recommended contract. Otherwise obtain agreement
  before changing the contract. Delegation does not expand implementation scope
  or authorize destructive/external actions.
- Owned specifications, machine contracts and identity domains use the current
  initial 0.1 baseline, including AoA contracts (`/0.1`) and versioned AoA law
  identifiers (`.v0.1`). Follow each contract's declared identifier syntax;
  do not import a different version merely because reference code uses it.
- Where an identifier is part of a canonical preimage, update dependent bodies,
  CIDs, schema pins, metadata and independent fixtures together, and retain
  `check:spec` and three-target MoonBit CI coverage. Never retain an old
  CID for a renamed body or compute expected fixtures from product output.
- Package release versions are independent of contract versions. External
  standards, dependencies and toolchains retain their selected versions and
  pins. See [Versioning policy](docs/design/versioning.md).
- During the `v0.0.x` product release series, remove superseded implementations
  in the change that replaces them. Follow the
  [replacement policy](docs/design/versioning.md#replacement-policy-during-v00x)
  for readers, writers, adapters, compatibility shims, fallbacks and their
  build and test wiring. List the removed paths and their replacements in the
  pull request description.
- Future version changes require an explicit decision and coordinated updates
  to the applicable checks. Do not rewrite published history without explicit approval.

## Local verification

Before selecting local test/build commands, read
[the local verification skill](.agents/skills/actql-local-verification/SKILL.md).
Open that file directly if the client does not discover repository skills.

- Default to focused MoonBit tests on the JS backend for the affected core
  packages, and targeted Node tests for SDK, adapters and scripts. Native-only
  or FFI changes need an explicitly selected matching-target diagnostic.
- Do not default to full Core, all-target, proof, packed acceptance or performance
  suites. Public-repository PRs run applicable hosted checks. Main integration
  runs every six hours and can be started manually. Local and PR
  review establish only the checks actually executed. Draft checks are
  preparation only and never establish merge
  or release evidence.
- Use the existing bounded/nonzero-test wrappers. Preserve incremental `_build`;
  do not edit, merge or switch a worktree while its gate runs, or run competing
  gates there. `--allow-heavy` is not human approval.
- Report executed checks and unverified coverage separately. Read the CI result
  for the exact submitted SHA when publication is part of the requested task.

Runtime builds, tarballs and reviewed generated artifacts follow
[Runtime package artifacts](docs/development.md#runtime-package-artifacts).

## Pull request CI use

Hosted CI selects a verification profile from the pull request's changes.
Each push to a Ready pull request runs the required checks for that profile.
Draft runs preparation and any selected targeted acceptance, such as Python
package checks. Additional checks can fail after marking the pull request
Ready. A later push can supersede a full run after it has already used
shared Linux and macOS runners.

- Open a pull request as Draft. Mark it Ready when the change is complete and
  the applicable local and Draft checks pass.
- When Ready CI needs a fix, convert the pull request to Draft before pushing
  it. The conversion cancels the in-progress CI run for that pull request.
  Mark it Ready again after the applicable local and Draft checks pass.
- Batch related fixes, review responses and necessary updates from main.
  While Ready, push only updates needed for integration.
- Do not push an empty commit or merge main only to start a run.

## Maintainable regression tests

- Exercise actual imported functions or public entry points. Do not reconstruct
  private production functions with source slicing and `eval`/`Function`.
- Assert results, refusal causes, authorization, ownership, resource accounting
  and cleanup. Helper names, unrelated source bytes, test grouping and historical
  command counts are not behavioral contracts.
- Define test and build recipes once. Check required coverage and prerequisite
  behavior instead of duplicating complete command strings in assertions.
- Keep independent expected values and canonical protocol, CID, ABI and artifact
  identity checks. A source-shape restriction needs a specific safety or machine
  contract; it must not freeze unrelated code.
- Remove migration-only snapshots after the current behavior has its own
  regression coverage. Do not maintain tests whose only assertion is that other
  tests or fixtures have not changed since an old implementation.
