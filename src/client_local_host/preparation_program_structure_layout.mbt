///|
/// Shared structural decoder recipe. It is neither the source/index owner nor
/// an admission. The same original phase caller supplies those dependencies.
priv struct ProgramStructureInventories {
  retained : @execution.PreparationRepresentationUnits
  containers_peak : @execution.PreparationRepresentationUnits
  carriers_peak : @execution.PreparationRepresentationUnits
  failure_peak : @execution.PreparationRepresentationUnits
}

///|
fn program_structure_units(
  h : Int64,
  r : Int64,
  w : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
/// Only the actual observer's fixed live data packet. Quotation controls are
/// funded separately by the original installed projection recipe, before even
/// this helper is called. The initial owner retains its existing work receipts.
fn program_structure_inspection_units() -> @execution.PreparationRepresentationUnits {
  let observed = @syntax.program_constructor_inspection_extent()
  program_structure_units(
    observed.record_headers,
    observed.reference_slots,
    observed.scalar_words,
  )
}

///|
fn program_structure_base_inventories(
  inventory : @syntax.ProgramConstructorInventory,
  source_depth : Int,
) -> ProgramStructureInventories? {
  guard @syntax.program_constructor_container_extent(inventory)
    is Some(containers) &&
    @syntax.program_constructor_control_extent(inventory) is Some(controls) &&
    @syntax.program_constructor_failure_extent(source_depth) is Some(failure) else {
    return None
  }
  let retained = containers.retained
  guard @execution.compose_preparation_representation([
      program_structure_units(
        controls.record_headers,
        controls.reference_slots,
        controls.scalar_words,
      ),
      program_structure_inspection_units(),
    ])
    is Some(carriers_peak) else {
    return None
  }
  Some({
    retained: program_structure_units(
      retained.record_headers,
      retained.reference_slots,
      retained.scalar_words,
    ),
    containers_peak: program_structure_units(
      containers.record_headers,
      containers.reference_slots,
      containers.scalar_words,
    ),
    carriers_peak,
    failure_peak: program_structure_units(
      failure.record_headers,
      failure.reference_slots,
      failure.scalar_words,
    ),
  })
}

///|
/// General identifier backing, including unchanged input separately owned by
/// the indexed source. Returned normalized text can overlap one normalization
/// workspace. The retained-output arm removes that SAME output from scratch;
/// the temporary-name arm keeps its output. They are sequential alternatives.
/// This recipe does not narrow Source/parameter/step bodies to Values facts.
fn program_structure_generic_inventories(
  inventory : @syntax.ProgramConstructorInventory,
  source_depth : Int,
) -> ProgramStructureInventories? {
  guard program_structure_base_inventories(inventory, source_depth)
    is Some(base) &&
    @canonical.nfc_lf_retained_output_units(inventory.retained_name_input_utf16)
    is Some(utf16) else {
    return None
  }
  let names : @execution.PreparationRepresentationUnits = {
    ..program_structure_units(inventory.retained_name_calls, 0L, 0L),
    owned_utf16_units: utf16,
  }
  let mut retained_scratch = program_structure_units(0L, 0L, 0L)
  let mut temporary_scratch = retained_scratch
  if inventory.retained_name_calls > 0L {
    let value = @canonical.nfc_lf_construction_scratch_extent(
      inventory.max_retained_name_input_utf16,
    ).unwrap()
    retained_scratch = {
      ..program_structure_units(
        value.record_headers,
        value.reference_slots,
        value.scalar_words,
      ),
      owned_utf16_units: value.owned_utf16_units,
    }
  }
  if inventory.normalization_calls > inventory.retained_name_calls {
    let value = @canonical.nfc_lf_construction_extent(
      inventory.max_temporary_name_input_utf16,
    ).unwrap()
    temporary_scratch = {
      ..program_structure_units(
        value.record_headers,
        value.reference_slots,
        value.scalar_words,
      ),
      owned_utf16_units: value.owned_utf16_units,
    }
  }
  // Componentwise maximum is a conservative majorant of the two disjoint
  // calls, not their sum. Each component uses the canonical owner's output.
  let workspace : @execution.PreparationRepresentationUnits = {
    record_headers: Int64::max(
      retained_scratch.record_headers,
      temporary_scratch.record_headers,
    ),
    reference_slots: Int64::max(
      retained_scratch.reference_slots,
      temporary_scratch.reference_slots,
    ),
    scalar_words: Int64::max(
      retained_scratch.scalar_words,
      temporary_scratch.scalar_words,
    ),
    owned_utf16_units: Int64::max(
      retained_scratch.owned_utf16_units,
      temporary_scratch.owned_utf16_units,
    ),
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([base.retained, names])
    is Some(retained) &&
    @execution.compose_preparation_representation([base.containers_peak, names])
    is Some(containers_peak) &&
    @execution.compose_preparation_representation([
      base.carriers_peak,
      workspace,
    ])
    is Some(carriers_peak) else {
    return None
  }
  Some({ ..base, retained, containers_peak, carriers_peak, })
}
