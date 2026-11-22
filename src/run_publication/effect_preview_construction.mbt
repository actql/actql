///|
/// Logical construction of this Owner's original private Preview identity.
/// The caller keeps the supplied wire alive separately. These are constructor
/// facts, including refused prefixes, not a tariff, admission or physical ACK.
pub(all) struct EffectPreviewIdentityConstructionInventory {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
} derive(Eq, Debug)

///|
/// parse_effect_preview_shape -> effect_member_row_inventory -> final identity.
/// Source and canonical forests coexist during conversion. The generated
/// protocol schema is immutable module material and is borrowed, not rebuilt
/// per Preview. Member/row controls below include malformed prefixes before
/// any provider-specific member/row limit can be checked by the caller.
pub fn effect_preview_identity_construction_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> EffectPreviewIdentityConstructionInventory? {
  guard protocol_wire_codec_construction_inventory(bytes, nodes, depth)
    is Some(codec) else {
    return None
  }
  let count = Int::min(bytes, nodes).to_int64()
  guard preview_identity_member_row_inventory(count) is Some(identity) else {
    return None
  }
  Some({
    record_headers: codec.record_headers + identity.record_headers,
    reference_slots: codec.reference_slots + identity.reference_slots,
    scalar_words: codec.scalar_words + identity.scalar_words,
    // Original per-row correlation/intended/create strings and member CIDs.
    owned_utf16_units: codec.owned_utf16_units + identity.owned_utf16_units,
    owned_wire_bytes: codec.owned_wire_bytes,
  })
}

///|
/// Preview authoring over a canonical template whose derived CID placeholders
/// have their final width. Its row_order arrays are initially empty. The
/// caller still owns the template wire and anything used to assemble it.
pub fn effect_preview_semantic_authoring_construction_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
  rows : Int,
  max_bytes : Int,
  max_nodes : Int,
) -> EffectPreviewIdentityConstructionInventory? {
  if bytes > max_bytes || nodes > max_nodes || rows < 0 {
    return None
  }
  // A row_order entry adds a 71-byte SHA256 CID, two quotes and at most
  // one comma. The existing empty array already accounts for its depth.
  let authored_bytes = Int64::min(
    max_bytes.to_int64(),
    bytes.to_int64() + 74L * rows.to_int64(),
  ).to_int()
  let authored_nodes = Int64::min(
    max_nodes.to_int64(),
    nodes.to_int64() + rows.to_int64(),
  ).to_int()
  guard protocol_wire_codec_construction_inventory(bytes, nodes, depth)
    is Some(template) &&
    protocol_wire_codec_construction_inventory(
      authored_bytes, authored_nodes, depth,
    )
    is Some(intermediate) &&
    effect_preview_identity_construction_inventory(
      authored_bytes, authored_nodes, depth,
    )
    is Some(admission) else {
    return None
  }
  // The template and returned row CID vectors coexist with intermediate
  // shape/identity derivation and the authored writer. They return before
  // the final admission, which keeps only the completed wire alongside its
  // full validator. The Native caller owns the original draft separately.
  Some({
    record_headers: template.record_headers +
    intermediate.record_headers +
    admission.record_headers,
    reference_slots: template.reference_slots +
    intermediate.reference_slots +
    admission.reference_slots,
    scalar_words: template.scalar_words +
    intermediate.scalar_words +
    admission.scalar_words,
    owned_utf16_units: template.owned_utf16_units +
    intermediate.owned_utf16_units +
    admission.owned_utf16_units,
    owned_wire_bytes: template.owned_wire_bytes +
    intermediate.owned_wire_bytes +
    admission.owned_wire_bytes,
  })
}

///|
fn preview_identity_member_row_inventory(
  count : Int64,
) -> EffectPreviewIdentityConstructionInventory? {
  guard @shape.collection_construction_extent({
      // EffectPreviewIdentity35R; per-member footprint/contract/Option and
      // relation-source carriers. Per-row CID/return/Some/error carriers are
      // included even when final identity comparison refuses the Preview.
      records: 1L + 16L * count,
      record_references: 35L + 24L * count,
      record_words: 4L * count,
      // 27 root vectors plus <=12 per-member vectors: the eight row
      // inventories, ordered correlations/states/values and footprint IDs.
      // Ordered arrays borrow Strings from the original row vectors.
      reference_arrays: 27L + 12L * count,
      reference_items: 40L * count,
      scalar_arrays: 1L + count,
      scalar_items: 2L * count,
      // Two global seen maps and one row index per member. Their entries
      // total <=3N; each member/row consumes an original JSON node.
      maps: 2L + count,
      map_entries: 3L * count,
    })
    is Some(identity) else {
    return None
  }
  Some({
    record_headers: identity.record_headers,
    reference_slots: identity.reference_slots,
    scalar_words: identity.scalar_words,
    owned_utf16_units: 255L * count + 142L,
    owned_wire_bytes: 0L,
  })
}

