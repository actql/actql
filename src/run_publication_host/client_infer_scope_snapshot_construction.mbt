///|
// Fixed preflight for the SAME snapshot emitter. The geometry sink adds its
// six counters, output variant and returned nine-scalar report to the existing
// measuring Writer. The quotation separately covers the text-frame,
// canonical-tree and Node-wrapper collection expansions. A fourth SAME
// expansion bounds the parser's smaller key-admission/map quotation. Remaining
// report/Result/Option controls and the five-field Source tuple emitter are
// fixed controls, not one retained copy per Source.
pub fn client_infer_scope_snapshot_measurement_capacity() -> @execution.ExecutionCapacity? {
  let quote = @shape.collection_construction_quotation_extent()
  guard @encode.measuring_writer_construction_extent(10, 3) is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + 20L + 4L * quote.record_headers,
      reference_slots: writer.reference_slots + 40L + 4L * quote.reference_slots,
      scalar_words: writer.scalar_words + 40L + 4L * quote.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return None
  }
  @execution.execution_capacity(bytes, bytes)
}

///|
/// Called only within the prefunded measurement above. It uses the SAME
/// emitter, original Scope strings and existing codec limits. No snapshot
/// body, guessed CID, permission or Resource admission is constructed here.
/// Node facts/slot-reference wrappers borrow their existing call evidence;
/// the cached snapshot String and its parse/encoding peak remain separate.
pub fn client_infer_scope_snapshot_construction_capacity(
  value : ClientInferCallScope,
  calls : Int,
) -> @execution.ExecutionCapacity? {
  if calls < 0 ||
    !client_infer_call_scope_generation_available(value) ||
    !@execution.completed_output_available(value.input) {
    return None
  }
  let writer = @encode.construction_measuring_writer(1000000, 100000, 100) catch {
    _ => return None
  }
  if emit_client_infer_call_scope_snapshot(value, writer) is Err(_) {
    return None
  }
  let g = @encode.finish_construction_measurement(writer) catch {
    _ => return None
  }
  // This original snapshot has only String leaves. data_keys:true preserves
  // their scalar text; canonical field sorting changes no encoded extent.
  guard @encode.text_writer_construction_inventory(g.bytes, g.nodes, g.depth)
    is Some(text) &&
    @decode.preserving_json_parser_construction_inventory(
      g.bytes,
      g.nodes,
      g.depth,
    )
    is Some(parser) else {
    return None
  }
  let n = g.nodes.to_int64()
  let f = g.fields.to_int64()
  let a = g.arrays.to_int64()
  let o = g.objects.to_int64()
  let d = g.depth.to_int64() + 1L
  // from_source(data_keys:true): variants, FrozenArray wrappers, object
  // pairs, exact-key maps, old/new array storage and bounded recursion/sort.
  // Scalar text is borrowed from the parser, never normalized/copied again.
  guard @shape.collection_construction_extent({
      records: n + f + a + o + d,
      record_references: n + 3L * f + 2L * a + 2L * o + 3L * d,
      record_words: n + f + o + 2L * d,
      reference_arrays: a + o,
      reference_items: 2L * n + 2L * f,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: o,
      map_entries: f,
    })
    is Some(canonical) &&
    @shape.collection_construction_extent({
      // Facts/identities/originals/boundary records and their retained refs;
      // slotWires, its originals copy and the slot-CID projection coexist.
      records: 20L,
      record_references: 64L,
      record_words: 16L,
      reference_arrays: 3L,
      reference_items: 3L * calls.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(wrappers) &&
    @execution.preparation_representation_cost({
      record_headers: wrappers.record_headers + 2L,
      reference_slots: wrappers.reference_slots + 1L,
      scalar_words: wrappers.scalar_words + 1L,
      owned_utf16_units: g.bytes.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      // Co-count the emitter and canonical writer, preserving parser,
      // canonical tree and returned cached wire through the actual return.
      record_headers: wrappers.record_headers +
      2L * text.record_headers +
      parser.record_headers +
      canonical.record_headers +
      2L,
      reference_slots: wrappers.reference_slots +
      2L * text.reference_slots +
      parser.reference_slots +
      canonical.reference_slots +
      1L,
      scalar_words: wrappers.scalar_words +
      2L * text.scalar_words +
      parser.scalar_words +
      canonical.scalar_words +
      1L,
      owned_utf16_units: g.bytes.to_int64() +
      2L * text.owned_utf16_units +
      parser.owned_utf16_units,
      owned_wire_bytes: g.bytes.to_int64(),
    })
    is Some(peak) else {
    return None
  }
  @execution.execution_capacity(retained, peak)
}
