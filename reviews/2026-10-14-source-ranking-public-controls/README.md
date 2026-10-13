# Installed Source controls for max/weighted ranking

This test-only child depends on the SourceView score-admission change #1930 at
`7454f01b69aec85ee692ddd2f458543f0ceb2842`. The parent submission is unchanged.
It prepares the existing max/weighted completion boundary. It does not implement
an evaluator or establish installed-product execution evidence.

## Inputs and expectations

The original independent control supplies left `{id:1,s:0.5}` and right
`{id:2,s:0.5}`. SourceView facts assert the original unique `id` and field-scoped
Relevance/Identity/[0,1] score `s`. Two distinct original Sources are necessary;
neither is a private captured-local snapshot.

Six normal declarations cover the two adopted policies through JSON, Pipe and
WITH/SQL. Weighted 0.5/0.5 produces scores 0.25; max produces scores 0.5. The tie
order is IDs 1,2 and the full ordered schema is non-null Number id/score/rank.
All these controls acquire each original Source once. The frontend JSON Program
has two connector inputs and therefore two Source reads; physical JSON pages
are a transport encoding, not the source-free Vector JSON control's zero-fetch
qualification. Four static refusals test an undeclared `id` score assertion and
an incompatible normalization for both policies, with zero Source reads.

These declarations are preparation only. Nothing has yet lowered or executed
these texts through the installed product. They do not replace the unchanged
Vector 9717 12+8 acceptance matrix or the already completed RRF cohort.

## Existing installation owner

`source-ranking-installed-source.mjs` uses the normal exported connector table,
RowDeclaration restore, Check Environment, authorization, credential Site,
RowSource and capture owners. The supplier sends only raw 0.5 rows and never
produces ranking results. Original source field order, exact charge ticket,
page admission refusal and cancellation are preserved. Resource-specific read
operations prevent the right Source from inheriting the left operation.

The actual `clientProgramRowSourceDeclarationJson` implementation exposes
Resource/source_ref/view_cid for each declared view. SourceView body array order
is a Catalog identity order, so query aliases match exact `view_cid`, never array
position or ResourceKind. The two Source schemas/facts have independent SHA-256
preimages embedded in the fixture and checked against the original corpus.

## Executed and pending

At fixed `2cdcb9b9569921894ff06571ae0eee39c67314bc`, Node-only `run-EwLVwq`
executed 7/7 cases through the existing 60-second/TERM5 non-Heavy guard. The alias
projection case uses a clearly marked mock declaration with reversed view bodies;
it is not Catalog admission, Runtime or Host acceptance. Raw receipts are retained
in the shared workspace `reviews/2026-10-14-b-source-ranking-score-evidence`.
A subsequent immutable-view-spec change does not inherit this test result as a
new-source pass; its same targeted check remains to be executed.

Public worker/delivery and registry-installed Local/HTTPS execution remain
pending the parent's focused admission/API checks and a separately allocated
normal four-package cohort. No producer, consumer, compiler, Native, Heavy,
real Provider or hosted CI started here. Calendar and the current Vector SQL
publication failure remain separate; this unit does not diagnose either.

## Release delivery preparation

True child `6102532a2acb546e40532cd2dd9aca8ad4256b14` connects the same controls
to the existing installed Client, transport custody, Source installation,
verified-case receipts and attach/resend/lookup hooks. The dedicated worker uses
those existing owners. The four-package consumer retains the normal registry,
clean source, manifest/digest fences and shared 300-second deadline. Original
Vector consumer and G's diagnostic files remain unchanged.

At exact clean 610253, `run-LyJjQY` executed Node 13/13 under the original
non-Heavy 60-second/TERM5 guard: supplier seven plus delivery/audit six. Relative
closure is eight test-only modules; an omitted supplier is independently
rejected. Audit-unit synthetic records detect changed values/schema/order,
additional replay acquisition, incomplete inventory and missing cleanup.
These fabricated records test the auditor only and are not actual Run receipts.
Owner80010/group and own lock are closed. The external exact handoff is
`delivery-preparation-handoff-610253.json` in the shared evidence directory.

Prepared public inventory stays six normal/four static refusals per transport,
12 expected rows and six Named Results per transport, 12 Source page/read/grants
per transport, and zero additional acquisition on reattach/resend/lookup/reread.
`prepared-release-public.mjs --producer|--consumer` preserves ordinary 300/TERM5.
The producer, public worker, registry consumer and Catalog/Runtime admission are
still unexecuted. JSON two-Source runtime support is unverified rather than
assumed from its syntactic representation. The current Vector post-acquisition
publication failure is a separate undetermined failure, not a diagnosis here.

## Explicit authored JSON acquisition boundary

Read-only caller tracing found the prepared one-stage JSON layout did not match
`installed-row-source.mjs:456` -> `prepare_client_query_acquisition` ->
`derive_query_acquisition`: the latter requires an exclusive Source -> Filter ->
Select occurrence, and `prepare_query_sequence` requires its owned two-step
prefix. A direct Source -> ranking edge cannot substitute this acquisition.

True child 360a83987afa8d54cc73352c66a344f03a674644 authors left/right acquisition
Stages explicitly, each with `filter: "true"` (the originally unfiltered extent)
and `select: ["id","s"]`, followed by the original ranking consumer of their
Results. No existing predicate is replaced, no field or Source is discarded,
and no lowering output is patched. Policies, weights, range, k, expected values,
ordered full schema and original two Source acquisitions are unchanged. The old
prepared JSON remains in Git history; it was never product acceptance evidence.

Exact clean360a Node13/13 `run-YklPeP` completed under the same60/TERM5 non-Heavy
recipe, with sourceclean and Owner86445/group/ownlock closure. The two-Source,
three-Stage installed Host path still requires actual admission/runtime evidence;
this shape correction and Node checks do not prove it. No Moon/pack/consumer or
new public E2E ran. External raw handoff: `explicit-acquisition-fixture-handoff-360a83.json`.
