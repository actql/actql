# NEAREST: common preparation versus installed Host execution

## Recorded boundary

Source inspection is pinned to main
`b7aa6cf21e45a086f32bcb6a480d8dfdde79d24f`. This is a connection report,
not a change to the adopted NEAREST semantics or a claim of public execution.
The [independent JSON control](../../spec/frontend/fixtures/nearest-keep/common-minimal.program.json),
[authored source](../../spec/frontend/fixtures/nearest-keep/kept.ordered.aql),
[expected rows](../../spec/frontend/fixtures/nearest-keep/expected-rows.json) and
[complete column contracts](../../spec/frontend/fixtures/nearest-keep/expected-schema.json)
remain unchanged.

The older [connection report](2026-10-01-nearest-keep-connection.md) records an
object-expression execution gap at its original baseline. Common object/property
lowering now exists. Do not continue treating that historical gap as the reason
to wait, or treat its resolution as completion of NEAREST execution.

| Boundary | Existing entry | Current evidence |
|---|---|---|
| Query scope and KEEP/AS | `query_program.lower_nearest_steps` | Existing source lowers to ordinary producer references, ToVectors, nearest, join-back and object projection; no query-only uniqueness claim |
| Common profile admission | `clientProgramCheckEnvironment` | Explicit VecA selection changes ordinary preparation from `check_unsupported` to a prepared owner in the diagnostic below |
| Ordinary Program preparation | `clientProgramPrepareEffectFreeWithParameters` | The unchanged JSON control checks when VecA is selected |
| Task compilation and official Plan/template issuance | `publicationControl.prepareCheckedClientCompiledRun(prepared, "tasks", policy)` | Issued through the existing compiler in the diagnostic; no separate issuer |
| Standard embedded Host selection | `embedded-local.mjs`, `clientProgramCheckEnvironmentWithPropertyGraphProfile` | Main passes `veca=false`; installed public JSON submission is refused before dispatch |
| Public source input | Host-owned aliases and Source View/schema publication | An execution-capable typed vector input and its exact publication generation must be supplied by the installed Host; this report does not fabricate one |
| Local/HTTP dispatch and Named Result | Existing Client/Host/VecA provider | Not established by the preparation or Plan diagnostic |

An admitted profile is neither execution authorization nor evidence that a
particular installed provider can execute every operation in that profile.
Do not enable the Host flag alone and call that an accepted execution path.

## Bounded installed-runtime diagnostic

These observations use normally packed packages from
`aa24b3f0c36fb643efafcc1a0e3206202db030be`, not newly packed main or this
documentation branch. Main source inspection and old-package execution are
separate evidence. The diagnostic did not modify the package, installed Host,
existing Store or common compiler.

1. Public `connect({mode: "local", ...}).aql(program, {format: "json", ...})`
   refuses the JSON control with `ClientProgramUnsupported` (422).
2. The package's own canonical Check Environment is admitted with all other
   selected profiles held constant. `veca=false` yields `check_unsupported`;
   `veca=true` yields the original prepared owner.
3. That owner is passed to the existing task compiler and compiled-Run issuer.
   Issuance succeeds with Plan identity
   `sha256:44dd5c123f26dec32f78b974f9c927f849af3dc095ad2b72ce799e3c874e34b0`.
   This is a diagnostic policy/context, not a reusable production Plan or
   permission to execute it.

The final two bounded diagnostic wrappers passed, one preparation observation
and one compile/issuance observation, each in less than one second. They do not
run nearest or compare rows. Initial harness attempts passed a noncanonical
environment newline, confused a prepared handle with a preparation outcome,
or used an instant without required milliseconds. Those harness failures are
excluded from product-defect and execution-success claims.

The preparation call shape is:

```js
const environment = moon.clientProgramCheckEnvironment(
  canonicalEnvironmentWire, evidenceBundleCid,
  false, true, true, false, false, false, false);
const outcome = moon.clientProgramPrepareEffectFreeWithParameters(
  programJson, "json", environment, undefined);
const prepared = moon.clientProgramPreparationReady(outcome);
// Preserve this owner. Its handle is not a wire credential.
// The installed Host must separately select capabilities and authorize dispatch.
```

