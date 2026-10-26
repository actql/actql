///|
/// Variable proof ownership for the single Number-Values preparation plan.
/// Fixed GeneratedSequence/cache/limits records are a separate component.
priv struct ClosedValuesPlanProofLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}

///|
fn closed_values_plan_proof_layout(
  fields : Int,
  longest_name : Int,
) -> ClosedValuesPlanProofLayout? {
  if fields < 1 || longest_name < 0 || fields > (2147483647 - 1) / 3 {
    return None
  }
  let f = fields.to_int64()
  let l = longest_name.to_int64()
  // Inventory10 words +closedRows Some; ResultEnvelope5 words; publication
  // rows/schema words and envelope/wire Some. Parent plan's slots are separate.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 6L,
    reference_slots: 3L,
    scalar_words: 10L + 1L + 5L + 2L + 1L + 3L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Schema proof owns seen[owner], rows[Some(count)], empty input_rows; Result
  // identity measurement owns seen[schema] and field_names[F]. Expression slot
  // proof for Values owns an empty collector/result array, no Expression nodes.
  let arrays = closed_values_program_arrays(6L, f + 3L, true)
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + 1L + 1L + 1L + 13L + 2L,
    reference_slots: 1L + 2L + 7L + 4L + 13L,
    scalar_words: 2L + 1L + 6L + 3L + 13L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Flat schema field_at constructs Field + Unqualified + Some. Sum all
  // occurrences: schema proof F, text-free proof F, Result wire proof F,
  // identity emission phases3/5 in both passes4F, name projections3F.
  // The name-only projections are majorized by full Field packets. All names
  // are borrowed on this exact Flat schema; no row/cell/name copy is charged.
  let field_views : @execution.PreparationRepresentationUnits = {
    record_headers: 3L * 10L * f,
    reference_slots: 4L * 10L * f,
    scalar_words: 3L * 10L * f,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Number contract emits exactly {nullable:false,type:"number"}:34 ASCII
  // bytes,3 value nodes, depth1. Root schema adds names/colon/comma/quotes.
  let wire = 2L + f * (l + 38L)
  if wire > 9223372036854775807L / 3L - 71L {
    return None
  }
  guard @encode.hash_writer_construction_inventory(3 * fields + 1, 2)
    is Some(hash) else {
    return None
  }
  // Hash and material writer coexist; hash control also majorizes material
  // writer's frames/maps, but its separate StringBuilder backing is below.
  let writers : @execution.PreparationRepresentationUnits = {
    record_headers: 2L * hash.record_headers,
    reference_slots: 2L * hash.reference_slots,
    scalar_words: 2L * hash.scalar_words,
    owned_utf16_units: 2L * hash.owned_utf16_units,
    owned_wire_bytes: 2L * hash.owned_wire_bytes,
  }
  let material : @execution.PreparationRepresentationUnits = {
    record_headers: 5L,
    reference_slots: 2L,
    scalar_words: 0L,
    owned_utf16_units: 3L * wire + 71L,
    owned_wire_bytes: 0L,
  }
  // One CheckedEmission owns pending<=3, two member tuples and their array,
  // Value/End/Members/Key/Bool/Text tags, sort closure and bounded view wrappers.
  // Sum both passes' F cursors even though each cursor finishes before next.
  let emission_arrays = closed_values_program_arrays(4L * f, 10L * f, true)
  let emission : @execution.PreparationRepresentationUnits = {
    record_headers: 2L * f * (1L + 2L + 8L + 1L + 6L),
    reference_slots: 2L * f * (4L + 4L + 8L + 1L + 6L),
    scalar_words: 2L * f * (3L + 8L + 2L + 12L),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([
      arrays, controls, field_views, writers, material, emission_arrays, emission,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ retained, temporary, })
}
