///|
test "non-native targets reject native publication storage" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"))
  guard @sqlite.load_library("") is Err(@sqlite.UnsupportedTarget) else {
    fail("non-native target accepted the native publication dependency")
  }
}

///|
test "non-native generated Content refuses Native custody without consuming the Common encoder" {
  let (encoder, rows) = generated_jsonl_test_input()
  assert_true(
    start_native_generated_content_output(encoder) is Err(UnsupportedTarget),
  )
  assert_eq(@publication.content_byte_completed_rows(encoder), 0)
  assert_true(
    @publication.advance_content_bytes(encoder, 64) is ContentBytesReady("", ..),
  )
  let text = StringBuilder()
  for row in rows {
    @publication.start_content_byte_row(encoder, _ => Some(row)).unwrap()
    guard @publication.advance_content_bytes(encoder, 64)
      is ContentBytesReady(piece, ..) else {
      fail("the original Common row did not finish")
    }
    text.write_string(piece)
  }
  assert_eq(text.to_string(), "{\"id\":1}\n{\"id\":2}\n")
  let completed = @publication.finish_content_bytes(encoder).unwrap()
  assert_eq((completed.row_count, completed.size_bytes), (2, 18))
}

///|
#warnings("-unused_value")
fn retain_native_wbtest_imports() -> Unit {
  let parsed = @source.parse_json("null", {
    max_input_bytes: 4,
    max_nodes: 1,
    max_depth: 0,
  })
  guard parsed is Ok(node) else { return }
  ignore(@json.from_source(node, 1, 0, 4) catch { _ => return })
  ignore(@encode.hashing_writer(1, 1, 0) catch { _ => return })
}
