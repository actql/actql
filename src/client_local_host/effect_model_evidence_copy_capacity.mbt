///|
/// Next optional copy phase over an already exported original bundle and the
/// SAME typed-input emitter. These are actual wire/constructor observations,
/// not the optional destination's maxBytes allowance. The caller reserves one
/// reusable window on its existing Model publication owner before decoding.
pub fn client_effect_model_evidence_copy_capacity(
  bundle_bytes : Int,
  bundle_nodes : Int,
  bundle_depth : Int,
  input : @encode.EncodingConstructionGeometry,
  other_text_units : Int,
  calls : Int,
) -> @execution.ExecutionCapacity? {
  if bundle_bytes < 1 ||
    bundle_nodes < 1 ||
    bundle_depth < 1 ||
    other_text_units < 0 ||
    calls < 1 ||
    calls > 128 {
    return None
  }
  guard program_artifact_parse_layout(
      (bundle_bytes, bundle_nodes, bundle_depth),
    )
    is Some(bundle) &&
    program_artifact_parse_layout(
      @encode.construction_geometry_usage(input),
      structure=Some(input),
    )
    is Some(frame) else {
    return None
  }
  // The bundle decoder, one typed-input decoder and that call's outgoing
  // strings coexist. Six is the JSON String encoder's maximum expansion per
  // observed unit (\uXXXX), not a representation tariff or retained-node count.
  // The complete bundle bounds its response/evidence subtrees; previous call
  // scratch ends at the Sink return and does not accumulate for the next call.
  let wire = 6L *
    (
      bundle_bytes.to_int64() +
      input.bytes.to_int64() +
      other_text_units.to_int64()
    )
  let nodes = bundle_nodes.to_int64() + input.nodes.to_int64()
  if wire > 2147483647L || nodes > 2147483647L {
    return None
  }
  guard @encode.text_writer_construction_inventory(
      wire.to_int(),
      nodes.to_int(),
      Int::max(bundle_depth, input.depth),
    )
    is Some(writer) &&
    @shape.collection_construction_extent({
      records: calls.to_int64(),
      record_references: 8L * calls.to_int64(),
      record_words: 0L,
      reference_arrays: 0L,
      reference_items: 4L * calls.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: calls.to_int64(),
    })
    is Some(inventory) &&
    @execution.compose_preparation_representation([
      bundle.value,
      frame.value,
      {
        record_headers: inventory.record_headers,
        reference_slots: inventory.reference_slots,
        scalar_words: inventory.scalar_words,
        owned_utf16_units: wire,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      bundle.temporary,
      frame.temporary,
      {
        record_headers: writer.record_headers,
        reference_slots: writer.reference_slots,
        scalar_words: writer.scalar_words,
        owned_utf16_units: writer.owned_utf16_units,
        owned_wire_bytes: wire,
      },
    ])
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
