///|
/// Ordinary Node JS source-owner storage, kept separate from checked/lowered/compiler owners.
/// Each vector is a logical representation inventory, not a byte allowance.
/// The original document String belongs to the input lease and is NOT repeated.
/// Source spans/decoded Strings shared by the indexed tree are charged once.
priv struct ClosedValuesSourceInventories {
  source_retained : @execution.PreparationRepresentationUnits
  _observed_source_shared_dependencies : @execution.PreparationRepresentationUnits
  source_growth_peak : @execution.PreparationRepresentationUnits
  indexed_additional : @execution.PreparationRepresentationUnits
  key_admission_peak : @execution.PreparationRepresentationUnits
  parser_ancestry_peak : @execution.PreparationRepresentationUnits
  decoder_ancestry_peak : @execution.PreparationRepresentationUnits
  parser_controls_peak : @execution.PreparationRepresentationUnits
  decoder_controls_peak : @execution.PreparationRepresentationUnits
}

///|
/// Construction bound from the original admitted source geometry. All arithmetic is
/// Int64 over Int-bounded disjoint input counts; the shared tariff subsequently
/// checks conversion to the original Ledger's byte dimensions.
///
/// This inventory is JS-only: StringBuilder concatenation uses old/new String
/// overlap. Native UInt16 builder backing needs its own explicit phase proof.
/// These named families are NOT a standalone phase grant: the structural
/// Program decoder, original input lease and fixed Root control envelope must
/// be composed by the same phase plan. Arrays/maps include growth overlap.
fn closed_values_source_inventories(
  facts : ClosedValuesLexicalFacts,
) -> ClosedValuesSourceInventories {
  let nodes = facts.node_upper.to_int64()
  let fields = facts.fields_upper.to_int64()
  let objects = facts.objects.to_int64()
  let arrays = facts.arrays.to_int64()
  let containers = objects + arrays
  let edges = if nodes > 0L { nodes - 1L } else { 0L }
  let depth = facts.depth_upper.to_int64() + 1L
  let quoted = facts.quoted_tokens.to_int64()
  // Node(value,span); payload Value variant; Span(6 scalar coordinates,path);
  // Field(key,key_span,value); decoded String; array wrapper/backing. Value
  // maxima also cover primitive variants; Null uses less than this bound.
  let source_retained : @execution.PreparationRepresentationUnits = {
    record_headers: 3L * nodes + 2L * fields + quoted + 2L * containers,
    reference_slots: 4L * nodes + 4L * fields + 9L * containers + 2L * edges,
    scalar_words: 8L * nodes + 6L * fields + 2L * containers,
    owned_utf16_units: facts.quoted_utf16_units.to_int64(),
    owned_wire_bytes: 0L,
  }
  // Indexed OwnedNode(value,span,parent,edge), OwnedValue, Edge, OwnedField,
  // indexed/child arrays and final Cursor+AdmissionUsage. Spans and strings
  // alias source owners. Child slots conservatively include both edge kinds.
  let indexed_additional : @execution.PreparationRepresentationUnits = {
    record_headers: 2L * nodes + edges + fields + 2L * containers + 4L,
    reference_slots: 6L * nodes +
    2L * edges +
    4L * fields +
    containers +
    8L * objects +
    11L,
    scalar_words: 3L * nodes +
    4L * edges +
    fields +
    2L * containers +
    8L * arrays +
    7L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Parser and decoder KeyAdmission maps are sequential phase dependencies,
  // never summed as simultaneously live. Conservatively allow all authored
  // object keys, including old/new bucket backing during growth. A later
  // ancestry-specific proof may tighten this explicitly recorded slack.
  let key_admission_peak : @execution.PreparationRepresentationUnits = {
    record_headers: 8L * objects + 4L * fields,
    reference_slots: 19L * objects + 11L * fields,
    scalar_words: 21L * objects + 13L * fields,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Per parser ancestry: Frame, Container variant, Point, pending key tuple
  // and Some, PathSegment; two growing reference arrays. One extra level
  // covers the current scalar/string under the deepest container.
  let parser_ancestry_peak : @execution.PreparationRepresentationUnits = {
    record_headers: 6L * depth + 6L,
    reference_slots: 9L * depth + 2L * (12L + 3L * depth) + 2L,
    scalar_words: 9L * depth + 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Decode Work variant retains active ancestry and one current Visit. Its
  // source/edge references borrow prior owners; a growing backing array and
  // simultaneous indexed/child backing replacement are separate storage.
  let decoder_ancestry_peak : @execution.PreparationRepresentationUnits = {
    record_headers: depth + 3L + containers + 1L,
    reference_slots: 3L * depth +
    12L +
    3L * depth +
    1L +
    4L +
    nodes +
    4L * containers +
    edges,
    scalar_words: 4L * depth + 2L + 4L * containers + edges,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Only these source-owned spans and decoded Strings remain anchored by the
  // indexed cursor once parse_program_input returns. AST Node/Field/container
  // owners do not escape that phase; never refund their shared dependencies.
  let source_shared_dependencies : @execution.PreparationRepresentationUnits = {
    record_headers: nodes + fields + quoted,
    reference_slots: nodes + fields,
    scalar_words: 6L * (nodes + fields),
    owned_utf16_units: facts.quoted_utf16_units.to_int64(),
    owned_wire_bytes: 0L,
  }
  let source_growth_peak : @execution.PreparationRepresentationUnits = {
    record_headers: containers,
    reference_slots: 4L * containers + edges,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Fixed parser control records, named by actual constructor family:
  // Parser, ParseLimits, JsonDocument, JsonParse, JsonString, three Points,
  // two noncoexisting builders (conservatively summed), five temporary Strings;
  // string/completion tuples+Some, ParsedSource/Usage, poll/Result, abort/error/
  // location/issue/path carriers. ASCII quick-check creates no NFC payload
  // arrays and no LF replacement; its frame+tagged-return inventory is added.
  let parser_controls_peak : @execution.PreparationRepresentationUnits = {
    record_headers: 1L +
    1L +
    1L +
    1L +
    1L +
    3L +
    2L +
    5L +
    (2L + 1L + 1L + 1L + 1L + 1L + 1L + 1L + 1L + 1L + 1L + 2L + 4L) +
    2L +
    1L +
    6L +
    7L,
    reference_slots: 4L +
    4L +
    1L +
    2L +
    2L +
    (2L + 1L + 1L + 2L + 1L + 1L + 4L + 1L + 1L + 1L + 3L + 2L) +
    1L +
    (8L + 2L * depth) +
    1L +
    10L +
    7L,
    scalar_words: 9L +
    3L +
    1L +
    4L +
    2L +
    9L +
    (2L + 1L + 1L + 3L + 1L + 1L + 1L + 1L + 1L + 1L + 6L) +
    2L +
    6L +
    14L +
    14L,
    owned_utf16_units: 2L * facts.longest_quoted_utf16.to_int64() +
    2L * (facts.longest_atom_utf16.to_int64() + 6L) +
    4L,
    owned_wire_bytes: 0L,
  }
  // Admission, Limits, Utf8Admission and its two Option carriers, poll/Result,
  // failure Issue plus copied path array and freshly constructed path variants.
  // Final Cursor/Usage were already counted in indexed_additional.
  let decoder_controls_peak : @execution.PreparationRepresentationUnits = {
    record_headers: 1L + 1L + 1L + 1L + 1L + 1L + 1L + 1L + 2L + depth,
    reference_slots: 4L + 1L + 1L + 1L + 1L + 2L + 1L + 8L + 2L * depth + depth,
    scalar_words: 5L + 4L + 3L + 1L + 2L + 2L + 1L + 1L + 2L + 2L * depth,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  {
    source_retained,
    _observed_source_shared_dependencies: source_shared_dependencies,
    source_growth_peak,
    indexed_additional,
    key_admission_peak,
    parser_ancestry_peak,
    decoder_ancestry_peak,
    parser_controls_peak,
    decoder_controls_peak,
  }
}
