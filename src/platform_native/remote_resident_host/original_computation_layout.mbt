///|
/// Trusted Host representation widths. Each width includes the corresponding
/// runtime header/alignment and backing representation. These are installation
/// inputs, not inferred from candidate wire or from a positive byte envelope.
/// This type selects no numeric Native profile.
pub(all) struct ResidentEffectComputationLayout {
  contract_record_bytes : Int64
  canonical_node_bytes : Int64
  string_overhead_bytes : Int64
  utf16_unit_bytes : Int64
  array_record_bytes : Int64
  object_record_bytes : Int64
  array_slot_bytes : Int64
  object_slot_bytes : Int64
  frame_slot_bytes : Int64
  measurement_fixed_bytes : Int64
  capture_control_bytes : Int64
} derive(Eq)

///|
fn original_computation_layout_valid(
  layout : ResidentEffectComputationLayout,
) -> Bool {
  layout.contract_record_bytes > 0L &&
  layout.canonical_node_bytes > 0L &&
  layout.string_overhead_bytes > 0L &&
  layout.utf16_unit_bytes > 0L &&
  layout.array_record_bytes > 0L &&
  layout.object_record_bytes > 0L &&
  layout.array_slot_bytes > 0L &&
  layout.object_slot_bytes > 0L &&
  layout.frame_slot_bytes > 0L &&
  layout.measurement_fixed_bytes > 0L &&
  layout.capture_control_bytes > 0L
}

///|
fn original_computation_add_charge(
  total : Int64,
  count : Int64,
  width : Int64,
) -> Result[Int64, @resources.LedgerIssue] {
  if total < 0L ||
    count < 0L ||
    width <= 0L ||
    count > (9223372036854775807L - total) / width {
    return Err(InvalidCharge)
  }
  Ok(total + count * width)
}

///|
/// Price only facts obtained from the original contract Owner. The capture
/// caller accumulates all six occurrences against the same nominal budget;
/// scratch frames are separately funded before this traversal is entered.
fn original_computation_extent_charge(
  extent : @publication.PublicationRepresentationExtent,
  layout : ResidentEffectComputationLayout,
  already_retained : Int64,
) -> Result[Int64, @resources.LedgerIssue] {
  if !original_computation_layout_valid(layout) {
    return Err(InvalidCharge)
  }
  let mut bytes = already_retained
  for
    (count, width) in [
      (extent.contract_records, layout.contract_record_bytes),
      (extent.contract_strings, layout.string_overhead_bytes),
      (extent.contract_text_utf16_units, layout.utf16_unit_bytes),
      (extent.canonical.nodes, layout.canonical_node_bytes),
      (extent.canonical.strings, layout.string_overhead_bytes),
      (extent.canonical.text_utf16_units, layout.utf16_unit_bytes),
      (extent.canonical.arrays, layout.array_record_bytes),
      (extent.canonical.objects, layout.object_record_bytes),
      (extent.canonical.array_backing_slots, layout.array_slot_bytes),
      (extent.canonical.object_backing_slots, layout.object_slot_bytes),
    ] {
    bytes = match original_computation_add_charge(bytes, count, width) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  Ok(bytes)
}

///|
/// Bound scratch before measuring any original contract. The read-only walker
/// has at most depth+1 live stack entries; pinned Array growth doubles its
/// backing. Charge both old and new backing during growth, plus the current
/// frame and its two pending successors. The fixed Host width also covers the
/// six-reference array, extent/pricing descriptors and array/control headers.
fn original_computation_workspace_charge(
  layout : ResidentEffectComputationLayout,
  max_depth : Int,
) -> Result[Int64, @resources.LedgerIssue] {
  if !original_computation_layout_valid(layout) || max_depth < 0 {
    return Err(InvalidCharge)
  }
  let required = max_depth.to_int64() + 1L
  let mut backing = 8L
  while backing < required {
    backing *= 2L
  }
  original_computation_add_charge(
    layout.measurement_fixed_bytes,
    2L * backing + 3L,
    layout.frame_slot_bytes,
  )
}

///|
fn original_computation_layout_admission(
  capacity : ResidentEffectComputationCapacity,
  max_depth : Int,
) -> Result[Unit, @resources.LedgerIssue] {
  if !original_computation_capacity_valid(capacity) {
    return Err(InvalidCharge)
  }
  if capacity.control_bytes < capacity.layout.capture_control_bytes {
    return Err(RetentionLimit)
  }
  let workspace = match
    original_computation_workspace_charge(capacity.layout, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if capacity.workspace_bytes < workspace {
    return Err(ExecutionLimit)
  }
  Ok(())
}
