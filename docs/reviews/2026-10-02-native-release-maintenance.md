# Recover a settled dispatch after a native binary upgrade

The ordinary executor still requires its inherited exclusive slot and an
exact match between its physical binary and the installed active component.
Cleanup does not execute that component. Requiring the maintenance binary
itself to match an old component prevented an upgraded operator from
discharging the original holder's saved runtime holdings.

`native_remote_resident_site recover-release --attempt ATTEMPT_CID
--expect-dispatch DISPATCH_CID`, with the original Site's global configuration,
selects only the saved dispatch. It does not poll, compile materials, create
an attempt, claim a start, or replay Output. The caller must retain the old
Site generation, bundle identity, delegation, journal, publication Store and
credential. Use the original configured physical paths, not a new empty Store.

The command checks exact dispatch identity and current delegation, obtains
the exclusive physical slot, opens the trusted installed bundle and original
journal, and refuses pending Output intents or an unacknowledged report for
that dispatch. It confirms zero Store reservations and successful Store close
before discharging the exact dispatch and durable holder holdings. Only then
does the existing cleanup owner select and persist its existing transitions.
There is no resource-zero-only transition or journal rewrite.

The resulting observation is sent through the existing authenticated status
operation. An unknown or rejected response leaves the durable Site state
available for an explicit repeat. Repeating recovery must preserve the
terminal revision, executor entry count and cleared holdings. A successful
HTTP observation does not replace inspection of the Cloud's durable owner.

The maintenance regression starts from NativeSettled/CleanupActive with two
saved holdings, after real execution and Output delivery. A different binary
recovers that exact journal; a foreign dispatch is refused and the direct
operator cannot enter execution without an inherited slot. Repeated recovery
confirms Released, unchanged revision, one executor entry, no pending intents,
no reserved payload bytes and no remaining bundle holdings. The existing
release-failure, lost reply, holder-exit and interrupted-recovery cases remain.

This is recovery acceptance, separate from the new-Run normal release path.
The historical Preview Run is not claimed recovered by these local tests.
Other failed Runs retain their independent evidence and cleanup obligations
in Cloud issue #88. No new recovery ledger, state name, forced generation
change or execution authorization is introduced.
