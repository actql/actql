///|
/// Host-private capacity allowances for the existing bounded row executor, not
/// measured heap/RSS or a replacement for any selected logical budget.
pub struct ExecutionCapacity {
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
pub fn generated_sequence_capacity(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  measurement : FixedInputGuardMeasureLimits,
) -> ExecutionCapacity? {
  let rows = limits.rows
  let retention_nodes = [
    rows.retained_entries,
    rows.metadata_entries,
    rows.output_values.max_nodes,
  ]
  let scratch_nodes = [
    rows.operation_entries,
    rows.metadata_entries,
    limits.max_frames,
    rows.input_values.max_nodes,
    rows.output_values.max_nodes,
    measurement.max_nodes,
    measurement.max_depth,
  ]
  let scratch_text = [
    rows.input_values.max_text_bytes,
    rows.output_values.max_text_bytes,
    measurement.max_bytes,
  ]
  let mut retained = 0L
  let mut scratch = 0L
  for count in retention_nodes {
    if count < 0 {
      return None
    }
    retained += count.to_int64() * 256L
  }
  if rows.output_values.max_text_bytes < 0 {
    return None
  }
  retained += rows.output_values.max_text_bytes.to_int64() * 8L
  for count in scratch_nodes {
    if count < 0 {
      return None
    }
    scratch += count.to_int64() * 256L
  }
  for count in scratch_text {
    if count < 0 {
      return None
    }
    scratch += count.to_int64() * 8L
  }
  // Fragments execute serially; their selected live-value and physical traversal
  // ceilings bound the transient frame/root allowance. Never lower those ceilings
  // to manufacture a fitting candidate, or use elapsed time as logical work.
  let mut fragment_peak = 0L
  for context in generated.contexts {
    let live = context.limits.max_live_value_bytes
    let physical = context.physical
    if live < 0L ||
      live > 9223372036854775807L / 264L ||
      physical.max_body_nodes < 0 ||
      physical.max_body_bytes < 0 ||
      physical.max_body_depth < 0 {
      return None
    }
    let traversal = (
        physical.max_body_nodes.to_int64() + physical.max_body_depth.to_int64()
      ) *
      256L +
      physical.max_body_bytes.to_int64() * 8L
    let roots = live * 264L
    if roots > 9223372036854775807L - traversal {
      return None
    }
    let required = roots + traversal
    if required > fragment_peak {
      fragment_peak = required
    }
  }
  if fragment_peak > 9223372036854775807L - scratch {
    return None
  }
  Some({ retained_bytes: retained, execution_bytes: scratch + fragment_peak, })
}
