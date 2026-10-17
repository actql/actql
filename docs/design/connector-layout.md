# Connector ownership and repository layout

The repository layout must make implementation ownership visible. Connector-
specific planning, execution, transport glue, and foreign interfaces belong to
that Connector. Common scheduling, assembly, and cross-Connector verification
remain outside every Connector tree.

## Owned implementation

The DuckDB implementation uses these roots:

```text
src/connectors/duckdb/
  acquisition/        source acquisition
  adapter/            SQL and physical-value compilation
  compute/            fixed-input Compute support
  driver/             common Host lifecycle integration
  host/               acquisition Host bridge
  host_native/        native Host bridge
  host_node/          Node Host bridge
  adapters/native/    DuckDB-specific native FFI
  conformance/        test-only real-engine fixtures

adapters/connectors/duckdb/node/
  ...                 Node I/O and native DuckDB integration
```

The native FFI is Connector-owned because its ABI, loading rules, and physical
behavior are specific to DuckDB. `src/platform_native/` is reserved for
product-neutral operating-system capabilities such as filesystems, HTTP, and
SQLite access.

The conformance package is deliberately inside the Connector tree so its
subject is clear. It is not a product Host, a public SPI, or a dependency that
product packages may import.

### Meaning and physical transport

Connector-specific meaning belongs to that Connector's MoonBit owner, including
request identity, ResourceRef derivation, response interpretation, page
completion and recovery matching. The foreign adapter performs the selected
physical operation and returns its observation. It retains the original opaque
request and cleanup responsibility instead of reconstructing them from fields.
Static Catalog or Command declarations can remain data; this does not move their
identity or recovery algorithms into an independent host-language implementation.

Moving a representation or digest computation does not change its existing
preimage, refusal behavior, authorization or unknown-outcome semantics. Separate
changes to those contracts require their own semantic decision. Shared
approval, dispatch, reconciliation and accounting remain with the existing
common owners. Adding a Source or Command must not introduce a Connector-local
Run scheduler, retry authority or approval state machine.

