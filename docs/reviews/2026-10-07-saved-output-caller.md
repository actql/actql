# Saved Output caller recovery

A completed two-task consumer can lose its holder after the original payload
was sealed and sent, before its first Output report became durable. This caller
continues that original Output; it does not execute either task again.

`prepare_resident_saved_output` selects the saved dispatch envelope and original
Run materials, checks the checked consumer task and configured Source, and
restores the common completed-custody projection from the existing observation.
It reads the reserved Output and the exact pending payload intent. Dispatch,
attempt, task, Run, result definition and Coordinator must agree. Current Site,
generation, delegation, lifetime, cancellation and exclusive ownership are
rechecked through trusted ports. Missing custody is refused.

`ResidentSavedOutput.recover` verifies the existing sealed publication payload
and selects the existing Transfer through the portable Output plan Owner. It
queries only that Transfer's destination and stops the actual payload reader;
it never reads, uploads or commits payload bytes. It uses the original committed
record to issue the first report, then saves report custody before any report
can be sent. Existing reports are reused without another Transfer query. Failed
query, current-scope check or save retains the original payload/intent; a failed
physical reader close retains the existing Transfer cleanup owner.

`recover-output --attempt <original-attempt> --expect-dispatch <dispatch-cid>
--intent-cid <original-output-intent-cid>` connects this continuation to the
normal Site configuration, authenticated HTTP clients and typed ACK persistence.
It holds the actual executor slot and reuses the existing stopped-holder
maintenance owner to verify the saved signed component and current active
bundle/Connector scope. It performs one bounded query and
one report exchange. A successful ACK is not formal release: original payload,
producer holding, receiver holding and borrow cleanup remain separate duties.
Owner-close failures and the primary failure are reported independently.

The maintenance tool does not claim the original executable identity, acquire
an execution component or a runtime holding. The saved signed component remains
the execution identity; a changed active bundle or scope refuses Output recovery.
Original materials must admit without reinterpreting old Graph/contract identity.
This change does not invent an old missing consumer output-file record.

The added Native consumer assertions use actual acquisition, retained Transfer,
Compute and SQLite observations. They cover missing Output custody, lost slot,
foreign attempt, Source, authority, generation and expired materials without
additional executor entry, journal revision or Output intent. They are refusal
coverage, not a successful historical recovery or public Client acceptance.
The metadata test separately rejects mismatched attempt/dispatch and malformed
payload intents. Full query-to-report-to-ACK recovery, old-Run publication/release,
new five-package/Native adoption and Preview acceptance remain to be established
with matching merged source and artifacts. The original failed Run's databases,
sealed payload, pending intent and logs remain protected.
