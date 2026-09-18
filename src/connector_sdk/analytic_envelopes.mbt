///|
/// Connector enforcement declaration for one exact analytic occurrence.
/// These are logical checked ceilings, not physical allocation estimates.
pub struct AnalyticEnvelope {
  step : Int
  input_wire_bytes : Int64
  output_wire_bytes : Int64
  partition_wire_bytes : Int64
  frame_memberships : Int64
  output_rows : Int64
}

///|
pub fn analytic_envelope(
  step : Int,
  input_wire_bytes : Int64,
  output_wire_bytes : Int64,
  partition_wire_bytes : Int64,
  frame_memberships : Int64,
  output_rows : Int64,
) -> Result[AnalyticEnvelope, FixedComputeIssue] {
  if step < 0 ||
    input_wire_bytes < 0L ||
    output_wire_bytes < 0L ||
    partition_wire_bytes < 0L ||
    frame_memberships < 0L ||
    output_rows < 0L {
    return Err(InvalidLimits)
  }
  Ok({
    step,
    input_wire_bytes,
    output_wire_bytes,
    partition_wire_bytes,
    frame_memberships,
    output_rows,
  })
}

///|
pub fn analytic_envelope_step(value : AnalyticEnvelope) -> Int {
  value.step
}

///|
pub fn analytic_envelope_input_wire_bytes(value : AnalyticEnvelope) -> Int64 {
  value.input_wire_bytes
}

///|
pub fn analytic_envelope_output_wire_bytes(value : AnalyticEnvelope) -> Int64 {
  value.output_wire_bytes
}

///|
pub fn analytic_envelope_partition_wire_bytes(
  value : AnalyticEnvelope,
) -> Int64 {
  value.partition_wire_bytes
}

///|
pub fn analytic_envelope_frame_memberships(value : AnalyticEnvelope) -> Int64 {
  value.frame_memberships
}

///|
pub fn analytic_envelope_output_rows(value : AnalyticEnvelope) -> Int64 {
  value.output_rows
}

///|
fn snapshot_analytic_envelopes(
  supplied : Array[AnalyticEnvelope],
  step_count : Int,
) -> Array[AnalyticEnvelope]? {
  if step_count < 0 {
    return None
  }
  let snapshot : Array[AnalyticEnvelope] = []
  for value in supplied {
    if value.step < 0 || value.step >= step_count {
      return None
    }
    for previous in snapshot {
      if previous.step == value.step {
        return None
      }
    }
    snapshot.push(value)
  }
  Some(snapshot)
}

///|
fn find_analytic_envelope(
  values : Array[AnalyticEnvelope],
  step : Int,
) -> AnalyticEnvelope? {
  for value in values {
    if value.step == step {
      return Some(value)
    }
  }
  None
}