///|
// Shared protocol wire codec only: preserving Source parser, canonical
// conversion/views, generated shape visits and canonical text/hash writers.
// Preview identity admission adds its member/row inventories separately.
fn protocol_wire_codec_construction_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
  geometry? : @encode.EncodingConstructionGeometry? = None,
  live_keys? : Int? = None,
) -> EffectPreviewIdentityConstructionInventory? {
  if bytes < 1 || nodes < 1 || depth < 1 {
    return None
  }
  let n = Int::min(bytes, nodes)
  let count = n.to_int64()
  let d = Int::min(n, depth).to_int64()
  let parser = match geometry {
    None =>
      @decode.preserving_json_parser_construction_inventory(bytes, n, depth)
    Some(value) =>
      @source.json_shaped_construction_extent(
        bytes,
        n,
        depth,
        value.fields,
        value.objects + value.arrays,
        value.objects,
        value.largest_object,
        value.strings,
        normalize_keys=false,
      ).map(value => {
        ..value,
        record_headers: value.record_headers + 1L,
        owned_utf16_units: value.owned_utf16_units + bytes.to_int64(),
      })
  }
  let canonical = match geometry {
    Some(value) =>
      @json.source_conversion_construction_extent(
        n,
        value.fields,
        value.objects,
        value.arrays,
        depth,
        0,
      ).bind(value => {
        @shape.add_collection_construction_extents(
          value.retained,
          value.scratch,
        )
      })
    None =>
      @shape.collection_construction_extent({
        // Canonical alternatives/FrozenArray wrappers, object-entry tuples,
        // input budget and recursive conversion controls. Key maps and sorted
        // fields belong to this conversion, not the already charged Source.
        records: 3L * count + 3L * d + 1L,
        record_references: 4L * count + 6L * d,
        record_words: 2L * count + 4L * d + 3L,
        reference_arrays: 2L * count,
        reference_items: 3L * count,
        scalar_arrays: 0L,
        scalar_items: 0L,
        maps: count,
        map_entries: count,
      })
  }
  // CanonicalValue traversals use ordered frames. Closed callers supply the
  // simultaneous unordered vocabulary of their actual manual emitters.
  // General/unknown callers retain the unchanged full-node key inventory.
  let keys = live_keys.unwrap_or(n)
  guard parser is Some(parser) &&
    canonical is Some(canonical) &&
    @encode.text_writer_live_key_inventory(bytes, keys, depth) is Some(text) &&
    @encode.hash_writer_live_key_inventory(keys, depth) is Some(hash) &&
    protocol_wire_validation_construction_extent(count) is Some(controls) else {
    return None
  }
  Some({
    record_headers: parser.record_headers +
    2L * canonical.record_headers +
    controls.record_headers +
    text.record_headers +
    hash.record_headers +
    8L,
    reference_slots: parser.reference_slots +
    2L * canonical.reference_slots +
    controls.reference_slots +
    text.reference_slots +
    hash.reference_slots,
    scalar_words: parser.scalar_words +
    2L * canonical.scalar_words +
    controls.scalar_words +
    text.scalar_words +
    hash.scalar_words,
    // Preserve parser/conversion/complete-wire comparison and text/hash
    // backings. Body/complete canonical views may coexist while a self-CID
    // field is added. This constructs no Preview member or row identity.
    owned_utf16_units: parser.owned_utf16_units +
    text.owned_utf16_units +
    hash.owned_utf16_units +
    4L * bytes.to_int64(),
    // Original UTF8 encode(wire) and the one active incremental hash sink.
    owned_wire_bytes: bytes.to_int64() + hash.owned_wire_bytes,
  })
}

///|
// Shared closed protocol validators. Borrowing an already admitted contract
// still constructs these checks, but does not construct a new Source parser
// or canonical conversion forest.
fn protocol_wire_validation_construction_extent(
  count : Int64,
) -> @shape.CollectionConstructionExtent? {
  @shape.collection_construction_extent({
    // Protocol visit/result continuations consume the existing <=8N work
    // budget. Include unique-array comparison/index material, row/create
    // inventory sorting and detached object_fields/array_values copies.
    records: 8L * count + 16L,
    record_references: 40L * count + 32L,
    record_words: 32L * count + 16L,
    reference_arrays: 8L,
    reference_items: 8L * count,
    scalar_arrays: 1L,
    scalar_items: count,
    maps: 1L,
    map_entries: count,
  })
}
