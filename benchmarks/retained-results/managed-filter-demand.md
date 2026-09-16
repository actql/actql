# Managed scalar-comparison demand

The managed-input completion connection now supports the existing compiler's
FilterSelect as well as CountGroup. This does not expand the compiler's supported
operators/types: the live fixture uses numeric `n > 1`, not an unimplemented
text comparison or arbitrary predicate.

Initial managed output measurement records per-column NULL counts alongside
byte/node subtotals and maxima, in the same value pass. Exact checked receiving
projection/rename/copy maps these facts to the requested column. The returned
record is informational: the demand rule fetches it through its owned input and
does not accept caller-supplied statistics as proof. Revoked inputs expose none.

For this finite eager comparison law, operand byte totals and NULL counts plus
the actual SQL true-row count determine logical demand. The rule measures the
RHS once for nonempty input; empty input does not demand the RHS. It reuses the
field's exact measured bytes, and does not decode or encode that column again.
Physical demand-measurement counters charge metadata/RHS work actually performed;
the consumer's logical input/output ledger remains separately charged.

Insufficient maxima/depth evidence returns `InputRepresentationRequired`, not a
fabricated first failing row. Production ordered fallback still needs integration.
False/true/NULL predicate size guards remain unchanged. Demand is consumed once
against an exactly bound receipt, after the installed execution verifier checks
the native operation. The connector preserves a demand failure as a typed demand
cause rather than collapsing it into generic unverified completion.

## Execution evidence and remaining work

The actual native path is fixed-input Compute → managed count →
managed numeric filter → common completion. The count input is independently
retained after the original material is physically reclaimed. Literal expected
counts and rows distinguish true (`3 > 1`) from false (`0 > 1`). With a four-byte
value ceiling, true succeeds while false rejects even though its output is empty.
The byte/node/NULL summaries are also checked for Unicode, NULL, duplicate and
empty source data; Core tests cover checked column reorder/copy and revocation.

The numeric fixture stores a second, native-number column view of its single
count row in the same physical frame, produced from the same native value. This
is a fixture-only codec, not a newly registered portable representation. Native
file reading is physical IO; the improvement claimed here is no repeated input
value admission/field canonical measurement, not zero IO.

Filter output still receives initial full value admission. This increment does
not yet transfer unchanged output-value evidence through selection, nor complete
take/sort/derive, Local, production requirement/representation/dispatch or managed
delegation integration. It is not the full new-profile performance result.

Verification: 427 execution-relation and 275 query-integration tests passed on
each of JS, Wasm and native; six native/manifest tests passed. Cross-target API,
documentation/contract, format and whitespace checks passed. No identity preimage,
normative profile body or pin was changed by these internal measured facts.
