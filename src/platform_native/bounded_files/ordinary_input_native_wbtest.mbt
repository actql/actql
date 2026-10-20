///|
fn ordinary_bounded_input_root() -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_BOUNDED_FILES_ROOT") is Some(root) &&
    root.has_prefix("/") else {
    fail("mandatory fresh ordinary bounded-input Root missing")
  }
  root
}

///|
// Real Native filesystem and diagnostic Root, not an entered Read supplier or
// ordinary CLI command qualification. Expected UTF-8 comes from this literal.
test "ordinary bounded text keeps Unicode whitespace and long basename exact" {
  let path = ordinary_bounded_input_root()
  let root = @filesystem.open_root(path).unwrap()
  let name = "parameter declarations-é-" + "a".repeat(130) + ".json"
  let writer = root.create_writer("ordinary-input-stage", 32L).unwrap()
  writer.append(b"{\"id\":7}\n").unwrap()
  writer.seal_file(name).unwrap() |> ignore
  assert_eq(
    read_bounded_ordinary_text_file_with_custody(
      path,
      name,
      9L,
      diagnostic_ceiling=Some(8),
    ).unwrap(),
    "{\"id\":7}\n",
  )
  assert_eq(
    read_bounded_ordinary_text_file_with_custody(
      path,
      name,
      9L,
      trim_newline=true,
      diagnostic_ceiling=Some(8),
    ).unwrap(),
    "{\"id\":7}",
  )
  // Existing managed object-name entry remains conservative.
  let old = read_bounded_text_file_with_custody(
    path,
    name,
    9L,
    diagnostic_ceiling=Some(8),
  ).unwrap_err()
  assert_true(old.issue() is Filesystem(@filesystem.InvalidName))
  old.retry_cleanup().unwrap()
  writer.cancel().unwrap()
  root.close().unwrap()
}

///|
test "ordinary bounded text preserves byte UTF8 and traversal refusals with cleanup" {
  let path = ordinary_bounded_input_root()
  let root = @filesystem.open_root(path).unwrap()
  let writer = root.create_writer("ordinary-invalid-stage", 8L).unwrap()
  writer.append(b"\xff").unwrap()
  writer.seal_file("invalid utf8.json").unwrap() |> ignore
  let invalid = read_bounded_ordinary_text_file_with_custody(
    path,
    "invalid utf8.json",
    8L,
    diagnostic_ceiling=Some(8),
  ).unwrap_err()
  assert_true(invalid.issue() is InvalidUtf8)
  invalid.retry_cleanup().unwrap()
  for name in ["../outside.json", "/absolute.json", "nested/params.json"] {
    let refused = read_bounded_ordinary_text_file_with_custody(
      path,
      name,
      8L,
      diagnostic_ceiling=Some(8),
    ).unwrap_err()
    assert_true(refused.issue() is Filesystem(@filesystem.InvalidName))
    refused.retry_cleanup().unwrap()
  }
  let over = read_bounded_ordinary_text_file_with_custody(
    path,
    "invalid utf8.json",
    0L,
    diagnostic_ceiling=Some(8),
  ).unwrap_err()
  assert_true(over.issue() is InvalidLimit)
  over.retry_cleanup().unwrap()
  writer.cancel().unwrap()
  root.close().unwrap()
}
