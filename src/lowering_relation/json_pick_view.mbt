///|
/// Read-only view of the exact prepared kernel's path. The mutable array never
/// crosses this boundary; indexed access borrows immutable segment spellings.
struct PreparedJsonPick {
  column : @schema.FieldName
  path : Array[String]
  output : String
}

///|
/// Constant-size dispatch inspection; unlike kernel_body this does not copy
/// the complete path before bounded execution can observe cancellation.
pub fn kernel_json_pick(kernel : PreparedKernel) -> PreparedJsonPick? {
  match kernel.body {
    JsonPick(column, path, output) => Some({ column, path, output, })
    _ => None
  }
}

///|
pub fn json_pick_column(value : PreparedJsonPick) -> @schema.FieldName {
  value.column
}

///|
pub fn json_pick_output(value : PreparedJsonPick) -> String {
  value.output
}

///|
pub fn json_pick_path_count(value : PreparedJsonPick) -> Int {
  value.path.length()
}

///|
pub fn json_pick_path_at(value : PreparedJsonPick, index : Int) -> String? {
  value.path.get(index)
}
