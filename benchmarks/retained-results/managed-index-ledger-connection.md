# Managed measurement index ledger connection

The fixed-capacity managed row-measurement index is now connected to the
existing physical task ledger for the managed retained DuckDB strategy entry.
It does not create a second attempt or a metadata-only ledger. The selected
task reserves its ordinary streamed completion capacity, file ceiling and
fixed index ceiling atomically before execution starts.

The index remains a distinct physical allocation from the retained file. When
the exact configured cell ceiling is enabled, the Host converts only the
index's capacity from the task reservation into a `TaskRetainedAllocation`.
That token grants no completion, publication, identity or read authority. The
managed output owns it and releases it when that output is revoked, after
clearing the retained index. File availability and index reclamation are not
substituted for one another.

For the checked four-cell fixture the index ceiling is:

```text
512-byte fixed owner/header + 4 * 64-byte cells = 768 bytes
```

The real Node/DuckDB strategy regression checks these ledger transitions:

| boundary | attempts | index held bytes | reserved retention |
| --- | ---: | ---: | ---: |
| managed retained open | 1 | 0 | stream base + 100,000-byte file ceiling + 768 |
| mismatched three-cell enable | 1 | 0 | unchanged |
| exact four-cell enable | 1 | 768 | stream base + 100,000 |
| managed output cancel | 1 | 0 | stream base + 100,000 |
| task close after settlement | 1 | 0 | 0 |

The same run executes the actual selected DuckDB query, receives its output
through the managed value path, seals a two-cell receipt and verifies that the
index reports two populated cells. The rejected ceiling does not allocate and
the exact allocation is not released by native settlement alone.

This closes the retained index's reservation/holding boundary. It does **not**
yet account for selection occurrence arrays, copied summaries, permutation
maps or copy-overlap scratch, and it does not switch the production standard
strategy entry to the new managed completion profile. Those remain separate
frontiers. Existing logical measurements, consumer charges, CID definitions
and legacy result contracts are unchanged.

Verification for this increment includes the full standard Node Host/DuckDB
integration test, strict cross-package checks and the existing index capacity
tests. The integration fixture is a lifecycle/accounting regression, not a
performance benchmark; the registered 27-case and 1 GiB performance gates
remain required for final acceptance.
