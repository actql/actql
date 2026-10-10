# Native Effect review delivery custody

The existing Site journal retains the original canonical Checkpoint report before
HTTP. An initial insertion requires the original admitted consumer's NativeSettled
observation, active cleanup responsibility and no saved cancellation. That check,
the exact current Site binding and report insertion share the existing SQLite
mutation. Failed or uncertain persistence does not permit sending. A conflicting
second review for the same consumer dispatch is rejected.

Reopening reads the saved original report without rebuilding Run materials,
refreshing expiry, selecting another attempt or executing Source/Compute. A saved
report remains reconciliation responsibility after cancellation or cleanup; it is
not permission to approve or restart work. Replay is fenced by the current durable
Site binding. Generation changes cannot send the old report.

The Native HTTP adapter sends only a retained report and requires a typed reply
bound to its report, dispatch and Checkpoint CIDs with the corresponding HTTP
status. It saves that reply before returning acceptance. Transport errors, bare
2xx responses, wrong replies and ACK-save failure cannot discharge responsibility.
An already saved ACK causes no additional send. Refusal remains a fixed, non-secret
attention result. This receipt changes no execution, Ledger, borrow or cleanup
state, and does not authorize retiring private continuation custody.

This follows #1208, with main as the final merge destination after the published
parents. Cloud report admission/waiting commit, the resident CLI call site and
formal package/binary adoption are still separate connections. This change does
not claim a public SDK waiting/approval or a complete Effect execution/recovery.
Protocol-authored journal fixtures are distinguished from #1208's genuine Native
Provider/Checkpoint Store fixture; neither substitutes for public Cloud acceptance.

The existing Native HTTP fixture composes a small authenticated HTTPS peer for
this boundary. The focused case uses real curl/SQLite and checks missing retained
report (zero sends), malformed 200, a foreign ACK, connection loss, ACK-save
failure, reopen/replay and no send after saved acceptance. The peer is a
protocol-authored fixture, not a substitute for Cloud waiting commit.
