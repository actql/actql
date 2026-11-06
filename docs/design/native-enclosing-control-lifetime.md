# Native enclosing control lifetime

Request controllers and their original Ledger may outlive the child's physical
Read. They therefore cannot be constructed in that child and then retained by
an outer admission. Moving a usage snapshot does not move the original Ledger.
The enclosing control lifetime uses an ordinary Read context on the same
transferred root allocator, not a second heap, capacity owner, or TLS substitute.

## Admission and representation

The root's original `SharedCapacity` admits one unborrowed control allocation
before creating the context. Each later cohort extends that same allocation,
with its expected current size. A retired, borrowed, foreign or closing claim
cannot be extended. Policy maxima are authorization data; only actually acquired
root backing is available for this claim. If more backing is needed, the existing
same-root growth transaction must acquire it first.

The private construction fact contains a maximum raw managed allocation request
and the total number of allocator requests in a closed cohort. It counts sequential
requests too: failed physical retirement can retain pages after their last managed
aliases disappear. A live-object maximum is insufficient. Earlier cohorts remain
charged until actual context retirement; observed free pages do not recycle credit.

For the closed small-object family, the quote uses the selected allocator's actual
page size, rounding, block/page metadata and slab threshold. Every request must
fit one page including metadata. The quote covers one page per request and one
page for the context. This is a conservative constructor bound, not a payload
ceiling or a conversion of logical representation bytes into Native bytes.

The admitted claim alone is not an activation ACK. Before entry, the same Read
context activates its required empty slabs through the existing owned allocator.
Every slab is registered in the original extent table before the fallible page
protection call. Failed or lost activation acknowledgement retains that exact
extent as pending retirement, even if its contents cannot safely be read. Partial
preparation fences entry and keeps the complete admitted claim until cleanup.

A prepared context consumes a private cumulative constructor-request count and
uses only its already activated slabs. It cannot obtain another page in a
constructor or silently use the ordinary runtime allocator. A new closed cohort
may be activated outside the Read while old aliases remain live. Its count and
claim are added only through the same original control path. These counts are
construction fences, not a standing application quota. Exhausting a certificate
is an implementation error, not a normal resource-refusal mechanism; issuers must
close all success and failure alternatives before a production caller may enter.

The entry port returns a scalar: it cannot allocate a managed Result after
entering the Read but before the quoted cohort begins.

An issuer must establish both complete request multiplicity and the selected
emitted Native layouts, including headers, external-object finalizer slots, array
backings, scalar Options, closures and error paths. Source representation units,
measured successful high-water use, or one observed record layout alone cannot
certify the entire Request constructor family. A changed target, compiler,
runtime or allocator must re-establish its representation proof.

## Explicit scope transitions

Enter the already admitted enclosing root Read only under its original backing
borrow. Leave that Read before leaving the root scope, and leave the root scope
before entering the child. The outer scope refuses to leave while its control
Read is active, preserving both frames for explicit unwind.

The private Request preparation predicate accepts ordinary clear scope, or the
exact enclosing root Read whose original domain/view/loan/extent chain belongs
to the same backing and physical generation. A foreign or inactive root, stale
child, or active child Read is not an enclosing control scope. This observation
neither enters a context nor grants constructor capacity. Nominal validators
still enforce transfer and logical currentness. Cleanup retains its existing
logical-stop/readiness order before the physical-scope observation; this predicate
does not promise that a refused cleanup made no logical progress.

## Retirement and continuation

A logical stop is not physical retirement. The context remains held while any
original managed alias or failed physical cleanup is outstanding. Its original
control claim is released only after the actual context ACK, and root mappings
close afterward. Partial context preparation stays reachable through the same
Host and backing. Empty unused slabs are retired too. A failed retirement is
retried on its original extent; no live count or cancellation fabricates the
physical ACK.

A partially failed extension can still have earlier live aliases. Their release
uses original provenance without entering another allocator, so it remains
available while new construction is fenced. A caller whose logical abort needs
additional constructors must certify and acquire that cleanup family before its
fallible phase, or end its context after those aliases are released. The private
mechanism does not yet establish that full Common Request continuation contract.

Host-retained wrapper or array references allocated in this context need an
explicit child-first retirement order. Completed internal child references can
be dropped only after their original physical and logical retirement; escaped
aliases must continue to block context close. Clearing references to hide a live
child, replacing the original Ledger, or copying an admission is not cleanup.

Every subsequent constructor cohort requires its own complete acquisition before
entry. The initial prefix does not authorize arbitrary later constructors or
impose a permanent Request limit. Canonical reservation/resize continues to own
the logical request; a Native physical supplier must retain that same original
association and satisfy its contiguous construction demand before acknowledging
growth. Aggregate free-byte observations alone do not prove that demand fits.

## Working-origin physical custody

The private working-origin carrier retains both the external root/extent chain
and the nominal Resource capacity, allocation and owner-borrow references. These
references preserve custody; their presence does not authenticate a Resource
association. A typed Common issuer must establish that association before using
this physical prerequisite. No public FFI, child admission or growth operation
is provided by the carrier alone.

Selection requires the exact entered root control Read and an unborrowed private
local-domain allocation. Its external-object size comes from the selected C and
Moon runtime layouts. The current cohort must cover that entire request before
construction. Selection is one-shot, including after revocation; an already-lent
ordinary allocation cannot be retrofitted.

Binding retains the complete original loan/view/domain graph before fallible
physical validation. Foreign graph inputs do not consume the bind; an attempted
bind with its own graph is not retried after refusal. The physical snapshot
requires the same process and observation thread, root generation, whole local
exclusive view and inactive child. Neither a matching byte amount nor an equal
recipe replaces those original identities.

Explicit revocation waits for the retained physical domain slot to be null and
its view's domain-live obligation to be cleared by actual domain retirement.
Revocation disables the carrier before releasing strong references. It returns
no Resource borrow, view, loan, allocation or mapping credit. Escaped carrier
aliases remain ordinary root Read aliases until their own last release. A
finalizer never supplies a physical retirement acknowledgment.
