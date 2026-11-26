///|
// Selected Host configuration only. These constructors use the existing
// initial Read; a parsed Cursor is DATA, never another Host or permission.
fn LocalCommandPreparationOriginal::prepare_host_metadata(
  self : Self,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, LocalCommandPreparationIssue] {
  guard self.host is Some(host) &&
    self.read is Some(read) &&
    (self.phase_open || self.journal_read_open) &&
    !self.closing &&
    !self.closed &&
    self.primary is None &&
    self.read_failure is None else {
    return Err(CommandUnavailable)
  }
  // Reuse the existing Journal constructor pattern: each new retained frame
  // stays beside the next constructor; completed scratch contributes only a
  // maximum. Neither a later phase nor a failed constructor refunds a Read.
  guard retained >= 0L &&
    execution >= 0L &&
    @execution.checked_preparation_add_product(
      self.metadata_retained,
      retained,
      1L,
    )
    is Some(total_retained) &&
    @execution.checked_preparation_add_product(
      self.metadata_retained,
      execution,
      1L,
    )
    is Some(total_execution) else {
    return Err(CommandUnavailable)
  }
  let result = host
    .prepare_domain_original_read_construction(
      read,
      total_retained,
      total_execution,
      Int64::max(retained, execution),
    )
    .map_err(issue => CommandRead(issue))
  if result is Ok(_) {
    self.metadata_retained = total_retained
  }
  result
}

///|
fn local_host_metadata_prepare(
  retained : Int64,
  execution : Int64,
) -> Unit raise ClientStop {
  if command_preparation_invocation.val is Some(original) {
    let result = original.prepare_host_metadata(retained, execution)
    if result is Err(issue) {
      original.retain_primary(issue)
    }
    command_preparation_result(result, stage=Some("configuration-metadata"))
  }
}

///|
fn local_host_metadata_units(
  headers : Int64,
  references : Int64,
  words : Int64,
  text : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: headers,
    reference_slots: references,
    scalar_words: words,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  }
}

///|
fn local_host_metadata_price(
  units : @execution.PreparationRepresentationUnits,
) -> Int64 raise ClientStop {
  @execution.preparation_representation_cost(units).unwrap_or_else(() => {
    stop("LocalCommandPreparationLayoutUnavailable")
  })
}

