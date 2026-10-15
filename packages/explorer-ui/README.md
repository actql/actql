# Shared read-only Explorer UI

This package contains the finite read model, public SDK read adapter and shared
React Plan viewer described below. The separate optional `@actql/explorer`
package supplies the built SPA, Hono Gateway and Local launcher; embedding the
UI library does not open a Host. Cloud route integration, controls and Sample
capture remain unavailable. Read-only Viewer acceptance does not establish Full
Explorer completion or add a gate to the initial Node release.

The [fixed E0 inventory](../../docs/reviews/2026-10-12-explorer-e0.md) records the
earlier read-model-only boundary and its inspected SHAs. Its outstanding UI and
Gateway work is historical, rather than the current package capability list.

Checked-in manifests are private development manifests. The optional
[Explorer release cohort](../../release/explorer-cohort.json) stages exact
package versions and dependency/peer metadata through the existing release
recipe. A verified RC can be installed normally from its fixed distribution;
that does not establish formal registry publication. For the standalone install
and launch interface, see [the Explorer package](../explorer/README.md).

`planReadModel` accepts a static projection already admitted by the SDK. It
preserves original logical occurrences, ports and input roles. Data edges come
only from `logical_output` locators. A `stage_input` remains an unresolved
external locator; no producer, control edge or Source is guessed. Source origins
are unavailable in this projection. The read model references the original
map identity without claiming a newly sealed projection identity.

`readStaticPlan`, `readExistingRun` and `describeExistingResult` call only the
existing public SDK methods. They do not compile a historical Run, submit,
wait, cancel, resume, reconcile, acquire a Source or send an Effect/Model.
Named Result description is metadata; payload delivery and receipt acceptance
remain a later explicit operation. An epoch drops old-scope results and errors;
it grants no permission, substitutes no session or Host control revision, and
never retries an operation.

Presentation is bounded to 256 steps and 1024 ports; overflow refuses the whole
view. It does not truncate a full map under its original CID. Static Plan/inspect
requests cap reads at 65536 bytes / 10000 nodes / depth 64, preserve tighter
caller limits, and leave invalid values to existing SDK admission. These
are view limits, not changes to Host computation or resource ceilings.

## Shared read-only Plan component

`@actql/explorer-ui/plan-explorer` exports `PlanExplorer({model, scopeKey})`.
Import `@actql/explorer-ui/styles.css` once in the embedding app. `model` is
the original admitted SDK/read-model projection; `scopeKey` invalidates only
presentation selection and viewport, and is not authority. The adapter must
discard delayed/unauthorized responses before passing a model into the view.

The default keyboard-accessible list and optional React Flow view preserve
original logical IDs, ports, both Join roles and unresolved Stage locators.
Flow uses ELK.js 0.12.0 in a disposable same-origin browser Worker. Only the
bounded original node/port IDs, port roles and real edges cross that Worker;
labels, Program/parameter text and session information do not. The Worker may
return finite coordinates for the complete original node set only. A five-second
presentation deadline, malformed response or Worker failure leaves Flow
unavailable; List remains available without changing any Host/Run state.
Leaving Flow or changing scope/Plan terminates the original Worker and discards
late replies. Unchanged topology retains placement and the user's viewport.
The embedding app's bundler emits the literal module Worker URL; its CSP must
permit same-origin workers. No blob, external Worker, runtime downloader or
eval exception is required. See [third-party notices](THIRD_PARTY_NOTICES.md).

Positions are presentation only. Static Plan does not have a fabricated Run,
physical timing, source origin or approval/control capability. The component
accepts no Client, endpoint or mutation hooks. Scope/Plan/map changes remount
selection. HTML is rendered as text, without raw HTML or remote image loading.

React/React DOM are peers (`>=19.3.0 <20`), with the embedding app selecting one
runtime. The finite tested dependency cohort follows observed Cloud Console
pins: React 19.3.0, Base UI 1.8.0, Lucide 1.51.0, Vite 8.3.2 and Tailwind 4.3.3.
React Flow 12.12.0 has compatible React peers. UI production dependencies stay
external in the library build; no React copy is bundled. No private Cloud
package is imported. The scoped neutral design tokens follow the existing
Console's Base UI/shadcn direction; global Tailwind preflight is not exported.
The package exports built CSS, so consumers do not scan its Tailwind source.

An SDK-admitted `actql-effectful-static-plan-view/0.1` retains the original
computation ports and renders checked Effect declarations in a separate table.
It does not create graph edges from declaration order. The view labels contract
minima independently from unknown current permission, gates, approval, resolved
targets and changed values; sealed Preview remains unavailable. Unsupported
installed profiles still refuse rather than exposing a computation-only Plan
as a complete Effectful static view.

`npm run build --prefix packages/explorer-ui` produces the ESM component and
CSS. The package's normal `prepack` performs this same build. This is a library,
not a Vite server, a launcher or a second `actql` binary. TanStack adapter/query
integration and Cloud Console route installation are later finite units.

The component tests exercise original-port refusals, bounded maps and actual
React static rendering. They do not establish browser focus/Flow interaction,
current-main Host end-to-end, Cloud installation or Full Explorer acceptance.

## Current Run and Owner observations

`@actql/explorer-ui/run-observation` exports `readRunObservation` and
`runObservationModel`. They retain the exact original Run reference and use
only existing `attach`, `Run.inspect` and one bounded `Run.observeOwners` page
(32 entries per Owner, 65536 bytes per SDK reply). The existing Gateway reply
ceiling still covers the combined presentation. A missing Owner API is
unavailable; malformed, foreign and stale observations refuse. The Run view is
copied into its smaller presentation before awaiting the separate Owner read.
No sample payload, cursor value, new Run, wait, cancellation or Result read is
issued by this projection.

`RunInspector` is exported from the existing `plan-explorer` component entry.
It shows current Run state, original identity, control revision, component
provenance, exact/bound/estimate/unknown quantities and independent per-Result
availability. Quantity values remain original decimal integer strings; there
is no numeric rounding, currency conversion or inferred zero. Run cancellation
acceptance, physical stop and cleanup pending stay separate. History preserves
each Owner's returned ordering, snapshot CID and revision vector; it is not a
global timeline and does not invent timestamps or complete-history coverage.

The current backend has no additional logical-step quantities, INFER counters,
elapsed/tokens/cost or sealed Preview projection. These remain unavailable;
neither a physical unit nor a terminal Run paints every logical step complete.
Null Plan bindings are not repaired from a separately read map or compilation.
The component owns no polling, SDK connection, authentication or execution.
The Local adapter offers explicit one-second read-only following of the same
reference, stops on the first observed terminal state, and clears/discards old
selection or session replies. Each refresh still passes the existing current
SDK/Host and Gateway authorization. Cloud adapters can use this same component
with their own authenticated reads.

