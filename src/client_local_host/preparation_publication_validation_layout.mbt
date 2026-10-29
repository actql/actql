///|
priv struct ProgramRetainedValidationLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}

///|
/// Plan/Usage/owned input records and serial checker records, conservatively
/// summed despite replacement: Host handle6, Plan5, Usage8, variant1,
/// computation inputs2x11, commit inputs10, computation checker12, commit8,
/// Result inputs5/checker15, artifact3/tuple4/evidence2, binding inputs8/checker8,
/// reference inputs9/checker7, inventory checker7/tuple2/NamedCid2 =21/144.
/// Every field charged as both ref and scalar; this is explicit small slack.
fn program_validation_inventory_layout(
  slots : Int64,
  arrays : Int,
) -> @execution.PreparationRepresentationUnits? {
  if slots < 0L || slots > 2147483647L || (arrays != 2 && arrays != 6) {
    return None
  }
  let copies = closed_values_program_arrays(arrays.to_int64(), slots, false)
  let records : @execution.PreparationRepresentationUnits = {
    record_headers: 21L,
    reference_slots: 144L,
    scalar_words: 144L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Escaping Some links: Host active/plan/checker(3), Core Plan originals/
  // retained(2), computation inputs/retained(2), commit inputs/retained(2).
  // Both checker families are summed conservatively, not claimed concurrent.
  let links : @execution.PreparationRepresentationUnits = {
    record_headers: 9L,
    reference_slots: 9L,
    scalar_words: 9L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let empty_fields = closed_values_program_arrays(1L, 0L, false)
  @execution.compose_preparation_representation([
    copies, records, links, empty_fields,
  ])
}

///|
/// Only for a plan whose SAME original matcher proves retained computation.
/// Result/binding/reference checks borrow canonical bodies; no row parser,
/// ContextHash, normalization, row-copy or new contract serialization occurs.
fn program_retained_validation_layout(
  slots : Int,
  arrays : Int,
  metadata_nodes : Int,
) -> ProgramRetainedValidationLayout? {
  if metadata_nodes < 1 {
    return None
  }
  guard program_validation_inventory_layout(slots.to_int64(), arrays)
    is Some(retained) else {
    return None
  }
  // ResultEvidence owns three growing scalar Bool occurrence-use arrays.
  // Their combined length is <=copied slots, preserving duplicates.
  let flags : @execution.PreparationRepresentationUnits = {
    record_headers: 9L,
    reference_slots: 3L,
    scalar_words: 42L + 3L * slots.to_int64(),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // exact_occurrence_order / exact_derivation_witness / named inventory entry
  // use object_fields detached arrays sequentially. Sum two whole metadata
  // node envelopes conservatively; tuple/canonical children remain borrowed.
  let fields = closed_values_program_arrays(
    2L,
    2L * metadata_nodes.to_int64(),
    true,
  )
  // New diagnostic concatenations are fixed protocol labels, never user text:
  // longest binding prefix+field38, index prefix+field36. Sum both outputs.
  let diagnostics : @execution.PreparationRepresentationUnits = {
    record_headers: 2L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 74L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      flags,
      fields,
      diagnostics,
      program_validation_carrier_layout(),
    ])
    is Some(temporary) &&
    @execution.preparation_representation_cost(retained) is Some(_) &&
    @execution.preparation_representation_cost(temporary) is Some(_) else {
    return None
  }
  Some({ retained, temporary, })
}

///|
/// Source-pinned constructor/call-site SUM for the finite protocol scaffold.
/// The manifest records 901 sites; per site one result wrapper plus at most
/// two four-slot tuple/phase payloads. Loop carriers do not accumulate; retained
/// records and variable arrays are separate. This is not a VM frame inventory.
fn program_validation_carrier_layout() -> @execution.PreparationRepresentationUnits {
  {
    record_headers: 2703L,
    reference_slots: 7208L,
    scalar_words: 7208L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
