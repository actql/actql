///|
fn platform_buffer_issue(
  issue : @resources.ImportedChildLedgerIssue,
) -> BufferIssue {
  match issue {
    @resources.Resource(issue) => Resource(issue)
    @resources.ForeignOriginal => ForeignOwner
    _ => Resource(@resources.ChildFundingUnavailable)
  }
}

///|
// Before decoding UTF8 or allocating the existing Source preflight controls.
// The actual wire length bounds the owned decoded String; no node-per-character
// tree bound or unused configured node maximum is allocated here.
fn platform_input_entry_bytes(bytes : Int) -> Int64? {
  let controls = @source.json_source_preflight_control_extent()
  @execution.preparation_representation_cost({
    record_headers: controls.record_headers,
    reference_slots: controls.reference_slots,
    scalar_words: controls.scalar_words,
    owned_utf16_units: bytes.to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
fn platform_input_parser_bytes(
  geometry : @source.JsonSourceGeometry,
  max_nodes : Int,
  max_depth : Int,
) -> Int64? {
  // This SAME scalar preflight bounds invalid prefixes too. Strings retain
  // their actual wire extent without pretending their characters are nodes.
  guard @decode.preserving_json_parser_construction_inventory(
      Int::max(1, geometry.input_bytes),
      Int::max(1, Int::min(max_nodes, geometry.node_upper)),
      Int::max(1, Int::min(max_depth, geometry.depth_upper)),
    )
    is Some(parser) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: parser.record_headers,
    reference_slots: parser.reference_slots,
    scalar_words: parser.scalar_words,
    owned_utf16_units: parser.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
// The existing Buffer owns its exact wire, staged cursor, failed constructor
// and retained Source tree. No Request/parser output escapes without the old
// BufferBorrow. Scalar/native/imported buffer paths keep their old algorithm.
fn seal_platform_buffer(
  pool : BufferPool,
  slot : BufferSlot,
  original : @resources.PlatformVMCapacity,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, BufferIssue] {
  // An interrupted/failed original stays reachable for cleanup. A caller
  // cannot silently start a replacement parser under that same transfer.
  if slot.parser_working is Some(_) {
    return Err(Closed)
  }
  guard platform_input_entry_bytes(slot.wire_length) is Some(entry) else {
    return Err(InvalidLimits)
  }
  let working = match
    @resources.reserve_platform_vm_working_capacity(original, entry, entry) {
    Err(issue) => return Err(platform_buffer_issue(issue))
    Ok(value) => value
  }
  slot.parser_working = Some(working)
  let wire = Bytes::from_array(slot.bytes)
  slot.wire = Some(wire)
  let text = @utf8.decode(wire) catch {
    _ =>
      // Preserve the original byte parser's invalid-UTF8 error/coordinates.
      // It fails before a tree; that error frame is covered by entry controls.
      return @source.parse_json_bytes_preserving(wire, {
          max_input_bytes: pool.max_wire_bytes,
          max_nodes,
          max_depth,
        })
        .map(_ => ())
        .map_err(issue => Input(issue))
  }
  let preflight = match
    @source.start_json_source_preflight(
      text,
      { max_input_bytes: pool.max_wire_bytes, max_nodes, max_depth, },
      data_keys=true,
    ) {
    Err(issue) => return Err(Input(issue))
    Ok(value) => value
  }
  slot.parser_preflight = Some(preflight)
  let mut observed : @source.JsonSourceGeometry? = None
  while observed is None {
    match @source.advance_json_source_preflight(preflight, 4096).unwrap() {
      @source.JsonSourceContinue(work~) =>
        match @resources.charge_planning(pool.ledger, work) {
          Err(issue) => return Err(Resource(issue))
          Ok(_) => ()
        }
      @source.JsonSourceFailed(issue, work~) =>
        match @resources.charge_planning(pool.ledger, work) {
          Err(error) => return Err(Resource(error))
          Ok(_) => return Err(Input(issue))
        }
      @source.JsonSourceReady(geometry, work~) =>
        match @resources.charge_planning(pool.ledger, work) {
          Err(issue) => return Err(Resource(issue))
          Ok(_) => observed = Some(geometry)
        }
    }
  }
  let geometry = observed.unwrap()
  guard platform_input_parser_bytes(geometry, max_nodes, max_depth)
    is Some(peak) else {
    return Err(InvalidLimits)
  }
  match @resources.grow_platform_vm_working_capacity(working, peak, peak) {
    Err(issue) => return Err(platform_buffer_issue(issue))
    Ok(_) => ()
  }
  let parser = @source.take_json_source_parser(preflight).unwrap()
  slot.parser = Some(parser)
  slot.parser_preflight = None
  while slot.source is None {
    match @source.advance_json_parse(parser, 4096).unwrap() {
      @source.JsonParseContinue(work~) =>
        match @resources.charge_planning(pool.ledger, work) {
          Err(issue) => return Err(Resource(issue))
          Ok(_) => ()
        }
      @source.JsonParseFailed(issue, work~) =>
        match @resources.charge_planning(pool.ledger, work) {
          Err(error) => return Err(Resource(error))
          Ok(_) => return Err(Input(issue))
        }
      @source.JsonParseComplete(parsed, work~) =>
        match @resources.charge_planning(pool.ledger, work) {
          Err(issue) => return Err(Resource(issue))
          Ok(_) => slot.source = Some(parsed.node)
        }
    }
  }
  slot.parser = None
  slot.bytes = []
  slot.input_complete = true
  Ok(())
}
