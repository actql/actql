# Execution namespace in the 0.1 baseline

The OSS execution namespace is an isolation coordinate, not a Cloud
Organization or Workspace and not a provider's own tenant identifier. A Cloud
adapter translates its selected execution boundary to `namespaceId`; the OSS
Host does not infer that value from provider metadata. The authority scope and
caller request ID remain the durable request key. Equal request IDs in distinct
authority scopes are independent. A pending or unknown request retains its
original namespace, authority scope, request ID and body across reconnects;
switching a Workspace cannot redirect or resubmit it.

| Contract or store | Current field and identity effect | Prior-format handling |
| --- | --- | --- |
| Public Client wire, RunRef and SDK | `namespaceId`; closed object shapes reject missing or extra fields | Reject before normal execution; do not rename a received field |
| Execution Context and Run-bound artifacts | `namespace_id`; changed canonical body changes its CID and dependent pins | Verify the current body and CID; do not re-label an old body |
| Remote credential grant and signature | `namespace_id` is in the signed grant body | Reject the old or mixed body; never reuse its signature |
| Effect and Acquisition evidence | `namespace_id` or `namespace_scope_cid` where the execution boundary is part of the preimage | No alias or identity-preserving rewrite |
| Client request journal | `namespace_id` column and exact 0.1 journal marker | Refuse unmarked or mismatched files before writable open |
| Local Publication Store | `isolation: execution-namespace` in the 0.1 Store marker | Refuse old or unknown Store roots without changing their contents |
| Native Publication Store | Exact 0.1 format marker, established under the Store lock after a read-only preflight | Refuse old or unidentified data before creating the lock or database |
| Installed Host root | Exact `actql-local-host-root/0.1` marker before journals or profiles are opened | Refuse nonempty unmarked or unknown roots before the first write |

This is a coordinated correction to the unpublished 0.1 contract, not a
backward-compatible rename. The version remains 0.1 and no compatibility
decoder, automatic migration, deletion or overwrite is installed. A markerless
root is fresh only when absent or empty. Prior or unidentified data remains on
disk, including records whose dispatch outcome is unknown. Refusal does not
classify those Runs as failed or cancelled and does not permit replay. If
retained old data needs service, its existing implementation and a separate
migration decision are required.

The root marker identifies the storage format; it is not an authorization
credential. Normal grant, scope, Run and current-permission checks remain
mandatory. Connector-specific tenant metadata and authored data fields with
that name are outside this execution-isolation change.
