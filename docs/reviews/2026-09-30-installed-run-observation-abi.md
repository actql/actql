# Installed Run observation ABI follow-up

Terminology note (2026-09-30): “ABI” in this historical title and report
refers to the internal MoonBit-to-JS bridge, not a native binary ABI or a
change to the public wire format. The original wording is retained.

The common Run-state issuer already distinguishes a live operation, a
confirmed terminal outcome, and an unobserved physical start. The installed
Host now supplies those facts through named internal arguments. Its control
observation uses the same pattern, including the journal revision, cancellation
request, confirmed pre-dispatch failure, and confirmed physical close.

`client_run_control_observation` previously returned `None` for every
`RunStateIssue`. It now raises `ClientProgramRunStateIssue::Projection` with
the original issue. The installed adapter keeps the existing
`InvalidRunControl` failure identity and retains the typed issue as its
internal primary cause. An absent or malformed runtime result also remains a
failure; it is never treated as a missing Run. Authorization and the journal
revision recheck still happen before the control observation is returned.

The selected MoonBit bridge is the source. Its RelA sibling and both public
interfaces are regenerated from that source. A real generated ABI test forces
an invalid revision, while the internal adapter tests verify the argument
order, error identity, and retained cause. The existing SQLite cancellation
and restart tests exercise the successful control observation.

This completes the named installed Run-state arguments and the H1 control
projection error noted in the H1–H3 audit. H3 still has targeted publication
contract role distinctions and lifecycle action translation. Acquisition
recovery ownership is submitted separately in PR #73.
