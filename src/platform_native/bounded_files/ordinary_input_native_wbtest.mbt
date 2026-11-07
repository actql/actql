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

///|
// Real ordinary file generation/Reader/UTF8 only. The callback is an explicit
// before-allocation test port, NOT an actual Request debit or physical grant.
test "observed ordinary input backs its actual extent before any payload Reader" {
  let path = ordinary_bounded_input_root()
  let root = @filesystem.open_root(path).unwrap()
  let text = "x".repeat(70000)
  let writer = root.create_writer("observed-input-stage", 70000L).unwrap()
  writer.append(@utf8.encode(text)).unwrap()
  let generation = writer.seal_file("observed input.json").unwrap()
  let observed = Ref(0L)
  let refused = read_bounded_text_file_selected(
    path,
    "observed input.json",
    2147483518L,
    false,
    Some(128),
    false,
    true,
    prepare_payload=Some(bytes => {
      observed.val = bytes
      false
    }),
  ).unwrap_err()
  assert_eq(observed.val, 70000L)
  assert_true(refused.issue() is PreparationUnavailable)
  assert_true(refused.reader is None && refused.rejected_reader is None)
  refused.retry_cleanup().unwrap()
  assert_eq(
    root.inspect_file_generation("observed input.json").unwrap(),
    Some(generation),
  )
  let calls = Ref(0)
  let result = read_bounded_text_file_selected(
    path,
    "observed input.json",
    2147483518L,
    false,
    Some(128),
    false,
    true,
    prepare_payload=Some(bytes => {
      calls.val += 1
      bytes == 70000L
    }),
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(result, text)
  writer.cancel().unwrap()
  root.close().unwrap()
}

///|
test "observed ordinary input keeps original generation across its preparation callback" {
  let path = ordinary_bounded_input_root()
  let root = @filesystem.open_root(path).unwrap()
  let writer = root.create_writer("observed-changing-stage", 4L).unwrap()
  writer.append(b"old").unwrap()
  let failure = read_bounded_text_file_selected(
    path,
    "observed-changing-stage",
    2147483518L,
    false,
    Some(128),
    false,
    true,
    prepare_payload=Some(bytes => {
      if bytes != 3L {
        return false
      }
      // Keep this writer's own staging/cleanup obligation. Changing its size
      // invalidates the observed generation without replacing another owner.
      writer.append(b"x").unwrap()
      true
    }),
  ).unwrap_err()
  assert_true(failure.issue() is Filesystem(@filesystem.GenerationMismatch))
  failure.retry_cleanup().unwrap()
  writer.cancel().unwrap()
  root.close().unwrap()
}
