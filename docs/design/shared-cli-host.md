# One Host for independent CLI clients

This is the selected ownership design for [shared CLI state](https://github.com/actql/actql/issues/3611)
and Saved results. It does not assert installed multi-process acceptance. Embedded Local
still has an exclusive state-directory owner; independent Local processes must
not bypass that lock or start replacement Hosts after an ownership refusal.

## Existing execution and transport owners

An operator explicitly starts one long-lived Host and its authenticated HTTPS
listener. The installed `@actql/local-node/http-host` entry already exposes
`openInstalledRemoteHttpHost`: the original installed Host backs its `handler`
and owns `close`. The surrounding application owns the physical TLS listener.
The public Native Client's existing Remote connection and operation routes
connect to this service. They do not adopt its state directory themselves.

The same Host may serve the SDK and the Explorer Gateway. Explorer uses an
existing public Client connection to it; its browser session is not a second
Account, execution authority or Store owner. Native, Node and other bindings
must advertise their actual supported operation families independently.

Startup is explicit. There is no background process discovery, implicit daemon
spawn, insecure fallback, removal of an existing lock or second scheduler.
Packaging a foreground launcher must reuse this installed entry and the
existing Native Remote transport rather than add another protocol interpreter.

The operator supplies the actual Host installation, stable workspace selection,
authentication and TLS identity. Authentication identifies a principal; it
does not grant execution, Run reads, Result delivery, Sample reads or controls.
Each operation retains the Host's current Account checks and original resource
admission. No default token or wildcard permission is introduced. Tokens,
private keys and provider credentials do not enter browser URLs or discovery
metadata. A listener address alone conveys no authority.

## Run identity and client lifetime

Each client retains the original Submission reference and stable operation
identity before sending. A returned Run reference is retained before waiting.
Concurrent requests use the same original journal, integer control revisions,
publication and Result owners. A client is not allowed to copy private handles
or recreate a Run from equal SQL. Same-name and duplicate request behavior is
decided by the existing request identity/fingerprint contract.

Closing a Client or exiting a CLI detaches that client. It does not call the
Host owner's `close`, cancel other clients' Runs or release another client's
retained material. Loss of an HTTP connection does not prove nonacceptance,
physical stop or cleanup. An uncertain response is looked up using its original
operation identity; a fresh submission is not a recovery mechanism.

Cancellation targets the same Run and observed control revision. Accepted
cancellation, later semantic cancellation, physical stop and resource return
remain distinct. Pause and step must use that same control owner once genuinely
implemented; the service cannot create those capabilities through routing.

## Owner close and restart

An explicit owner shutdown first fences listener admission, then settles its
original transport responsibilities and awaits the existing Host close. The
listener's close callback is not the Host's physical cleanup acknowledgement.
Failure or pending cleanup keeps the original owner and responsibility; it
does not permit a competing owner or synthesized success. A retry addresses
that same close attempt rather than constructing another Host.

After an owner crash, a new explicit owner must pass the existing exclusive
ownership and recovery admission with the original state, installation and
authority inputs. A stale endpoint or lost connection cannot authorize lock
reclamation or prove the previous process has stopped. Original Saved and
request lookup remain distinct from new execution. Recovery cannot resend an
uncertain external operation merely because a client reconnects.

## Required installed acceptance

The same immutable installed Host and CLI candidate must establish:

- Parallel independent successful submissions with independent full Result
  expectations, sharing one actual state directory and Saved history.
- Separate-process reads of each original Saved Run without submission,
  provider replay or replacement Run identity.
- Duplicate and conflicting named submissions through the existing identity
  contract, including an uncertain original response and original lookup.
- Cancellation while another client's work remains live, and one client
  exiting or crashing without closing the shared owner or another client's
  resources.
- Actual owner close, owner exit/crash and explicit restart, retaining original
  cleanup failures, pending/Unknown facts and nonresend obligations.
- Current authorization refusals, finite resource admission and malformed or
  foreign references. A transport fixture or schema pass cannot substitute
  for the original Host, journal and physical cleanup observations.

Success in one process with multiple SDK objects is not this multi-process
acceptance. Source design, component checks, ordinary installed behavior and
main adoption remain separate requirements.
