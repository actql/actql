///|
/// Actual no-input SourceView/local-input wrappers. This is a component, NOT
/// the complete Context grant. Caller must establish zero ORIGINAL catalog
/// SourceViews and SchemaSnapshots, no carrier facts/pushdown, no parameters,
/// one Stage and one Values Result. Zero declared inputs alone is insufficient.
/// Common call/result/failure carriers belong the separate scaffold component.
fn closed_values_empty_sourceview_layout() -> @execution.PreparationRepresentationUnits? {
  // Nineteen named families in the source-backed inventory; attach_pipeline_inputs
  // is constructed twice. Includes stage_source_refs (not program_references).
  // Forty-eight records include the one Some(position): 73 refs,71 words.
  // Six allocated map/makei closures retain at most four original references
  // each (owner, source, limits, budget); no copied source text is introduced.
  let records : @execution.PreparationRepresentationUnits = {
    record_headers: 48L + 6L,
    reference_slots: 73L + 24L,
    scalar_words: 71L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Explicit arrays33/items28 and Maps21/entries14. Entry distribution is
  // sixteen empty Maps, three Stage-body Maps4, two Stage-index Maps1.
  // Include copied arrays/maps and their growth rather than equality-dedup.
  let arrays = closed_values_program_arrays(33L, 28L, true)
  let maps = closed_values_program_maps(21L, 14L, true)
  @execution.compose_preparation_representation([records, arrays, maps])
}
