///|
/// Explicit application ceilings, not language defaults or provider estimates.
/// Source scan rows and intermediate Compute rows are intentionally distinct.
pub(all) struct DataProfile {
  source_rows : Int
  task_rows : Int
  columns : Int
  value_bytes : Int
  wire_bytes : Int
  value_nodes : Int
  text_bytes : Int
  work : Int
  entries : Int
  batch_bytes : Int
}

///|
pub fn validate_data_profile(value : DataProfile) -> Bool {
  value.source_rows > 0 &&
  value.task_rows > 0 &&
  value.columns > 0 &&
  value.columns <= 256 &&
  value.value_bytes > 0 &&
  value.wire_bytes > 0 &&
  value.wire_bytes <= 2147483647 / 3 &&
  value.value_nodes > 0 &&
  value.text_bytes > 0 &&
  value.work > 0 &&
  value.entries > 0 &&
  value.batch_bytes > 0 &&
  value.batch_bytes <= value.wire_bytes &&
  value.source_rows <= 2147483647 / value.columns &&
  value.task_rows <= 2147483647 / value.columns - value.source_rows
}
