///|
test "non-native targets reject native publication storage" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"))
  guard @sqlite.load_library("") is Err(@sqlite.UnsupportedTarget) else {
    fail("non-native target accepted the native publication dependency")
  }
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
