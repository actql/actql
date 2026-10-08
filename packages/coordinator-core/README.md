# Coordinator Core

`@actql/coordinator-core` exposes the portable shared Coordinator owner. Its
`bundleRetention` namespace contains client value construction, canonical wire
admission, identities, and projections for bundle retention. It has no Node
adapter dependency and can be consumed by a Worker. Existing Coordinator exports
remain available alongside this namespace.

## Bundle retention client

1. Use `prepareDistribution(existingBundleCids)` and `prepareHoldScope(input)`
   for the caller's own hold on explicitly permitted existing bundles. Scope
   includes Coordinator authority, workspace, authority scope CID, environment,
   set revision CID, runtime bundle CID, Site key and generation, and attempt ID.
2. Send `prepareCustodyContextQuery(distribution, scope)` through the existing
   authenticated channel. `custodyRequestJson` and `custodyRequestIdentity` supply
   the exact request bytes and CID. Admit the reply with
   `admitCustodyResponseJson(originalRequest, responseBody, responseCid)`.
3. A `context` reply supplies catalog context. It is not retained readiness;
   `custodyResponseObservation` returns an empty string. Persist the exact
   `custodyResponseBinding` using `holdBindingJson` and `holdBindingIdentity`
   before preparing or sending a retain request.
4. Use `prepareCustodyRequest(distribution, originalBinding, 'retain')` to request
   custody. The existing Site authorization and quota decisions still apply.
   Pure construction or a valid CID grants no permission.
5. After interruption, re-admit the saved distribution and original binding with
   `admitDistributionJson` and `admitHoldBindingJson`. Use that binding for
   `'query'` or `'release'`. Do not refresh its catalog, initial revision, or
   attempt ID, and do not treat transport errors as proof of absence.
6. Admit every response against its exact original request. Only an
   `observation` response can report `retained`, `fenced`, `unresolved`, or
   `unavailable`. This is custody evidence, not Run or dispatch authorization.

The namespace is frozen and its five handle types are opaque. Projections retain
the shared owner's ordered string-array format. Optional catalog and revision
projections return `undefined`; revision zero is preserved. The namespace has
the client methods consumed by Node's `sendRemoteBundleCustody`, and performs no
network I/O, automatic retry, installation, activation, Store mutation, or
authority setup. Callers keep their existing authentication, policy, and quota
boundaries.
