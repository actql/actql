# Pipeline contextual order resolution

`pipeline_typing.resolve_contextual_orders` atomically visits all checked steps,
including named branches not selected by the final current. The opaque result
retains the original pipeline and per-step order resolutions. Accessors return
detached arrays; a caller cannot construct a successful result for a subset.

The boundary invokes existing operation-specific rules rather than treating all
ordering requirements as interchangeable:

- Nonempty sort and top-k complete candidate keys; empty sort adds no requirement.
- Take requires its preselection sequence, including its permitted key completion.
- Lag requires key completion, not just inherited input order.
- Position-sensitive analytic calls require position completion; rank-only calls
  do not acquire a new position requirement.
- Prefix watermark and pivot(first) use their actual input sequence, never their
  own output order or an inserted sort.
- Every ordered aggregate and nest child order is resolved with the existing
  aggregate/child-specific rules.

Step count, work and name-byte budgets are inclusive. Every visited step costs
one work unit; analytic pending entries also cost one each. Group and nest
resolvers consume the remaining shared work/text budgets, not a fresh allowance.
Key/sequence resolutions already computed during pipeline checking retain their
existing evidence without rebuilding it. Any failure returns no partial result.

These are conditional static resolutions, not observed execution evidence or an
executable plan. Runtime uniqueness, tie checks, pattern/profile obligations,
capacity closure and enforcement remain in the original pipeline. Result
publication order is checked separately by `resolve_publication_orders`.
External input order admission and the combined all-obligation discharge boundary
remain unfinished. This API does not declare every pending obligation satisfied.
