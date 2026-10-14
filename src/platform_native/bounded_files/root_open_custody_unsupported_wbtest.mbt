///|
test "configured bounded Root still refuses unsupported target with original custody" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_BOUNDED_FILES_ROOT").unwrap_or(
    "configured-root",
  )
  let failure = match read_bounded_text_file_with_custody(root, "value", 32L) {
    Err(value) => value
    Ok(_) => fail("non-Native target admitted physical Root")
  }
  assert_true(failure.issue() is Filesystem(@filesystem.UnsupportedTarget))
  assert_true(failure.rejected_root is Some(_))
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.rejected_root is None)
  assert_true(failure.issue() is Filesystem(@filesystem.UnsupportedTarget))
}
