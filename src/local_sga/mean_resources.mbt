///|
/// Installed realization limits, not authored mean semantics. Exact work is
/// the cumulative number of calls to the existing exact reduction primitives;
/// coefficient bits bound each primitive's atomic input and scratch growth.
pub(all) struct MeanLimits {
  max_samples : Int
  max_exact_operations : Int
  max_coefficient_bits : Int
  max_temporary_bytes : Int
} derive(Eq, Debug)

///|
/// Private reservation retained by the execution owner until stopped cleanup.
/// Slots and bytes are the selected logical quantities, not a compiler heap
/// theorem. External input generations remain reserved by their existing
/// producer/consumer owners and are not replaced by this output reservation.
struct MeanReservation {
  output_limits : @storage.Limits
  scratch_slots : Int
  scratch_bytes : Int
  exact_operations : Int
  coefficient_bits : Int
}

///|
pub(all) enum MeanResourceIssue {
  InvalidMeanLimits
  MeanSampleLimit
  MeanTemporaryLimit
  MeanWorkspaceLimit
} derive(Eq, Debug)

///|
pub fn mean_limits_valid(profile : MeanLimits) -> Bool {
  profile.max_samples >= 1 &&
  profile.max_exact_operations >= 0 &&
  profile.max_coefficient_bits >= 1 &&
  profile.max_coefficient_bits <= 8192 &&
  profile.max_temporary_bytes >= 0
}

///|
/// Reserve all simultaneous private roots before reading a sample. The output
/// Store subsequently enforces the remainder, including retained record/key
/// growth, value traffic and bounded append work. No meter resets by field.
pub fn prepare_mean_reservation(
  checked : @graph_type.CheckedMean,
  limits : @storage.Limits,
  profile : MeanLimits,
) -> Result[MeanReservation, MeanResourceIssue] {
  if !mean_limits_valid(profile) {
    return Err(InvalidMeanLimits)
  }
  let samples = @graph_type.mean_sample_count(
    @graph_type.checked_mean_options(checked),
  )
  if samples > profile.max_samples {
    return Err(MeanSampleLimit)
  }
  guard @graph_type.mean_output(checked) is @carrier.GraphValue(graph) &&
    @storage.graph_snapshot_append_workspace_slots(graph, limits)
    is Some(append) else {
    return Err(InvalidMeanLimits)
  }
  // One occurrence-position entry and one retained borrowed input reference
  // per sample; one canonical token reference per possible retained node.
  // Equality/recheck frames retain up to two values, measured under the
  // installed value-node/depth quotas. Append owns its separate staging.
  let slots = append.to_int64() +
    2L * samples.to_int64() +
    limits.max_nodes.to_int64() +
    16L * limits.max_value_nodes.to_int64() +
    8L * limits.max_value_depth.to_int64() +
    64L
  if slots > limits.max_workspace_slots.to_int64() || slots > 2147483647L {
    return Err(MeanWorkspaceLimit)
  }
  // The exact owner keeps total/present support and one numerator/denominator.
  // Sixteen coefficient-sized units cover these roots and the simultaneously
  // live add/multiply/shift/divide operands and results; an extra bit permits
  // the rejected carry/doubled remainder. This selected quantity is a bit-byte
  // envelope, not allocator overhead. Keys already owned by immutable input
  // and output storage are references, not newly serialized private copies.
  let coefficient_bytes = (profile.max_coefficient_bits.to_int64() + 8L) / 8L
  let bytes = 16L * coefficient_bytes + 2L * limits.max_value_bytes.to_int64()
  if bytes > profile.max_temporary_bytes.to_int64() || bytes > 2147483647L {
    return Err(MeanTemporaryLimit)
  }
  // Private temporary bytes have their own installed ceiling and must be
  // included in provider capacity. They do not consume or enlarge the output
  // Store's retained-value quota; both coexist until stopped cleanup.
  Ok({
    output_limits: {
      ..limits,
      max_workspace_slots: limits.max_workspace_slots - slots.to_int(),
    },
    scratch_slots: slots.to_int(),
    scratch_bytes: bytes.to_int(),
    exact_operations: profile.max_exact_operations,
    coefficient_bits: profile.max_coefficient_bits,
  })
}

///|
pub fn mean_reserved_output_limits(value : MeanReservation) -> @storage.Limits {
  value.output_limits
}

///|
pub fn mean_reserved_scratch_slots(value : MeanReservation) -> Int {
  value.scratch_slots
}

///|
pub fn mean_reserved_scratch_bytes(value : MeanReservation) -> Int {
  value.scratch_bytes
}

///|
fn mean_reserved_arithmetic(value : MeanReservation) -> MeanArithmeticBudget {
  { max_bits: value.coefficient_bits, remaining: value.exact_operations, }
}