///|
// Installed control DATA. Limits1H3W, ready-geometry/Node Some2H2R2W and original
// resource-error/Err wrappers2H2R2W precede variable construction.
let local_host_metadata_entry_bytes : Int64 = {
  let source = @source.json_source_preflight_control_extent()
  @execution.preparation_representation_cost({
    record_headers: source.record_headers + 5L,
    reference_slots: source.reference_slots + 4L,
    scalar_words: source.scalar_words + 7L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
fn local_host_metadata_parser_quote(
  geometry : @source.JsonSourceGeometry,
) -> (Int64, Int64)? {
  let nodes = Int::max(1, geometry.node_upper)
  let depth = Int::max(1, Int::min(64, geometry.depth_upper))
  let fields = Int::min(geometry.fields, nodes - 1)
  let objects = Int::min(geometry.objects, nodes)
  let arrays = Int::min(geometry.arrays, nodes - objects)
  // Preserve the existing non-normalizing parser. Actual preflight nodes,
  // fields and containers size the tree; text bytes never price node counts.
  guard @source.json_shaped_construction_extent(
      Int::max(1, geometry.input_bytes),
      nodes,
      depth,
      fields,
      objects + arrays,
      objects,
      fields,
      Int::min(geometry.quoted_tokens, nodes),
      normalize_keys=false,
    )
    is Some(source) &&
    @decode.admission_construction_inventory(
      nodes, fields, objects, arrays, depth,
    )
    is Some(index) &&
    @source.json_index_borrowed_construction_extent(
      nodes,
      fields,
      geometry.quoted_raw_utf16_units.to_int64(),
      keep_spans=true,
      string_nodes=Some(
        Int::min(nodes, Int::max(0, geometry.quoted_tokens - geometry.fields)),
      ),
    )
    is Some(borrowed) else {
    return None
  }
  let retained = @execution.compose_preparation_representation([
    local_host_metadata_units(
      borrowed.record_headers,
      borrowed.reference_slots,
      borrowed.scalar_words,
      borrowed.owned_utf16_units,
    ),
    local_host_metadata_units(
      index.indexed.record_headers,
      index.indexed.reference_slots,
      index.indexed.scalar_words,
      0L,
    ),
  ])
  let working = @execution.compose_preparation_representation([
    local_host_metadata_units(
      source.record_headers,
      source.reference_slots,
      source.scalar_words,
      source.owned_utf16_units,
    ),
    local_host_metadata_units(
      index.indexed.record_headers,
      index.indexed.reference_slots,
      index.indexed.scalar_words,
      0L,
    ),
    local_host_metadata_units(
      index.keys.record_headers,
      index.keys.reference_slots,
      index.keys.scalar_words,
      0L,
    ),
    local_host_metadata_units(
      index.ancestry.record_headers,
      index.ancestry.reference_slots,
      index.ancestry.scalar_words,
      0L,
    ),
    local_host_metadata_units(
      index.controls.record_headers,
      index.controls.reference_slots,
      index.controls.scalar_words,
      0L,
    ),
  ])
  guard retained is Some(retained) &&
    working is Some(working) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(working) is Some(e) else {
    return None
  }
  Some((r, Int64::max(e, local_host_metadata_entry_bytes)))
}

///|
fn local_host_settings_cursor(
  text : String,
  max_input_bytes? : Int = 2147483646,
  max_nodes? : Int = 2147483646,
) -> @decode.Cursor raise ClientStop {
  guard command_preparation_invocation.val is Some(_) else {
    return local_input_cursor(text)
  }
  local_host_metadata_prepare(0L, local_host_metadata_entry_bytes)
  // These are Int/String rejection bounds, not an allocated future maximum.
  // The SAME Source preflight observes actual bytes before the grammar phase.
  let bytes = Int64::min(2147483646L, 3L * text.length().to_int64()).to_int()
  let preflight = @source.start_json_source_preflight(
    text,
    {
      max_input_bytes: Int::min(max_input_bytes, Int::max(1, bytes)),
      max_nodes: Int::min(max_nodes, Int::max(1, text.length())),
      max_depth: 64,
    },
    data_keys=true,
  ).unwrap_or_else(() => stop("LocalInputNotAdmitted"))
  let mut observed : @source.JsonSourceGeometry? = None
  while observed is None {
    match @source.advance_json_source_preflight(preflight, 4096).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(geometry, ..) => observed = Some(geometry)
      @source.JsonSourceFailed(_) => {
        @source.cancel_json_source_preflight(preflight)
        stop("LocalInputNotAdmitted")
      }
    }
  }
  let geometry = observed.unwrap()
  guard local_host_metadata_parser_quote(geometry) is Some((r, e)) else {
    @source.cancel_json_source_preflight(preflight)
    stop("LocalCommandPreparationLayoutUnavailable")
  }
  // Publish refusal before dropping the SAME staged parser. The Read owner,
  // not a parser/Data destructor, keeps physical cleanup responsibility.
  let original = command_preparation_invocation.val.unwrap()
  let funded = original.prepare_host_metadata(r, e)
  if funded is Err(issue) {
    original.retain_primary(issue)
    @source.cancel_json_source_preflight(preflight)
  }
  command_preparation_result(funded, stage=Some("configuration-metadata"))
  let parser = @source.take_json_source_parser(preflight).unwrap()
  let mut parsed_source : @source.Node? = None
  while parsed_source is None {
    match @source.advance_json_parse(parser, 4096).unwrap() {
      @source.JsonParseContinue(..) => ()
      @source.JsonParseComplete(parsed, ..) => parsed_source = Some(parsed.node)
      @source.JsonParseFailed(_) => stop("LocalInputNotAdmitted")
    }
  }
  let source = parsed_source.unwrap()
  @decode.admit(source, {
    max_nodes: Int::max(1, geometry.node_upper),
    max_depth: 64,
    max_string_bytes: Int::max(1, geometry.input_bytes),
    max_total_string_bytes: Int::max(1, geometry.input_bytes),
  }).unwrap_or_else(() => stop("LocalInputNotAdmitted"))
}

///|
fn local_host_settings_object(
  cursor : @decode.Cursor,
  keys : Array[String],
  path_depth : Int,
  invalid : String,
) -> @decode.ObjectView raise ClientStop {
  if command_preparation_invocation.val is Some(_) {
    let units = @decode.closed_object_construction_extent(
      cursor,
      keys.length(),
      path_depth,
    ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
    let bytes = local_host_metadata_price(
      local_host_metadata_units(
        units.record_headers,
        units.reference_slots,
        units.scalar_words,
        0L,
      ),
    )
    local_host_metadata_prepare(bytes, bytes)
  }
  @decode.closed_object(cursor, keys).unwrap_or_else(() => stop(invalid))
}

///|
// Call-expanded fixed schema work:32 lookup/element wrappers,18 text and
// six numeric Result alternatives, the number closure, four allowed-key
// arrays(28 entries) and the optional signing validation array(3 entries).
fn local_host_settings_fields_prepare() -> Unit raise ClientStop {
  if command_preparation_invocation.val is None {
    return
  }
  let calls = @shape.scale_collection_construction_extent(
    @decode.indexed_child_construction_extent(),
    32L,
  ).unwrap()
  let body = @shape.collection_construction_extent({
    records: 25L,
    record_references: 25L,
    record_words: 24L,
    reference_arrays: 5L,
    reference_items: 31L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let issue = @decode.issue_path_construction_extent(4L).unwrap()
  let bytes = local_host_metadata_price(
    local_host_metadata_units(
      calls.record_headers + body.record_headers + issue.record_headers,
      calls.reference_slots + body.reference_slots + issue.reference_slots,
      calls.scalar_words + body.scalar_words + issue.scalar_words,
      0L,
    ),
  )
  local_host_metadata_prepare(0L, bytes)
}

///|
// Before elements() copies Cursor wrappers, and before the result Array or
// LocalHostSettings/caller pair are constructed. Original Strings/Spans stay borrowed
// from the funded immutable index; this quote adds no second text copy.
fn local_host_settings_array_prepare(count : Int) -> Unit raise ClientStop {
  if command_preparation_invocation.val is None {
    return
  }
  let n = count.to_int64()
  let retained = @shape.collection_construction_extent({
    records: 9L,
    record_references: 28L,
    record_words: 9L,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let working = @shape.collection_construction_extent({
    records: 9L,
    record_references: 28L,
    record_words: 9L,
    reference_arrays: 2L,
    reference_items: 2L * n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let names = @shape.key_admission_construction_extent(1, count).unwrap()
  let child = @decode.indexed_child_construction_extent()
  let calls = @shape.scale_collection_construction_extent(child, n).unwrap()
  let r = local_host_metadata_price(
    local_host_metadata_units(
      retained.record_headers,
      retained.reference_slots,
      retained.scalar_words,
      0L,
    ),
  )
  let e = local_host_metadata_price(
    local_host_metadata_units(
      working.record_headers + calls.record_headers + names.record_headers,
      working.reference_slots + calls.reference_slots + names.reference_slots,
      working.scalar_words + calls.scalar_words + names.scalar_words,
      0L,
    ),
  )
  local_host_metadata_prepare(r, e)
}

///|
// Only the selected Host configuration uses observed-size intake. Other
// runtime/Store/Journal readers retain their independently selected contracts.
fn local_host_configuration_text_file(
  root : String,
  name : String,
) -> String raise ClientStop {
  guard command_preparation_invocation.val is Some(original) else {
    return text_file(root, name, 65536L)
  }
  match command_project_original_text(root, name) {
    Ok(text) => text
    Err(failure) => {
      // A before-Reader resource refusal has already retained its original
      // issue. Do not replace it with the Reader's consequent refusal.
      let issue = original.primary.unwrap_or_else(() => {
        CommandFilesystem(failure.issue())
      })
      original.retain_primary(issue)
      command_preparation_result(Err(issue), stage=Some("configuration-read"))
    }
  }
}
