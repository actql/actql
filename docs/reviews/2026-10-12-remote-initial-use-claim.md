# Remote initial-use claim connection

Status: private Resource connection; production Host/Journal installation and
physical acceptance remain incomplete. This is not a new permission or an
independent credential use Owner.

## Existing failure boundary

An absent Credential DB record and absent Checkpoint do not prove that an
original Catalog GET was never sent. The first Resource ordinal must therefore
depend on the original Site Journal's initial-acceptance stamp, rather than on
absence in a potentially replaced database. The stamp is issued only by the
real initial acceptance transaction; duplicates and old records cannot acquire
one retroactively.

## Resource order

The explicit installation requires both original-custody callbacks:

1. Check the original grant/scope, operation, request bytes, trusted lifetime,
   revocation and current Host authorization through the existing Resource code.
2. Inspect the original nominal credential-use record. An existing record stays
   on the original retained-ordinal path and never calls the initial callback.
   Observation errors other than exact NotFound refuse selection.
3. For a missing Remote record, invoke the trusted original Journal claim before
   selecting a Resource ordinal or constructing a nominal use. NotFound merely
   selects this proof obligation; it is not permission or an unsent assertion.
4. Recheck Host/caller current permission, trusted lifetime and durable revocation
   after the claim callback. Loss of permission preserves the Journal claim but
   creates no Resource ordinal/use or terminal success.
5. Select and persist the original Resource use. The existing post-save callback
   retains that exact nominal use before the final send fences and Provider I/O.

The original callbacks may retain failed/uncertain persistence. A claim reply
loss is returned without a Resource ordinal or send. A later call must consult
the same Journal; it may not issue another claim from empty credential storage.
Concurrent initial callbacks must use the same existing Journal CAS, which
admits one claim. A saved Resource use takes existing read-only reconciliation;
it is not sent again or replaced with another nominal use.

Local and Local-preparation paths do not use the Remote callbacks. Their
original target, raw-response custody and read-only recovery remain unchanged.
The default Resource installer remains unchanged; this explicit private
installation is not installed by the production CLI yet.

## Dependencies and outstanding installation

The Resource post-save hook comes from OSS #1499 at
`33b0357c422f6331dc09ddec303bb7e4ee58d882`. D's original read-only Resource
helpers are normally merged from #1504 at
`3e395ed7f975510d7b185e96f509f3cb88fbe8dc`; that Local dependency is not claimed
as main acceptance. The initial Journal stamp itself is #1505 at
`e630fdf8371ed930fbc63bd7a031be97d1ab7323` and is a separate dependency of the
trusted installation, not supplied by a success callback in production.

Still required: supply the actual original Host admission/current Account
permission, original Journal custody continuity, original Run Ledger/reviewed
cost envelope and confirmed cleanup/restoration. A newly created Site Journal
with the same configured generation does not establish historical eligibility.
The stamp is not read/write/approval authority, Provider success or cleanup.
Production evidence-read remains default-deny.

## Verification boundary

The three new physical Resource fixtures require the existing real HTTP/SQLite
fixture and fail if it is absent. They cover claim refusal before ordinal/use,
saved-use replay after failed retention, and current-permission loss during the
claim. They are compile-only until an explicit physical verification window.
Pure existing retention and Local read-only checks are reported separately.
The new fixed `ForeignEffectMaterials` CLI diagnostic fixture is also
Native compile-only. The normal integration exposed the previously missing
exhaustive branch; the branch logs no caller/provider payload.
No Provider, public Effect, Result/release, Preview or hosted CI acceptance is
asserted by this preparation unit.

Current main `8334cedac2200004a60d69b40d5a715200f59e72` (including the
reviewed #1483/#1486 integration) is normally merged. The original Host
subject/current/admission suppliers remain uninstalled; their three existing
struct warnings are retained without suppression or dummy construction.
