# Managed output verification on selected DuckDB attempts

The connector now has `ManagedDuckDBComputeOutput`, an output mode of an actual
selected `DuckDBComputeAttempt`. It reuses the candidate binding, input admission,
join validation and installed transport verifier of that attempt. It does not
create a second permissive Compute implementation.

Beginning managed output requires complete input measurement and valid join
evidence. It consumes the same remaining input/output measurement ledger and
uses the selected row ceiling, value ceiling, physical limits and typed output
schema. The output mode is claimed once. Old in-memory and CID-bearing streamed
output cannot begin on that attempt, nor can legacy completion consume it.

Output chunks produce a `ManagedOutputValueReceipt` without row-array encoding
or a logical content CID. That receipt alone remains provisional. After actual
transport settlement, verification checks the attempt, input/output measurement,
join evidence and consumer demand. Demand uses the existing laws and, when
present, the exact one-use accumulated input demand. Failed verification closes
the attempt rather than resetting its budget or changing backend.

`verified_managed_duckdb_compute_material` additionally checks the exact retained
receipt and current material availability. It returns no evidence before output
verification, after transport revocation, after upstream loss before completion,
or after cancellation. The Store retention port is installed on the precise
output-admission stream before receiving rows. Storage verification remains
trusted installed Host wiring, not a path/digest comparison.

## Integration boundary still open

This increment supplies the selected attempt's finite verifier, not a complete
managed Run. The Host must still admit the profile and identity/publication
requirements, connect the actual native transport and Store, use this verifier
in the common managed completion boundary, and dispatch downstream managed
consumers. The old default remains unchanged. No requested logical identity is
waived by selecting this low-level receiver; selecting it without satisfying the
admitted identity obligations is not profile conformance.

The integration tests use real checked owners and selected attempts, but an
installed test transport and retention callback. They are not a live DuckDB
managed-profile benchmark. They check successful provisional verification,
unsettled transport, consumer predicate-size rejection, upstream and material
revocation, exclusive output modes, cancellation, malformed values, and shared
input-plus-output budget exhaustion. No new-profile performance claim is made.

Verification passed: all 275 `query_integration` tests on JS, Wasm and native;
the installed Node Host deny-warning check; cross-target public interfaces;
full documentation/contract checks; formatting and whitespace checks.
