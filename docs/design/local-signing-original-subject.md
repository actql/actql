# Original subject suppliers for Local signing

The normative owner is [Direct Local signing identity metadata](../../spec/contracts/local-signing-credential.md).
This decision clarifies the nominal supplier of existing fields in the initial
Client Local profile. It introduces no identity domain, canonical body change,
permission or new Owner.

`ClientRequestIdentity` separates a LogicalRequestScope from an
IntentFingerprint. The fingerprint binds the checked Program Definition,
effective Parameter Values and admitted caller-input selection. The scope
distinguishes logical requests with equal input meaning. Signing therefore
binds its `request_cid` to the original fingerprint and `request_scope_cid` to
the same original logical scope, with the authenticated Submission scope kept
separately. The submitted-content identity belongs to a different nominal
Owner and cannot be substituted because it also has CID spelling.

The initial Client Local `submission_scope_cid` uses the original retained
reference's existing Submission identity: `native_client_submission_request_id`.
Its `actql-submission-identity/0.1` body binds epoch CID and caller nonce. Two
nonces under one epoch and one nonce under different epochs therefore remain
different submissions. The epoch CID or authority scope alone is too broad;
the logical request scope has a different domain. No extra reference hash is
needed. This selects the previously unspecified Signing field supplier rather
than changing those existing identity laws or historical signed bytes.

Read that reference through the authenticated retained Submission/Run-admission
owner, not from an incoming CID assertion. Keep original request/Run/Checkpoint
control revision and current Client/Reviewer/key checks around observation.
Identity projection after epoch expiry does not renew the epoch or grant
signing permission. Old Resume and Preparation field suppliers remain unchanged.

The existing paired approval/capture custody retains the actual invocation,
checked material owner, Preview and persisted Checkpoint. Its current-fenced
projection supplies the invocation from that retained chain. The authored
Checkpoint RunUnit coordinate selects the UnitDefinition in the same checked
owner. An earlier acquisition/producer unit is permitted; selecting the first
unit instead of the Checkpoint coordinate would bind the wrong computation.

This projection cannot reconstruct a missing capture, borrow a preparation
fence while waiting, recompile an old Program or backfill old journal rows.
Current live custody and durable restoration are distinct. Client RunRead,
Reviewer resolve, signer key authority and issuer issue authority remain
independent checks before and after their own observations; separate Store and
journal reads are not one atomic transaction.

The flat grant schema, field names, CID domain and canonical bytes are
unchanged. Past signed evidence is preserved and cannot be relabeled as new
operational authority. Original claim/outcome/Unknown and cleanup retain their
existing Owners and responsibilities.

## Scope observation boundaries

The Native signing operation carries the same opaque subject read across its
Submission and current callbacks. The private scope reader returns that checked
view; the public Unit facade remains unchanged. A scope assembled entirely from
these current originals does not re-admit its own immutable fields. Adjacent
private helpers reuse the immediately preceding material check only when no
callback or physical/Journal observation intervenes.

After a subject or Submission callback, the complete material check still
compares the original Client RunRead, Reviewer registration, Checkpoint revision
and cancellation state. The final original key projection and noncallback subject
lifetime fence remain after the last callback, including refusal paths. The
initial signing view rechecks material after authority selection and retains the
same subject for the existing transaction fences. No observation is a reusable
permission, a signing grant, a replacement capture or a physical acknowledgement.

The one-shot signer carries that same checked view through its own phases. Each
constructor, confirmed transaction and physical signing boundary rechecks the
complete material and the same subject/receiver lifetimes. After the original
claim COMMIT, subsequent locked checks bind the same actual retained grant/use;
the preclaim view's absent use cannot substitute for it. A separate public
candidate read starts with a fresh complete scope observation. Durable history,
expiry/revocation, cancellation and final locked checks remain independent.

The saved command forwards its actual captured Journal Read into metadata,
authority and Account observations. Only that active Read may reuse its
admitted adoption material; relevant original writes invalidate it, and closing
or leaving the Read refuses further use. A clock callback precedes the next
Read observation. Resident and configured callers retain their independent
full-current path. This is no process-wide cache or replacement Allow.

At the Host locked boundary, the existing helper observes the actual Sign
Account and then the same subject without callbacks. The following immutable
scope comparison consumes that observation instead of repeating every Account
and key callback. Transaction, physical signing, public-entry and final subject
checks remain separate boundaries.

Before application writes, the saved publication constructor uses the original
receipt encoder's byte/node/depth facts and the closed member/row/final receipt
structure. CID text length is not a JSON node count. Its parser, writer, output
and failed-child overlap still acquire backing on the same Read under unchanged
limits; the quote is neither a policy increase nor publication authority.

