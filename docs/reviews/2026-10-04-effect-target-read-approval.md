# Deferred Effect target reads

Issue: [#317](https://github.com/actql/actql/issues/317).

## Boundary and ownership

The installed Salesforce Effect exposes a pure target inventory from the
checked Program and its restored, published Mappings. The common Host decides
every distinct `(connection, resource, read)` tuple **before computation**.
Members sharing a tuple retain their individual Mapping and physical bindings.
The inventory includes the Site binding, publication generation, Program/Unit,
member, Mapping, operation, key and fields. It performs no provider I/O.

A deferred tuple becomes an ordinary `read_access` / `run_unit` Checkpoint with
its own `read_scope` artifact. The existing encrypted continuation Store retains
the original submission and complete inventory; the existing journal owns the
answer and same-Run continuation. A later tuple replaces the active Checkpoint
through the existing atomic continuation transition. An answer for the first
tuple does not approve the second. No additional ledger or scheduler is added.

On restart the Host reconstructs the original admission and target inventory.
The target owner checks every earlier committed approval's currency and the
current installed account decision. Changed bindings, rejection, expiry and
current denial cannot authorize a provider call. Source acquisition permissions
and Effect-commit permissions remain separate. Target read approval describes
read scope, not the eventual Preview or a write.

The same target owner supplies the pre-Preview and current-use read decisions.
The credential Site admits only a privately recorded target decision whose
principal, account, context, tuple and exact member binding match its current
installation. Its token can authorize record observation and that Resource's
Catalog describe; it cannot authorize a query or an Effect write.

The active resume admission is consumed before computation starts. A process
loss after that boundary retains the original responsibility instead of
replaying Source, Model or Effect work. Later read scopes and Effect commit use
the same existing atomic next-Checkpoint transition. An unknown Effect remains
unknown; its captured holdings are not released or re-sent by this feature.

## Supported profile and compatibility

This connects the installed Salesforce Effect's existing single-Unit Program
profile and the common Host's bounded target inventory. The existing Source
continuation remains a separate subtype with its original capture/restoration
rules. There is no new public Checkpoint kind, wire version or approval schema.

Installations without the pure inventory and exact account/context connection
retain the explicit unsupported deferred-read behavior. A new target deferral
after computation has already been captured is not reinterpreted as a fresh
pre-computation continuation. Deferred Model execution remains the separate
[#310](https://github.com/actql/actql/issues/310) boundary.

The implementation is based on main
`8899d1041b390bb7c60742ce79277859e229da61`, which includes merged
[#332](https://github.com/actql/actql/pull/332). That existing implementation
supplies the same-Run atomic transition and computation restoration. The
target-read diff preserves subsequent provider-neutral Source and main work;
there is no unmerged feature dependency.

## Verification and remaining evidence

Focused adapter diagnostics currently establish:

- Three pure-inventory cases: distinct tuples, multiple members of one tuple,
  immutable bindings, changed Site/generation and unresolved Mapping refusal
- Five target-owner cases: sequential approvals, changed binding/submission,
  expired/rejected approval, current denial, foreign tuple and bounded inventory
- Three real gate/SQLite/encrypted-Store/SDK cases: separate read-scope answers,
  service restart, repeated exact signed answer, same Run, rejection and expiry
- The ordinary Checkpoint/Source/Effect-custody selection, including those new
  owner tests: 39 passing cases
- Standard HTTPS Host plus the real installed Site: zero provider calls before
  both target approvals, separate commit approval, restart at each boundary,
  exact rows/column contract, four writes and no final-restart replay
- Rejected/current-denied target reads leave no provider I/O or retained capture
- A real HTTPS response dropped after approval commits is retried after Host
  restart using the SDK's exact signed answer; the result is duplicate, the
  other target still waits, and no provider I/O occurs
- Lost write response after target approval retains durable holdings and does
  not resend on another restart; the existing immediate-read case also passes
- Immediate Host read permits followed by deferred commit obtain new decisions
  on restart; permit completes, while reject or a new unsupported deferral
  fails before I/O and retires the capture through the existing owner
- The credential Site independently refuses foreign generation/origin/revision
  bindings, and cannot turn a target token into query or write permission
- Native and Broad second-Source approval restores the first captured Source
  and reproduces the optional target binding during Effect-commit recovery
- Client acceptance registration/selection checks: 19 passing cases, preserving
  the Source-read and optional-Effect cases

These diagnostics reuse retained runtime artifacts. They are not fresh-packed
or exact-submitted-SHA Core evidence. Full local Core, all-target, proof and
performance campaigns were not run.

The existing packed Salesforce harness now includes an eight-process target
approval case on both Local and HTTPS. Its independent oracle is
[`effect-target-read-approval.expected.json`](../../scripts/fixtures/effect-target-read-approval.expected.json):
two read approvals, separate commit approval, provider read/write counts,
exact Named Result rows and column contract, same request/Run and no replay.
Outer and generated child syntax checks pass. Fresh-packed execution and the
required automatic PR CI remain pending; the feature is not ready to close
#317 until that evidence is available.

## Exact data custody

Submission document and parameter strings, nested JSON strings and opaque
provider bindings use the SDK Host-port value encoder at every target-read
boundary: inventory, approval scope/review, retained continuation, the outer
Effect-commit continuation and recovery comparison. Inventory and scope CIDs
hash the same value-preserving preimage retained for those boundaries. The
credential Site compares the independently supplied opaque binding exactly.
Configuration identity encoders and public contract versions are unchanged.

Existing `/0.1` records have no encoder discriminator. A byte-identical prior
ASCII or NFC record remains admissible; normalization is never a fallback for
a changed submission or binding. The target owner refuses a saved normalized
record that differs from the current original before resume entry. The public
Host still reconstructs admission and compares the resulting RunDefinition
with the original before computation or provider dispatch. Already-lost
original text cannot be recovered or relabeled by this repair.

Regression coverage includes independently ordered inventory/scope preimages,
composed/decomposed text, CR/LF, nested strings, exact encrypted evidence across
separate processes, explicit old-encoder ASCII/NFC/decomposed fixtures, outer
continuation mismatch before authorization, and the real credential Site's
zero-I/O rejection. A source-check guard keeps the three data-envelope modules
from importing the configuration encoder. The public HTTPS test follows
submit, target approval, Host restart, commit approval, another restart,
publication of exact original rows and no replay after the final restart.
These source-checkout cases are separate from fresh-packed and hosted CI
verification. Provider-neutral row/Preview migration is tracked separately in
[#459](https://github.com/actql/actql/pull/459).
