///|
test "non-native targets reject the native filesystem capability" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT"))
  guard open_root("") is Err(UnsupportedTarget) else {
    fail("non-native target accepted the native filesystem capability")
  }
  assert_true(open_private_root("") is Err(UnsupportedTarget))
}

///|
test "non-native private Root custody retains refusal without acquiring a directory" {
  let original = match open_private_root_with_custody("") {
    Err(value) => value
    Ok(_) => {
      fail("non-native private Root custody was admitted")
      return
    }
  }
  assert_true(original.issue() is UnsupportedTarget)
  assert_true(original.root is None)
  original.retry_cleanup().unwrap()
  assert_true(original.issue() is UnsupportedTarget)
  let invalid = match
    open_private_root_with_custody("", diagnostic_ceiling=Some(0)) {
    Err(value) => value
    Ok(_) => {
      fail("invalid private Root limit was admitted")
      return
    }
  }
  assert_true(invalid.issue() is InvalidLimit)
  assert_true(invalid.root is None)
}
