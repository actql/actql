///|
/// Complete source/index phase projection for the fixed ordinary Node JS
/// constructor. Input document backing is a separate owner supplied by caller.
struct ClosedValuesSourcePhaseLayout {
  retained : PreparationRepresentationUnits
  parser_temporary : PreparationRepresentationUnits
  decoder_temporary : PreparationRepresentationUnits
}

///|
fn closed_values_units_subtract(
  left : PreparationRepresentationUnits,right : PreparationRepresentationUnits,
) -> PreparationRepresentationUnits? {
  if right.record_headers<0L || right.reference_slots<0L || right.scalar_words<0L ||
    right.owned_utf16_units<0L || right.owned_wire_bytes<0L ||
    left.record_headers<right.record_headers || left.reference_slots<right.reference_slots ||
    left.scalar_words<right.scalar_words || left.owned_utf16_units<right.owned_utf16_units ||
    left.owned_wire_bytes<right.owned_wire_bytes {return None}
  Some({record_headers:left.record_headers-right.record_headers,
    reference_slots:left.reference_slots-right.reference_slots,
    scalar_words:left.scalar_words-right.scalar_words,
    owned_utf16_units:left.owned_utf16_units-right.owned_utf16_units,
    owned_wire_bytes:left.owned_wire_bytes-right.owned_wire_bytes})
}

///|
/// Span and decoded String backing pass from the source AST into the indexed
/// tree. Charge that shared dependency ONCE in retained, not again as parser
/// scratch. Private AST containers coexist with the growing index. Parser and
/// decoder controls are sequential scopes; caller takes their execution max.
fn closed_values_source_phase_layout(facts : ClosedValuesLexicalFacts) -> ClosedValuesSourcePhaseLayout? {
  let owner=closed_values_source_inventories(facts)
  guard closed_values_units_subtract(owner.source_retained,owner.source_shared_dependencies) is Some(ast_private) else {return None}
  guard closed_values_sum_layouts([owner.source_shared_dependencies,owner.indexed_additional]) is Some(retained) else {return None}
  guard closed_values_sum_layouts([ast_private,owner.source_growth_peak,owner.key_admission_peak,
    owner.parser_ancestry_peak,owner.parser_controls_peak]) is Some(parser_temporary) else {return None}
  guard closed_values_sum_layouts([ast_private,owner.key_admission_peak,
    owner.decoder_ancestry_peak,owner.decoder_controls_peak]) is Some(decoder_temporary) else {return None}
  Some({retained,parser_temporary,decoder_temporary})
}