The current ordinary parameter contract explicitly excludes Vector and Ref
declarations (`parameter_binding/identity.mbt`). Do not bypass that contract by
placing a vector in an ordinary parameter, relabeling an array, or interpolating
values into source. Parameter expansion is not required merely to install a
valid typed vector source.

## Connection responsibilities and unchanged acceptance

Ownership update, 2026-10-04: standard Host connection is assigned to **A**.
The independent fixture directory and prepared acceptance consumer below are
handed over unchanged; no new acceptance framework is needed. **B** retains
Frontend resolution/lowering and handles concrete Frontend defects reported
from that connection work. There is no pending C connection artifact or
fixed-SHA handoff for this feature. The recorded probes remain historical
preparation/Plan evidence, not public Local/HTTP execution.
Any actual common VecA provider/Carrier deficiency belongs to its common owner;
it must be demonstrated separately from the present profile refusal. No Host,
kernel, task partitioning, Store or recovery code is changed by this report.

The connection work needed for public acceptance is:

- Installed VecA capability selection tied to the provider's supported contract.
- A typed vector input through the existing public installation and alias
  publication, with source/schema/generation bindings and ordinary read rules.
- The existing compiled task path and Named Result publication, preserving
  capacity, cancellation, captured producer reuse and current authorization.

First execute the unchanged minimal JSON control. Then execute the authored
NEAREST source from installed Local and HTTP Clients, comparing the existing
independent values and complete `Result.describe()` contracts. One query produces
two rows; both must retain the nullable query note and distinct candidate keys.
Query key alone must never become a unique Result key. The ordered source must
return ranks 1 then 2 even though candidate input order is b then a. Internal
join, key and sort slots must remain absent from the Result.

Continue with omitted KEEP, empty input, nullable retained columns, invalid keys,
dimensions, unsupported shapes, same-request resubmission, Result re-reading and
the existing no-reacquisition rules. Refusals must precede Run acceptance and
provider I/O. A JSON success alone does not close the authored-source obligation.
Composite keys and wider CTE/set/JOIN assembly remain separate recorded gaps;
this report neither implements them nor turns them into permanent restrictions.

## Prepared public acceptance consumer

`scripts/fixtures/nearest-public-input.mjs` reads the unchanged independent
fixtures. It prepares five positive cases (JSON control/empty, authored KEEP,
omitted KEEP and empty source) and four source refusals. It calls the existing
public query acceptance driver and checks full descriptions, rows, stream
completion, attach/re-read/resubmit reuse and unchanged counters on refusal.
It does not install a source or alter a Host capability. The cases are prepared
acceptance targets, **not executed public NEAREST evidence**.

After the Host connection unit supplies a real installation, both transports
use the same consumer:

```js
import {connect} from '@actql/node';
import {exerciseNearestPublicInput} from './nearest-public-input.mjs';
await exerciseNearestPublicInput(connect, installedConnectOptions, {
  directory: independentlyAuthoredFixtureDirectory,
  requestPrefix: 'nearest-local', // use a distinct HTTP prefix
  observe: observeExistingRunJournalAndSourceIo,
});
```

Copy the consumer, its existing `public-query-input.mjs` dependency and the
independent `nearest-keep` fixture directory to an external installation.
`queries` and `candidates` must be real published aliases for the input rows and
typed schemas in the JSON fixture, not test-only resolver injections. The
installation must expose nullable `note` and dimension-2 embeddings. No default
source selection, parameter-vector workaround or array-to-vector coercion is
introduced here.

## Local verification of the prepared consumer

The two changed JavaScript files pass `node --check`. Loading the independent
fixtures confirms five positives/four refusals, distinct case names, preserved
empty-input schema, multiset treatment of the un-ordered JSON control and the
independently specified ordered-source ranks. Selected document links and
`git diff --check` pass. These are fixture preparation and syntax checks, not
executed Client or NEAREST tests.

Main was normally merged; the selected Host profile, bridge, parameter contract
and NEAREST lowering/checker files are unchanged between the earlier inspected
main and the integrated main above. No full local Core, packed installation,
proof or performance campaign was run for this handoff. This fixture is not
enabled in the default packed corpus until A supplies the real Host connection.
