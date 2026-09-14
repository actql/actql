///|
fn scored_body(
  declarations : String,
  type_? : String = "{\"nullable\":false,\"type\":\"number\"}",
) -> String {
  "{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"score\":" +
  type_ +
  "},\"nullable\":false,\"type\":\"object\"},\"score_contracts\":" +
  declarations +
  ",\"source_ref\":\"source:local/s/rows\",\"version\":\"actql-local-input-schema/0.1\"}"
}

///|
test "input score declaration retains independent identity and bounded indexed ownership" {
  let declaration = "{\"score\":{\"domain\":\"relevance\",\"normalization\":\"normalized\",\"range\":[0,1]}}"
  let body = scored_body(declaration)
  let bytes = @utf8.encode(body)
  // Independently canonicalized and hashed with Node, not the snapshot emitter.
  let expected = "sha256:be5fa7523f42ea4143a219d9426207fc87bd34ce219f5a0e6be028a08ed520ac"
  let snapshot = read(bytes, expected, caps()).unwrap()
  assert_eq(score_count(snapshot), 1)
  let (field, score) = score_at(snapshot, 0).unwrap()
  assert_eq(field, "score")
  assert_eq(score.domain, "relevance")
  assert_eq(score.normalization, "normalized")
  assert_eq((score.minimum, score.maximum), (0.0, 1.0))
  assert_false(score.explicit_higher_is_better)
  assert_true(score_at(snapshot, -1) is None)
  assert_true(score_at(snapshot, 1) is None)
  assert_true(materialization(snapshot) is None)
  let writer = @encode.writer(10000, 1000, 100)
  emit(snapshot, writer)
  assert_eq(@encode.finish(writer), body)
  let writer = @encode.writer(10000, 1000, 100)
  emit_type_projection(snapshot, writer)
  assert_false(@encode.finish(writer).contains("score_contracts"))
  let (size, nodes) = usage(snapshot)
  assert_true(
    read(bytes, expected, { max_bytes: size, max_nodes: nodes, max_depth: 100, })
    is Ok(_),
  )
  assert_true(
    read(bytes, expected, {
      max_bytes: size - 1,
      max_nodes: nodes,
      max_depth: 100,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    read(bytes, expected, {
      max_bytes: size,
      max_nodes: nodes - 1,
      max_depth: 100,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "score assertions validate their own fields type and closed semantics" {
  for
    declaration in [
      "null", "[]", "{\"absent\":{\"domain\":\"r\",\"normalization\":\"n\",\"range\":[0,1]}}",
      "{\"score\":{\"domain\":\"\",\"normalization\":\"n\",\"range\":[0,1]}}", "{\"score\":{\"domain\":\"r\",\"normalization\":\"\",\"range\":[0,1]}}",
      "{\"score\":{\"domain\":\"r\",\"normalization\":\"n\",\"range\":[1,0]}}", "{\"score\":{\"domain\":\"r\",\"normalization\":\"n\",\"range\":[0]}}",
      "{\"score\":{\"domain\":\"r\",\"higher_is_better\":false,\"normalization\":\"n\",\"range\":[0,1]}}",
      "{\"score\":{\"domain\":\"r\",\"normalization\":\"n\",\"range\":[0,1],\"verified\":true}}",
    ] {
    let bytes = @utf8.encode(scored_body(declaration))
    assert_true(
      read(bytes, "sha256:" + @sha.hex(bytes), caps()) is Err(InvalidSnapshot),
    )
  }
  let declaration = "{\"score\":{\"domain\":\"r\",\"higher_is_better\":true,\"normalization\":\"n\",\"range\":[0,1]}}"
  for
    type_ in [
      "{\"nullable\":true,\"type\":\"number\"}", "{\"nullable\":false,\"type\":\"string\"}",
    ] {
    let bytes = @utf8.encode(scored_body(declaration, type_~))
    assert_true(
      read(bytes, "sha256:" + @sha.hex(bytes), caps()) is Err(InvalidSnapshot),
    )
  }
  for d in [declaration, "{}"] {
    let body = scored_body(d)
    let bytes = @utf8.encode(body)
    let snapshot = read(bytes, "sha256:" + @sha.hex(bytes), caps()).unwrap()
    assert_eq(score_count(snapshot), if d == "{}" { 0 } else { 1 })
    let writer = @encode.writer(10000, 1000, 100)
    emit(snapshot, writer)
    assert_eq(@encode.finish(writer), body)
  }
}
