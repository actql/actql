# Engine MoonBit ownership migration

Date: 2026-09-19. Branch: `feat/engine-remote-site-completion`.

This ledger records product decision owners while the Engine milestone moves
common control out of handwritten environment code. It is not a completion
report. A row is complete only when every product caller uses the MoonBit
owner and the superseded decision implementation has been removed.

| Boundary | Product owner | Adapter responsibility | Current removal condition |
| --- | --- | --- | --- |
| Publication contract identity and admission | `run_publication` | Persist and retrieve admitted wire | Complete for current publication callers; the independent JavaScript fixture remains test-only. |
| Publication and delivery progression | `run_publication` | Perform bounded Store, clock, and sink operations | Product callers use MoonBit actions; continue auditing failure and cleanup branches as native publication is connected. |
| Durable Result row framing | `run_publication` | Supply bounded byte chunks and await emitted rows | Formal publication delivery uses the MoonBit parser. Remove `store-local/row-frames.mjs` after Local import, DuckDB import, and retained examples use the same owner. |
| Execution Site and Transfer lifecycle | `execution_site` and `remote_transfer` | Stream bytes, observe stop, persist exact transitions | Remote paths use MoonBit transitions. The in-process Host orchestration audit remains open. |
| Remote dispatch and reconciliation | `remote_site_protocol` | HTTPS and SQLite physical operations | Current Node and native integration slices use the portable owner. The full native standard Host and separated-network profile remain open. |
| Runtime bundle lifecycle | `remote_bundle` | Verify signatures, install bytes, synchronize files, and persist transitions | Product dispatch is bound to the active bundle. Native bundle operations and the separated-network update profile remain open. |
| Credential use | `remote_credential` | Resolve and apply a secret within a scoped HTTP operation | Node integration is connected. Native standard-Host credential use remains open. |
| Local and DuckDB task progression | common Host and Connector packages | Native evaluation, database calls, cancellation delivery, and stop observation | Handwritten Node orchestration still contains migration targets. Node-free Local and bounded native DuckDB execution remain open. |

The JavaScript retained-row parser is not a second authority for formal
publication after this change. It remains a temporary product implementation
for the explicitly listed import paths. Its tests stay as independent physical
fixtures; they are not used to validate a second publication state machine.
