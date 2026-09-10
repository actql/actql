# Repository conventions

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
  CIDs, schema pins, metadata and independent fixtures together, then run
  `npm run check:docs` and the three-target MoonBit checks. Never retain an old
  CID for a renamed body or compute expected fixtures from product output.
- Package release versions are independent of contract versions. External
  standards, dependencies and toolchains retain their selected versions and
  pins. See [Versioning policy](docs/design/versioning.md).
- Future version changes require an explicit decision and coordinated updates
  to the applicable checks. Do not rewrite published history without explicit approval.
