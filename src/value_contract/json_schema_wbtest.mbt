///|
fn schema_fixture(fields : Array[(String, Contract)]) -> Contract {
  object_contract(fields, nullable=false, max_fields=256, max_name_bytes=20000).unwrap()
}

///|
test "strict schema projection preserves nested nullable closed required fields" {
  let contract = schema_fixture([
    (
      "a",
      array_contract(primitive(NumberType, nullable=true), nullable=false).unwrap(),
    ),
    ("b", schema_fixture([("quote\"", primitive(StringType, nullable=false))])),
    ("z", primitive(BooleanType, nullable=true)),
  ])
  let expected = "{\"additionalProperties\":false,\"properties\":{\"a\":{\"items\":{\"anyOf\":[{\"type\":\"number\"},{\"type\":\"null\"}]},\"type\":\"array\"},\"b\":{\"additionalProperties\":false,\"properties\":{\"quote\\\"\":{\"type\":\"string\"}},\"required\":[\"quote\\\"\"],\"type\":\"object\"},\"z\":{\"anyOf\":[{\"type\":\"boolean\"},{\"type\":\"null\"}]}},\"required\":[\"a\",\"b\",\"z\"],\"type\":\"object\"}"
  let mut work = None
  for quantum in [1, 7, 64] {
    let writer = @encode.writer(2000, 100, 16)
    let cursor = start_json_schema_emission(contract, writer, 40).unwrap()
    let mut done = false
    let mut steps = 0
    for _ in 0..<1000 {
      for _ in 0..<quantum {
        if !done {
          done = advance_json_schema_emission(cursor).unwrap()
          steps += 1
        }
      }
      if done {
        break
      }
    }
    assert_true(done)
    assert_eq(@encode.finish(writer), expected)
    if work is Some(previous) {
      assert_eq(steps, previous)
    }
    work = Some(steps)
  }
}

///|
test "strict schema projection refuses root variants and never erases constraints" {
  for
    contract in [
      primitive(NumberType, nullable=false),
      with_nullability(schema_fixture([]), true),
    ] {
    let writer = @encode.writer(5000, 100, 20)
    assert_true(
      start_json_schema_emission(contract, writer, 40) is Err(Unsupported),
    )
  }
  for
    child in [
      primitive(DateType, nullable=false),
      primitive(TimestampType, nullable=true),
      primitive(JsonType, nullable=false),
      decimal_contract(20, 4, nullable=false).unwrap(),
      vector_contract(3.0, nullable=false).unwrap(),
      string_contract(nullable=false, min_length=Some(0L)).unwrap(),
      string_contract(nullable=false, max_codepoints=Some(100L)).unwrap(),
      string_contract(nullable=false, max_utf8_bytes=Some(100L)).unwrap(),
      array_contract(
        primitive(NumberType, nullable=false),
        nullable=false,
        max_items=Some(1L),
      ).unwrap(),
      { nullable: false, shape: ResourceRef(resource_kind="fixture"), },
      { nullable: false, shape: ContentRef(media_type=None), },
    ] {
    let writer = @encode.writer(5000, 100, 20)
    let cursor = start_json_schema_emission(
      schema_fixture([("unsupported", child)]),
      writer,
      40,
    ).unwrap()
    let mut refused = false
    for _ in 0..<100 {
      match advance_json_schema_emission(cursor) {
        Err(Unsupported) => {
          refused = true
          break
        }
        Ok(false) => ()
        _ => fail("constraint disappeared")
      }
    }
    assert_true(refused && cursor.closed && cursor.pending.is_empty())
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
test "strict schema empty object has exact bytes nodes depth and no width allocation" {
  let expected = "{\"additionalProperties\":false,\"properties\":{},\"required\":[],\"type\":\"object\"}"
  let contract = schema_fixture([])
  let writer = @encode.writer(expected.length(), 5, 2)
  let cursor = start_json_schema_emission(contract, writer, 20).unwrap()
  while !advance_json_schema_emission(cursor).unwrap() {
    ()
  }
  assert_eq(
    @encode.finish_text_usage(writer),
    (expected, expected.length(), 5, 2),
  )
  for
    (bytes, nodes, depth) in [
      (expected.length() - 1, 5, 2),
      (expected.length(), 4, 2),
      (expected.length(), 5, 1),
    ] {
    let writer = @encode.writer(bytes, nodes, depth)
    let cursor = start_json_schema_emission(contract, writer, 20).unwrap()
    let mut refused = false
    for _ in 0..<100 {
      match advance_json_schema_emission(cursor) {
        Err(Limit) => {
          refused = true
          break
        }
        Ok(false) => ()
        _ => fail("exact schema writer limit not enforced")
      }
    }
    assert_true(refused && cursor.closed)
  }
}

///|
test "strict schema long field cursors cancel and exact limits remain enforced" {
  let name = "x".repeat(1024) + "😀"
  let contract = schema_fixture([(name, primitive(BooleanType, nullable=false))])
  let writer = @encode.writer(5000, 100, 10)
  let cursor = start_json_schema_emission(contract, writer, 30).unwrap()
  let mut inside = false
  for _ in 0..<100 {
    advance_json_schema_emission(cursor).unwrap() |> ignore
    if cursor.key is Some(_) {
      for _ in 0..<3 {
        advance_json_schema_emission(cursor).unwrap() |> ignore
      }
      if cursor.key is Some(_) {
        inside = true
        break
      }
    }
  }
  assert_true(inside)
  cancel_checked_emission(cursor)
  cancel_checked_emission(cursor)
  assert_true(advance_json_schema_emission(cursor) is Err(Closed))
  assert_true(
    cursor.pending.is_empty() && cursor.key is None && cursor.text is None,
  )
  for
    (bytes, nodes, depth, frames) in [
      (10, 100, 10, 30),
      (5000, 2, 10, 30),
      (5000, 100, 1, 30),
      (5000, 100, 10, 2),
    ] {
    let writer = @encode.writer(bytes, nodes, depth)
    let cursor = start_json_schema_emission(contract, writer, frames).unwrap()
    let mut limited = false
    for _ in 0..<1000 {
      match advance_json_schema_emission(cursor) {
        Err(Limit) => {
          limited = true
          break
        }
        Ok(false) => ()
        _ => fail("limit ignored")
      }
    }
    assert_true(limited && cursor.closed)
  }
}