Bulk physical conversion can preserve Arrow, file or engine representations
without materializing every value as a MoonBit object. Its schema, absence/NULL,
numeric and encoding rules, order, chunks, EOS, custody and simultaneous copy
bounds must still satisfy the selected contract. See the
[bulk execution resource boundary](implementation-port.md#bulk-execution-resource-boundary)
and [language binding boundary](portable-execution-boundary.md#language-bindings-and-artifact-correspondence).

## Composition and integration

Rebuild-time assemblies remain in `src/connectors_builtin*` and
`adapters/connectors-builtin/`. They select installed Connector contributions
but do not own Connector behavior.

Cross-component verification remains in packages such as
`src/query_integration/`, `src/node_host_conformance/`, and the corresponding
adapter tests. Integration code may depend on Connector implementations;
common Host and scheduler packages may not.

## Enforced boundaries

Repository gates enforce three constraints:

1. Common execution packages have no direct or transitive dependency on a
   package below `src/connectors/`.
2. Product packages do not import conformance packages.
3. A Local-only bundle contains no DuckDB package, Node adapter, native FFI,
   addon, or linked DuckDB library marker.

These constraints apply to future Connectors as well. Adding Salesforce,
Neo4j, or another backend must extend the Connector-owned roots instead of
creating new product-specific top-level platform packages.

## Original Effect selection boundary

UPDATE and `command.target.published_store` use the same existing selection
Owner. Field-target Commands and canonical relation STORE do not acquire this
selection context. Valid mixed occurrences retain their separate original
Stage/Effect/header bindings; equal target strings do not merge purposes.

`run_publication_host/client_effect_target_selections.mbt` and its package-local
original-data projection retain the checked selection, its original prepared
Owner, canonical bytes/CID and saved-material admission. The eight selection
fields and the existing installation preimage have one MoonBit meaning. The
original prepared/allowed/Run readers still bind the independently retained
Compiled Plan and Run Definition, authorization and optional selection presence.
An equal CID, a copied JS array or parsed saved data cannot construct the opaque
selection or replace those original Owners. Existing absent-context identities
and all canonical preimages are unchanged.

The Node adapter observes the actual installed row factory's configuration,
Mapping inventory and generation, converts those facts, and retains their
physical lifetime. Common compares them with the original selection; JavaScript
does not define another selection schema, digest or canonical equality. Current
checks remain before physical work and after asynchronous boundaries. The
private request-journal installation uses the same runtime's bounded DATA
reader, and owner-only recovery returns the original saved admission evidence;
neither path grants disclosure, write, dispatch or retry authority.

The generated private DATA codec snapshots values once and transports JSON. Its
byte/node/depth ceilings come from that same Owner; it has no semantic field list,
normalization, CID or opaque constructor. Public DATA named `$tag`, `_0` or `_1`
is ordinary data here, not a MoonBit compiler representation. Compiler Result and
tuple interpretation uses the existing generated private binding.

The JS projection borrows the same prepared/selection/runtime references for
the projection's lifetime. DATA conversion temporarily overlaps the input,
bounded detached snapshot/keys and encoded wire; Common admission additionally
uses its bounded source/decoder/canonical writer workspace. These are not free
memory, physical retirement ACKs, capacity reservations or a numerical profile.
Releasing references or completing a synchronous comparison makes none of those
claims. The original Run, Store, Checkpoint, Unknown and cleanup responsibilities
stay with their existing Owners.

## Original Content preparation projection

The existing execution-relation export owns the issued Content Reference and
its per-cell inventory. The existing Effect capture owns the exact prepared
computation, captured input pin, member, Command field and local Artifact.
`client_effect_command_content.mbt` joins those originals in a bounded,
read-only projection; a parsed Content envelope, equal wire or CID cannot
reconstruct that occurrence or replace another Run's original input.

That admission must occur before the transient export's normal finally. For a
checked Command with a mapped Content field, the same Common Owner moves the
exact export reference backing into the existing local Artifact. It copies no
rows, Ref values or canonical material. The old receipt loses its bind/reissue
right; immutable schema, logical identity, bytes and CID facts remain unchanged.
Later preparation reads the moved inventory, never a cancelled export receipt
or a newly parsed envelope. The capture retains the Artifact before the move
can invoke a fallible original-current callback.

The projection reads only a declared Content input mapped from an original
Result field. It checks field/work ceilings and original availability, then
rechecks the same input retention after the Reference's Host callback. Its
private constructor and original back-reference reject copied views. The
installed adapter also checks its original installation/current fence before
and after projection. Invalid, foreign, unavailable or retired inputs refuse;
retention alone is not availability or authorization.

A synchronous trusted Command preparation can borrow the same view repeatedly
for one row/input. The capture retains it before further caller callbacks and
retires it through its existing input cleanup, including failure and cancellation
paths. The view, its original record, row/name cache, callbacks, original input,
Artifact and Reference coexist until those references actually retire. Release
cuts the view's back-references only: it is not byte acquisition, physical FD or
transport cleanup, a capacity loan, a Store ACK, a permission or a numerical
profile. The Artifact then revokes and scrubs that same reference backing with
bounded work. An incomplete scrub retains the same Artifact and parent input
pin for cleanup retry; it does not return the input's allowance early. A future
asynchronous child must remain under that same cleanup Owner
before its first await; this projection does not implement or authorize it.

The private Common/RelA bridges are generated from the existing shared bridge
source and use the normal compiler binding. The focused execution-relation,
input-retention and actual installed Host tests distinguish issuer identity,
work exhaustion, callback retirement, copied views and parent cleanup. Their
scope is not physical Content upload, cold recovery or public Provider acceptance.

## Owned guarded request preparation

An installed UPDATE/upsert driver may use the existing `prepareRequestChild`
port when its exact conditional request depends on an authorized target read.
The Host first obtains each member's original target-read decision, then passes
the row index and a zero-argument read-grant supplier closed over that exact
member, Run/dispatch and row. No write authorization is substituted for the
read, and denied reads create no child or provider work.
The existing selected-preparation current assertion is passed through unchanged
for the child's physical pre-send and post-await checks. An absent assertion
does not manufacture currentness; the driver's actual original Site/Scope and
installation obligations remain required.

The same capture retains the original child before method lookup, currentness
checks or asynchronous preparation. The child acquires the target through its
existing physical owner and derives the final request from that original
before observation. Only then does the existing Common request/selector/value
and Preview path admit it. At capture, `observeTargets` projects the same
original before/version; later apply-current reads and recovery keep their
existing independent obligations. An already identified request is not
patched with a newly read condition.

Children, pending prepare/read/close state, request/before aliases and callback
closures remain in the existing bounded capture inventory. Stage cleanup does
not return parent input/Artifact/Source custody before original child retirement.
Current refusal, cancellation and prepare failure drive that same cleanup;
Promise completion or a cancel request is not a physical ACK. This port issues
no capacity or permission. Missing supplier funding remains unavailable.
The existing Command caller omits `rowIndex` and the selected-preparation
`assertCurrent`; its indexed `authorizationForRow` callback is optional. Typed
consumers distinguish these contexts by the presence of `rowIndex`, preserving
the required zero-argument supplier for guarded rows. A Command never receives
a synthetic row index or read grant to satisfy a declaration.

Pure synchronous preparation and the existing Command child path are unchanged;
this connection does not add DELETE to the separate saved-selection domain.
