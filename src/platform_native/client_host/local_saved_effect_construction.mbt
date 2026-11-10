///|
// Source and indexed DATA constructors only. This does not quote a compiler,
// approve a Checkpoint, grant disclosure, or reconstruct a Model invocation.
// The original String is borrowed; decoded tree text and index backing are new.
fn saved_effect_wire_construction(
  geometry : @source.JsonSourceGeometry,
) -> (Int64, Int64, Int64)? {
  let nodes = Int::max(1, geometry.node_upper)
  let depth = Int::max(1, geometry.depth_upper)
  guard geometry.input_bytes > 0 &&
    geometry.input_utf16_units >= 0 &&
    geometry.fields >= 0 &&
    geometry.fields < nodes &&
    @source.json_shaped_construction_extent(
      geometry.input_bytes,
      nodes,
      depth,
      geometry.fields,
      geometry.objects + geometry.arrays,
      geometry.objects,
      geometry.fields,
      Int::min(nodes, geometry.quoted_tokens),
      normalize_keys=false,
    )
    is Some(working) &&
    @source.json_tree_retained_construction_extent(
      nodes,
      geometry.fields,
      geometry.objects,
      geometry.arrays,
      geometry.input_utf16_units.to_int64(),
    )
    is Some(tree) &&
    @decode.admission_construction_inventory(
      nodes,
      geometry.fields,
      geometry.objects,
      geometry.arrays,
      depth,
    )
    is Some(index) else {
    return None
  }
  guard @execution.preparation_representation_cost({
      record_headers: tree.record_headers + index.indexed.record_headers,
      reference_slots: tree.reference_slots + index.indexed.reference_slots,
      scalar_words: tree.scalar_words + index.indexed.scalar_words,
      owned_utf16_units: tree.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      // Parser tree/scratch plus the index, its sequential key admission and
      // decoder ancestry. Borrowed input text has no second UTF8-decoded copy.
      record_headers: working.record_headers +
      index.indexed.record_headers +
      index.keys.record_headers +
      index.ancestry.record_headers +
      index.controls.record_headers,
      reference_slots: working.reference_slots +
      index.indexed.reference_slots +
      index.keys.reference_slots +
      index.ancestry.reference_slots +
      index.controls.reference_slots,
      scalar_words: working.scalar_words +
      index.indexed.scalar_words +
      index.keys.scalar_words +
      index.ancestry.scalar_words +
      index.controls.scalar_words,
      owned_utf16_units: working.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(peak) else {
    return None
  }
  let (header, unit, _, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || pointer <= 0L {
    return None
  }
  let mut capacity = 1L
  while capacity < geometry.input_utf16_units.to_int64() {
    capacity *= 2L
  }
  let raw = Int64::max(
    header + (capacity + 1L) * unit,
    array_header + (12L + 3L * nodes.to_int64()) * pointer,
  )
  Some((retained, Int64::max(retained, peak), raw))
}

///|
// One preflight and the SAME one-use parser, followed by the existing indexed
// admission. Each retained cursor coexists with the original Store custody and
// earlier returned cursors until this review retires. Scratch is a phase peak.
pub fn NativeLocalSavedEffectReview::admit_wire_in_original_read(
  self : NativeLocalSavedEffectReview,
  wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[@decode.Cursor, NativeLocalAdoptionIssue] {
  guard !self.retired &&
    self.attempted &&
    self.capture.read_callback_active &&
    self.capture.read_facts_valid &&
    self.capture.original_resources is Some(original) &&
    original.active_phase is Some(@arena.HostRead) &&
    !original.interrupted else {
    return Err(OriginalResourceScopePending)
  }
  let control = @source.json_source_preflight_control_extent()
  let control_bytes = @execution.preparation_representation_cost({
    // Fixed call-expanded reports/tuples, current/resize call frames,
    // preflight/parser carriers and the returned index observation. No wire,
    // tree or policy-sized buffer is hidden in this finite control packet.
    record_headers: control.record_headers + 128L,
    reference_slots: control.reference_slots + 384L,
    scalar_words: control.scalar_words + 256L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  guard @execution.checked_preparation_add_product(
      self._retained_constructor_bytes,
      control_bytes,
      1L,
    )
    is Some(prelude) else {
    return Err(ConfigurationLimit)
  }
  match
    original.host.prepare_domain_original_read_construction(
      original.read,
      prelude,
      prelude,
      control_bytes,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(OriginalResources(@arena.Read(issue)))
  }
  if self.retired {
    return Err(Journal(CustodyLost))
  }
  let preflight = match
    @source.start_json_source_preflight(
      wire,
      {
        max_input_bytes: limits.max_wire_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      },
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  defer @source.cancel_json_source_preflight(preflight)
  let geometry = while true {
    match @source.advance_json_source_preflight(preflight, 4096) {
      Ok(@source.JsonSourceContinue(..)) => continue
      Ok(@source.JsonSourceReady(value, ..)) => break value
      _ => return Err(Journal(CustodyLost))
    }
  } nobreak {
    return Err(Journal(CustodyLost))
  }
  guard saved_effect_wire_construction(geometry) is Some((retained, peak, raw)) &&
    @execution.checked_preparation_add_product(
      self._retained_constructor_bytes,
      retained,
      1L,
    )
    is Some(next_retained) &&
    @execution.checked_preparation_add_product(prelude, peak, 1L)
    is Some(execution) else {
    return Err(ConfigurationLimit)
  }
  // Keep the attempted inventory before the original grow/current can fail.
  // No partial return refunds its debit or replaces the existing Read owner.
  self._retained_constructor_bytes = next_retained
  match
    original.host.prepare_domain_original_read_construction(
      original.read,
      next_retained,
      execution,
      raw,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(OriginalResources(@arena.Read(issue)))
  }
  if self.retired {
    return Err(Journal(CustodyLost))
  }
  saved_effect_admit_preflight(preflight, limits)
}

///|
// Consumes the exact preflight cursor once. This helper supplies no backing;
// the original Read method admits its measured constructor before entering.
fn saved_effect_admit_preflight(
  preflight : @source.JsonSourcePreflight,
  limits : @checkpoint.WireLimits,
) -> Result[@decode.Cursor, NativeLocalAdoptionIssue] {
  let parser = match @source.take_json_source_parser(preflight) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  defer @source.cancel_json_parse(parser)
  let parsed = while true {
    match @source.advance_json_parse(parser, 4096) {
      Ok(@source.JsonParseContinue(..)) => continue
      Ok(@source.JsonParseComplete(value, ..)) => break value
      _ => return Err(Journal(CustodyLost))
    }
  } nobreak {
    return Err(Journal(CustodyLost))
  }
  @decode.admit(parsed.node, {
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_string_bytes: limits.max_wire_bytes,
    max_total_string_bytes: limits.max_wire_bytes,
  }).map_err(_ => Journal(CustodyLost))
}
