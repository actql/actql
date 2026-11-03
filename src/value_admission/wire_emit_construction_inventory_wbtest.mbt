///|
test "typed fragment inventory bounds escaped chunks with no value prewalk" {
  let builder = prepare_object_value(1, data_keys=true).unwrap()
  let name = "k".repeat(130)
  let text = "\u0001".repeat(130) + "é😀"
  assert_true(append_object_field(builder, name, Text(text)))
  let value = finish_object_value(builder).unwrap()
  let writer = @encode.buffered_writer(5000, 10, 3, wire_emit_fragment_byte_bound())
  let cursor = start_wire_emit(value, writer)
  let fragments = []
  let mut polls = 0
  while true {
    let inventory = wire_emit_next_construction_inventory(cursor).unwrap()
    assert_true(inventory.record_headers > 0L)
    let before = @encode.observed_writer_usage(writer).0
    let done = advance_wire_emit(cursor)
    let after = @encode.observed_writer_usage(writer).0
    assert_true(after - before <= wire_emit_fragment_byte_bound())
    fragments.push(@encode.drain_buffered_output(writer))
    polls += 1
    if done { break }
    if polls > 100 { assert_true(false) }
  }
  let (bytes, nodes, depth) = @encode.finish_buffered_usage(writer)
  let expected = @encode.writer(5000, 10, 3)
  emit_wire_value(value, expected)
  assert_eq(fragments.join(""), @encode.finish(expected))
  assert_eq((bytes, nodes, depth), (923, 2, 1))
  assert_true(polls > 10)
}

///|
test "typed emit inventory includes only selected Decimal construction scratch" {
  let output = @encode.buffered_writer(1000, 10, 3, 1000)
  let text = start_wire_emit(Text("x"), output)
  let decimal = start_wire_emit(Decimal({ coefficient: "-1", precision: 38, scale: 38, }), output)
  let plain = wire_emit_next_construction_inventory(text).unwrap()
  let selected = wire_emit_next_construction_inventory(decimal).unwrap()
  assert_eq(plain.owned_utf16_units, 0L)
  assert_true(selected.owned_utf16_units > 0L)
  assert_true(selected.record_headers > plain.record_headers)
  cancel_wire_emit(text)
  cancel_wire_emit(decimal)
  @encode.cancel_writer(output)
}

///|
test "typed fragment inventory retains the original issued reference envelope" {
  let wire = content_reference_wire().replace(
    old="\"issuer_evidence\":{}",
    new="\"issuer_evidence\":{\"original\":[\"" + "z".repeat(1024) + "\",null]}",
  )
  let checked = issue_reference(
    bind_reference_issuer((_, value) => value == wire, _ => true),
    reference_contract("{\"type\":\"content_ref\",\"nullable\":false}"),
    wire,
    { max_bytes: 10000, max_nodes: 64, max_depth: 5, max_text_units: 10000, },
  ).unwrap()
  let output = @encode.buffered_writer(10000, 64, 5, wire_emit_fragment_byte_bound())
  let cursor = start_wire_emit(checked.value, output)
  let fragments = []
  let mut turns = 0
  while true {
    assert_true(wire_emit_next_construction_inventory(cursor) is Some(_))
    let before = @encode.observed_writer_usage(output).0
    let done = advance_wire_emit(cursor)
    assert_true(@encode.observed_writer_usage(output).0 - before <= wire_emit_fragment_byte_bound())
    fragments.push(@encode.drain_buffered_output(output))
    turns += 1
    if done { break }
    if turns > 1000 { assert_true(false) }
  }
  @encode.finish_buffered_usage(output) |> ignore
  assert_eq(fragments.join(""), wire)
}

///|
test "typed deep then shallow inventory owns retained backing and retires stale frames" {
  let mut deep = Null
  for _ in 0..<40 { deep = array_value([deep]) }
  let value = array_value([deep, Boolean(true)])
  let output = @encode.buffered_writer(10000, 100, 50, 10000)
  let cursor = start_wire_emit(value, output)
  let mut deep_seen = false
  let mut shallow_seen = false
  for _ in 0..<500 {
    let before = cursor.pending.length()
    let done = advance_wire_emit(cursor)
    if before > 30 { deep_seen = true }
    if deep_seen && cursor.pending.length() <= 2 {
      shallow_seen = true
      let expected = wire_emit_construction_inventory(cursor.pending.capacity().to_int64(), None).unwrap()
      assert_eq(wire_emit_next_construction_inventory(cursor).unwrap(), expected)
    }
    if cursor.pending.length() < before && cursor.pending.capacity() >= before {
      assert_true(cursor.pending.unsafe_get(before - 1) is WireRetired)
    }
    @encode.drain_buffered_output(output) |> ignore
    if done { break }
  }
  assert_true(deep_seen && shallow_seen)
  @encode.finish_buffered_usage(output) |> ignore
}

///|
test "completed nested reference cursors cannot survive in vacated typed slots" {
  let wire = content_reference_wire().replace(
    old="\"issuer_evidence\":{}",
    new="\"issuer_evidence\":{\"deep\":" + "[".repeat(30) + "null" + "]".repeat(30) + "}",
  )
  let checked = issue_reference(
    bind_reference_issuer((_, value) => value == wire, _ => true),
    reference_contract("{\"type\":\"content_ref\",\"nullable\":false}"),
    wire,
    { max_bytes: 10000, max_nodes: 100, max_depth: 40, max_text_units: 10000, },
  ).unwrap()
  let output = @encode.buffered_writer(20000, 200, 45, 10000)
  let cursor = start_wire_emit(array_value([checked.value, checked.value]), output)
  let mut completed_references = 0
  for _ in 0..<1000 {
    let before = cursor.pending.length()
    let reference = cursor.pending.last() is Some(ReferenceNext(_))
    let done = advance_wire_emit(cursor)
    if reference && cursor.reference_frames == 0 {
      completed_references += 1
      if cursor.pending.capacity() >= before {
        assert_true(cursor.pending.unsafe_get(before - 1) is WireRetired)
      }
    }
    assert_true(wire_emit_next_construction_inventory(cursor) is Some(_))
    @encode.drain_buffered_output(output) |> ignore
    if done { break }
  }
  assert_eq(completed_references, 2)
  @encode.finish_buffered_usage(output) |> ignore
}
