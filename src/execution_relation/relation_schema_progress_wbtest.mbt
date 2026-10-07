///|
test "schema identity preparation resumes recursive fields with fixed wire and CID" {
  let text = @contract.string_contract(
    nullable=true,
    min_length=Some(1L),
    max_codepoints=Some(4L),
    max_utf8_bytes=Some(16L),
  ).unwrap()
  let decimals = @contract.array_contract(
    @contract.decimal_contract(9, 2, nullable=true).unwrap(),
    nullable=false,
    max_items=Some(3L),
  ).unwrap()
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("\ue000"), decimals),
      (@schema.Unqualified("😀"), text),
    ],
    max_fields=2,
    max_name_bytes=7,
  ).unwrap()
  for quantum in [1, 7, 64] {
    let cursor = start_relation_schema_identity(schema, {
      max_fields: 2,
      max_bytes: 217,
      max_nodes: 16,
      max_depth: 3,
    }).unwrap()
    assert_true(finish_relation_schema_identity(cursor) is Err(NotFinished))
    let mut done = false
    for _ in 0..<1000 {
      let (finished, used) = advance_relation_schema_identity(cursor, quantum).unwrap()
      assert_true(used > 0 && used <= quantum)
      if finished {
        done = true
        break
      }
    }
    assert_true(done)
    let identity = finish_relation_schema_identity(cursor).unwrap()
    assert_eq(
      relation_schema_cid(identity),
      "sha256:e13e51f472cae3497095edf7f88922ebd7bf0b1c48f2bc31480b47406728c2e6",
    )
    assert_eq(relation_schema_usage(identity), (217, 16, 2))
    assert_eq(relation_schema_field_names(identity), ["😀", "\ue000"])
    assert_true(cursor.names.is_empty() && cursor.schema is None)
    assert_true(cursor.hash_writer is None && cursor.wire_writer is None)
    assert_true(finish_relation_schema_identity(cursor) is Err(Closed))
  }
  for
    limits in [
      { max_fields: 2, max_bytes: 216, max_nodes: 16, max_depth: 3, },
      { max_fields: 2, max_bytes: 217, max_nodes: 15, max_depth: 3, },
      { max_fields: 2, max_bytes: 217, max_nodes: 16, max_depth: 2, },
    ] {
    let cursor = start_relation_schema_identity(schema, limits).unwrap()
    let mut refused = false
    for _ in 0..<1000 {
      match advance_relation_schema_identity(cursor, 1) {
        Err(Encoding(@encode.OutputLimit)) => {
          refused = true
          break
        }
        Ok((false, 1)) => ()
        _ => fail("wrong schema one-short cause")
      }
    }
    assert_true(refused && cursor.closed && cursor.schema is None)
    assert_true(cursor.hash_writer is None && cursor.wire_writer is None)
    assert_true(
      cursor.names.is_empty() && cursor.contract is None && cursor.key is None,
    )
  }
}

///|
test "schema preparation cancels during hash and wire emission without partial identity" {
  let name = "x".repeat(1024) + "😀"
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified(name),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=1028,
  ).unwrap()
  for pass in [0, 1] {
    let cursor = start_relation_schema_identity(schema, {
      max_fields: 1,
      max_bytes: 2000,
      max_nodes: 10,
      max_depth: 10,
    }).unwrap()
    let mut found = false
    for _ in 0..<1000 {
      advance_relation_schema_identity(cursor, 1).unwrap() |> ignore
      if cursor.pass == pass && cursor.phase == 2 {
        for _ in 0..<3 {
          advance_relation_schema_identity(cursor, 1).unwrap() |> ignore
        }
        assert_eq(cursor.phase, 2)
        found = true
        break
      }
    }
    assert_true(found && cursor.identity is None)
    assert_true(cancel_relation_schema_identity(cursor))
    assert_false(cancel_relation_schema_identity(cursor))
    assert_true(cursor.schema is None && cursor.hash_writer is None)
    assert_true(cursor.wire_writer is None && cursor.names.is_empty())
    assert_true(advance_relation_schema_identity(cursor, 1) is Err(Closed))
    assert_true(finish_relation_schema_identity(cursor) is Err(Closed))
    assert_eq(@schema.field_count(schema), 1)
  }
}

///|
test "schema preparation preserves conditional presence and empty maps" {
  let source = presence_test_schema()
  let expected = "{\"id\":{\"nullable\":false,\"type\":\"number\"},\"p\":{\"contract\":{\"nullable\":true,\"type\":\"number\"},\"presence\":\"conditional\"}}"
  let identity = identify_relation_schema(source, schema_identity_limits()).unwrap()
  assert_eq(relation_schema_wire(identity), expected)
  // Independent SHA-256 of the literal above, calculated with Node crypto.
  assert_eq(
    relation_schema_cid(identity),
    "sha256:10ce8369a6cadfefd6e712b9af9320c69915df75a0a9654c7d69788ef23a437c",
  )
  let empty = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let cursor = start_relation_schema_identity(empty, {
    max_fields: 0,
    max_bytes: 2,
    max_nodes: 1,
    max_depth: 1,
  }).unwrap()
  for _ in 0..<8 {
    if advance_relation_schema_identity(cursor, 1).unwrap().0 {
      break
    }
  }
  assert_eq(
    relation_schema_cid(finish_relation_schema_identity(cursor).unwrap()),
    "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
  )
}
