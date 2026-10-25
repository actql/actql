///|
/// One funded compiler phase on the existing prepared owner. This component is
/// Node JS only; its closed-builder String sharing is pinned to concat backend.
priv struct ClosedValuesCompilationLayout {
  retained : PreparationRepresentationUnits
  temporary : PreparationRepresentationUnits
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_facts : Int
  max_witnesses : Int
}

///|
fn closed_values_compilation_layout(
  facts : ClosedValuesLexicalFacts,
  fields : Int,
  rows : Int,
) -> ClosedValuesCompilationLayout? {
  if fields < 1 ||
    rows < 0 ||
    facts.longest_quoted_utf16 < 0 ||
    facts.quoted_utf16_units < 0 ||
    facts.depth_upper < 0 ||
    facts.depth_upper > 2147483645 {
    return None
  }
  // Original shape inspection proves every row has each exact schema key.
  // ASCII lexical text therefore contains those names at least R+1 times
  // (schema and rows), with unrelated metadata only increasing the numerator.
  // This is a source-derived bound, not a second scan or a shortened name.
  let names = Int64::min(
    fields.to_int64() * facts.longest_quoted_utf16.to_int64(),
    facts.quoted_utf16_units.to_int64() / (rows.to_int64() + 1L),
  )
  if names > 2147483647L {
    return None
  }
  // The one checked Values node is values_0. The existing emitter's literal
  // golden pins this generated identity; user aliases do not replace it.
  let node_id_units = 8
  guard compilation_pipeline_shape(fields, rows, names.to_int(), node_id_units)
    is Some(pipeline) &&
    compilation_fragment_shape(pipeline.facts, node_id_units) is Some(fragment) &&
    closed_values_compilation_metadata_layout(
      fields,
      facts.longest_quoted_utf16,
    )
    is Some(meta) else {
    return None
  }
  let depth = Int::max(9, Int::max(facts.depth_upper + 2, meta.max_depth))
  guard compilation_add_wire_shapes(fragment, meta.graph_extra, 9)
    is Some(graph) &&
    compilation_add_wire_shapes(
      facts,
      meta.material_extra,
      facts.depth_upper + 1,
    )
    is Some(material) &&
    compilation_add_wire_shapes(fragment, facts, depth) is Some(large_plan) &&
    compilation_add_wire_shapes(large_plan, meta.plan_extra, depth)
    is Some(plan) else {
    return None
  }
  let width = Int::max(14, fields)
  guard compilation_parse_layout(pipeline.facts, Int::max(4, fields))
    is Some(aoa_parse) &&
    compilation_parse_layout(fragment, Int::max(6, fields))
    is Some(fragment_parse) &&
    compilation_parse_layout(facts, Int::max(4, fields)) is Some(program_parse) &&
    compilation_parse_layout(material, width) is Some(material_parse) &&
    compilation_parse_layout(graph, width) is Some(graph_parse) else {
    return None
  }
  let contract_bytes = 75L + 38L * fields.to_int64() + 6L * names
  if contract_bytes > 2147483647L {
    return None
  }
  let bytes = Int::max(
    plan.input_bytes,
    Int::max(meta.max_wire_bytes, contract_bytes.to_int()),
  )
  let nodes = Int::max(plan.node_upper, meta.max_nodes)
  guard compilation_artifact_retained_layout(
      plan.input_bytes,
      fragment.input_bytes,
      contract_bytes.to_int(),
    )
    is Some(artifact) &&
    closed_values_sum_layouts([artifact, meta.retained]) is Some(retained) else {
    return None
  }
  // Every parser returns before the next starts. Conservatively retain all
  // five canonical values, even those no longer returned by intermediate parts.
  // Private AST/admission scratch takes a componentwise phase maximum; shared
  // decoded String owners remain in each parse.value, never silently refunded.
  guard closed_values_sum_layouts([
      aoa_parse.value,
      fragment_parse.value,
      program_parse.value,
      material_parse.value,
      graph_parse.value,
    ])
    is Some(canonical_values) else {
    return None
  }
  let parser = compilation_scratch_max(
    compilation_scratch_max(aoa_parse.temporary, fragment_parse.temporary),
    compilation_scratch_max(
      program_parse.temporary,
      compilation_scratch_max(material_parse.temporary, graph_parse.temporary),
    ),
  )
  // Eleven large writer invocations: pipeline measure/text/hash-compare;
  // output contract buffered hash, fragment text, graph text; semantic text,
  // raw/canonical material text; Plan hash/text. Only one has live Map frames.
  // Completed writers keep depth-capacity backing and fixed SHA/control owners.
  // All nine material builder objects persist conservatively, but to_string
  // returns their SAME JS String backing (stringbuilder_concat.mbt).
  guard compilation_writer_ancestry_layout(nodes, depth, width, 1, 1, bytes)
    is Some(active_writer) &&
    closed_values_writer_layout(0, depth, 11, 9, 0) is Some(closed_writers) &&
    compilation_program_emitter_layout(facts, Int::max(4, fields))
    is Some(program_emitter) &&
    compilation_number_contract_emitter_layout() is Some(contract_emitter) &&
    compilation_canonical_emitter_layout(depth) is Some(canonical_emitter) else {
    return None
  }
  let wires : PreparationRepresentationUnits = {
    record_headers: 6L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 2L * pipeline.facts.input_bytes.to_int64() +
    graph.input_bytes.to_int64() +
    facts.input_bytes.to_int64() +
    2L * material.input_bytes.to_int64(),
    owned_wire_bytes: 0L,
  }
  // Exactly one live Number-cell read/emission packet. Sequential rows do not
  // retain Field/Some/Ok/ExpressionFrame owners. The bridge's borrowed artifact
  // relay adds one reference, not another compilation or character owner.
  let cell : PreparationRepresentationUnits = {
    record_headers: 12L,
    reference_slots: 13L,
    scalar_words: 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([
      meta.temporary,
      canonical_values,
      parser,
      active_writer,
      closed_writers,
      wires,
      program_emitter,
      compilation_parts_control_layout(),
      cell,
      contract_emitter,
      canonical_emitter,
      closed_values_compilation_call_controls(),
    ])
    is Some(temporary) else {
    return None
  }
  Some({
    retained,
    temporary,
    max_wire_bytes: bytes,
    max_nodes: nodes,
    max_depth: depth,
    max_facts: meta.max_facts,
    max_witnesses: meta.max_witnesses,
  })
}
