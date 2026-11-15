///|
// SAME original Unicode/byte preflight, geometry only. The fixed/depth
// controls are prepaid by the managed group; no tree/admission is issued.
fn installed_effect_dependency_wire_geometry(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> @source.JsonSourceGeometry? {
  if wire.length() == 2147483647 || !work(wire.length() + 1) {
    return None
  }
  let cursor = match
    @source.start_json_source_preflight(
      wire,
      { max_input_bytes: max_bytes, max_nodes, max_depth, },
      data_keys=true,
    ) {
    Ok(cursor) => cursor
    Err(_) => return None
  }
  defer @source.cancel_json_source_preflight(cursor)
  while true {
    match @source.advance_json_source_preflight(cursor, 4096) {
      Ok(@source.JsonSourceReady(geometry, ..)) => return Some(geometry)
      Ok(@source.JsonSourceContinue(..)) => ()
      _ => return None
    }
  } nobreak {
    None
  }
}

///|
// Input-dependent spelling envelope for attempted strict canonicalization,
// including a refused noncanonical number/escape/key. Its active per-body
// codec policy still refuses exactly as before. No aggregate policy cap or
// entry credit is obtained from these byte quantities.
fn installed_effect_dependency_wire_capacity(
  geometry : @source.JsonSourceGeometry,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  let nodes = Int::min(geometry.node_upper, max_nodes)
  let depth = Int::max(1, Int::min(geometry.depth_upper, max_depth))
  guard nodes > 0 &&
    geometry.input_bytes > 0 &&
    @source.json_source_geometry_construction_extent(geometry, nodes, depth)
    is Some(source) &&
    @canonical.nfc_lf_retained_output_units(
      geometry.quoted_raw_utf16_units.to_int64(),
    )
    is Some(normalized) else {
    return None
  }
  let spelling = Int64::max(
    geometry.input_bytes.to_int64(),
    6L * normalized +
    25L * geometry.atoms.to_int64() +
    8L *
    (
      geometry.fields.to_int64() +
      geometry.objects.to_int64() +
      geometry.arrays.to_int64()
    ),
  )
  let output_bytes = Int64::min(spelling, max_bytes.to_int64()).to_int()
  let shaped : @encode.EncodingConstructionGeometry = {
    bytes: output_bytes,
    nodes,
    depth,
    arrays: Int::min(geometry.arrays, nodes),
    objects: Int::min(geometry.objects, nodes),
    fields: Int::min(geometry.fields, nodes - 1),
    largest_object: Int::min(geometry.fields, nodes - 1),
    strings: Int::min(geometry.quoted_tokens, nodes),
    text_units: Int64::min(normalized, 2147483647L).to_int(),
  }
  guard installed_effect_dependency_body_capacity(shaped) is Some(body) &&
    @execution.preparation_execution_capacity({
      retained: {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: source.record_headers,
        reference_slots: source.reference_slots,
        scalar_words: source.scalar_words,
        owned_utf16_units: source.owned_utf16_units,
        owned_wire_bytes: geometry.input_bytes.to_int64(),
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(parser) &&
    standard_create_sum_capacities([body, parser], sequential_workspace=false)
    is Some(required) else {
    return None
  }
  Some(required)
}

///|
// The receipt has already been bound to this captured Run by the caller.
// Hash the COMPLETE borrowed UTF8 preimage before using its canonical encoder
// quantities. Equal claimed CIDs alone never select this smaller constructor.
// Strict body admission below still checks grammar, canonical bytes, CID and
// all semantic references; this projection issues no body or authority.
fn installed_effect_dependency_original_relation_geometry(
  wire : String,
  cid : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
  observed : @source.JsonSourceGeometry,
  work : (Int) -> Bool,
) -> @encode.EncodingConstructionGeometry? {
  if bytes != observed.input_bytes ||
    nodes < 1 ||
    depth < 1 ||
    nodes > observed.node_upper ||
    depth > observed.depth_upper ||
    !work(wire.length()) {
    return None
  }
  guard @sha.text_hex(wire) is Ok(hash) && "sha256:" + hash == cid else {
    return None
  }
  Some({
    bytes,
    nodes,
    depth,
    arrays: Int::min(observed.arrays, nodes),
    objects: Int::min(observed.objects, nodes),
    fields: Int::min(observed.fields, nodes - 1),
    largest_object: Int::min(observed.fields, nodes - 1),
    strings: Int::min(observed.quoted_tokens, nodes),
    // The exact original canonical preimage cannot expand under NFC/LF or
    // canonical escaping. Raw quoted spelling still conservatively bounds
    // decoded text; no untrusted/raw body gets this conclusion.
    text_units: observed.quoted_raw_utf16_units,
  })
}

///|
// One sequential raw hash plus borrowed receipt/scalar/variant controls.
// Use the existing hashing owner's complete constructor/finish recipe, not a
// hand-picked byte allowance. No data-sized buffer is made by text_hex.
fn installed_effect_dependency_original_hash_capacity(
  originals : Int,
) -> @execution.ExecutionCapacity? {
  if originals < 0 {
    return None
  }
  guard @encode.hash_writer_construction_inventory(0, 0) is Some(hash) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      // Two usage tuples + the selected geometry/variant/result alternatives.
      record_headers: hash.record_headers + 8L,
      reference_slots: hash.reference_slots + 12L,
      scalar_words: hash.scalar_words + 24L,
      owned_utf16_units: hash.owned_utf16_units + 71L,
      owned_wire_bytes: hash.owned_wire_bytes,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
