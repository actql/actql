///|
test "native filesystem rejects a missing root" {
  guard open_root("/actql/missing/native-store") is Err(RootOpen(_)) else {
    fail("missing native Store root was accepted")
  }
}

///|
test "native filesystem bounds and durably links one generation" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let staging = "stage-" + token
  let final_name = "object-" + token
  let writer = root.create_writer(staging, 4L).unwrap()
  assert_true(writer.cleanup_pending())
  assert_true(writer.append(b"ab") is Ok(_))
  assert_true(writer.append(b"cd") is Ok(_))
  assert_true(writer.append(b"e") is Err(CapacityExceeded))
  assert_eq(writer.written(), 4L)
  let generation = writer.seal(final_name).unwrap()
  assert_eq(generation.size, 4L)
  assert_true(writer.is_sealed())
  assert_false(writer.cleanup_pending())
  assert_true(root.verify_generation(final_name, generation))
  let repeated = writer.seal(final_name).unwrap()
  assert_eq(repeated.device, generation.device)
  assert_eq(repeated.inode, generation.inode)
  assert_eq(repeated.size, generation.size)
  assert_true(writer.cancel() is Ok(_))
  assert_false(writer.cleanup_pending())
  assert_false(root.verify_generation(final_name, generation))
  assert_true(writer.cancel() is Ok(_))
}

///|
test "native filesystem rejects invalid names and committed conflicts" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  guard root.create_writer("../escape", 1L) is Err(InvalidName) else {
    fail("invalid staging name was accepted")
  }
  guard root.create_writer("negative-limit", -1L) is Err(InvalidLimit) else {
    fail("negative limit was accepted")
  }
  let token = @env.now().to_string()
  let final_name = "conflict-object-" + token
  let first = root.create_writer("conflict-a-" + token, 1L).unwrap()
  let second = root.create_writer("conflict-b-" + token, 1L).unwrap()
  first.append(b"a").unwrap()
  second.append(b"b").unwrap()
  ignore(first.seal(final_name).unwrap())
  assert_true(second.seal(final_name) is Err(Conflict))
  assert_true(second.cleanup_pending())
  second.cancel().unwrap()
  first.cancel().unwrap()
}
