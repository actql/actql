///|
#external
type OriginalNodeManagedRunReference

///|
#external
priv type OriginalNodeManagedPreparedIdentity

///|
// JS-only ABI erasure for reference comparison in the fixed installed Root.
// This private representation has no constructor/export/admission semantics.
// The typed P itself remains retained below; only the Root's exact pointer
// comparison can accept it, never a field, CID, callback or scalar value.
fn[P] original_node_managed_prepared_identity(
  prepared : P,
) -> OriginalNodeManagedPreparedIdentity = "%identity"

///|
/// This callback has a distinct purpose from the Source-only child supplier.
/// Capture it from the same selected ordinary/preload original at Common
/// initialization. Missing operation stays unavailable; there is no fallback
/// to Source ports, scalar limits or a later callback table.
extern "js" fn capture_original_node_managed_run_supplier(
  loader : OriginalNodeSourceModuleLoader,
  operation : String,
) -> OriginalNodeSourceChildSupplier =
  #|(loader, operation) => {
  #|  const ordinary = process.execArgv.length === 0 && process.env.NODE_OPTIONS === undefined;
  #|  const root = ordinary
  #|    ? loader('../../../../../adapters/host-node/node-public-initial-control-bootstrap.cjs')
  #|    : loader('../../../../../adapters/host-node/infer-trusted-node-preload.cjs');
  #|  const method = Object.getOwnPropertyDescriptor(root, operation);
  #|  if (method === undefined || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') return () => null;
  #|  const callback = method.value, apply = Reflect.apply;
  #|  return (original, prepared) => apply(callback, root, [original, prepared]);
  #|}

///|
let original_node_managed_run_supplier : OriginalNodeSourceChildSupplier = capture_original_node_managed_run_supplier(
  original_node_source_module_loader(original_node_source_module_url()),
  "prepareOriginalManagedRunPorts",
)

///|
// A distinct fixed operation is required even though it uses the same Run
// original and imported-child ABI. Missing Model supply cannot fall back to
// the Source/Compute callback captured above, before or after initialization.
let original_node_local_mock_model_run_supplier : OriginalNodeSourceChildSupplier = capture_original_node_managed_run_supplier(
  original_node_source_module_loader(original_node_source_module_url()),
  "prepareOriginalLocalMockModelRunPorts",
)

///|
extern "js" fn original_node_managed_run_ports(
  supplier : OriginalNodeSourceChildSupplier,
  original : OriginalNodeManagedRunReference,
  prepared : OriginalNodeManagedPreparedIdentity,
) -> OriginalNodeSourceChildPorts =
  #|(supplier, original, prepared) => supplier(original, prepared)

///|
extern "js" fn abort_original_node_managed_run_unpublished(
  ports : OriginalNodeSourceChildPorts,
) -> Int =
  #|ports => ports.cancelUnpublished()

///|
/// Return the unstarted admission first: the same Host must retain it before
/// any fallible start/take. Only the actual fixed Node installer can recognize
/// this run original, its purpose and its complete pre-admitted joint recipe.
pub fn[P] prepare_node_managed_run_admission(
  original : OriginalNodeManagedRunReference,
  prepared : P,
) -> Result[NodeManagedRunAdmission[P], ImportedChildLedgerIssue] {
  let ports = original_node_managed_run_ports(
    original_node_managed_run_supplier,
    original,
    original_node_managed_prepared_identity(prepared),
  )
  prepare_node_original_child_ports(ports).map(child => {
    prepare_node_managed_run_original(child, prepared, () => {
      imported_child_status(abort_original_node_managed_run_unpublished(ports))
    })
  })
}

///|
/// The actual selected installation must have admitted its separate finite
/// local-Mock purpose before this fixed callback can return original ports.
/// This entry cannot issue that service from a caller value, limits or Ledger.
pub fn[P] prepare_node_local_mock_model_run_admission(
  original : OriginalNodeManagedRunReference,
  prepared : P,
) -> Result[NodeManagedRunAdmission[P], ImportedChildLedgerIssue] {
  let ports = original_node_managed_run_ports(
    original_node_local_mock_model_run_supplier,
    original,
    original_node_managed_prepared_identity(prepared),
  )
  prepare_node_original_child_ports(ports).map(child => {
    prepare_node_managed_run_original(
      child,
      prepared,
      () => {
        imported_child_status(
          abort_original_node_managed_run_unpublished(ports),
        )
      },
      purpose=LocalMockModel,
    )
  })
}
