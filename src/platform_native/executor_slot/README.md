# Original scoped process stop

The opt-in scoped holder extends this existing executor-slot Owner. Preparation
requires an already-held original Slot and captures a separate open description
of that exact inode. This anchor pins identity without keeping the inherited
holder lock alive in the parent. Refused preparation retains the same carrier
for partial cleanup; the original pre-spawn Slot remains independently owned.

Bind the opaque holder into the existing original region/child record before
its one spawn attempt. `require_prepared` checks unattempted preparation; it is
neither launch permission nor a resource grant. `child` and `channel` return
only the actual original aliases. A failed spawn result must not be interpreted
as not-started: an unconfirmed parent descriptor close can retain an actual
child. No PID, wire, equal file metadata or caller Boolean constructs a holder
or a scoped-stop observation.

`poll_stop` is nonblocking. It needs the original child's actual `waitpid`
observation, confirmed cleanup of its own Channel descriptors, and reacquisition
of the original inode lock after inherited descendants relinquish it. The
returned opaque stop keeps that lock and inode pin. `require_current(expected)`
requires the holder captured by the region Owner before spawn, the same original
child/Channel, and the still-current pin. Another holder is refused even if a
path or observed PID happens to match. Observed pathname replacement is sticky.

The existing physical region Owner must separately retire all its mappings,
views, FD borrowers and original lease under its own contract. A scoped stop is
not that cleanup ACK, a Store ACK, or an authorization decision. Only after that
physical cleanup ACK may it call `stop.close`. An unconfirmed consumed close
retains the same carrier, never retries a raw descriptor and never acknowledges
composite cleanup. `holder.cleanup` does not kill a child or release a live stop
pin. It handles unstarted/failed preparation and records completion only after
an explicitly closed stop.

The holder, anchor, stop and their actual code-root references belong to the
parent/control lifetime and must be outside an exclusive child mapping that
the observation can retire. The caller must fund that actual holding through
its existing parent Owner; these APIs issue no Ledger, profile or capacity.
They are synchronous, thread-confined to the preparing control thread and have
no user callbacks. Foreign-thread operations refuse; aliases must not be used
concurrently or transferred to another runtime. Best-effort finalizers are not
cleanup acknowledgements. The old spawn/wait APIs and their result semantics
remain unchanged.
