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
fn validate_data_profile(value : DataProfile) -> Bool {
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

///|
// Bounded application policy, not a predicted canonical representation size.
// Two input representations and one output are supplemented by per-import-row
// parameter/type envelopes, INSERT acknowledgements and statement metadata.
// Actual transport is still charged and can reject values exceeding this policy.
fn profile_compute_transfer_capacity(value : DataProfile) -> Int64 {
  value.wire_bytes.to_int64() * 3L +
  value.task_rows.to_int64() * 2L * (value.columns.to_int64() * 128L + 256L) +
  8192L
}

///|
// Completion metadata contains output field names and at most two owned input
// bindings, never one entry per row/value. Data scratch retains its own budget.
fn profile_completion_entries(value : DataProfile) -> Int {
  if value.columns < 2 {
    2
  } else {
    value.columns
  }
}

///|
fn profile_values(value : DataProfile) -> @execution.ValueLimits {
  {
    max_nodes: value.value_nodes,
    max_text_bytes: value.text_bytes,
    max_depth: 100,
    max_work: value.work,
  }
}

///|
fn profile_measurement(
  value : DataProfile,
) -> @execution.FixedInputGuardMeasureLimits {
  {
    max_work: value.work,
    // Fixed Compute measures up to two inputs and one output cumulatively.
    max_bytes: value.wire_bytes * 3,
    max_nodes: value.value_nodes,
    max_depth: 100,
  }
}

///|
fn profile_transport(
  value : DataProfile,
  rows : Int,
) -> @duckdb.TransportColumnLimits {
  // This is a per-frame decoder budget, not a cumulative receipt allowance.
  let batch_rows = if rows < 128 { rows } else { 128 }
  let batch_nodes = (batch_rows + 1) * value.columns + 1
  {
    max_bytes: value.batch_bytes,
    max_nodes: if value.value_nodes < batch_nodes {
      value.value_nodes
    } else {
      batch_nodes
    },
    max_columns: value.columns,
    max_rows: batch_rows,
    max_text_bytes: if value.text_bytes < value.batch_bytes {
      value.text_bytes
    } else {
      value.batch_bytes
    },
  }
}

///|
fn profile_physical(
  value : DataProfile,
  rows : Int,
) -> @duckdb.PhysicalResultLimits {
  {
    max_rows: rows,
    max_cells: rows * value.columns,
    max_nodes: value.value_nodes,
    max_text_bytes: value.text_bytes,
  }
}