Saved schema intake retains the existing admitted dependency body, its actual
encoder byte/node/depth facts and object width. The same measured Read parser
cursor feeds canonical admission once; the business constructor backs its
canonical body and carriers before entry. A longer column label changes text
bytes, not structural nodes or field count. The final durable binding borrows
that same opaque body and still checks its kind, schema CID, exact wire, current
limits and original result fields. Callers without that body retain the existing
full schema admission path; independent Store verification is unchanged.

Closed PublicationContract constructors retain their canonical return values
and wires; parser/index/key-normalization scratch remains in their full original
execution peak rather than a second returned Source forest. Each payload stream
allocates at most its actual encoded payload size and the existing 64KiB chunk
maximum; the Read quote uses the same selected chunk size. These are lifetime
and representation correspondences, not a raised Read ticket or a new grant.

The saved file application keeps restoration and response construction on the
same original byte reservation. After its original Ledger view is issued, a
response continuation may grow that reservation only with that exact view in
the same entered business scope. The default constructor retains its pristine,
unclaimed contract. Absolute extents grow monotonically, including actual
response backing and every earlier ACK; attempts, holdings and transfers are
never reset or refunded. The same work record increments an actual completed-ACK
byte counter before fallible child close; startup funds row slots and the current
I/O envelope, not every future row's maximum page. The callback runs outside file locks, followed by the
same current filesystem generation and original logical row-version checks.
Each row's separate attempt reserves its possible transfer bytes in the existing
Ledger's transfer field. Its retained and execution amounts are zero because
the same work entry already holds the complete I/O construction envelope.
Observed and uncertain transfer charges and consumed attempts survive settlement;
the row token neither duplicates that working extent nor refunds its history.
Receipt currentness retains the exact dispatch and reads its original
Submission/Run/Checkpoint inside that Journal's existing transaction. Account,
Reviewer and key checks still run at the original callback boundaries. The
same epoch Owner advances its watermark through that transaction's CAS; only
the outer receipt transaction commits it. No uncommitted successor is cached,
and ordinary lookup still cannot start a nested transaction.
Before a saved file application claims or dispatches a row, it checks the
retained physical Store, namespace and original Read/SQLite route. Publication
borrows that same Store and route; it does not acquire a second exclusive lock
or replace the Store, Database or routing original. The existing publisher
separately binds the same resumed Request, definition and current Account;
observation custody is not publication authority. Pending publication children
retire before the observation owner closes that original Store and its roots.
Missing Store custody cannot initialize another namespace.
The captured Host Journal and publication Store keep their distinct original
Database bindings. The publisher retains the already bound Journal operation
for metadata/current reads, while payload and index work use the Store's own
operation. Only an actual dispatch or original publisher can join that same
Journal transaction for checkpoint/epoch currentness. For the Store commit,
the Journal transaction and cancellation fence remain held while its routing
flight returns; authorization callbacks borrow and return that same Journal
route, then the Store performs its own exchange. The Journal route must reenter
before its outer transaction can commit. Missing return or reentry stays pending
and cannot prove non-publication, authorize a resend or acknowledge cleanup.
The existing retained publisher keeps the actual Store commit result, including
its original error, before attempting Journal reentry. A separate typed routing
issue preserves a failed return/reentry. Neither observation promotes success
through a missing acknowledgement, and another commit is refused; the same
pending publication remains responsible for reconciliation and retirement.
The final Saved Run-state CAS also borrows the same Journal operation from the
actual opaque publication observation's original publisher. Its original
reference/Request join, independent RunRead Account, current publication and CAS
remain in place; Store commit is not a substitute for that acknowledgement.
First acceptance of an Effect Run retains the same original compiler's
prepared invocation and authorization in the existing Journal observation
envelope, alongside its original material packet. The projection validates the
original Effect owner and Run; it creates no Effect-free compilation, policy or
permission. Saved observation uses this retained metadata with its independent
current Read. Already accepted rows without these originals remain unavailable;
restoration and repeated acceptance cannot backfill them from a new compiler.
Terminal Journal Database close explicitly enters its existing cleanup route.
The sibling publication Store may already have selected cleanup on their same
paired Host; an independently healthy Journal routing carrier cannot resume
normal scope after that transition. The original Database close, scope return
and metadata retirement each keep their separate acknowledgements.
The restoration-to-application boundary first retains the composed extent as
data, then enters that same original constructor to acquire usable backing before
resizing its byte token. A Read-side resize alone cannot acquire more business
backing; an unchanged policy ceiling is not an already acquired window.

## Reviewer proof artifacts

Approved Effect Resolutions already require both the same-key signed Approval
Attestation and the signed Resolution. The earlier Local profile described only
the latter preimage supplier; it did not provide an operational entrance for
the former existing obligation. The ReviewerProof purpose now names exactly
these two typed original Checkpoint artifacts. Their separate exact preimages,
original subject/key/current fences, durable grants/uses and consumed work stay
independent. HostAttestation still uses its separate original key and purpose.

