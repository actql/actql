# Private Model current-cut read-only reconciliation

`recoverOriginalModelCurrentCut(observation, {parkReceipt, savedReceipt})` is a
private entrance of the existing installed SQLite Journal. It reads the exact
existing link, verifies installed nominal Resource and Store observations using
the existing Common cut projection, and reselects complete ordered Run-local
facts after verification. It neither rewrites a link nor recreates an old ACK.

The returned Journal-member reference has status `reconciled`. Its original
observation may be read and reconfirmed. Copied, foreign, old-connection or stale
references remain refused. `commitOriginalModelCurrentCut` and
`invalidateOriginalModelCurrentCut` reject this reference. The existing live
`linked` operation's exact-CAS/confirmed-COMMIT path and mutation fence remain
unchanged.

The current layout does not persist invalidation intent identity/outcome. A
before-COMMIT throw can leave the old link while the original operation remains
Unknown. Reopening cannot distinguish that data from an unattempted operation.
Accordingly, a matching read-only reconciliation does not permit invalidation,
Resource one-shot consumption, unpark, restore, Entry, Provider send or retry.
A null link is not an ACK. The later existing-Owner private-layout unit must
close that missing durable identity; no caller Boolean or CID fills the gap.

Verification receives immutable borrowed nominal facts from trusted installed
issuers. The Journal runs their callbacks outside its transaction boundary,
then checks all original facts and exact link again. Application configuration
or receipt JSON cannot replace those issuers. This API does not install them or
derive their authority. Failed verification leaves their original custody and
cleanup responsibility unchanged.

All retained facts, exact link string, candidate serialization, parsed trees,
canonical comparison workspace, new reference/observation and their overlap
with Resource/Store controls require the same original holding envelope before
production use. Escaped references carry only a frozen tag: their membership
and borrowed facts stay in the existing Journal WeakMaps, with no added public
callback or Owner. Repeated observations are not a free numerical allowance.
Normal funding and the installed public recovery entrance remain unavailable
until their actual suppliers and acceptance are present.

The Node reconciliation tests use real SQLite with explicit Resource, Store and
Common fixture ports. They establish only read-only Journal behavior and
refusals, not authenticated cold Resource admission, real Store ACK, physical
one-shot consumption or an installed INFER recovery E2E.
