# Native holder Provider installation for Resume

The Remote holder accepts an optional operator-controlled `--effect-resume-root`
directory. On the first exact Resume it opens the existing credential Resource
service and supplies it to the original-Reviewer consumer. Absence keeps the
existing no-send path. An incomplete or invalid present installation retains
the same task/Review as pending; it does not restart Source or Compute.

## Trusted configuration

The directory contains these fixed bounded files:

| Files | Purpose |
| --- | --- |
| `workspace-id.txt`, `installation.txt` | Selected Cloud workspace and installation |
| `host-key-id.txt`, `host-public-key.pem` | Independently installed Host signature verification key |
| `credential-issuer.txt`, `credential-key-id.txt`, `credential-public-key.pem` | Existing Provider grant issuer verification registration |
| `write-grant-cid.txt`, `write-grant.json`, `write-grant-signature.txt` | Original signed Provider grant envelope |
| `write-path.txt`, `write-use-id.txt`, `credential-org-id.txt` | Explicit create operation path, original credential use and Provider organization |
| `provider-token-path.txt`, `provider-ca-path.txt`, `credential-db-path.txt` | Existing secret-file, TLS and durable credential Resource service inputs |
| `effect-connector-registration.txt`, `effect-connector-revision.txt` | Independently installed Effect Connector identity |

Each file is limited to the smaller of the existing file limit and 65,536 bytes.
Scalar files contain the exact value without a trailing newline. No value is
trimmed or normalized. Program, dispatch and proposed approval cannot select
these files, keys, paths or grants. Operator configuration is trusted input and
must retain its existing filesystem protection. Values are not logged.

The actual existing signature verifier admits the Provider grant before opening
the Provider client or credential database. Its scope must match the installed
workspace, Site generation, runtime and Effect Connector. A Source delegation
does not authorize an Effect. The grant's Provider principal is separate from
the original HTTP principal and current Reviewer authority returned by Cloud.
The Host verification key is also independent of the Provider issuer key.

The existing approved-row Owner still checks the original Run, dispatch,
attempt, Catalog, organization, request path and canonical body. It obtains the
durable Ledger claim and calls the existing credential Resource service. That
service retains grant expiry, revocation, scope and use accounting; the holder
does not add a second permission or outcome store.

## Continuity and cleanup

Every use rechecks the original bounded configuration snapshot. Removal or
rotation denies a new send instead of replacing retained authority. Snapshot
continuity is not current Reviewer authorization: the separate scoped Cloud
read and existing Native verifier/Host admission still provide that check.

The holder retains the exact HTTP client and SQLite database until their close
operations succeed. Each success flag is set after its actual close, so retry
does not double-close a completed resource. Setup failure retains its primary
reason while retrying acquired resources, before any Provider use or send. The
existing Source/Compute/Review and slot obligations remain with their Owners. Installation
closure is separate from Effect outcome, Ledger cleanup and dispatch release.

## Completion boundary

This change installs Provider access and Resume configuration in the production
Remote holder. Original Review policy and publication installation are still
required; this change does not manufacture Preview, approval or a completed
Effect. Restoring a genuine Effect producer after holder reconstruction remains
an independent original-custody connection, without requery or reprepare.

The three Native scope cases cover independent Provider identity, foreign scope
or read grants, and invalid/incomplete attempts, including the existing valid
zero attempt. Matching Native compilation compiles these cases but does not
execute them. Physical HTTP, cryptography, Provider I/O, approval, public Result,
restart and formal release acceptance remain unverified by this preparation.

The parent is OSS #1445, after #1444 and its existing dependencies. The final
merge target is OSS main. Formal Cloud adoption requires the merged source and
matching package/Native cohort; no formal pin is changed by this PR.
