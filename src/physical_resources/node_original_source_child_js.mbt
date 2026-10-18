///|
#external
type OriginalNodeSourceReference

///|
#external
priv type OriginalNodeSourceModuleLoader

///|
#external
priv type OriginalNodeSourceChildPorts

///|
#module("node:module")
extern "js" fn original_node_source_module_loader(
  url : String,
) -> OriginalNodeSourceModuleLoader = "createRequire"

///|
extern "js" fn original_node_source_module_url() -> String =
  #|() => import.meta.url

///|
// Resolve only the SAME installed private startup. A caller cannot supply a
// module path, callback table, numeric quota or substitute another receiver.
extern "js" fn original_node_source_child_ports(
  loader : OriginalNodeSourceModuleLoader,
  source : OriginalNodeSourceReference,
) -> OriginalNodeSourceChildPorts =
  #|(loader, source) => {
  #|  const root = loader('../../../../../adapters/host-node/infer-trusted-node-preload.cjs');
  #|  const method = Object.getOwnPropertyDescriptor(root, 'prepareOriginalSourceChildPorts');
  #|  if (method === undefined || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') return null;
  #|  return Reflect.apply(method.value, root, [source]);
  #|}

///|
extern "js" fn original_node_source_child_present(
  ports : OriginalNodeSourceChildPorts,
) -> Bool =
  #|ports => ports !== null && ports !== undefined

///|
extern "js" fn original_node_source_child_status(
  ports : OriginalNodeSourceChildPorts,
  operation : Int,
) -> Int =
  #|(ports, operation) => ports.status(operation)

///|
extern "js" fn original_node_source_child_amount(
  ports : OriginalNodeSourceChildPorts,
  ordinal : Int,
) -> Int64 =
  #|(ports, ordinal) => ports.limit(ordinal)

///|
extern "js" fn original_node_source_child_report(
  ports : OriginalNodeSourceChildPorts,
  planning : Int,
  attempts : Int,
  holdings : Int,
  transferred : Int64,
  uncertain : Int64,
  reserved_transfer : Int64,
  held : Int64,
  reserved_retention : Int64,
  reserved_execution : Int64,
  peak_retention : Int64,
) -> Int =
  #|(ports, planning, attempts, holdings, transferred, uncertain, reservedTransfer,
  #|    held, reservedRetention, reservedExecution, peakRetention) =>
  #|  ports.report(planning, attempts, holdings, transferred, uncertain,
  #|    reservedTransfer, held, reservedRetention, reservedExecution, peakRetention)

///|
/// Consume the actual Node Source installation's nominal original once.
/// The fixed startup owns the full same-VM phase, request/occurrence and all
/// external supplier duties. This function creates no parent, reservation,
/// physical allocation, send authority or initial-control conversion.
pub fn prepare_node_original_source_child(
  source : OriginalNodeSourceReference,
) -> Result[ImportedChildLedger, ImportedChildLedgerIssue] {
  let loader = original_node_source_module_loader(original_node_source_module_url())
  let ports = original_node_source_child_ports(loader, source)
  if !original_node_source_child_present(ports) {
    return Err(Unavailable)
  }
  prepare_imported_child_port(
    1L,
    _ => original_node_source_child_status(ports, 0),
    _ => original_node_source_child_status(ports, 1),
    (_, ordinal) => original_node_source_child_amount(ports, ordinal),
    (_, _) => -42L,
    (_, usage) =>
      original_node_source_child_report(
        ports,
        usage.planning_work,
        usage.attempts,
        usage.holdings,
        usage.transferred_bytes,
        usage.uncertain_transfer_bytes,
        usage.reserved_transfer_bytes,
        usage.held_bytes,
        usage.reserved_retention_bytes,
        usage.reserved_execution_bytes,
        usage.peak_retention_bytes,
      ),
    _ => original_node_source_child_status(ports, 2),
    fixed_capacities=false,
  )
}
