# Runtime public facades

Public runtime entry points forward the values declared by their existing
TypeScript interfaces. Local observation exposes `createHostObservationConnection`
and `observationLimits`. Result access exposes `installResultAccessAuthority`,
`installResultAccessService`, `deliverAuthorizedResult`,
`inspectAuthorizedDeliveryAttempt`, and `describeAuthorizedResult`.

Each export is the canonical implementation's original function or value.
The facade creates no wrapper, alternate registry, authority or lifecycle owner.
Canonical modules retain private nominal associations and their internal imports.

The module forwards no calls and adds no callback or asynchronous boundary.
Current authorization, delivery sequencing, cancellation and physical cleanup
remain obligations of the original services and their selected physical adapters.
Importing a facade does not allocate a Run, reserve capacity or grant access.

Failures retain the canonical error class, code, cause and cleanup behavior.
`ResultAccessError` remains an implementation export used by internal consumers;
the public Result entry does not export its constructor. Observation's internal
projection, context and installation helpers remain on the canonical module.

Package export targets must be included in the same package's file inventory.
The runtime builder continues to generate and check the complete canonical
Result implementation copy; the public facade never replaces that copy.
Extensions require the existing typed and runtime public surfaces to agree.

Source-level facade checks compare actual namespaces and original identities,
preserve private nominal refusal, and retain the canonical generator input.
These checks do not establish an installed runtime or physical cleanup result.
