///|
#borrow(root)
extern "C" fn test_fail_root_sync(root : Root, failures : Int) -> Unit = "actql_native_filesystem_test_fail_root_sync"

///|
test "native filesystem rejects a missing root" {
  guard open_root("/actql/missing/native-store") is Err(RootOpen(_)) else {
    fail("missing native Store root was accepted")
  }
}

///|
test "native filesystem grants one process owner per Store lock" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let first_root = open_root(path).unwrap()
  let second_root = open_root(path).unwrap()
  let owner = first_root.acquire_lock("runtime-bundle-test.lock").unwrap()
  assert_true(
    second_root.acquire_lock("runtime-bundle-test.lock") is Err(Lock(_)),
  )
  assert_true(owner.close())
  let successor = second_root.acquire_lock("runtime-bundle-test.lock").unwrap()
  assert_true(successor.close())
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
  let reader = root.open_reader(final_name, generation).unwrap()
  assert_true(writer.cancel() is Ok(_))
  assert_false(writer.cleanup_pending())
  assert_false(root.verify_generation(final_name, generation))
  let first = reader.next(2).unwrap()
  assert_eq(first.bytes, b"ab")
  assert_false(first.eof)
  let second = reader.next(2).unwrap()
  assert_eq(second.bytes, b"cd")
  assert_false(second.eof)
  let terminal = reader.next(2).unwrap()
  assert_eq(terminal.bytes, b"")
  assert_true(terminal.eof)
  assert_true(reader.finish() is Ok(_))
  reader.close().unwrap()
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

///|
test "native filesystem reader requires exact generation and full read" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let final_name = "read-object-" + token
  let writer = root.create_writer("read-stage-" + token, 3L).unwrap()
  writer.append(b"abc").unwrap()
  let generation = writer.seal(final_name).unwrap()
  let wrong = { ..generation, size: 2L, }
  assert_true(root.open_reader(final_name, wrong) is Err(GenerationMismatch))
  let reader = root.open_reader(final_name, generation).unwrap()
  assert_true(reader.next(0) is Err(InvalidReadSize))
  assert_true(reader.next(1048577) is Err(InvalidReadSize))
  assert_eq(reader.next(1).unwrap().bytes, b"a")
  assert_true(reader.finish() is Err(IncompleteRead))
  reader.close().unwrap()
  assert_true(reader.next(1) is Err(ReaderClosed))
  let complete_reader = root.open_reader(final_name, generation).unwrap()
  assert_eq(complete_reader.next(3).unwrap().bytes, b"abc")
  complete_reader.finish().unwrap()
  writer.cancel().unwrap()
}

///|
test "native filesystem reclaims only the exact durable generation" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let name = "reclaim-object-" + token
  let writer = root.create_writer("reclaim-stage-" + token, 3L).unwrap()
  writer.append(b"abc").unwrap()
  let generation = writer.seal(name).unwrap()
  assert_eq(root.inspect_generation(name).unwrap(), Some(generation))
  let wrong = { ..generation, inode: generation.inode + 1UL, }
  assert_true(root.reclaim_generation(name, wrong) is Err(GenerationMismatch))
  assert_true(root.verify_generation(name, generation))
  root.reclaim_generation(name, generation).unwrap()
  assert_false(root.verify_generation(name, generation))
  assert_eq(root.inspect_generation(name).unwrap(), None)
  root.reclaim_generation(name, generation).unwrap()
}

///|
test "native filesystem retries directory sync after unlink" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let name = "reclaim-sync-object-" + token
  let writer = root.create_writer("reclaim-sync-stage-" + token, 3L).unwrap()
  let ownership = writer.ownership()
  writer.append(b"abc").unwrap()
  let generation = writer.seal(name).unwrap()
  assert_eq(ownership.device, generation.device)
  assert_eq(ownership.inode, generation.inode)
  test_fail_root_sync(root, 2)
  assert_true(root.reclaim_generation(name, generation) is Err(Cleanup(_)))
  assert_eq(root.inspect_generation(name).unwrap(), None)
  assert_true(root.reclaim_generation(name, generation) is Err(Cleanup(_)))
  assert_eq(root.inspect_generation(name).unwrap(), None)
  root.reclaim_generation(name, generation).unwrap()
  root.sync_directory().unwrap()
}
