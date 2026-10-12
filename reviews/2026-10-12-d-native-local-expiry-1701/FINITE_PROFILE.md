# Native Local finite Run policy profile

This is the first portable unit for #1701, not installed CLI completion.
The adopted change fixes the initial-adoption lifetime bug. It does not add
execution, publication, read, credential or external egress permission.

## Existing requirements and confirmed behavior

The product assembler selects availability 86,400,000 ms, deletion
172,800,000 ms and metadata deletion 604,800,000 ms from initial adoption.
Read expiry is also 86,400,000 ms. These values remain unchanged. The existing
retention Owner includes the availability endpoint; Native read excludes its
expiry endpoint. Neither endpoint is the deletion endpoint.

The original absolute profile and seven original bodies remain valid legacy
representations. Restoration and repeated adoption must retain their exact
bytes and custody. An expired old Result or grant must not become available
because a new profile was selected.

## Adopted correction and identity boundary

`actql-local-run-policy-profile/0.1` is a distinct, closed, finite private
configuration original. Its canonical body contains the four fixed durations
and the actual Data Policy, retention, metadata and clock dependency CIDs.
Its CID hashes the whole canonical body. The reader requires exact canonical
bytes, matching real dependency bodies, one dependency of each kind and the
original effective Data Policy. A copied CID is not authenticated custody.

`client_local_run_policy_profile` constructs metadata from admitted existing
originals. `admit_client_local_run_policy_profile` restores that metadata
against the retained originals. `issue_client_local_run_retention_policy`
constructs a regular existing retention Policy from a first acceptance time.
These APIs are pure and cannot adopt, authorize, accept, renew or retry a Run.
The existing publication/retention contracts and their canonical bodies are
unchanged; newly issued absolute deadlines receive their ordinary new CIDs.
The schema and independent canonical vector accompany the closed reader.

This explicitly adds a profile representation. It does not interpret any
legacy absolute policy as rolling, and does not change the agreed duration,
existing Owner, current authorization, expiry or deletion meaning.

## Required Native connection, still unfinished

Only a new Submission may select a newly issued policy. Its first issuance
time, profile original, exact policy bytes and request/Run identities must
enter the existing original accept transaction together. Repeated lookup,
response-loss recovery and read must use the saved original. Missing evidence
must refuse rather than generate a new policy, grant or attempt.

New installation must explicitly adopt the finite profile through the existing
file selection/adoption Owner within installation <= 6 and Host selection <= 8.
The absolute original read configuration must not silently authorize rolling
egress: current Account, original Result Policy, selected stdout purpose and
the original read/grant Owner remain separately required.

For an existing adopted generation, #1701 also requires a public, explicit,
authorized immutable upgrade append. It must preserve the original adoption,
old profile and old Run/Result/grant deadlines and CIDs; only subsequent new
Submissions select the appended profile. No state deletion, internal file
editing, custody repair or automatic re-adoption is permitted. Its exact append
API/canonical record will be recorded in the following Native connection unit.
Legacy upgrade is an unfinished part of this Issue, not future out-of-scope work.

## Acceptance boundaries

Controlled-clock portable cases cover T0, just before, exact availability,
+1 ms and deletion, unchanged saved originals, fixed durations, dependency
loss/change and noncanonical/extended profiles. They do not prove a physical
restart, current authority or a Native read endpoint.

Native acceptance, real restart/re-adoption, atomic acceptance response loss,
explicit legacy upgrade, and ordinary installed Darwin consumer acceptance
remain required. The system-wide clock will not be changed. No next-day
physical acceptance or new installed E2E is claimed by this unit. Hosted CI,
new producer, Heavy, publication, deployment and live Provider execution are 0.
