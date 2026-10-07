///|
test "checked emission visits wide object children with exact bounded frame custody" {
  let number = primitive(NumberType, nullable=false)
  let fields = Array::makei(129, i => ("k" + (1000 + i).to_string(), number))
  let contract = object_contract(
    fields,
    nullable=false,
    max_fields=129,
    max_name_bytes=645,
  ).unwrap()
  let expected = StringBuilder()
  expected.write_string("{\"additional_properties\":false,\"fields\":{")
  for i in 0..<129 {
    if i > 0 {
      expected.write_string(",")
    }
    expected.write_string(
      "\"k" +
      (1000 + i).to_string() +
      "\":{\"nullable\":false,\"type\":\"number\"}",
    )
  }
  expected.write_string("},\"nullable\":false,\"type\":\"object\"}")
  let wire = expected.to_string()
  for quantum in [1, 7, 64] {
    let writer = @encode.writer(wire.length(), 5 + 3 * 129, 3)
    let cursor = start_checked_emission(contract, writer, 8)
    let mut peak = 1
    let mut done = false
    for _ in 0..<10000 {
      for _ in 0..<quantum {
        if !done {
          done = advance_checked_emission(cursor)
          peak = peak.max(cursor.pending.length())
        }
      }
      if done {
        break
      }
    }
    assert_true(done)
    assert_eq(peak, 8)
    assert_eq(@encode.finish_text_usage(writer), (wire, wire.length(), 392, 3))
    assert_true(
      cursor.pending.is_empty() && cursor.key is None && cursor.text is None,
    )
  }
  let writer = @encode.writer(wire.length(), 392, 3)
  let cursor = start_checked_emission(contract, writer, 7)
  let mut refused = false
  for _ in 0..<100 {
    if !refused {
      try advance_checked_emission(cursor) |> ignore catch {
        @encode.OutputLimit => refused = true
        _ => fail("wrong frame limit")
      }
    }
  }
  assert_true(refused && cursor.closed && cursor.pending.is_empty())
}

///|
test "checked emission yields inside long keys and reference text then cancels once" {
  let text = "x".repeat(1024) + "😀"
  for
    contract in [
      object_contract(
        [(text, primitive(NumberType, nullable=false))],
        nullable=false,
        max_fields=1,
        max_name_bytes=1028,
      ).unwrap(),
      { shape: ResourceRef(resource_kind=text), nullable: false, },
    ] {
    let writer = @encode.writer(5000, 100, 10)
    let cursor = start_checked_emission(contract, writer, 20)
    let mut found = false
    for _ in 0..<100 {
      advance_checked_emission(cursor) |> ignore
      // Both cursors are exclusive borrows of the caller's writer.
      if cursor.key is Some(_) || cursor.text is Some(_) {
        for _ in 0..<3 {
          advance_checked_emission(cursor) |> ignore
        }
        if cursor.key is Some(_) || cursor.text is Some(_) {
          found = true
          break
        }
      }
    }
    assert_true(found && !cursor.done)
    cancel_checked_emission(cursor)
    cancel_checked_emission(cursor)
    assert_true(cursor.closed && cursor.pending.is_empty())
    assert_true(cursor.key is None && cursor.text is None)
    assert_true(
      try {
        @encode.finish(writer) |> ignore
        false
      } catch {
        @encode.ClosedWriter => true
        _ => false
      },
    )
  }
}

///|
test "checked emission preserves writer exact byte node depth and embedding" {
  let number = primitive(NumberType, nullable=false)
  let expected = "{\"nullable\":false,\"type\":\"number\"}"
  for
    (bytes, nodes, depth) in [
      (expected.length() - 1, 3, 1),
      (expected.length(), 2, 1),
      (expected.length(), 3, 0),
    ] {
    let writer = @encode.writer(bytes, nodes, depth)
    let cursor = start_checked_emission(number, writer, 8)
    assert_true(
      try {
        while !advance_checked_emission(cursor) {
          ()
        }
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      },
    )
    assert_true(cursor.closed && cursor.pending.is_empty())
  }
  let writer = @encode.writer(expected.length() + 2, 4, 2)
  @encode.begin_array(writer)
  let cursor = start_checked_emission(number, writer, 8)
  while !advance_checked_emission(cursor) {
    ()
  }
  cancel_checked_emission(cursor)
  // Successful child transfer leaves the enclosing writer with its caller.
  @encode.end_array(writer)
  assert_eq(@encode.finish(writer), "[" + expected + "]")
}
