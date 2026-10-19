# Ordinary Embedded Host trust boundary

Status: adopted. The normative owners are
[ordinary Host trust and resources](../spec/execution.md#initial-node-control-preparation)
and [initial Local Mock authorization](../spec/execution.md#initial-local-mock-authorization).
This is an intentional reduction of startup-wide proof obligations, not a claim
that the former physical guarantees are preserved by a simpler implementation.

## Problem and evidence

The previous execution requirements made initial Node preparation depend on
an actual selected startup and complete simultaneous coverage of input,
closures, module/runtime/library domains and partial-failure custody. The
reference Host consequently described a process-once, omitted-options recipe,
fixed preload/load ancestry and a runtime-internal byte envelope. Native startup
also inspected private libc stdio state before ordinary command initialization.
Those checks do not establish isolation from arbitrary malicious code in the
same process and make normal embedding depend on unrelated startup conditions.

Type/authorization admission, external-send recovery, native memory safety and
process provenance address different threats. Requiring all of them at every
public entry made legitimate installed applications unavailable without adding
a defensible same-process security boundary.

The selected platform documentation supports a narrower interpretation:

- [Node permissions](https://nodejs.org/docs/latest-v22.x/api/permissions.html)
  restrict trusted code's resource access and are not a malicious-code sandbox.
- [Node worker limits](https://nodejs.org/api/worker_threads.html)
  cover JS-engine resources, exclude external ArrayBuffer storage and do not
  prevent whole-process out-of-memory termination.
- [DuckDB memory limits](https://duckdb.org/docs/current/configuration/pragmas.html)
  describe buffer-manager coverage rather than every result and runtime object.
- [SQLite close](https://www.sqlite.org/c3ref/close.html) distinguishes busy
  explicit close from deferred destruction. Logical closure is not proof of
  immediate physical release.

These comparisons motivate scope, not automatic adoption of their APIs or a
new backend implementation.

## Accepted responsibility

| Subject | Ordinary product responsibility |
| --- | --- |
| Program, Parameters, files, HTTP and Provider output | Bounded parsing, type/semantic validation and applicable authority. |
| Effect and approval | Same target, Preview, Checkpoint, current authority, signer role/purpose and explicit decision. |
| Durable Run/Result and recovery | Integrity, original saved materials, fenced ownership and no blind resend after uncertainty. |
| ActQL-owned work and storage | Explicit limits and real acquisition/failure/cleanup for the units the implementation controls. |
| OS, runtime, standard libraries and embedding application | Trusted execution platform, with tested API/ABI compatibility and documented limitations. |
| Hostile executable code or untrusted tenants | Appropriate process/OS isolation in the deployment; object identity checks are not its substitute. |

Trusting the platform does not make SQL safe to forward to an unrestricted
native engine. [Untrusted DuckDB work](https://duckdb.org/docs/current/operations_manual/securing_duckdb/overview.html)
still needs its applicable configuration and isolation. Existing Core checking,
operation permissions and bounds remain in force.

## Normal initialization and limits

Public open/connect or ordinary CLI main is the legitimate start of a Host
instance. It validates documented options, captures internal configuration,
loads the packaged Core and acquires actual Store, crypto, buffers and selected
workers through the existing Owners. No special preload, no-options-only
entry, one-Host-per-process right, patch-exact Node/OpenSSL match, private libc
fields or proof of prior imports is required.

Compatibility checks retain necessary platform/API/ABI and component-integrity
constraints. Reproducible build pins stay in build and validation. Diagnostic
flags are rejected only for a concrete supported-operation conflict, not for
being ambient configuration. Supported ranges must be tested; this decision
does not declare an untested platform compatible.

Ordinary trusted JS/Python options may use their documented callbacks and
object forms. Copy known configuration before asynchronous use and keep the
existing field/type validation. Do not introduce a general data-only public
API restriction or account for arbitrary caller closure graphs before reading
options. Untrusted encoded requests instead enter through bounded byte parsing
and then the same semantic validation.

Instances have active, closing and closed state. Reopen and multiple independent
Hosts work in one process, while actual state-directory locking and shared
resource ownership apply. Runtime/module caching is permitted without a Host
claim over the cache's full lifetime. Run-level calls, costs and send history
are never reset by replacing its Host.

Retain input/depth/row/batch/transfer/result/call/token/concurrency/deadline and
managed-buffer limits in their existing Owners. Describe each limit's subject;
neither a scalar Ledger nor an estimated envelope proves allocated memory or a
hard RSS ceiling. Normal platform allocation is a valid supplier. Handle actual
allocation failure instead of demanding an earlier whole-runtime issuer or
using a fake allocation ACK. No new framework, Owner, Ledger or retry engine
is needed for this boundary change.

## Three distinct lifetime obligations

| Resource | Completion |
| --- | --- |
| DB/statement, FD, socket, active task, shared native or zero-copy memory | Original explicit close/stop/release semantics, preserving pending work and real users. |
| Ordinary copied managed values | Release the Host's retained references; runtime GC can occur later. |
| Shared modules, JIT, allocator or crypto-library caches | Process/platform baseline, outside ordinary Host-close conditions. |

A native arena with live users remains busy even if its users contain strings
or arrays. Correct their ownership or move ordinary runtime values to an
appropriate allocation domain; never ignore a real busy result or free memory
still in use. The same distinction applies to zero-copy Results and asynchronous
Provider/Reader operations. A close_v2-style API cannot be reported as immediate
deallocation merely because its logical close succeeded.

Confirmed business outcome, unfinished cleanup and external-send Unknown are
separate. Memory reclamation that the runtime has not exposed is not evidence
of an uncertain external write. Conversely, confirmed computation does not
release an active socket or authorize a possibly sent call to execute again.

## Mock setup and recovery

An explicit trusted Mock choice consents to first setup of its limited Account
profile, Local Reviewer and real purpose-confined key. Mere discovery of an
untrusted Project, authored text or an equal CID is not consent. Setup grants
selected Mock reads, answer use and Local control/Result access, while the
selected UPDATE uses explicit existing Delegate/Checkpoint approval. No manual
Account, Reviewer, external login or key-registration steps are required for
the ordinary Mock experience; no automatic approve is introduced.

Bind to the actual Mock backend/installation, principal, Project/managed area
and resource contracts. Never resolve live Credentials, initialize live
Providers or fall back to them after a Mock error. One approval can discharge
coincident review restrictions on the same Preview; a changed target or Preview
needs its applicable new approval.

Freshness is an ordinary exclusive creation/adoption operation. Persist the
existing initialization intent before separate file creation, create without
overwriting operator content, and confirm the concrete generated configuration
against the same intent. Parallel initializers serialize, observe or conflict;
an interrupted initializer recovers the same attempt. SQLite transactions do
not make external file creation atomic. No earlier trusted freshness marker
or historical pathname proof is required to start this process.

Provenance identifies the original profile and generated configuration;
current operator configuration decides current authority. Deny/restriction is
effective, expansion needs authorized change, and missing adopted config/keys
or Store is not a signal to regenerate authority. Reconstruct restart handles
from validated persisted installation and backend/current identity rather than
requiring cross-process pointer identity. Contract-compatible data edits can
serve new Runs; old Runs keep their saved inputs, answers and Previews.

## Compatibility and acceptance

The old four initial-control requirements are retired and replacement
requirements need fresh implementation evidence. This document supplies no
API, execution proof or numerical profile. Existing wire schemas, canonical
Run/Result/approval preimages and contract version strings are unchanged by
this prose decision. A concrete bootstrap profile or later necessary schema
change must carry its real body, pins and independent vectors together.

Acceptance uses one fixed ordinary package candidate: public SELECT 1 and
close without special preload; documented state-directory/options; reopen and
independent Hosts; managed-limit failure and actual resource cleanup; Mock
JOIN/inference; no write before explicit approval; same-Run restart/Result;
and refusal of Deny, live same-alias substitution or missing adopted state.
Memory checks inspect owned handles, retained resources and repeated-use growth,
not exact return of process RSS to its initial value after every close.

Node, Native, Python and Cloud retain their separate product completion gates.
Cloud #138 remains Source/Compute/Effect/Approval/Recovery without silently
adding INFER to that issue. This boundary change neither shrinks v0.1 nor claims
that unconnected normal resource or Mock suppliers already exist.
