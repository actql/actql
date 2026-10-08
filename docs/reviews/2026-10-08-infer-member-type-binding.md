# INFER member binding from the selected ModelTask owner

Date: 2026-10-08. Frontend implementation by B. The broader source-to-common-
Program objective remains open. This change follows the Graph member-binding
branch; it does not implement an inference executor or change Model capture.

## Counterexample

```aql
SELECT DISTINCT 'a' AS id |> EXTEND 'urgent' AS text
|> INFER `model-task:risk-score.v1` ITEM KEY (id)
   INPUT (text = text) KEEP (id) AS assessment
|> SELECT assessment.VALUE.RISK AS risk
```

The fixed ModelTask declares a closed output object with non-null STRING `risk`
and nullable STRING `reason`. INFER publishes its `value` as nullable, following
the common outcome contract. Before this change, lowercase member names passed
ordinary checking but uppercase names remained `VALUE`/`RISK` in the Program.
The Frontend lost the receiver type at INFER. Pre-fix `run-0OA6Xu` recorded the
failing independent expression comparison (0/1 selected test); it did not run a
public Model provider or establish a public Run failure.

## Connection and boundaries

The source preparation bridge passes the exact selected `ModelTasks` owner from
`CheckEnvironment` into `source_frontend.bind_query_context`. The binder rejects
facts from a different published environment. Standard Host admission already
checks these tasks from the same admitted environment wire; this is a Frontend
publication binding, not a new common Model execution restriction or permission.

The member pass checks the already-lowered prefix through the existing
`pipeline_typing.check_carriers`, with that owner and available input type
Carriers. It retains the actual INFER output type before the KEEP/AS projection.
Member spellings follow common closed-object contracts; selector and literal
values are unchanged. Key facts must come from actual prefix operations such as
DISTINCT or assert_rows. ITEM KEY alone never supplies uniqueness evidence.

Successful probes and prefix copies use the existing work accounting. A refused
probe reserves the remaining allowance and stops further probes; ordinary
checking remains responsible for semantic diagnostics. No work limit increases,
guessed output schema, separate evaluator or alternate execution path are added.

External input attachments carry schema types, not existing key witnesses or
Graph producer definitions. Prefixes needing those original owners can still
defer member binding. Completing that metadata coverage remains separate work;
this change does not turn the limitation into a permanent language restriction.

## Independent controls and focused evidence

`src/query_program/infer_member_test.mbt` includes an independently handwritten
complete JSON Program through VALUES, DISTINCT, INFER, object projection and
nullable member projection. It passes ordinary checking and fixes nullable
STRING output contracts plus explicit Result column order `risk`, `reason`.
The contract/schema identities are retained from the existing infer-owner
fixture. Its explicit combined environment CID was calculated independently
from its canonical body, not copied from product output.

Six focused tests cover folded/quoted members, projected receivers, literal
preservation, exact owner retention, wrong environment, unknown task/member,
and absence of a key proof. The JSON fixture was corrected to use the existing
nonempty VALUES schema and derive its string value; internal canonical schema
index order is not mistaken for declared Result column order. Product expected
values and public column order were not weakened.

- `run-KJuBfk`: 13/13 JS across the initial infer, existing Graph member and
  member-work-budget checks.
- `run-eCR86b`: 22/22 JS, selecting `infer_member_test.mbt`, `infer_test.mbt`
  and `source_frontend/lower_test.mbt` through the nonzero bounded wrapper.
- The same invocation regenerated the two affected interfaces with scoped
  `moon info --target js` and passed read-only RelA Node source freshness.
- `git diff --check` and the public fixture's Node syntax check passed.

These checks cover working changes over
`6690ad972299267cdd1c38f6f8911101101d1dce`; they are not clean submitted-HEAD
execution, cross-target evidence, or CI success. Local evidence is retained in
`_build/local-checks/attempts` and `_build/focused-evidence` in the B worktree.

## Public acceptance

The existing deterministic installed ModelTask fixture and common execution
consumer now contain 12 positive cases and 6 preparation refusals. Added cases
exercise folded outcome/value/input_key names, nullable projection, empty input,
failed-provider typed NULL and absence of a key proof. Independent expected rows
and complete Result.describe contracts remain separate from implementation.

Run normal five-package packing from the clean implementation SHA, retain the
manifest and each digest, then run the existing selected consumer:

```sh
node scripts/packed-client-packages.mjs <outside-checkout-directory>
ACTQL_PACKED_CLIENT_PACKAGES=<outside-checkout-directory> \
  node scripts/test-packed-public-query.mjs --infer-source-only
```

The consumer covers Local/HTTPS Named Result rows, declared column order, typed
NULLs, stream completion, reread/resend, and a new-process capture replay with
no additional provider call. Refusals must precede Run admission and provider
I/O. External paid model calls are unnecessary. This selected public execution
is pending; prepared fixtures and successful lowering are not execution proof.
Graph public acceptance, external Graph provenance and the genuine typed
NEAREST Source installation remain separate unfinished obligations.

## First clean-head public attempt and integration

`run-0P1JeG` normally generated all five packages from clean
`29d09ec2028cfd3eac08733bf1205c60b55ae1fc`. Its external manifest retains that
revision and all five SHA-256 digests. The consumer completed its 12 preliminary
profile tests, then the first Local minimal source failed before Host submit:
the old fixture supplied a bare `requestId`, which the current SDK refuses with
`SubmissionReferenceRequired`. No INFER execution or public rows were observed.
The exact stderr is retained in `public-query-evidence-H48Qzo/006.stderr.log`.

The fixture now uses existing `newSubmission`/`lookupSubmission` only. It saves
the original epoch-bound reference before submission, reuses it for resends, and
reads the same retained identity in the new-process capture replay. Confirmed
input refusal checks the common not_accepted outcome/problem, zero accepted Run
records and zero Model calls. No old request-ID fallback is retained.

Main `f299df8092021f3f8fe5d3072a57a512c9dd7872` is adopted through the updated
Graph parent `8ef34a5de5568cbd45cc586900b7af91f4e0ca7f`, merged as
`bd1fadfb26f1dec8c9892517594e4e6d8e633c85`. The conflict combined the INFER
owner/input arguments with the bounded prefix importer; it preserved main's
member scan, copy and receiver work tests. Old package evidence remains tied to
its source revision. Fresh integrated-source public execution is still required.

`run-rLnSRG` passed 36/36 selected JS tests after this integration: INFER member,
existing INFER/binder callers and all retained member-budget controls. RelA Node
source freshness and the updated public fixture's Node syntax check also passed.
This is evidence of the integrated working revision; it does not relabel the
earlier package failure or establish Local/HTTPS rows.
