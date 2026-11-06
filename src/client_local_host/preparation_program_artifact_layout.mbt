///|
// The generic compiler emits Unicode JSON data, then parses it preserving
// data keys. It must not borrow the old numeric/ASCII lexical eligibility.
// Codec geometry bounds every container by nodes and fields by nodes-1; the
// original parser still enforces its actual admitted codec, never this shape.
fn program_artifact_parse_layout(
  geometry : (Int, Int, Int),
) -> CompilationParseLayout? {
  let (bytes, nodes, depth) = geometry
  if bytes < 1 || nodes < 1 || depth < 0 {
    return None
  }
  guard @source.json_literal_construction_extent(
      bytes,
      nodes,
      Int::max(1, depth),
    )
    is Some(source) &&
    compilation_canonical_layout({
      nodes,
      arrays: 0,
      objects: nodes,
      fields: nodes - 1,
      depth,
      largest_object: nodes - 1,
    })
    is Some(canonical) &&
    @source.json_index_borrowed_construction_extent(
      nodes,
      nodes - 1,
      bytes.to_int64(),
      keep_spans=false,
    )
    is Some(text) else {
    return None
  }
  let strings : @execution.PreparationRepresentationUnits = {
    record_headers: text.record_headers,
    reference_slots: text.reference_slots,
    scalar_words: text.scalar_words,
    owned_utf16_units: text.owned_utf16_units,
    owned_wire_bytes: 0L,
  }
  let parser : @execution.PreparationRepresentationUnits = {
    record_headers: source.record_headers,
    reference_slots: source.reference_slots,
    scalar_words: source.scalar_words,
    owned_utf16_units: source.owned_utf16_units,
    owned_wire_bytes: bytes.to_int64(),
  }
  // parse_plan_identity_value encodes the original String, then parse-bytes
  // owns its decoded document. The literal constructor already includes the
  // latter's text/tree. The former wire backing is independently live here.
  guard @execution.compose_preparation_representation([canonical.tree, strings])
    is Some(value) &&
    @execution.compose_preparation_representation([
      parser,
      canonical.tree,
      canonical.temporary,
    ])
    is Some(temporary) else {
    return None
  }
  Some({ value, temporary, })
}

