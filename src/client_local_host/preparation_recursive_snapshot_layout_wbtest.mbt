///|
test "recursive snapshot geometry covers independent nested Unicode canonical storage" {
  // Bare rows:32 UTF-8 bytes,7 value nodes,5 open containers. The logical
  // relation wrapper adds28 bytes,2 value nodes and one container.
  let wire = "[{\"x\":{\"a\":[1,{\"b\":\"東京\"}]}}]"
  let quote = recursive_snapshot_layout(60, 9, 6, 1, 1).unwrap()
  let source = @source.parse_json(wire, {
    max_input_bytes: 32,
    max_nodes: 7,
    max_depth: 5,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 7,
    max_depth: 5,
    max_string_bytes: 32,
    max_total_string_bytes: 32,
  }).unwrap()
  let admission = @identity.start_cursor_admission(
    cursor,
    7,
    5,
    32,
    32,
    data_keys=true,
  ).unwrap()
  let mut value : @identity.CanonicalValue? = None
  for _ in 0..<1000 {
    match @identity.advance_cursor_admission(admission) {
      @identity.CursorAdmissionContinue => ()
      @identity.CursorAdmissionComplete(v, _, _) => {
        value = Some(v)
        break
      }
      _ => fail("independent nested cursor admission")
    }
  }
  let actual = @identity.representation_extent(value.unwrap(), 7, 5, 32).unwrap()
  assert_eq((actual.nodes, actual.arrays, actual.objects), (7L, 2L, 3L))
  let containers = actual.arrays + actual.objects
  let measured : @execution.PreparationRepresentationUnits = {
    record_headers: actual.nodes + 3L * containers + 3L + 4L,
    reference_slots: actual.nodes +
    2L * containers +
    actual.array_backing_slots +
    actual.object_backing_slots +
    6L,
    scalar_words: actual.nodes + 2L * containers,
    owned_utf16_units: 5L,
    owned_wire_bytes: 0L,
  }
  assert_true(
    @execution.preparation_representation_cost(quote.retained).unwrap() >=
    @execution.preparation_representation_cost(measured).unwrap(),
  )
  let writer = @encode.writer(32, 7, 5)
  @identity.emit_value(value.unwrap(), writer)
  assert_eq(@encode.finish(writer), wire)
  assert_true(recursive_snapshot_layout(30, 3, 2, 0, 0) is Some(_))
  assert_true(recursive_snapshot_layout(60, 9, 9, 1, 1) is None)
  assert_true(recursive_snapshot_layout(60, 2, 6, 1, 1) is None)
  assert_true(recursive_snapshot_layout(60, 9, 6, -1, 1) is None)
  assert_true(recursive_snapshot_layout(60, 2147483647, 6, 1, 1) is None)
}
