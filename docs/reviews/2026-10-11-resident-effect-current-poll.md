# Resident Effect current-query poll routing

The current-query Owner supplies the original dispatch and exact fresh query
bytes. `remote_poll_effect_current_json` and the formal Coordinator package's
`effectCurrentObservations.pollJson` carry them through the existing typed poll
operation. Callers cannot replace the dispatch through this issuer.

Routing admission checks closed canonical outer and inner syntax, dispatch
identity equality, and the existing 65,536-byte query profile. The outer frame
is limited to 131,072 bytes. It does not admit transported report, Checkpoint,
member, authorization or Ledger facts as the holder's own custody. The holder
must use its own accepted report with the existing query admission and Native
observation Owner. A routing observation never grants execution, approval,
publication or cleanup permission.

The resident command checks current dispatch delegation and retains pending
responsibility while its original review Owner is unavailable. The legacy
dispatch-only client and nonresident agent refuse the new operation rather
than executing it. This change does not install a fabricated review Owner or
complete authenticated Cloud query delivery and reply acceptance.

This PR depends on OSS #1337's current-query/reply API. Its final merge target
is main; after #1337 reaches main, integrate main normally and retarget this
PR. OSS #1340 separately supplies original checked member selection. Cloud
must formally adopt the merged source with matching packages and Native binary
before reporting production acceptance.

The fixed poll preimage uses Python JSON encoding of existing independent
dispatch and query inputs. No expected identity is copied from product output.
Focused portable tests cover exact routing, dispatch substitution, closed
canonical framing, bounded refusal and the distinction between routing and
the receiving holder's original report admission. Package tests exercise the
actual installed runtime export and reject copied nominal handles.

Hosted CI remains stopped. Physical Native Effect execution, authenticated
Cloud query transport, Preview acceptance, approval/restart and formal release
remain outside the evidence established by these framing and compiler checks.
