# Original resident Effect resume transport

## Boundary

The common report-bound delivery was present, but the resident poll protocol
could not carry it to the original dispatch. The formal Coordinator package now
offers `effectResumeDeliveries.preparePollJson` alongside `prepareJson`, using
the same opaque report, current caller snapshot checks and common issuer.

The closed envelope preserves the canonical original request JSON and exact
delivery JSON. Its dispatch identity must agree with both. It carries no new
materials, Run, execution attempt, grant, receiver or cleanup evidence.
Routing admission returns transport bytes only. It does not return an admitted
Resolution or a usable resume claim. The receiving existing review Owner must
still authenticate against its own durable accepted report and independently
observe/fence the current claim before any send.

The installed CLI currently has no receiving review Owner. It checks existing
dispatch delegation, then reports `effect-resume-pending` without starting,
settling or releasing work. Dispatch-only clients reject this operation. This
change intentionally does not claim Native or public Cloud Effect execution.

The inner delivery retains the existing 262144-byte ceiling. The bounded outer
envelope allows JSON string framing up to 1048576 UTF-8 bytes; it does not change
dispatch, Run materials, capture, retention or execution resource ceilings.

## Remaining production connection

The existing Native entry point
`prepare_native_resident_effect_review_from_context` consumes the original
physical input context and requires a normalization journal and binding
name/digest metadata. The existing retained-holder context test explicitly uses
fixture normalization policy. That fixture is not a production issuer.

The admitted `ClientEffectRunMaterials` exposes the original prepared Program,
compilation, allowed Run, definition and request. The checked Program's syntax
Owner exposes binding names, but the inspected materials path does not provide
the original normalization journal or bound-value digests to this connection.
This connection must obtain those facts from their existing preparation Owner;
it must not invent an empty journal/catalog, reconstruct author values from
Provider output, or substitute fixture CIDs.

F owns this Native holder installation and Cloud handout connection. A reviews
the original preparation/evidence Owner boundary. Independent Reviewer and Host
authentication, the original accepted report, current claim fencing, durable
saved-response settlement and physical cleanup remain separate obligations.

## Adoption

Final merge target is OSS `main`. The merged report-bound delivery and
Coordinator exports are the prerequisite; no unmerged dependency is used.
Cloud adoption must use a merged source and matching formal packages and Native
binary. No Cloud pin, deployment, Preview or historical Run is changed here.
Public SDK approval, restart, Effect execution, Result and formal release remain
required acceptance for Cloud #138.
