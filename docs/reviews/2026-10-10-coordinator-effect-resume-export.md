# Coordinator Effect resume delivery export

`@actql/coordinator-core.effectResumeDeliveries.prepareJson` exposes the common
original-report delivery issuer. It accepts the opaque report admitted by
`effectCheckpointReports`, the saved verified Resolution wire, independently
installed authentication/Reviewer facts, and the existing resume Owner's claim.
The adapter passes typed fields to the MoonBit bridge; only the common issuer
serializes the delivery body. It does not recreate Run materials or issue a new
Checkpoint, authorization, claim or attempt.

The bridge re-admits the attested Resolution against the original report's
Checkpoint before invoking `prepare_remote_effect_resume_delivery`. JavaScript
cannot manufacture the private report handle by copying metadata. Inputs are
bounded, claim generation uses an exact positive Int64 `bigint`, and sparse or
oversized Reviewer arrays are refused. Authentication facts use the existing
Checkpoint Owner's field names without normalizing their values.

The JavaScript boundary snapshots typed caller facts once. It rejects strings
using their UTF-16 length before UTF-8 encoding, then checks actual encoded bytes
against the remaining aggregate budget. An oversized rejected input cannot first
allocate an unbounded encoded buffer, and mutable accessors cannot substitute
different facts between validation and the common Owner call.

This is serialization and common metadata admission, not physical signature
verification or current permission. The Cloud caller must authenticate and
persist the original Resolution through the existing Run Owner, durably acquire
the claim, and recheck its current authorization and fence before delivery. The
Native receiving boundary independently requires the original report's durable
ACK, current claim, physical signature verification and current Provider authority.
No unknown Effect outcome becomes permission to replay a write.

The existing packed Coordinator acceptance copies the independent resume vector
alongside its original report vector and runs the new export cases. Type acceptance
rejects a dispatch substituted for the report and a number substituted for exact
claim generation. Syntax-only signatures in these vectors are not physical Cloud
or Native write acceptance.

The common/Native delivery dependency is OSS #1311. The final merge target of this
export is OSS main after that dependency, followed by formal merged-source Cloud
package/binary adoption. Cloud resume handout, normal Site CLI installation and
public Effect acceptance remain separate unfinished connections.
