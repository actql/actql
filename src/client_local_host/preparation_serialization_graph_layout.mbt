///|
// Use the existing compiler/parser/writer construction units on this exact
// Content constructor geometry. Final graph.wire is a String, not another
// parsed Graph; the JS wire getter remains an alias of that SAME backing.
// Prefix/Result trees remain co-held across construction and failure. Active
// sequential codec scratch is a maximum, never one codec cap per operation.
fn serialization_graph_construction_cost(
  value : @publication_host.ClientSerializationGraphConstruction,
) -> Int64? {
  let held_values = [value.barrier, value.node]
  let active_values = [value.barrier, value.node, value.output_contract]
  let wires = [value.node, value.graph]
  let mut scratch : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  if value.input_contract is Some(contract) {
    active_values.push(contract)
  }
  if value.prefix is Some(prefix) {
    held_values.push(prefix.fragment)
    wires.push(prefix.fragment)
    active_values.push(prefix.initial_pipeline)
    active_values.push(prefix.pipeline)
    active_values.push(prefix.fragment)
    active_values.push(prefix.output_contract)
    for contract in prefix.input_contracts {
      active_values.push(contract)
    }
    guard program_artifact_parse_layout(prefix.initial_pipeline)
      is Some(initial) &&
      program_artifact_parse_layout(prefix.pipeline) is Some(projected) &&
      program_artifact_parse_layout(prefix.fragment) is Some(fragment) &&
      @execution.compose_preparation_representation([
        initial.value,
        projected.value,
        compilation_scratch_max(
          initial.temporary,
          compilation_scratch_max(projected.temporary, fragment.temporary),
        ),
      ])
      is Some(active) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, active)
  }
  if value.input_edge is Some(edge) {
    held_values.push(edge)
    active_values.push(edge)
    wires.push(edge)
  }
  for projection in value.projections {
    held_values.push(projection.node)
    held_values.push(projection.edge)
    active_values.push(projection.pipeline)
    active_values.push(projection.parts)
    active_values.push(projection.node)
    active_values.push(projection.edge)
    wires.push(projection.node)
    wires.push(projection.edge)
    guard program_artifact_parse_layout(projection.pipeline) is Some(pipeline) &&
      program_artifact_parse_layout(projection.parts) is Some(parts) &&
      @execution.compose_preparation_representation([
        pipeline.value,
        compilation_scratch_max(pipeline.temporary, parts.temporary),
      ])
      is Some(active) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, active)
  }
  for root in value.roots {
    held_values.push(root)
    active_values.push(root)
    wires.push(root)
  }
  for plan in value.results {
    active_values.push(plan)
    wires.push(plan)
  }
  let mut held : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  for body in held_values {
    guard program_artifact_parse_layout(body) is Some(parse) &&
      @execution.compose_preparation_representation([held, parse.value])
      is Some(next) else {
      return None
    }
    held = next
  }
  for body in active_values {
    guard program_artifact_parse_layout(body) is Some(parse) &&
      compilation_writer_ancestry_layout(body.1, body.2, body.1, 1, 1, body.0)
      is Some(writer) &&
      compilation_canonical_emitter_layout(body.2) is Some(emitter) &&
      @execution.compose_preparation_representation([writer, emitter])
      is Some(active) else {
      return None
    }
    scratch = compilation_scratch_max(
      scratch,
      compilation_scratch_max(parse.temporary, active),
    )
  }
  // Graph construction emits this final wire but never parses it. Preserve
  // only its real writer/emitter workspace here, not a fictitious Graph tree.
  guard compilation_writer_ancestry_layout(
      value.graph.1,
      value.graph.2,
      value.graph.1,
      1,
      1,
      value.graph.0,
    )
    is Some(writer) &&
    compilation_canonical_emitter_layout(value.graph.2) is Some(emitter) &&
    @execution.compose_preparation_representation([writer, emitter])
    is Some(active) else {
    return None
  }
  scratch = compilation_scratch_max(scratch, active)
  let mut text = 0L
  for body in wires {
    guard @execution.checked_preparation_add_product(
        text,
        body.0.to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
  }
  // Existing separate fragment/contract/result CID Strings and their headers;
  // these are not copies of the already counted JSON String occurrences.
  guard @execution.checked_preparation_add_product(
      text,
      wires.length().to_int64(),
      2L * (7L + 64L),
    )
    is Some(text) &&
    @execution.compose_preparation_representation([
      held,
      scratch,
      {
        record_headers: 3L * wires.length().to_int64(),
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: text,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(peak) else {
    return None
  }
  @execution.preparation_representation_cost(peak)
}

///|
// The selected provenance walk retains borrowed operation/Source originals.
// Only its real collection/key construction is additional to that parent.
fn serialization_policy_collection_cost(
  value : @checked.SerializationPolicyConstruction,
) -> Int64? {
  guard @shape.collection_construction_extent(value.collections) is Some(units) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: units.record_headers,
    reference_slots: units.reference_slots,
    scalar_words: units.scalar_words,
    owned_utf16_units: value.key_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
// Effective policy and response bodies coexist until the original Graph
// issuer returns. Response bodies are emitted/hashed, not parsed. Only the
// effective body enters the existing dependency admission once. Writer/hash
// scratch is sequential; all body Strings remain simultaneously retained.
fn serialization_acquired_policy_body_cost(
  value : @checked.SerializationPolicyConstruction,
) -> Int64? {
  let effective = value.effective
  guard program_artifact_parse_layout(effective) is Some(parse) &&
    @encode.hash_writer_construction_inventory(effective.1, effective.2)
    is Some(hash) &&
    @encode.text_writer_construction_inventory(
      effective.0,
      effective.1,
      effective.2,
    )
    is Some(text) else {
    return None
  }
  let hash : @execution.PreparationRepresentationUnits = {
    record_headers: hash.record_headers,
    reference_slots: hash.reference_slots,
    scalar_words: hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  }
  let text : @execution.PreparationRepresentationUnits = {
    record_headers: text.record_headers,
    reference_slots: text.reference_slots,
    scalar_words: text.scalar_words,
    owned_utf16_units: text.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  let mut temporary = compilation_scratch_max(
    parse.temporary,
    compilation_scratch_max(hash, text),
  )
  let mut strings = effective.0.to_int64()
  if value.response_total is Some(total) {
    strings += total.0.to_int64()
  }
  if value.response_max is Some(maximum) {
    guard @encode.text_writer_construction_inventory(
        maximum.0,
        maximum.1,
        maximum.2,
      )
      is Some(writer) else {
      return None
    }
    temporary = compilation_scratch_max(temporary, {
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
  }
  guard @execution.compose_preparation_representation([
      parse.value,
      temporary,
      {
        record_headers: value.bodies.to_int64(),
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: strings + 71L,
        // One emitted body's original UTF-8 hash input can coexist with all texts.
        owned_wire_bytes: Int::max(
          effective.0,
          match value.response_max {
            None => 0
            Some(value) => value.0
          },
        ).to_int64(),
      },
    ])
    is Some(units) else {
    return None
  }
  @execution.preparation_representation_cost(units)
}
