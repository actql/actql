///|
// Same parser/codec/collection construction owners as the existing compiler.
// Request and barrier trees coexist with all emitted prefix/suffix nodes and
// possible Result projections. Final graph.wire is not parsed by its issuer.
fn model_graph_construction_cost(
  value : @publication_host.ClientInferGraphConstruction,
) -> Int64? {
  let held = [value.request, value.barrier]
  let active = [value.request, value.barrier, value.node, value.output_contract]
  let wires = [value.request, value.graph, value.node]
  if value.lookup is Some((body, node)) {
    // The encoded barrier document and final lookup-node String coexist at
    // node construction, before that node enters the Graph's retained tree.
    active.push(body)
    wires.push(body)
    wires.push(node)
  }
  let mut labels = 0L
  let mut scratch : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  for fragment in value.fragments {
    labels += fragment.node_id.length().to_int64()
    wires.push(fragment.fragment)
    active.push(fragment.initial_pipeline)
    active.push(fragment.pipeline)
    active.push(fragment.fragment)
    active.push(fragment.output_contract)
    for contract in fragment.input_contracts {
      active.push(contract)
    }
    guard program_artifact_parse_layout(fragment.initial_pipeline)
      is Some(initial) &&
      program_artifact_parse_layout(fragment.pipeline) is Some(projected) &&
      program_artifact_parse_layout(fragment.fragment) is Some(body) &&
      @execution.compose_preparation_representation([
        initial.value,
        projected.value,
        compilation_scratch_max(
          initial.temporary,
          compilation_scratch_max(projected.temporary, body.temporary),
        ),
      ])
      is Some(peak) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, peak)
  }
  // Graph arrays retain these parsed originals, including the barrier node.
  for body in value.nodes {
    held.push(body)
    active.push(body)
  }
  for bodies in [value.edges, value.roots] {
    for body in bodies {
      held.push(body)
      active.push(body)
      wires.push(body)
    }
  }
  for projection in value.projections {
    wires.push(projection.node)
    active.push(projection.pipeline)
    active.push(projection.parts)
    guard program_artifact_parse_layout(projection.pipeline) is Some(pipeline) &&
      program_artifact_parse_layout(projection.parts) is Some(parts) &&
      @execution.compose_preparation_representation([
        pipeline.value,
        compilation_scratch_max(pipeline.temporary, parts.temporary),
      ])
      is Some(peak) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, peak)
  }
  for plan in value.results {
    wires.push(plan)
    active.push(plan)
  }
  let mut retained : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  for body in held {
    guard program_artifact_parse_layout(body) is Some(parse) &&
      @execution.compose_preparation_representation([retained, parse.value])
      is Some(next) else {
      return None
    }
    retained = next
  }
  for body in active {
    guard program_artifact_parse_layout(body) is Some(parse) &&
      compilation_writer_ancestry_layout(body.1, body.2, body.1, 1, 1, body.0)
      is Some(writer) &&
      compilation_canonical_emitter_layout(body.2) is Some(emitter) &&
      @execution.compose_preparation_representation([writer, emitter])
      is Some(peak) else {
      return None
    }
    scratch = compilation_scratch_max(
      scratch,
      compilation_scratch_max(parse.temporary, peak),
    )
  }
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
    is Some(peak) else {
    return None
  }
  scratch = compilation_scratch_max(scratch, peak)
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
  guard @execution.checked_preparation_add_product(
      text,
      wires.length().to_int64(),
      2L * 71L,
    )
    is Some(text) &&
    @execution.compose_preparation_representation([
      retained,
      scratch,
      {
        record_headers: 3L * wires.length().to_int64(),
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: text + labels,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(peak) else {
    return None
  }
  @execution.preparation_representation_cost(peak)
}

///|
// The lookup uses the SAME target-provenance collection inventory as Content:
// two actual target walks and the separately retained effective Request fold.
// Each call's full collection bound stays charged; hash writers are sequential
// and only the three generated policy CIDs remain held. No response body is
// encoded/parsed here and no serialization occurrence or capacity is invented.
fn model_keyed_policy_construction_cost(
  value : @checked.SerializationPolicyConstruction,
) -> Int64? {
  guard serialization_policy_collection_cost(value) is Some(collections) &&
    @encode.hash_writer_construction_inventory(
      value.effective.1,
      value.effective.2,
    )
    is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: hash.record_headers + 3L,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units + 3L * 71L,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(writer) else {
    return None
  }
  @execution.checked_preparation_add_product(writer, collections, 3L)
}
