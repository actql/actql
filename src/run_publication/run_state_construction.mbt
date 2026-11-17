///|
/// Existing bounded RunState projection and its later observation admission.
/// This is construction DATA, not a status, authority, Store ACK or changed
/// semantic limit. The caller keeps this packet coheld with its live validator.
pub fn run_state_observation_construction_inventory(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  guard publication_returned_contract_inventory(max_bytes, max_nodes, max_depth)
    is Some(tree) &&
    protocol_wire_codec_construction_inventory(max_bytes, max_nodes, max_depth)
    is Some(codec) else {
    return None
  }
  let n = Int::min(max_bytes, max_nodes).to_int64()
  guard @shape.collection_construction_extent({
      // Availability records and fixed observation/state/controller carriers.
      records: 16L + n,
      record_references: 64L + 3L * n,
      record_words: 32L,
      // names/observations/timestamps, ordered/declared copies, times,
      // unknown/available actions and independent duplicate/target inventories.
      reference_arrays: 12L,
      reference_items: 16L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  let retained = {
    // The accepted observation and revised saved-State originals can coexist.
    // Count their genuine canonical/text DATA, not temporary parser cursors.
    record_headers: 2L * tree.record_headers + 8L,
    reference_slots: 2L * tree.reference_slots + 32L,
    scalar_words: 2L * tree.scalar_words + 16L,
    owned_utf16_units: 2L * tree.owned_utf16_units + 2L * max_bytes.to_int64(),
    owned_wire_bytes: 2L * tree.owned_wire_bytes,
  }
  Some(
    (
      retained,
      {
        record_headers: codec.record_headers + controls.record_headers,
        reference_slots: codec.reference_slots + controls.reference_slots,
        scalar_words: codec.scalar_words + controls.scalar_words,
        owned_utf16_units: codec.owned_utf16_units,
        owned_wire_bytes: codec.owned_wire_bytes,
      },
    ),
  )
}
