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
  if bytes < 1 || nodes < 1 || depth < 1 {
    return None
  }
  let n = Int::min(bytes, nodes)
  let count = n.to_int64()
  let d = Int::min(n, depth).to_int64()
  guard @decode.preserving_json_parser_construction_inventory(bytes, n, depth)
    is Some(parser) &&
    @encode.text_writer_construction_inventory(bytes, n, depth) is Some(text) &&
    @encode.hash_writer_construction_inventory(n, depth) is Some(hash) &&
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
    is Some(canonical) &&
    @shape.collection_construction_extent({
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
    is Some(identity) &&
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
    is Some(controls) else {
    return None
  }
  Some({
    record_headers: parser.record_headers +
    2L * canonical.record_headers +
    identity.record_headers +
    controls.record_headers +
    text.record_headers +
    hash.record_headers +
    8L,
    reference_slots: parser.reference_slots +
    2L * canonical.reference_slots +
    identity.reference_slots +
    controls.reference_slots +
    text.reference_slots +
    hash.reference_slots,
    scalar_words: parser.scalar_words +
    2L * canonical.scalar_words +
    identity.scalar_words +
    controls.scalar_words +
    text.scalar_words +
    hash.scalar_words,
    // The canonical DATA String bodies borrow the preserving Source. Sum of
    // serialized correlation/intended subtrees is <=B, not B for EACH row.
    // Include create-after wires, full canonical comparison and old/new
    // String growth. Create re-admits its after subtree while the full
    // canonical Preview remains live, hence the second canonical forest.
    // Content CIDs71U, row-identity JSON <=113U (Int occurrence <=10 digits),
    // and member CIDs71U are cumulative; row/hash temporaries are sequential.
    owned_utf16_units: parser.owned_utf16_units +
    text.owned_utf16_units +
    hash.owned_utf16_units +
    4L * bytes.to_int64() +
    255L * count +
    142L,
    // Original UTF8 encode(wire) and the one active incremental hash sink.
    owned_wire_bytes: bytes.to_int64() + hash.owned_wire_bytes,
  })
}
