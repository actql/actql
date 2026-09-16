///|
/// Read-only facts for one exact receiving column. A returned record is not an
/// issuer capability: consumers must obtain it from their bound read, rather
/// than accept a caller-supplied record as evidence. Depth is a conservative
/// successful admission depth, not a measured exact maximum.
pub(all) struct ManagedColumnMeasurement {
  rows : Int
  bytes : Int
  nodes : Int
  max_value_bytes : Int
  null_rows : Int
  admitted_depth : Int
} derive(Eq, Debug)

///|
/// Finite checked projection/rename/copy only. No row selection is inferred.
/// Logical column indices are translated through the exact receiving view.
pub fn[T] managed_producer_read_column_measurement(
  input : ManagedProducerRead[T],
  column : Int,
) -> ManagedColumnMeasurement? {
  if !managed_producer_read_available(input) {
    return None
  }
  guard input.columns.get(column) is Some(source) else { return None }
  let receipt = input.output.material.receipt
  guard receipt.column_usage.get(source) is Some((bytes, nodes)) &&
    receipt.column_maxima.get(source) is Some(max_value_bytes) &&
    receipt.column_nulls.get(source) is Some(null_rows) else {
    return None
  }
  Some({
    rows: receipt.rows,
    bytes,
    nodes,
    max_value_bytes,
    null_rows,
    admitted_depth: receipt.measured_depth,
  })
}
