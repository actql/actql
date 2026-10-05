# Public Hybrid placement: existing contracts and missing connections

Initial gap map for [OSS #480](https://github.com/actql/actql/issues/480).
G owns the connection plan; A reviews planner/Run ownership and F reviews Cloud
ownership. This is source inspection, not Hybrid execution acceptance.

## Inspection boundary

- OSS main: `eb74d7b65d0f338ef5862a7d9cd7397744a08eaa`.
- Cloud main: `ec1e406b0c5f8c20de10190ef6d4d2e90826d7aa`.
- Inspected Git blobs, without changing either product or starting a deployment,
  data transfer, local test campaign or Actions run.
- #170 remains the actual-candidate/performance unit inside an explicitly chosen
  Host. #458's local observations do not prove automatic cross-Host placement.
  Cloud #138's remote execution and historical recovery #88 remain independent.

The Cloud admission restriction is confirmed at this revision. It expresses an
unsupported product scope; its existence is not an authorization bypass or a
new runtime regression.

## Four different choices

| Choice | Current owner | What it establishes |
| --- | --- | --- |
| Client connection / Run owner | Client wire plus installed Host admission | Who owns one request, Run, status, cancellation and publication |
| Acquisition candidate | `query_planning`, connector registration and source capture | A realization of the same checked source requirement, including required residual work |
| Compute candidate | Installed `physical_host` contributions and dispatch | An eligible implementation of a checked-ready task under the existing ledger |
| Cross-Site placement | Host-installed Site policy, common Site control and Transfer | A destination for that implementation with exact input, generation and capacity bindings |

A benchmark Host switch establishes only an experiment condition. A Native
acquisition choice is not a Cloud placement, and a cheaper Compute implementation
does not obtain disclosure or execution permission.

## Existing contract and implementation map

| Boundary | Reusable contract / code | Missing public connection |
| --- | --- | --- |
| Connection admission | `spec/contracts/actql-client-host.json`, `packages/client-wire/index.d.ts`, `packages/sdk/index.mjs` | Wire accepts `hybrid/local` with `movementPolicyRef` and `cloudConnectionRef`; `hybrid/cloud` requires runners and a movement policy. References are not resolved into an admitted execution installation. |
| Embedded Local | `packages/node/index.mjs`, `packages/local-node/index.mjs`, `adapters/host-node/embedded-local.mjs` | Node routes embedded local-owned Hybrid to Local; Local explicitly throws `LocalHybridUnavailable`. Installed admission and negotiation still couple mode and owner. Changing the wrapper alone would not connect planning. |
| Cloud admission | Cloud `src/ingress/cloud-owned-client-run-host.ts`, `src/composition/prototype-worker.ts` | Both dispatch and authorization require `remote/remote`; the composition rejects runners/consent references. The returned profile is remote-owned. No installed Hybrid profile exists here. |
| Cloud assignment | Cloud `src/config/prototype-cloud-config.ts`, `src/composition/prototype-worker.ts` | Config has one Site selection; the durable wake copies it. `siteAssigned` checks Workspace/authority scope. This is configured assignment, not selection among a Local/Cloud candidate set. |
| Candidate installation | `docs/design/query-physical-strategy.md`, `docs/design/physical-strategy-execution.md` | Exact registrations, immutable implementation subsets, feasibility, resource envelopes and single-use dispatch already exist. A public Hybrid connection does not install the eligible destinations or bind them to this choice. |
| Placement / cost | `adapters/host-common/execution-sites.mjs`, `adapters/host-common/strategy.mjs` | Existing Site policy binds contribution registrations to exact Site handles; common control checks generation, capacity, transfer availability and estimates. The default is one in-process Site. In-process Site handles are not authenticated remote endpoints. |
| External ranking | `docs/design/placement-policy-wire.md` | An authenticated external policy can rank an already feasible bounded set. Its decision cannot add capabilities, grants or budgets. This is neither a connection resolver nor authority to upload inputs. |
| Transfer / custody | `adapters/host-common/managed-site-transfer.mjs`, `adapters/site-node/https-direct-transfer.mjs`, `adapters/site-node/https-transfer-store.mjs` | Existing transfer control preserves exact occurrence/material/generation, source and destination responsibilities, retained copies and cleanup. The managed coordinator's documented scope is explicit in-process Transfer; remote adapters need a reviewed public-Run association rather than being treated as that same in-process implementation. |
| Run / recovery | Local `client-run-start.mjs`, `client-dispatch-owner.mjs`, installed journal/publication; Cloud `coordinator-owner.ts`, `remote-site-transport.ts`, retained Run host | Existing request lookup, durable intent, observation/retransmission, cancellation fence and release remain the owners. No verified bridge binds the public Hybrid Run, selected Site attempt and receiver custody across these installations. |

The generic HTTP Host test `local-owned Hybrid Cloud ref reaches Host
authorization before use` in `adapters/host-node/client-http.test.mjs` checks
admission facts with a supplied Host. It does not execute a Hybrid Program.
Likewise, wire acceptance and remote transport fixtures do not establish this
missing product connection.

## Required connections, without new owners

1. Resolve the connection's registered assistance/runner and movement-policy
   references from trusted Host configuration under current principal authority.
   Reject missing, foreign, expired or mismatched bindings before acquisition
   or transfer; do not resolve arbitrary endpoints supplied by Program data.
2. Keep one existing semantic Run owner and request identity. Project the exact
   checked-ready task into the existing immutable capability/Site installation.
   Bind candidate registration, runtime revision, Site generation, input
   occurrence and transfer/retention/execution quantities independently.
3. Use common feasibility and selection, preserving unknown estimates and
   rejected candidates. Record its actual choice before I/O, and match the
   dispatch/physical attempt to that choice afterwards. Supply bounds rather
   than deriving an upper bound from the observed output or fastest sample.
4. Evaluate current data disclosure independently of execution activation and
   recheck at the actual boundary. Existing in-process coverage for unprotected
   Sites cannot authorize transfer to a Cloud/Runner destination. The managed
   transfer coordinator already authorizes required copies before starting the
   first one; retain that ordering when connecting a remote provider.
5. Bind remote dispatch, transfer receipts and retained output to the same Run
   and exact selected generation. Keep source custody until required receiver
   acceptance/stop, and retain every pending cleanup obligation through retries.
   An accepted terminal observation is not physical stop or complete cleanup.
6. Reuse request lookup, cancellation, unknown-outcome and release mechanisms.
   A possibly sent task cannot be relocated/retried as new work. A cheaper
   replacement or a generation change supplies no execution authority.

Calling the ordinary Cloud Client `submit()` from a Local execution would create
a separate semantic Run, not a task placement inside the original Run. Removing
`ClientConnectionDenied`, relabeling `owner`, or reusing an in-process Site's
unprotected coverage are also insufficient implementations.

## Smallest proposed placement unit and review boundary

After the current #170 selection/performance unit, start with one existing
bounded numeric/NULL Relation Program, one Source and one unary Compute task.
Keep an explicit finite pair of installed destinations, fixed before Run
acceptance; do not add automatic Host migration, hot runner registration,
Effect/INFER, fan-out or arbitrary DAG support. The Source's existing checked
requirement and capture must remain unchanged between eligible placements.

Local-owned Hybrid is a proposed first profile: it names an existing Cloud
assistance connection in the current wire and can retain the Local request/Run
owner. It is **not yet an agreed implementation**. In particular, an ordinary
Cloud-owned Run endpoint cannot be reused as an internal task endpoint merely
by changing its mode. Before implementing this bridge, A/F must resolve:

- Which existing task/dispatch admission accepts a Local-owned original Run at
  the registered Cloud assistance boundary, and how that boundary authenticates
  its Run/authority/occurrence without accepting a second Run or forged owner.
- How trusted `cloudConnectionRef` / `movementPolicyRef` registration becomes
  exact eligible Site, runtime and policy bindings; the wire fixes reference
  shape but does not define this deployment resolver.
- Which existing transfer/retention representation both implementations can
  admit, including origin/receiver grants, bounds, generation and failure
  evidence. Unknown costs must remain unknown, not zero.
- Whether an existing public ownership contract supplies this delegation. If
  not, describe the smallest normative difference before widening acceptance.

These are concrete composition/authority gaps, not permission to invent a new
scheduler, Run owner, ledger or retry fallback. Cloud-owned Hybrid remains a
separate supported wire form; it must not be silently translated to the proposed
Local-owned unit.

## Eventual bounded acceptance

Use one public Client Program and request/Run identity with independent expected
rows, type/NULL/order contract and Result. Vary one admitted estimate or capacity
fact to obtain a second actual eligible placement; keep the same semantics and
obligations through residual processing. Check the actual candidate/dispatch/
attempt association, not a test-side route label.

Retain focused negative observations: an unauthorized cheaper destination gets
zero input and zero Compute; missing transfer feasibility cannot win; stale
generation or changed authority cannot dispatch; failure/unknown keeps custody;
formal cancellation stops new work and cleanup retries do not restart Compute;
the last holding is returned exactly once. Reuse existing owner regressions
rather than adding an operator-by-failure matrix.

Record deterministic local transport acceptance separately from live Cloud
deployment acceptance. Neither this map nor #170's benchmark receipts establish
public Hybrid, remote recovery completeness or physical heap upper bounds.
No deployment or new-destination disclosure is authorized by this proposal.

## Progress and verification

Completed here: fixed-revision source gap map and a bounded proposal for A/F
review. Product implementation, focused acceptance, live Cloud evidence and
performance savings are uncompleted. No local build/test or CI rerun was added
for this document. The #412 actual-image/mutation/restoration/final-consumer
acceptance remains a separate open requirement; source/fixture correspondence
does not close it.
