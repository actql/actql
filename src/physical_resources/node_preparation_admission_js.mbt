///|
/// Capture the fixed preparation-purpose supplier at Common initialization.
/// It cannot fall back to already checked Compute or Source-only supply.
let original_node_local_preparation_supplier : OriginalNodeSourceChildSupplier = capture_original_node_managed_run_supplier(
  original_node_source_module_loader(original_node_source_module_url()),
  "prepareOriginalLocalPreparationPorts",
)

///|
/// Retain the unstarted original before any fallible start/take. The fixed
/// ordinary installation supplies this exact input receipt and its admitted
/// initial resource projection; callers cannot construct those ports here.
/// The resulting child is the same one later adopted by the installed Run.
pub fn[I] prepare_node_local_preparation_admission(
  original : OriginalNodeManagedRunReference,
  input : I,
) -> Result[NodePreparationAdmission[I], ImportedChildLedgerIssue] {
  let ports = original_node_managed_run_ports(
    original_node_local_preparation_supplier,
    original,
    original_node_managed_prepared_identity(input),
  )
  prepare_node_original_child_ports(ports).map(child => {
    prepare_node_preparation_original(child, input, () => {
      imported_child_status(abort_original_node_managed_run_unpublished(ports))
    })
  })
}

///|
fn[I] prepare_node_preparation_original(
  child : ImportedChildLedger,
  input : I,
  abort_unpublished : () -> Result[Unit, ImportedChildLedgerIssue],
) -> NodePreparationAdmission[I] {
  {
    admission: Some(
      prepare_node_managed_run_original(
        child,
        input,
        abort_unpublished,
        purpose=LocalPreparation,
      ),
    ),
    transitioning: false,
  }
}
