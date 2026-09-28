# Salesforce Effects on the standard Host

This records the installed Salesforce Effect: what it binds, when it writes,
what it refuses, and how it recovers. Scope: a Values-origin Program with one
Effect Unit whose Effects reference its Results (Result-backed create, Id
update and external-Id upsert). Effect Programs that also acquire from a
source, payload-only creates, delete, Bulk, decimal/date/datetime
conversions and multi-connection Hosts are out of scope. A Host with both a
source profile and an Effect profile is unsupported in this scope; it is not
claimed to read and write in one Program.

## Status

- On this branch (not yet on main): the installation profile, the explicit publication,
  the capture/Preview/apply/recovery factory, the Host seam and the package
  publication entry. They are tested through the common completion and
  recovery owners against a local HTTPS mock org.
- The standard Host's Effect path (#29) is merged. Behind the Remote HTTP
  Host and the public Client, a single-tuple Set is submitted, previewed,
  held for the whole-Set approval, approved, resumed after a Host restart,
  written once per row and published; a further restart writes nothing. A
  rejected Set, a revoked commit and a changed target write nothing.
- Not yet: the Host options object and Effect profile loading on the Remote
  HTTP, Embedded Local and packed `connect()` entries (C), and the tarball
  Effect run through them.
- Real org: not yet exercised for Effects. The mock evidence does not stand
  in for it.

## Installation and publication

`actql-installed-salesforce-effect/0.1` has exactly these keys:

- `siteProfilePath` (absolute; the installed Site profile, which holds secret references only);
- `publicationPath` (absolute);
- `connectorId`;
- `accountConfigurationWire`;
- `writes`: 1 to 16 Result-referencing writes, each one of:
  - `{resource, kind: 'createFromResult', sources: [{target, field, nullBehavior}]}`;
  - `{resource, kind: 'update', fields}`;
  - `{resource, kind: 'upsert', key, fields}`.

The profile holds no secret value or private key. An unknown version or an
invalid profile is refused before any Site or provider I/O.

`publishInstalledSalesforceEffect` (package: `publishEffect`) is the explicit
publication step. It describes exactly the written Resources, generates each
write's execution Mapping and the Check Environment from that one
declaration, and replaces one generation file atomically: the source
generation (as for the read path), each Mapping's reference and CID, and the
environment CID. A Host start restores it without provider I/O and
regenerates the Mappings and the environment from the restored declaration;
any difference (`SalesforceEffectPublicationMismatch`), another Site binding
(`ForeignSalesforceDeclaration`) or edited text is refused. A partial
publication is never mixed with the previous one.

## What the approval binds

The approval subject is the semantic CID of the sealed private Effect Set
Preview. It covers every field of the Preview except its own CID, the run
definition identity (checked separately), the authoring context and each
row's idempotency key. Through it:

| Fact | Bound by |
|---|---|
| Target rows, before and after values, intended changes | Preview rows (`target_row_identity`, `before`, `after`, `intended_changes`) and the target guard version |
| Members, their order and row order | `effects[]`, member CIDs, `changes[]`, `row_order` |
| Mapping (write kind, fields, key) | `resolved_mapping_contract_cid` from the Check Environment |
| Captured Result inputs | `result_artifact_cid`, `source_binding_cid` |
| Org, Site generation, connection revision, origin, principal, runtime | `capability_evidence_cid` (the Site's attestation of its installed runtime and connection for the dispatch) |

The factory adds no parallel copy of these. It adds current checks against
them before any provider I/O: the installed Mapping must be the Preview's
resolved Mapping, and on recovery the Site as installed now must attest the
same capability for the same requests. The Preview carries no raw org
identifier; record identifiers and field values are in the private Preview
only.

## When it writes

1. Capture (after Compute): the Results and pinned inputs are stored; every
   guarded member's check read is decided on the Site's gate before any
   provider I/O; each member's Resource is described, its requests built from
   the Result rows and its targets read; the Preview is authored and the
   capture committed. No write grant exists yet.
2. Apply: the common owner decides the target reads and the Effect commit for
   the whole sealed Set, once per Host tuple, and refreshes current use (a
   describe per member, a fresh check-read decision and target reads).
3. Each row's write grant is issued only for its member's tuple decision for
   the sealed Set (`subjectCid`). A missing tuple decision, another tuple's,
   another Set's or a copied decision sends nothing. A decision of the Host's
   Checkpoint commit gate is admitted only when that gate decided it for the
   Site's principal under the Site's exact account configuration; the gate
   itself records these facts on the decisions it returns, so no caller can
   register one, and they are never a durable approval.

## Refusals and recovery (mock org evidence)

- A denied commit, or a check read that is not allowed: no write; with the
  read denied, not even a target read.
- After a restart, one member of a two-member Set changed: each change sends
  nothing. Changes tested: permission denied for one tuple, that member's
  Mapping republished, Site generation republished, target record changed,
  and the Host running another runtime.
- A captured Set resumed after a restart writes each row once; a further
  resume sends nothing and publishes the same Result.
- A reply lost after the send: the row stays unknown; a restart sends
  nothing more.
- A non-2xx single-record reply is not a typed Salesforce outcome in the
  existing provider, so that row stays unknown (not failed); later rows of the
  member are not sent under halt, and a restart sends nothing more.
- A capture that fails after storing Results releases its unpublished
  payloads and keeps its own cause; a failed release is attached to it.

## Open items

| Item | Owner | Needed | Acceptance |
|---|---|---|---|
| One Set approval over several Host tuples | C | The commit Checkpoint binds every tuple of the Set; resume admits each listed tuple whose current account outcome still permits it | Approved two-Resource Set: one Checkpoint, 4 writes (each row once), Run succeeded with the Named Result, 0 more writes on restart; a tuple denied at resume: 0 writes, Run failed, capture retired. The todo test in `installed-salesforce-effect.host.test.mjs` is only the reproducer, not evidence |
| Pre-send current-state refusal on resume | C | A refusal proven before any send of the generation ends the resume as failed and retires the capture | Changed target after approval: 0 writes, Run failed, stop observed, capture and source holdings retired, no cleanup pending. With any dispatching or unknown row the Run stays needs_reconciliation, never failed, and nothing is resent |
| Host options object and Effect profile loading; Embedded and packed entries | C | `effectProfilePath` / `ACTQL_LOCAL_EFFECT_PROFILE` through `installed-effect.mjs`; Host's own evidence key; same account text and principal as the Host | Invalid profile refused before provider I/O; source plus Effect refused |
| Tarball and Embedded Effect run | C, D | The entries above | Preview → approval → restart → update → Named Result from an install outside the checkout |
| Live org Effect verification | D | Budget and cleanup reserve per the private record | Update of the dedicated test object, cleanup of created records |
| Typed single-record failure outcomes | D (provider) | A contract for classifying non-2xx replies as definite failures | Rejected rows reported failed without resend |
| Effects with external acquisition | shared | Effect compiler over acquired inputs | Out of this scope |
