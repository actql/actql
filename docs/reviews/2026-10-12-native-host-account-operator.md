# Explicit Resident Host Account operator supplier

This continues the bounded Account installer. It supplies the actual private
holder caller from an explicitly selected operator root; it does not claim
physical Native or public Effect acceptance.

## Input entry

`--effect-host-account-root` is optional and inherited by the existing holder
process argument path. Unselected means None. An explicitly empty/repeated root
is refused. The holder reads and admits its selected input before the Source
start claim, so invalid selection does not begin Source acquisition. Setup
failure closes the already opened output resources, environment and slot through
the existing cleanup functions.

The root contains the following exact UTF-8 files (no implicit trimming):

- `account.json`: the operator's existing execution-account configuration.
- `host-principal.txt`, `host-account-id.txt`, `host-configuration-cid.txt`,
  `host-authorization-context-cid.txt`: independently installed original Host
  subject, account, Common configuration CID and original context CID.
- `host-read-connection.txt`, `host-read-resource.txt`,
  `host-publication-connection.txt`, `host-publication-resource.txt`: separate
  Host-defined evidence read and Coordinator publication selectors.
- `workspace-id.txt`, `installation.txt`, `host-identity-expires-ms.txt`:
  installed Cloud identity read scope and expiry ceiling, not a Run renewal.

The Account file is capped at the smaller of the existing operator
`--max-file-bytes` and 1,000,000 bytes. Each private scalar is capped at the
smaller of that limit and 512 bytes. Existing Common admission supplies the
configuration CID and decision. This command neither constructs Allow entries
nor derives the principal/account/context from Source, Role or Reviewer.

## Current fences

The actual opaque Account installation is paired with the existing control
client (same configured TLS/Site credential) and the private original-consumer
identity URL. Fresh query challenges use the existing platform entropy source;
unavailable entropy closes the read, not the original responsibility.

The operator scalar snapshot is reread at each current fence. Deleted, changed
or unreadable inputs, expired installation, lost executor-slot ownership, and
an Account file above the operator cap refuse admission. Account content is
re-admitted and decided independently at each permission fence. This snapshot
check is not an Allow, grant or physical cleanup proof.

The existing holder verifies original producer/consumer/journal custody and the
original Run execution context, and performs the authenticated original Cloud
principal read before and after Common permission selection. Cloud independently
checks current Site/receiver/caller-floor ownership. Read and publication remain
separate purposes; unresolved delegation has no answer supplier and is refused.
Existing signing/send fences and pending/unknown cleanup responsibility remain.

## Acceptance status

The supplied Host record is now constructed by the real CLI loader; no dummy
record or warning suppression is used. This removes the installer-only
never-constructed warning through the actual call path.

Two Native caller counterexamples are compiled only: missing versus selected
invalid root; deleted/replaced original principal and selector snapshot. The
existing eight portable Account tests are executed at this new source, but they
do not execute the Native filesystem, control HTTP or these two Native cases.

No production Account/secret is installed, no Provider/deploy operation is
performed, and no public approval/Effect/Result/release is claimed. Actual
installation and finite physical acceptance remain separate. Journal/stamp,
Resource, Ledger and D's Local client/issuer files are unchanged. The final
merge destination is main after the installer parent is integrated.
