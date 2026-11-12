///|
// Initial controls and the ACTUAL original selector only. Future Catalog/
// retention/page ceilings are not initial demand or a grant to read.
fn row_input_initial_capacity(
  preparation : RowInputPreparation,
) -> @execution.ExecutionCapacity? {
  row_input_phase_capacity(preparation, 0L, 0L, 0L, 0L, 0, None)
}

///|
// Existing constructor inventories, priced by their shared owners. Counts
// describe the same retained metadata plus ONE actually received page. The
// next page grows the same RowRun reservation before new construction.
fn row_input_phase_capacity(
  preparation : RowInputPreparation,
  nodes : Int64,
  text : Int64,
  observations : Int64,
  token_units : Int64,
  body_bytes : Int,
  geometry : @source.JsonSourceGeometry?,
) -> @execution.ExecutionCapacity? {
  let request = @sourcequery.source_acquisition_request(preparation.original)
  let fields = @sourcequery.parameterized_request_field_count(request)
  let ordering_fields = if fields > 1 { fields.to_int64() } else { 0L }
  let mut paths = 0L
  let mut pattern = 0L
  for index in 0..<fields {
    let field = @sourcequery.parameterized_request_field_at(request, index).unwrap()
    let value = match field.value {
      CheckedLiteral(value) => value.value
      BoundParameter(parameter) => parameter.value.value
      UnboundHostBinding(_) => return None
    }
    match (field.field.slot.field_name, value) {
      ("paths", @admitted.Array(values)) =>
        paths = @admitted.element_count(values).to_int64()
      ("glob", @admitted.Text(value)) => pattern = value.length().to_int64()
      _ => ()
    }
  }
  let width = @schema.field_count(preparation.schema).to_int64()
  guard @execution.checked_preparation_add_product(0L, observations, width)
    is Some(cells) &&
    @execution.checked_preparation_add_product(cells, paths, 1L) is Some(slots) &&
    @shape.collection_construction_extent({
      // Progress/page/selection/equality, quota, parser slots and alternatives.
      // Literal glob tokens/component String headers use actual pattern units.
      records: 32L + 2L * pattern,
      record_references: 56L + pattern,
      record_words: 59L + pattern,
      // One synchronous publication Request writer borrows a sorted field
      // reference array. Reserve it on THIS Source before its first callback,
      // retain it through page growth and reuse it only after a writer returns.
      // Neither the original transport fields nor their binding indices move.
      reference_arrays: observations +
      3L +
      (if ordering_fields > 0L { 1L } else { 0L }),
      reference_items: slots + width * 4L + ordering_fields,
      scalar_arrays: 4L,
      scalar_items: paths + 3L * (pattern + 1L) + width * 3L,
      maps: 1L,
      map_entries: observations,
    })
    is Some(collections) else {
    return None
  }
  let preflight = @source.json_source_preflight_control_extent()
  guard @execution.preparation_representation_cost({
      record_headers: collections.record_headers + preflight.record_headers,
      reference_slots: collections.reference_slots + preflight.reference_slots,
      scalar_words: collections.scalar_words + preflight.scalar_words,
      // Path strings are borrowed. Glob components, continuation strings and
      // this actual UTF8 page's decoded input have separate original backing.
      owned_utf16_units: pattern + token_units + body_bytes.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(0L, text, 6L) is Some(wire) &&
    @execution.checked_preparation_add_product(wire, nodes, 8L) is Some(wire) &&
    @execution.execution_capacity_inventory_add(
      controls,
      @execution.ValueNodeSlots,
      nodes,
      4,
    )
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      retained,
      @execution.DecodedTextBytes,
      text,
      2,
    )
    is Some(retained) &&
    @execution.execution_capacity_inventory_add(
      retained,
      @execution.CanonicalWireBytes,
      wire,
      1,
    )
    is Some(retained) else {
    return None
  }
  guard geometry is Some(actual) else {
    return @execution.execution_capacity(retained, retained)
  }
  let limits = preparation.limits.page
  let nodes = Int::max(1, Int::min(actual.node_upper, limits.max_nodes))
  let depth = Int::max(1, Int::min(actual.depth_upper, limits.max_depth))
  guard @source.json_source_geometry_construction_extent(actual, nodes, depth)
    is Some(parser) &&
    @execution.preparation_representation_cost({
      record_headers: parser.record_headers,
      reference_slots: parser.reference_slots,
      scalar_words: parser.scalar_words,
      owned_utf16_units: parser.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(page) &&
    @execution.checked_preparation_add_product(retained, page, 1L)
    is Some(execution) &&
    // The same decoded envelope/index and typed-admission temporary backing.
    @execution.execution_capacity_inventory_add(
      execution,
      @execution.ValueNodeSlots,
      nodes.to_int64(),
      2,
    )
    is Some(execution) else {
    return None
  }
  guard @decode.admission_construction_inventory(
      nodes,
      Int::min(actual.fields, nodes),
      Int::min(actual.objects, nodes),
      Int::min(actual.arrays, nodes),
      depth,
    )
    is Some(index) &&
    @execution.preparation_representation_cost({
      record_headers: index.indexed.record_headers +
      index.keys.record_headers +
      index.ancestry.record_headers +
      index.controls.record_headers,
      reference_slots: index.indexed.reference_slots +
      index.keys.reference_slots +
      index.ancestry.reference_slots +
      index.controls.reference_slots,
      scalar_words: index.indexed.scalar_words +
      index.keys.scalar_words +
      index.ancestry.scalar_words +
      index.controls.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(index_bytes) &&
    @execution.checked_preparation_add_product(execution, index_bytes, 1L)
    is Some(execution) else {
    return None
  }
  @execution.execution_capacity(retained, execution)
}

///|
fn grow_row_input_capacity(
  run : RowRun,
  acquisition : RowInputAcquisition,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, RowHostIssue] {
  guard run.physical is Some(physical) &&
    row_input_acquisition_capacity(acquisition, physical.provider_capacity)
    is Some(base) &&
    row_input_initial_capacity(acquisition.preparation) is Some(initial) else {
    return Err(Physical(InvalidLimits))
  }
  let retained = @execution.execution_capacity_retained_bytes(base)
  let execution = @execution.execution_capacity_execution_bytes(base)
  let extra_r = @execution.execution_capacity_retained_bytes(capacity) -
    @execution.execution_capacity_retained_bytes(initial)
  let extra_e = @execution.execution_capacity_execution_bytes(capacity) -
    @execution.execution_capacity_execution_bytes(initial)
  guard @execution.checked_preparation_add_product(retained, extra_r, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(execution, extra_e, 1L)
    is Some(execution) &&
    @execution.checked_preparation_add_product(
      execution,
      physical.execution_scratch,
      1L,
    )
    is Some(execution) else {
    return Err(Physical(InvalidLimits))
  }
  let (old_r, old_e) = match
    @resources.reservation_capacity_amounts(
      physical.ledger,
      physical.reservation,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match
    @resources.grow_execution_reservation_capacity(
      physical.ledger,
      physical.reservation,
      Int64::max(old_r, retained),
      Int64::max(old_e, execution),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  Ok(())
}

///|
fn grow_row_input_listing_phase(
  run : RowRun,
  read : RowSourceRead,
  acquisition : RowInputAcquisition,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, RowHostIssue] {
  match grow_row_input_capacity(run, acquisition, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // Resource current checks may reenter cancellation. Retain neither a cached
  // proof nor permission to parse after the original read has been revoked.
  if !row_input_read_current(run, read) {
    return Err(InvalidState)
  }
  Ok(())
}

///|
// The original Source preflight transfers its SAME parser once. There is no
// second parse, geometry scan or opaque handle from another namespace. Retain
// the actual cursor on the original read before fallible Resource/current work.
fn prepare_row_input_listing_page(
  run : RowRun,
  read : RowSourceRead,
  acquisition : RowInputAcquisition,
  body : Bytes,
) -> Result[@source.Node, RowHostIssue] {
  guard read.listing is Some(progress) && progress.retention is Some(budget) else {
    return Err(InvalidState)
  }
  if body.length() > read.page_limits.max_bytes {
    return Err(Source(InvalidPage))
  }
  let mut tokens = 0L
  for token in progress.tokens {
    tokens += token.length().to_int64()
  }
  let capacity = match
    row_input_phase_capacity(
      acquisition.preparation,
      budget.nodes.to_int64(),
      budget.text.to_int64(),
      progress.observations.length().to_int64(),
      tokens,
      body.length(),
      None,
    ) {
    Some(value) => value
    None => return Err(Physical(InvalidLimits))
  }
  match grow_row_input_listing_phase(run, read, acquisition, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let text = @utf8.decode(body) catch {
    _ => return Err(Source(ListingProtocol))
  }
  let source = match
    @source.start_json_source_preflight(text, {
      max_input_bytes: read.page_limits.max_bytes,
      max_nodes: read.page_limits.max_nodes,
      max_depth: read.page_limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(Source(ListingProtocol))
  }
  progress.preflight = Some(source)
  let actual = while true {
    match @source.advance_json_source_preflight(source, 1024) {
      Ok(JsonSourceContinue(_)) => ()
      Ok(JsonSourceReady(actual, ..)) => break actual
      _ => return Err(Source(ListingProtocol))
    }
  } nobreak {
    return Err(Source(ListingProtocol))
  }
  // Translation bytes are not physical transfer bytes. Actual Source geometry
  // bounds the next tree/metadata construction; selected policy still limits
  // admission, and no all-future maximum becomes an initial reservation.
  let nodes = Int64::min(
    budget.max_nodes.to_int64(),
    budget.nodes.to_int64() + actual.node_upper.to_int64(),
  )
  let text_bytes = Int64::min(
    budget.max_text.to_int64(),
    budget.text.to_int64() + actual.input_bytes.to_int64(),
  )
  let observations = progress.observations.length().to_int64() +
    actual.objects.to_int64()
  let capacity = match
    row_input_phase_capacity(
      acquisition.preparation,
      nodes,
      text_bytes,
      observations,
      tokens + actual.quoted_raw_utf16_units.to_int64(),
      body.length(),
      Some(actual),
    ) {
    Some(value) => value
    None => return Err(Physical(InvalidLimits))
  }
  match grow_row_input_listing_phase(run, read, acquisition, capacity) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if run.input_progress is Some(retained) {
    retained.nodes = Int64::max(retained.nodes, nodes)
    retained.text = Int64::max(retained.text, text_bytes)
    retained.rows = Int64::max(retained.rows, observations)
    retained.tokens = Int64::max(
      retained.tokens,
      tokens + actual.quoted_raw_utf16_units.to_int64(),
    )
  }
  let parser = match @source.take_json_source_parser(source) {
    Ok(value) => value
    Err(_) => return Err(Source(ListingProtocol))
  }
  progress.preflight = None
  progress.parser = Some(parser)
  while true {
    match @source.advance_json_parse(parser, 1024) {
      Ok(JsonParseContinue(_)) => ()
      Ok(JsonParseComplete(parsed, ..)) => {
        progress.parser = None
        return Ok(parsed.node)
      }
      _ => return Err(Source(ListingProtocol))
    }
  } nobreak {
    Err(Source(ListingProtocol))
  }
}
