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
#external
priv type OriginalNodeSourceChildSupplier

///|
#module("node:module")
extern "js" fn original_node_source_module_loader(
  url : String,
) -> OriginalNodeSourceModuleLoader = "createRequire"

///|
extern "js" fn original_node_source_module_url() -> String =
  #|() => import.meta.url

///|
// Capture the SAME selected startup once while the actual installed runtime
// initializes. The ordinary Root publishes its table before loading this
// namespace. Never resolve a later table at Source submission, and never
// borrow a preload original for an ordinary installation.
extern "js" fn capture_original_node_source_child_supplier(
  loader : OriginalNodeSourceModuleLoader,
) -> OriginalNodeSourceChildSupplier =
  #|loader => {
  #|  const explicitStartup = process.execArgv.some(value =>
  #|    value === '@actql/node/selected-infer-startup' || value === '@actql/local-node/selected-infer-startup');
  #|  const root = explicitStartup
  #|    ? loader('../../../../../adapters/host-node/infer-trusted-node-preload.cjs')
  #|    : loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs');
  #|  const method = Object.getOwnPropertyDescriptor(root, 'prepareOriginalSourceChildPorts');
  #|  if (method === undefined || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') return () => null;
  #|  const callback = method.value, apply = Reflect.apply;
  #|  return source => apply(callback, root, [source]);
  #|}

///|
let original_node_source_child_supplier : OriginalNodeSourceChildSupplier = capture_original_node_source_child_supplier(
  original_node_source_module_loader(original_node_source_module_url()),
)

///|
extern "js" fn original_node_source_child_ports(
  supplier : OriginalNodeSourceChildSupplier,
  source : OriginalNodeSourceReference,
) -> OriginalNodeSourceChildPorts =
  #|(supplier, source) => supplier(source)

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
  let ports = original_node_source_child_ports(
    original_node_source_child_supplier, source,
  )
  prepare_node_original_child_ports(ports)
}

///|
fn prepare_node_original_child_ports(
  ports : OriginalNodeSourceChildPorts,
) -> Result[ImportedChildLedger, ImportedChildLedgerIssue] {
  if !original_node_source_child_present(ports) {
    return Err(Unavailable)
  }
  prepare_imported_child_port(
    1L,
    _ => original_node_source_child_status(ports, 0),
    _ => original_node_source_child_status(ports, 1),
    (_, ordinal) => original_node_source_child_amount(ports, ordinal),
    (_, _) => -42L,
    (_, usage) => {
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
      )
    },
    _ => original_node_source_child_status(ports, 2),
    fixed_capacities=false,
  )
}
