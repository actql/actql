# Managed fixed-input demand boundary

The fixed DuckDB adapter can now bind its existing consumer demand laws to a
`ManagedOutputValueReceipt`, without constructing the old CID-bearing stream
receipt. This removes an integration dependency on output row-array encoding;
it does not remove the demand obligation or attest execution.

`ManagedFixedComputeDemand` binds the exact compiled Compute, receiving owner,
output target, managed receipt and value ceiling. Input availability is checked
when measuring and when matching the resulting evidence. A receipt from another
bound invocation is rejected, even if its schema and values agree. A new output
receipt cannot use the evidence for an earlier receipt.

Both modes use the existing demand implementation:

- In-memory fixed input can be measured through the existing comparison laws.
- A retained input's already accumulated `FixedImportDemand` can be consumed
  once, without replaying the input scan. Its exact Compute, limits, verified
  input scan and liveness remain mandatory. Failed demand is not relabelled as
  a reusable success.

The integration tests use checked owners and admitted managed physical output.
They independently assert two input rows, one true and one false comparison,
the exact seven-work/three-byte/three-node usage, nine logical predicate bytes,
and the same five-byte ceiling success/four-byte rejection as the old receipt
path. They also check foreign owner, Compute, receipt, ceiling and input
revocation. A separate retained Acquisition fixture feeds the real fixed import
accumulator and checks its one-use consumption into managed demand.

This is demand evidence only. It does not prove that DuckDB produced the given
output, that the Store retained it, or that publication is authorized. The
installed attempt must bind its actual receiver and transport, input/output
measurement, selected obligations and retained material before calling managed
completion. No production dispatch selects this new path yet; no new-profile
performance result is claimed. The next integration is that installed attempt,
not a callback that accepts a content receipt as execution proof.

Verification: all 273 `query_integration` tests passed on each of JS, Wasm and
native, including both new demand cases. Full documentation/contract checks,
cross-target interface generation, formatting and whitespace checks passed.
