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

- The specification and pinned machine contracts are authoritative. Reference
  implementations are implementation material, not an immutable version authority.
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
  suites. Manual integration CI retains full verification; local and PR results
  establish only the checks actually executed. Draft CI is preparation only; its
  final check remains incomplete until Ready triggers normal required coverage.
- Use the existing bounded/nonzero-test wrappers. Preserve incremental `_build`;
  do not edit, merge or switch a worktree while its gate runs, or run competing
  gates there. `--allow-heavy` is not human approval.
- Report executed checks and unverified coverage separately. Read the CI result
  for the exact submitted SHA when publication is part of the requested task.

Runtime builds, tarballs and reviewed generated artifacts follow
[Runtime package artifacts](docs/development.md#runtime-package-artifacts).
