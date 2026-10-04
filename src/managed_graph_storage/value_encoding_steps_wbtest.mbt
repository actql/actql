///|
fn encoded_fixture_value() -> @value.CheckedValue {
  @value.admit(
    @contract.primitive(@contract.JsonType, nullable=false),
    cursor("{\"z\":[null,2],\"a\":{\"d\":[true]}}"),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn complete_value_encoding(
  value : ValueEncoding,
  quantum : Int,
) -> Result[(String, Int, Int, Int), Issue] raise {
  let mut total = 0
  for _ in 0..<1000 {
    let poll = advance_value_encoding(value, quantum)
    let work = match poll {
      ValueEncodingContinue(work~)
      | ValueEncodingComplete(_, work~, ..)
      | ValueEncodingFailed(_, work~) => work
    }
    assert_true(work >= 1 && work <= quantum)
    total += work
    match poll {
      ValueEncodingContinue(..) => ()
      ValueEncodingComplete(text, bytes~, nodes~, ..) =>
        return Ok((text, bytes, nodes, total))
      ValueEncodingFailed(issue, ..) => return Err(issue)
    }
  }
  abort("value encoding did not terminate")
}

///|
test "Storage wire encoding resumes without reinterpreting construction limits" {
  let values = [encoded_fixture_value()]
  let expected = "[{\"a\":{\"d\":[true]},\"z\":[null,2]}]"
  for quantum in [1, 7, 64] {
    let builder = prepare(property_fixture(), DeclaredNodes, {
      ..property_limits(),
      max_work: 8,
    }).unwrap()
    let encoding = start_value_encoding(builder, values, 0, 0)
    let (text, bytes, nodes, steps) = complete_value_encoding(encoding, quantum).unwrap()
    assert_eq((text, bytes, nodes), (expected, 33, 8))
    assert_true(steps > nodes)
    assert_eq(builder.work, 0)
    assert_true(builder.open && builder.owns_private)
    cleanup_value_encoding(encoding)
    cleanup_value_encoding(encoding)
    assert_eq(values.length(), 1)
    assert_true(
      advance_value_encoding(encoding, 1) is ValueEncodingFailed(Closed, work=0),
    )
    assert_true(cancel(builder))
  }
  let builder = prepare(property_fixture(), DeclaredNodes, {
    ..property_limits(),
    max_work: 8,
  }).unwrap()
  assert_eq(encoded_values(builder, values, 0, 0), Ok((expected, 33, 8)))
  assert_eq(encoded_values(builder, values, 0, 1), Err(WorkLimit))
  assert_true(cancel(builder))
}

///|
test "Storage wire encoding reports failed work and keeps cleanup with its owner" {
  let values = [encoded_fixture_value()]
  for
    (limits, expected) in [
      ({ ..property_limits(), max_value_bytes: 32, }, ValueLimit),
      ({ ..property_limits(), max_value_nodes: 7, }, ValueLimit),
      ({ ..property_limits(), max_value_depth: 3, }, ValueLimit),
      ({ ..property_limits(), max_work: 7, }, WorkLimit),
      ({ ..property_limits(), max_total_value_bytes: 32, }, ValueLimit),
    ] {
    let builder = prepare(property_fixture(), DeclaredNodes, limits).unwrap()
    let encoding = start_value_encoding(builder, values, 0, 0)
    assert_eq(complete_value_encoding(encoding, 1), Err(expected))
    assert_true(builder.open && builder.owns_private)
    assert_true(encoding.writer is Some(_))
    cleanup_value_encoding(encoding)
    assert_true(
      encoding.writer is None &&
      encoding.emission is None &&
      encoding.values is None,
    )
    assert_eq(values.length(), 1)
    assert_true(cancel(builder))
  }
}

///|
test "Storage wire cancellation preserves borrowed values and original builder" {
  let values = [encoded_fixture_value()]
  for
    phase in [
      ResolveValueEncoding,
      BeginValueEncoding,
      NextValueEncoding,
      EmitValueEncoding,
      EndValueEncoding,
      FinishValueEncoding,
    ] {
    let builder = prepare(property_fixture(), DeclaredNodes, property_limits()).unwrap()
    let encoding = start_value_encoding(builder, values, 0, 0)
    assert_true(
      advance_value_encoding(encoding, 0)
      is ValueEncodingFailed(InvalidLimits, work=0),
    )
    assert_true(encoding.phase == ResolveValueEncoding)
    for _ in 0..<100 {
      if encoding.phase == phase {
        break
      }
      assert_true(
        advance_value_encoding(encoding, 1) is ValueEncodingContinue(work=1),
      )
    }
    assert_true(encoding.phase == phase)
    cleanup_value_encoding(encoding)
    cleanup_value_encoding(encoding)
    assert_true(
      encoding.writer is None &&
      encoding.emission is None &&
      encoding.values is None,
    )
    assert_eq(values.length(), 1)
    assert_true(builder.open && builder.owns_private)
    assert_eq(
      encoded_values(builder, values, 0, 0),
      Ok(("[{\"a\":{\"d\":[true]},\"z\":[null,2]}]", 33, 8)),
    )
    assert_true(cancel(builder))
  }
}
