# Explorer read model (E0 / initial E1 preparation)

This private package currently contains a finite read model and public SDK read
adapter only. It installs no React viewer, Gateway, launcher, Cloud adapter,
controls, Sample capture or authority. It is not an Explorer release or a Node
release gate. See [the fixed E0 inventory](../../docs/reviews/2026-10-12-explorer-e0.md).

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

The future common UI uses the adopted React/Vite/TanStack/Tailwind/shadcn stack,
with React/Query peers, original-port Flow and exported built CSS. Its installation,
Hono loopback/session security, real build and public read acceptance are still
outstanding. This component fixture acceptance alone cannot establish those.
# Shared read-only Plan component

`@actql/explorer-ui/plan-explorer` exports `PlanExplorer({model, scopeKey})`.
Import `@actql/explorer-ui/styles.css` once in the embedding app. `model` is
the original admitted SDK/read-model projection; `scopeKey` invalidates only
presentation selection and viewport, and is not authority. The adapter must
discard delayed/unauthorized responses before passing a model into the view.

The default keyboard-accessible list and optional React Flow view preserve
original logical IDs, ports, both Join roles and unresolved Stage locators.
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

`npm run build --prefix packages/explorer-ui` produces the ESM component and
CSS. The package's normal `prepack` performs this same build. This is a library,
not a Vite server, a launcher or a second `actql` binary. TanStack adapter/query
integration and Cloud Console route installation are later finite units.

The component tests exercise original-port refusals, bounded maps and actual
React static rendering. They do not establish browser focus/Flow interaction,
current-main Host end-to-end, Cloud installation or Full Explorer acceptance.

