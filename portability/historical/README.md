# Historical Graph fixtures (not executable compatibility)

These `.txt` files preserve the previous tuple-profile fixtures and coverage
claims. They are evidence at their original source, not MoonBit inputs or a
fallback that accepts old Graph bodies or snapshot profiles.

- `graph-expression-scope-pre-property-graph.mbt.txt`: original scope fixture
  before the definition-selected MATCH migration, source `446d9cc84500122db08b8a1504c99219717dfe8d`.
- `local-family-coverage-pre-property-graph.json.txt`: original coverage
  inventory, source `5b317a6ee111e5b4ea3694e3db7da9d2042a4160`. Its tuple-profile
  completion claims are not valid for the new Graph representation.
- `graph-typing-*-pre-property-graph.mbt.txt`: seventeen original typing
  fixture files, source `adaa9832e`. Each archived file was compared byte for
  byte with `git show` before the retirement commit. Twelve unsupported
  tuple-consumer test files are no longer executable; five supported fixture
  files are replaced with current typed identities, scoped predicates,
  explicit TRAIL and independent path identity contracts.
- `managed-graph-runtime-output-pre-property-graph.mbt.txt`: the original
  tuple retention/consumer fixtures, source
  `bf02dc660463bcb72bf8f171a9a408020f442b2b`. All seven lifecycle obligations
  remain executable on the current profile: independent typed identities,
  exact consumer/owner bindings, source revocation, atomic failure and final
  reclamation. These internal port tests do not claim public snapshot I/O.

The current typing package checks unsupported consumers as typed refusals,
and tests the supported subset's exact/one-short budgets, repeated identity
occurrences, qualified Relation selection, projection order, copied indexed
reads and diagnostic locations. It does not claim that old consumer algorithms
are connected to the new Graph. Resource/cancellation, configured-Store public
snapshot and aggregate Core acceptance remain separately required.

- `managed-graph-storage-pre-property-graph.mbt.txt`: original five tuple
  storage fixtures from `d1d7c9abf57ef1ac08817279ac0dd161890e88ac`. All five
  obligations have current executable counterparts: parallel keyed edges,
  admitted indexed lookup and revocation, refusal of endpoint synthesis,
  atomic key/capacity/work/cancellation boundaries, and independently counted
  UTF-8 byte limits. Duplicate nodes now reject even identical content.
- `bounded-graph-diff-pre-property-graph.mbt.txt`: original three tuple delta
  tests from the same checkpoint. The endpoint-tuple delta implementation is
  withdrawn rather than reinterpreted as independent-key Graph semantics.
  Current executable tests require typed refusal before snapshot allocation;
  they do not claim delta support or its old capacity/completion guarantees.

- `lowering-graph-*-pre-property-graph.mbt.txt` and
  `lowering-carrier-projection-pre-property-graph.mbt.txt`: eleven original
  files from `ff364752f462185fb1c41d32cb82b2f438a9e10e`, verified byte-for-byte
  against the committed originals. Current executable MATCH and TRAIL tests
  retain definition-scoped identities, ordered/repeated selectors, predicates,
  copied indexed views and finite preparation limits. The current constructor
  preserves repeated producer roles, an independent edge key, shared endpoint
  roles and finite preparation without tuple expansion. Mixed Vectors tests
  remain executable. Twenty positive tests for unsupported Graph algorithms
  are historical only: current executable regressions require typed refusal
  for thirteen structural/query operations and both unconnected projections,
  not successful execution or their former completion/capacity claims.