The Checkpoint Owner shares the existing closed Approval subject/claim rules
between unsigned preparation and signed Evidence admission. It emits the same
existing attestation/evidence bodies and exposes admitted proof material for
actual same-key cryptographic verification before Host signing. This adds no
sign-any-bytes entrance, caller-supplied preimage or new authority/Owner/Ledger.
Existing Resolution factories and their canonical bytes remain unchanged; old
grant/use history is neither rewritten nor reinterpreted as another preimage.

The initialized Reviewer keeps one original operation for each artifact. Its
completed Effect Approval may precede the single Resolution that binds that
exact signed evidence CID. The storage append accepts this pair only through
the original typed Resolution, the original successful Approval grant/use and
stored signature, and the existing Checkpoint evidence admission. Changing an
operation name, decision, key, preimage or unfinished outcome cannot create a
second original for either artifact. Configured issuer operations keep their
existing exact-preimage rule. Neither successful signature nor Resolution
admission implies a resume claim, applied Effect or final Result.

## Selected operator Host input

Pure Native product assembly accepts an explicitly supplied Host configuration
body and preserves its exact bytes as an additional original. It does not
observe an operator path, create a Host file, prove absence or select a default
from a fresh private Product directory. The physical initializer must retain
the actual public Host selection and its current/custody lifetime before
supplying that body. Explicit signers, including an empty map, cannot select
the initialized default key. The additional original extends only the bounded
configuration inventory; execution, work, retry and memory policy stay with
their existing Owners. Restored installations never regenerate this input.

The Native command selects `~/.config/actql/host.json` or the explicit
`--host-config` path. An explicit path is resolved from the invocation's cwd;
Project configuration does not select it. The existing Adoption owner retains
the actual no-follow Root, file observation and bytes before use. Only an
explicit first initialization may exclusively create an absent default file.
A missing explicit `--host-config` file refuses even during initialization;
only the implicit standard path is created. A missing file on restore refuses.
Existing files are never replaced with the default, including files with an
explicit empty signer map.

The selected configuration manifest binds the operator file's actual
generation and content, rather than the generation of its Product-side copy.
Live current checks use the same operator Root namespace and file observation.
The original command retains partial constructors and the exclusive Writer;
cleanup closes Adoption first, then the operator capture, before returning its
original Read. Closing the capture invalidates retained views and acknowledges
only the original filesystem children, not signing or business completion.

The current Native default installer consumes the absent-policy configuration.
An explicit Account, policy or signer configuration refuses until its own
consumer is connected; it cannot silently choose the initialized default key.
This implementation boundary does not restrict the public Host contract or
make a successful configuration capture an approval/resume proof. The npm
initializer forwards an explicit Host selector unchanged to that same Native
entrance and never reads or creates the authority file itself.

## Continuation after the answer

An acknowledged Approved Resolution advances the Journal revision. The
pre-answer signing scope remains bound to its original revision; continuation
must not overwrite that scope, re-sign or issue another Run to make it current.
The actual signing wrapper may retain a continuation view only from its own
successful Resolution commit. That view keeps the original subject, Client
reference, Reviewer registration, independent Host public-key original and
admitted authentication. It contains no new signing grant or physical ACK.

Before claiming, the existing Host rechecks current Client RunRead, Reviewer
resolve authority, adopted Host/key custody and the same subject lifetime.
The existing Journal readmits the stored Resolution and alone claims/fences
its original intent and generation. This uses the current continuation clock;
the historical verification instant cannot extend approval expiry. Claim entry
is once-only, including failure or Unknown. A returned settlement-only fence
cannot authorize another send.

The saved command backs the view/callback/claim frame in its same original
Read, retains the view before fallible signer close, and returns it only after
that original close acknowledges. Signer retirement does not invalidate the
already admitted answer or grant a mutation. Alias retirement invalidates the
view without changing durable intent, consumed work or physical cleanup duties.
Provider dispatch, response/outcome receipts and final publication remain
separate operations under the same original Journal/Store owners.

The claim retains the same `ResumedApproval` already parsed after signature
admission. A saved UPDATE evaluates the actual target's `effect` tuple, not
the separate realization's `write` tuple. Its original member, Mapping,
installation binding, sealed Preview and current Account/context must match.
The existing decision Owner admits only the verified reviewer's actual claims,
then binds that answer through `bind_dispatch_authorization` at `EffectCommit`.
A claim or `Delegate` alone remains insufficient; denial and changed bindings
still refuse. Whole-set target checks follow claim acquisition before any row
dispatch, and the original generation/lease fence remains before every IO step.
