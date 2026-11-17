///|
// The original Host pairs this immutable wire with its SAME nominal Preview
// before entry. Unknown/raw wire callers retain the general constructor quote.
fn review_original_wire_geometry(
  wire : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @encode.EncodingConstructionGeometry? {
  let cursor = match
    @source.start_json_source_preflight(
      wire,
      { max_input_bytes: bytes, max_nodes: nodes, max_depth: depth, },
      data_keys=true,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  defer @source.cancel_json_source_preflight(cursor)
  while true {
    match @source.advance_json_source_preflight(cursor, 4096) {
      Ok(@source.JsonSourceReady(value, ..)) => {
        if value.node_upper < 1 ||
          value.node_upper > nodes ||
          value.depth_upper < 1 ||
          value.depth_upper > depth {
          return None
        }
        return Some({
          bytes: value.input_bytes,
          nodes: value.node_upper,
          depth: value.depth_upper,
          arrays: value.arrays,
          objects: value.objects,
          fields: value.fields,
          largest_object: value.fields,
          strings: Int::min(value.node_upper, value.quoted_tokens),
          text_units: value.input_bytes,
        })
      }
      Ok(@source.JsonSourceContinue(..)) => ()
      _ => return None
    }
  } nobreak {
    None
  }
}

///|
// The closed emitter borrows each selected input subtree once. Per row only
// effect_id and preview_strength are repeated. Per-member scope wrappers and
// the fixed policy/envelope add at most8M+64 nodes/fields/strings, M+4 objects
// and4 arrays. These are conservative constructor counts, not raised limits.
fn review_original_output_bound(
  input : @encode.EncodingConstructionGeometry,
  members : Int,
  rows : Int,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @encode.EncodingConstructionGeometry? {
  let extra = 2L * rows.to_int64() + 8L * members.to_int64() + 64L
  let n = input.nodes.to_int64() + extra
  let f = input.fields.to_int64() + extra
  let o = input.objects.to_int64() + members.to_int64() + 4L
  let a = input.arrays.to_int64() + 4L
  let d = input.depth.to_int64() + 4L
  if bytes < 1 ||
    n > nodes.to_int64() ||
    d > depth.to_int64() ||
    f > n ||
    o + a > n ||
    n > 2147483647L {
    return None
  }
  Some({
    bytes,
    nodes: n.to_int(),
    fields: f.to_int(),
    objects: o.to_int(),
    arrays: a.to_int(),
    depth: d.to_int(),
    largest_object: Int::max(14, input.largest_object),
    strings: Int64::min(n, input.strings.to_int64() + extra).to_int(),
    text_units: bytes,
  })
}

///|
fn review_original_inventory_for_geometry(
  input_geometry : @encode.EncodingConstructionGeometry,
  members : Int,
  rows : Int,
  review_bytes : Int,
  review_nodes : Int,
  review_depth : Int,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  let count = members.to_int64() + rows.to_int64()
  if members < 0 || rows < 0 || count > input_geometry.nodes.to_int64() {
    return None
  }
  guard protocol_wire_codec_construction_inventory(
      input_geometry.bytes,
      input_geometry.nodes,
      input_geometry.depth,
      geometry=Some(input_geometry),
      // Preview semantic hash: root20 minus3 omitted, member27, row8 minus
      // idempotency. These unordered frames can coexist:17+27+7=51.
      live_keys=Some(17 + 27 + 7),
    )
    is Some(shape) &&
    preview_identity_member_row_inventory(count) is Some(identity) else {
    return None
  }
  let input : EffectPreviewIdentityConstructionInventory = {
    record_headers: shape.record_headers + identity.record_headers,
    reference_slots: shape.reference_slots + identity.reference_slots,
    scalar_words: shape.scalar_words + identity.scalar_words,
    owned_utf16_units: shape.owned_utf16_units + identity.owned_utf16_units,
    owned_wire_bytes: shape.owned_wire_bytes,
  }
  match
    review_original_output_bound(
      input_geometry, members, rows, review_bytes, review_nodes, review_depth,
    ) {
    Some(output_geometry) => {
      guard protocol_wire_codec_construction_inventory(
          output_geometry.bytes,
          output_geometry.nodes,
          output_geometry.depth,
          geometry=Some(output_geometry),
          // Review root/scope/member/row literal keys. Canonical payloads
          // are ordered and allocate no unordered key entries.
          live_keys=Some(13 + 1 + 4 + 8),
        )
        is Some(output) else {
        return None
      }
      review_construction_inventory_parts(
        input,
        shape,
        output,
        output_geometry.bytes,
        output_geometry.nodes,
        output_geometry.depth,
        geometry=Some(output_geometry),
      )
    }
    None => {
      // A smaller policy can refuse a prefix before complete shape is known.
      // Keep the general independent category bounds for that refused path.
      let nodes = Int::min(review_bytes, review_nodes)
      guard protocol_wire_codec_construction_inventory(
          review_bytes, nodes, review_depth,
        )
        is Some(output) else {
        return None
      }
      review_construction_inventory_parts(
        input, shape, output, review_bytes, nodes, review_depth,
      )
    }
  }
}

///|
/// Constructor facts only. The trusted original Host supplies identity and wire
/// from the SAME private admission-map key; no Bool or public CID claims this
/// association. Final projection still re-admits shape/CIDs/Run and policy.
pub fn effect_review_original_construction_inventory(
  original : EffectPreviewIdentity,
  preview_wire : String,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  review_bytes : Int,
  review_nodes : Int,
  review_depth : Int,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  guard review_original_wire_geometry(
      preview_wire, preview_bytes, preview_nodes, preview_depth,
    )
    is Some(geometry) else {
    return None
  }
  let mut rows = 0L
  for row_keys in original.row_keys {
    rows += row_keys.length().to_int64()
  }
  if rows > 2147483647L {
    return None
  }
  review_original_inventory_for_geometry(
    geometry,
    original.member_cids.length(),
    rows.to_int(),
    review_bytes,
    review_nodes,
    review_depth,
  )
}
