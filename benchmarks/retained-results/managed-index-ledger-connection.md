# Managed body and measurement-index ledger connection

The retained body and fixed-capacity managed row-measurement index are now
connected to the existing physical task ledger for the managed retained DuckDB
strategy entry. They do not create a second attempt or a metadata-only ledger.
The selected task reserves its ordinary streamed completion capacity, file
ceiling and fixed index ceiling atomically before execution starts.

The index remains a distinct physical allocation from the retained file. When
the exact configured cell ceiling is enabled, the Host converts only the
index's capacity from the task reservation into a `TaskRetainedAllocation`.
After the installed Store has sealed the exact managed body, its actual byte
count is converted from the separately admitted file ceiling into another
allocation before managed material is issued. These tokens grant no
completion, publication, identity or read authority. The managed output owns
and releases both when that output is revoked, clearing the retained index
first. Store availability and ledger ownership are both required and are not
substituted for one another.

For the checked four-cell fixture the index ceiling is:

```text
512-byte fixed owner/header + 4 * 64-byte cells = 768 bytes
```

The real Node/DuckDB strategy regression checks these ledger transitions:

The ledger fixture supplies a 321-byte retained-body proof through the
installed Store boundary so both transitions remain visible:

| boundary | attempts | held bytes | reserved retention |
| --- | ---: | ---: | ---: |
| managed retained open | 1 | 0 | stream base + 100,000-byte file ceiling + 768 |
| mismatched three-cell enable | 1 | 0 | unchanged |
| exact four-cell enable | 1 | 768 | stream base + 100,000 |
| rejected 100,001-byte body | 1 | 768 | unchanged |
| sealed body retained | 1 | 768 + 321 | stream base + 100,000 - 321 |
| native execution settled | 1 | 768 + 321 | unchanged |
| managed output cancel | 1 | 0 | stream base + 100,000 - 321 |
| task close after settlement | 1 | 0 | 0 |

The same run executes the actual selected DuckDB query, receives its output
through the managed value path, seals a two-cell receipt and verifies that the
index reports two populated cells. The rejected ceiling does not allocate and
the separately admitted 100,000-byte file ceiling cannot borrow the stream
base to accept a 100,001-byte body. Neither exact allocation is released by
native settlement alone.

This closes the managed body's and retained index's reservation/holding
boundaries before graph publication. Ownership transfer into production
managed graph completion is still pending. This does **not**
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