///|
// Input-derived compiler construction envelope, not a policy allowance or a
// minimum. Keep the actual wires and canonical values conservatively until
// the constructor returns. Sequential parser/writer scratch uses a maximum,
// not the sum of every per-task parser limit. No codec maximum is multiplied
// by task count and no fixed controller/wrapper census is introduced.
fn program_artifact_construction_extents(
  value : @publication_host.ClientPureCompilationConstruction,
) -> (Int64, Int64)? {
  let bounded = (geometry : (Int, Int, Int)) => {
    (
      Int::min(geometry.0, value.limits.max_wire_bytes),
      Int::min(geometry.1, value.limits.max_nodes),
      Int::min(geometry.2, value.limits.max_depth),
    )
  }
  // Fragment nodes/Result projection values are contained in the completed
  // graph. Its canonical envelope covers their simultaneously held trees;
  // do not multiply full initial pipeline trees by the number of tasks.
  let held_values = [value.graph, value.material]
  for input in value.borrowed_inputs {
    held_values.push(input)
  }
  let active_values : Array[(Int, Int, Int)] = []
  let wires : Array[(Int, Int, Int)] = []
  for input in value.borrowed_inputs {
    active_values.push(input)
  }
  for fragment in value.fragments {
    active_values.push(fragment.initial_pipeline)
    active_values.push(fragment.pipeline)
    active_values.push(fragment.fragment)
    // Task graph construction retains Fragment records until its writer
    // returns, whereas initial/projected pipeline text is local to one task.
    wires.push(fragment.fragment)
    for contract in fragment.input_contracts {
      active_values.push(contract)
    }
    active_values.push(fragment.output_contract)
    if !value.tasks {
      wires.push(fragment.output_contract)
    }
  }
  for projection in value.projections {
    active_values.push(projection.pipeline)
    active_values.push(projection.parts)
  }
  active_values.push(value.program)
  active_values.push(value.material)
  active_values.push(value.graph)
  for
    bodies in [
      value.facts.entries,
      value.facts.limits,
      value.facts.bindings,
      value.witnesses.bodies,
    ] {
    for body in bodies {
      held_values.push(body)
      active_values.push(body)
      wires.push(body)
    }
  }
  for body in value.results {
    wires.push(body)
    active_values.push(body)
  }
  // Semantic text, provisional material and its canonical output coexist.
  // Manifest retains its fact-array text, preimage and final wire. Plan's
  // hash/text writers are sequential; their common active workspace is below.
  for
    body in [
      value.program,
      value.material,
      value.material,
      value.graph,
      value.fact_manifest,
      value.fact_manifest,
      value.fact_manifest,
    ] {
    wires.push(body)
    active_values.push(body)
  }
  // The final Executable Plan is emitted from these SAME admitted canonical
  // children by finish_client_executable_plan_body. It is never Source-parsed
  // during this constructor. Retain its wire and writer backing, without an
  // invented whole-Plan parser/tree peak.
  wires.push(value.executable_plan)
  let mut held : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let mut scratch = held
  for body in held_values {
    guard program_artifact_parse_layout(bounded(body)) is Some(parse) &&
      @execution.compose_preparation_representation([held, parse.value])
      is Some(next) else {
      return None
    }
    held = next
  }
  // An initial canonical pipeline can coexist with its projected value.
  // Fragment construction now consumes that SAME admitted value without a
  // second pipeline parse. The remaining Fragment wire/graph parses and this
  // conservative local overlap remain; no whole-compiler funding is inferred.
  for fragment in value.fragments {
    guard program_artifact_parse_layout(bounded(fragment.initial_pipeline))
      is Some(initial) &&
      program_artifact_parse_layout(bounded(fragment.pipeline))
      is Some(projected) &&
      program_artifact_parse_layout(bounded(fragment.fragment)) is Some(node) &&
      @execution.compose_preparation_representation([
        initial.value,
        projected.value,
        compilation_scratch_max(
          initial.temporary,
          compilation_scratch_max(projected.temporary, node.temporary),
        ),
      ])
      is Some(active) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, active)
  }
  for projection in value.projections {
    guard program_artifact_parse_layout(bounded(projection.pipeline))
      is Some(pipeline) &&
      program_artifact_parse_layout(bounded(projection.parts)) is Some(parts) &&
      @execution.compose_preparation_representation([
        pipeline.value,
        compilation_scratch_max(pipeline.temporary, parts.temporary),
      ])
      is Some(active) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, active)
  }
  guard program_artifact_parse_layout(value.program) is Some(program) &&
    program_artifact_parse_layout(value.material) is Some(material) &&
    @execution.compose_preparation_representation([
      program.value,
      material.temporary,
    ])
    is Some(material_active) else {
    return None
  }
  scratch = compilation_scratch_max(scratch, material_active)
  for body in active_values {
    guard program_artifact_parse_layout(bounded(body)) is Some(parse) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, parse.temporary)
  }
  let mut text = 0L
  for body in wires {
    let body = bounded(body)
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
  // Only emission, not the preceding Source parser family, visits the final
  // Plan here. The actual later reader owns its independent read reservation.
  active_values.push(value.executable_plan)
  for body in active_values {
    let body = bounded(body)
    guard compilation_writer_ancestry_layout(
        body.1,
        body.2,
        body.1,
        1,
        1,
        body.0,
      )
      is Some(writer) &&
      compilation_canonical_emitter_layout(body.2) is Some(emitter) &&
      @execution.compose_preparation_representation([writer, emitter])
      is Some(active) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, active)
  }
  // Each returned body has at most a logical CID and selected contract CID.
  // Their separate String backings are not the copies inside encoded JSON.
  guard @execution.checked_preparation_add_product(
      text,
      wires.length().to_int64(),
      2L * (7L + 64L),
    )
    is Some(text) else {
    return None
  }
  let wire_text : @execution.PreparationRepresentationUnits = {
    record_headers: 3L * wires.length().to_int64(),
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  }
  // The constructor's returned graph/value/wire ownership is separate from
  // its nonescaping parser, ancestry-map, writer and local projection frames.
  // Keep the small extent-return Some/tuple (2H/1R/2W) conservatively with
  // retained metadata. No physical holding or consumed work is refunded.
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 2L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.compose_preparation_representation([
      held, wire_text, controls,
    ])
    is Some(retained) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(scratch) is Some(e) &&
    @execution.checked_preparation_add_product(r, e, 1L) is Some(_) else {
    return None
  }
  Some((r, e))
}
