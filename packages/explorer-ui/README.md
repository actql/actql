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
