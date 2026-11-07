# Pipeline ordinary Node runtime input review

The reviewed production source is `c82a8b1eb8eeb69060181e860d3e4a1bc1155bdd`.
Its `node_managed_run_admission_js.mbt` and
`node_original_source_child_js.mbt` capture the original ordinary Node CJS
module through the generated JS module's existing five-parent relative path.
The separate selected-infer startup branch and its preload remain unchanged.

The existing pipeline snapshot omitted
`adapters/host-node/ordinary-node-resource-runtime.cjs`. Consequently its two
source-only mutation workspaces could compile the import while lacking the
actual file required at execution. The complete original CJS is now one literal
snapshot input. Existing materialization copies its independently observed
bytes and executable mode; existing identity, link rejection, restoration and
source-change checks cover that same file. No build output or dependency tree
is copied, and no resource constructor, supplier, callback or permission is
substituted.

The complete inventory module differs only by that literal path in
`snapshotFiles`. Its imports, functions, lazy history reads, current-checkout
validation and all original snapshot roots remain unchanged. Its existing
reviewed digest therefore changes to bind these new bytes; this is not a
waiver for unknown imports, effects or configurations. Session's existing
transitive inventory-helper digest and all refusal rules remain unchanged.

The CJS itself is unchanged. It imports no other modules. At evaluation it
creates its private WeakMap and frozen declaration table; admission and retained
controls remain behind the existing operations and their original identity and
current checks. The new regression loads this actual frozen table from both
copied workspaces without invoking any operation or constructing funding.
Separate changed-file controls require both workspaces to reject altered CJS
bytes at restoration.

This review covers physical source dependency closure. It changes no scientific
mutation, fixed-case expectation, compiler flag, target selection, typed error,
resource limit or authority. It does not establish a mutation kill, image
execution, evidence reuse, normal Host operation or full CI success. The separate
Session image-staging omission remains a distinct requirement.
