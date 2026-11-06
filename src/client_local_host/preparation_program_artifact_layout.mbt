///|
// The generic compiler emits Unicode JSON data, then parses it preserving
// data keys. It must not borrow the old numeric/ASCII lexical eligibility.
// Codec geometry bounds every container by nodes and fields by nodes-1; the
// original parser still enforces its actual admitted codec, never this shape.
fn program_artifact_parse_layout(
  geometry : (Int, Int, Int),
  structure? : @encode.EncodingConstructionGeometry? = None,
) -> CompilationParseLayout? {
  let (bytes, nodes, depth) = geometry
  if bytes < 1 || nodes < 1 || depth < 0 {
    return None
  }
  let (
    arrays,
    objects,
    fields,
    parse_fields,
    largest_object,
    string_values,
    text_units,
  ) = match structure {
    Some(value) if @encode.construction_geometry_usage(value) == geometry =>
      (
        Int::min(nodes, value.arrays),
        Int::min(nodes, value.objects),
        Int::min(nodes - 1, value.fields),
        Int::min(nodes - 1, value.fields),
        Int::min(nodes - 1, value.largest_object),
        Int::min(nodes, value.strings),
        value.text_units.to_int64(),
      )
    _ => (0, nodes, nodes - 1, nodes, nodes - 1, nodes, bytes.to_int64())
  }
  if arrays < 0 || objects < 0 || fields < 0 {
    return None
  }
  let containers = Int64::min(
    nodes.to_int64(),
    arrays.to_int64() + objects.to_int64(),
  ).to_int()
  let parser_largest = match structure {
    Some(value) if @encode.construction_geometry_usage(value) == geometry =>
      largest_object
    _ => nodes // Preserve the generic parser's pending-key refusal bound.
  }
  guard @source.json_shaped_construction_extent(
      bytes,
      nodes,
      Int::max(1, depth),
      parse_fields,
      containers,
      objects,
      parser_largest,
      string_values,
      normalize_keys=false,
    )
    is Some(source) &&
    compilation_canonical_layout({
      nodes,
      arrays,
      objects,
      fields,
      depth,
      largest_object,
    })
    is Some(canonical) &&
    @source.json_index_borrowed_construction_extent(
      nodes,
      fields,
      text_units,
      keep_spans=false,
      string_nodes=Some(string_values),
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
  Some({ value, temporary, output_tree: canonical.tree, })
}

///|
// Only when this SAME output is already covered by an explicit live pipeline
// slot (or the later nonoverlapping direct Values graph slot). Keep all Source,
// String, parser, sort, map and ancestry scratch. This retires no Resource work
// or physical holding and cannot be used as a constructor/admission witness.
fn program_artifact_scratch_without_output(
  parse : CompilationParseLayout,
) -> @execution.PreparationRepresentationUnits? {
  let a = parse.temporary
  let b = parse.output_tree
  if b.record_headers > a.record_headers ||
    b.reference_slots > a.reference_slots ||
    b.scalar_words > a.scalar_words ||
    b.owned_utf16_units > a.owned_utf16_units ||
    b.owned_wire_bytes > a.owned_wire_bytes {
    return None
  }
  Some({
    record_headers: a.record_headers - b.record_headers,
    reference_slots: a.reference_slots - b.reference_slots,
    scalar_words: a.scalar_words - b.scalar_words,
    owned_utf16_units: a.owned_utf16_units - b.owned_utf16_units,
    owned_wire_bytes: a.owned_wire_bytes - b.owned_wire_bytes,
  })
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
  let parse_body = (
    body : (Int, Int, Int),
    structure : @encode.EncodingConstructionGeometry?,
  ) => program_artifact_parse_layout(body, structure~)
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
  let held_values = [
    (value.graph, value.parser_geometry.graph),
    (value.material, value.parser_geometry.material),
  ]
  for index in 0..<value.borrowed_inputs.length() {
    held_values.push(
      (
        value.borrowed_inputs[index],
        value.parser_geometry.borrowed_inputs.get(index).unwrap_or(None),
      ),
    )
  }
  let active_values : Array[
    ((Int, Int, Int), @encode.EncodingConstructionGeometry?),
  ] = []
  let wires : Array[(Int, Int, Int)] = []
  for index in 0..<value.borrowed_inputs.length() {
    active_values.push(
      (
        value.borrowed_inputs[index],
        value.parser_geometry.borrowed_inputs.get(index).unwrap_or(None),
      ),
    )
  }
  for fragment in value.fragments {
    active_values.push((fragment.initial_pipeline, fragment.pipeline_geometry))
    active_values.push((fragment.pipeline, fragment.pipeline_geometry))
    active_values.push((fragment.fragment, fragment.fragment_geometry))
    // Task graph construction retains Fragment records until its writer
    // returns, whereas initial/projected pipeline text is local to one task.
    wires.push(fragment.fragment)
    for contract in fragment.input_contracts {
      active_values.push((contract, None))
    }
    active_values.push(
      (fragment.output_contract, fragment.output_contract_geometry),
    )
    if !value.tasks {
      wires.push(fragment.output_contract)
    }
  }
  for projection in value.projections {
    active_values.push((projection.pipeline, None))
    active_values.push((projection.parts, None))
  }
  active_values.push((value.program, value.parser_geometry.program))
  active_values.push((value.material, value.parser_geometry.material))
  active_values.push((value.graph, value.parser_geometry.graph))
  for
    bodies in [
      value.facts.entries,
      value.facts.limits,
      value.facts.bindings,
      value.witnesses.bodies,
    ] {
    for body in bodies {
      held_values.push((body, None))
      active_values.push((body, None))
      wires.push(body)
    }
  }
  for body in value.results {
    wires.push(body)
    active_values.push((body, None))
  }
  // Semantic text, provisional material and its canonical output coexist.
  // Manifest retains its fact-array text, preimage and final wire. Plan's
  // hash/text writers are sequential; their common active workspace is below.
  for
    (body, structure) in [
      (value.program, value.parser_geometry.program),
      (value.material, value.parser_geometry.material),
      (value.material, value.parser_geometry.material),
      (value.graph, value.parser_geometry.graph),
      (value.fact_manifest, None),
      (value.fact_manifest, None),
      (value.fact_manifest, None),
    ] {
    wires.push(body)
    active_values.push((body, structure))
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
  for (body, structure) in held_values {
    guard parse_body(bounded(body), structure) is Some(parse) &&
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
    guard parse_body(
        bounded(fragment.initial_pipeline),
        fragment.pipeline_geometry,
      )
      is Some(initial) &&
      parse_body(bounded(fragment.pipeline), fragment.pipeline_geometry)
      is Some(projected) &&
      parse_body(bounded(fragment.fragment), fragment.fragment_geometry)
      is Some(node) &&
      program_artifact_scratch_without_output(initial) is Some(initial_scratch) &&
      program_artifact_scratch_without_output(projected)
      is Some(projected_scratch) &&
      (if value.tasks {
        Some(node.temporary)
      } else {
        // Direct Values' original parsed Fragment node is local to graph
        // emission, not retained in ClientValuesPlanGraph. It is gone before
        // the later graph parse; that same final graph slot already bounds
        // this child tree. Task/Model retained graphs keep their old overlap.
        program_artifact_scratch_without_output(node)
      })
      is Some(node_scratch) &&
      @execution.compose_preparation_representation([
        initial.value,
        if value.tasks {
          projected.value
        } else {
          // The direct Values issuer carries ONE original aoa.body into the
          // Fragment. No projected second pipeline exists on this branch.
          {
            record_headers: 0L,
            reference_slots: 0L,
            scalar_words: 0L,
            owned_utf16_units: 0L,
            owned_wire_bytes: 0L,
          }
        },
        compilation_scratch_max(
          initial_scratch,
          compilation_scratch_max(projected_scratch, node_scratch),
        ),
      ])
      is Some(active) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, active)
  }
  for projection in value.projections {
    guard parse_body(bounded(projection.pipeline), None) is Some(pipeline) &&
      parse_body(bounded(projection.parts), None) is Some(parts) &&
      @execution.compose_preparation_representation([
        pipeline.value,
        compilation_scratch_max(pipeline.temporary, parts.temporary),
      ])
      is Some(active) else {
      return None
    }
    scratch = compilation_scratch_max(scratch, active)
  }
  guard parse_body(value.material, value.parser_geometry.material)
    is Some(material) &&
    @execution.compose_preparation_representation([
      // The original material emitter cuts its local parsed Program after
      // synchronous emission and BEFORE parsing raw material. Its returned
      // canonical material includes that Program, already held above.
      material.temporary,
    ])
    is Some(material_active) else {
    return None
  }
  scratch = compilation_scratch_max(scratch, material_active)
  for (body, structure) in active_values {
    guard parse_body(bounded(body), structure) is Some(parse) else {
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
  active_values.push(
    (value.executable_plan, value.parser_geometry.executable_plan),
  )
  for (body, structure) in active_values {
    let body = bounded(body)
    let keys = match structure {
      Some(shape) if @encode.construction_geometry_usage(shape) == body =>
        shape.largest_object
      _ => body.1
    }
    guard compilation_writer_ancestry_layout(body.1, body.2, keys, 1, 1, body.0)
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
