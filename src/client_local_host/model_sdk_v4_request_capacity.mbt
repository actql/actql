///|
/// Additional construction DATA for the closed SDK-v4 request verifier. This
/// is not a reservation, a new allowance, or an opaque engine/GC heap bound.
/// Expected wires can remain captured until the SAME original Read retires;
/// Only one serial writer/expected-parse workspace is additionally needed.
pub fn installed_node_model_sdk_v4_request_capacity(
  max_rows : Int,
  max_request_bytes : Int,
  projection_nodes : Int,
  projection_depth : Int,
) -> @execution.ExecutionCapacity? {
  if max_rows < 1 ||
    max_request_bytes < 1 ||
    max_request_bytes > 357913941 ||
    projection_nodes < 1 ||
    projection_nodes > 2147483629 ||
    projection_depth < 1 ||
    projection_depth > 2147483644 {
    return None
  }
  let expected_bytes = 6 * max_request_bytes
  let nodes = projection_nodes + 18
  let depth = projection_depth + 3
  guard @encode.text_writer_construction_inventory(expected_bytes, nodes, depth)
    is Some(writer) &&
    @source.json_literal_construction_extent(expected_bytes, nodes, depth)
    is Some(expected) &&
    @contract.checked_emission_construction_extent(projection_nodes)
    is Some(emission) else {
    return None
  }
  // The full expected parse is a CONSERVATIVE Source-parser envelope for
  // native JSON.parse, not a claim that it has Node/Value/Span wrappers. Its
  // decoded keys, values, growth and malformed-input construction are included.
  //
  // The previous verifier ALREADY parsed the actual body and compared a full
  // expected tree made from generation/messages and a separate schema parse.
  // The new Common profile preserves that tree's values, shape and depth.
  // Canonical key order does not increase the matching tree's worst ancestor
  // arrays, descriptors, recursion or possible cycle-memo domain. Those SAME
  // actual-parse/compare/SDK duties stay with the complete previous Read base;
  // do not rebill them here, release them early, or call them unrelated spare.
  // Charging the entire new expected parse is conservative: the old schema
  // parse/literal-building base is deliberately not subtracted from the Read.
  // Full-body caller controls: two (role, content) pairs, start/advance/finish
  // result alternatives, one two-pair Array and the four scalar work costs.
  // Literal role/key Strings and original materials stay borrowed.
  guard @shape.collection_construction_extent({
      records: 5L,
      record_references: 7L,
      record_words: 3L,
      reference_arrays: 1L,
      reference_items: 2L,
      scalar_arrays: 1L,
      scalar_items: 4L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(caller) else {
    return None
  }
  // The returned String1H, isolated verifier closure1H1R and its context1H1R
  // survive per row. The new eight-field return tuple is only a handoff peak;
  // no completed writer, parsed tree, comparison key array or memo is retained.
  // The writer inventory already includes that SAME returned String, so remove
  // it from workspace instead of charging another output copy alongside it.
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 3L * max_rows.to_int64(),
      reference_slots: 2L * max_rows.to_int64(),
      scalar_words: 0L,
      owned_utf16_units: max_rows.to_int64() * expected_bytes.to_int64(),
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: writer.record_headers -
      1L +
      expected.record_headers +
      emission.record_headers +
      caller.record_headers +
      1L,
      reference_slots: writer.reference_slots +
      expected.reference_slots +
      emission.reference_slots +
      caller.reference_slots +
      8L,
      scalar_words: writer.scalar_words +
      expected.scalar_words +
      emission.scalar_words +
      caller.scalar_words,
      owned_utf16_units: writer.owned_utf16_units -
      expected_bytes.to_int64() +
      expected.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
