# Selected DuckDB to common managed completion

The installed Node facade now connects selected Compute output to the common
`ManagedCompletedOutput` boundary. It distinguishes a value-only receiver from
an actual selected-attempt receiver; only the latter can issue this completion.
Neither is returned as an old `CompletedOutput` or CID-bearing Artifact.

Before receiving output, the Host installs `ManagedDuckDBCompletion` for the
exact attempt, checked completion preparation, final target and complete input
bindings. It supplies an admitted managed-profile handle and an installed
authorization check. That check must cover the selected use/identity obligations
and applicable resource admission/settlement, at the relevant phase. It cannot
replace the connector's transport, join, demand, measurement or material checks.
It is not a Program-controlled callback or a generic `validated` field.

The Node receiver passes actual typed transport columns into the managed attempt,
uses its remaining input/output budget, and installs Store retention before the
first row. After transport settlement and retaining the exact output, the
connector verifies demand and the material binding. Common completion then
checks owner, target, schema, inputs and liveness. The connector additionally
checks authorization and attempt/material state after callback execution.
Issuance is consumed once; a failed completion cannot be retried by changing
policy back. Another successful completion cannot reuse the same attempt.

The completed value carries independent Store lifetime, not a requirement to
keep revalidating the closed native session or upstream contents. Explicit
managed-output cancellation invalidates its Node holding; physical cleanup is a
separate awaited Store operation. This does not grant a downstream pin or read
authorization merely from the completion handle.

## Actual native integration exercised

`managed-compute-host.test.mjs` executes product `runFixedCompute` with SQL and
parameters from the installed MoonBit Host, the pinned bounded native transport,
and the product `matchesFixedCompute` session binding. The conformance fixture
supplies checked setup and admits the complete registered profile body; it does
not substitute a successful execution verifier.

The fixture exercises populated and empty filter/project results, including
NULL, Unicode and duplicate occurrences. It writes bounded physical transport
frames into the real Store and seals a physical digest, without creating a
logical output row-array CID. Those frames are **fixture-only storage**, not a
newly registered codec or public Artifact format. Expected output values are
literal independent expectations.

Successful native settlement, typed receipt, independent holding and admitted
read-only policy reach common managed completion. The fixture also checks:

- a false initial Host policy rejects preparation;
- a retained value alone is not verified execution;
- releasing transport evidence before verification rejects it;
- policy revocation before completion rejects issuance and later revival;
- legacy completion cannot consume managed output;
- another attempt's completion port cannot consume the output or revoke its
  actual attempt merely by presenting equal configuration;
- a value-only retained receiver cannot claim selected Compute verification;
- repeated completion fails without invalidating the first successful output;
- a sealed independent output survives release of the native session evidence;
- cancellation invalidates the logical holding before physical reclamation;
- awaited cleanup leaves no pending cleanup or reserved bytes.

## Not yet delivered

This is a real native-to-common-completion integration, but not full managed
execution acceptance. The test Host explicitly adopts read-only obligations.
Production requirement derivation/issuer adoption, the strategy DAG dispatcher,
managed downstream consumers, named Result publication, a registered physical
codec and accepted process delegation must still connect to this boundary.
Local and finite filter/sort/take/derive evidence-transfer paths also remain.
No new-profile performance ratio or completion of the registered performance
gates is claimed. Existing default entries and mandatory-CID contracts remain
unchanged.

Verification passed: 275 query-integration tests on each of JS, Wasm and native;
the real managed Compute integration, five managed-manifest/retention tests and
the existing standard Host integration; cross-target API consistency; full
documentation/contracts; formatting and whitespace checks. The last two new
negative cases were rerun with all six managed Node tests passing.
