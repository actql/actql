# Managed identity-state checkpoint

Date: 2026-09-17.

This checkpoint connects the managed profile's identity obligations to the
common completion object. It implements the diagnostic distinction already
pinned by `actql-managed-retained-execution/0.1`; it does not change a logical
CID preimage or the existing CID-bearing Artifact contracts.

## Runtime state

Each admitted identity subject and domain now has one of four states:

| Identity | Source | Runtime state |
| --- | --- | --- |
| Not established | Retained | A scoped late request may be admitted |
| Not established | Unavailable | A late request is rejected |
| Established | Retained | CID and exact source are both available |
| Established | Unavailable | CID remains recorded; data is not readable |

The source state is derived from the exact completed material's current
availability. It is not a caller-supplied boolean. The standard managed task
path records `ordered_rows` for `task_output` as unestablished with its source
retained. The real standard Host regression observes that state after common
completion.

Managed DuckDB queries also retain the exact Host-derived obligation object
from their receiving request. Compilation cannot replace it with a default or
remove an identity deadline. A CID-dependent request is still excluded before
candidate comparison because the installed DuckDB candidate does not yet
provide that deadline capability.

## Delayed establishment boundary

Delayed establishment is accepted only through the verifier installed on the
exact completion port. The verifier receives the domain, subject, canonical
contract CID, proposed logical CID and exact retained material. The common
layer checks both CID syntax and source availability before and after the
verifier call. It refuses unknown subjects, unavailable sources, absent
issuers and conflicting second identities.

An establishment failure does not revoke the previously valid managed
completion. Once an identity is established, loss of the source changes only
the source dimension; it does not erase or fabricate the CID. An unestablished
identity whose source is lost cannot be established later.

The independent fixture covers successful delayed establishment, malformed
and conflicting CIDs, an absent issuer, and source loss before and after
establishment. This proves the common state machine and scoped issuer boundary.
It is not evidence that the standard DuckDB product path currently computes a
logical CID on demand. That connector remains CID-free and is rejected when a
known consumer or publication requires logical identity.

## Verification

- `execution_relation`: 458/458 JS tests passed at this checkpoint.
- The real standard DuckDB Host regression passed and observed an explicit
  unestablished/retained task-output identity.
- Public interfaces were regenerated with the pinned MoonBit toolchain.

Native and Wasm package tests, the full Node suite and documentation gates are
run at the integration checkpoint; this document does not claim those broader
gates from the focused runs above.
