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

///|
test "native filesystem adopts a public name exclusively and keeps the generation" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let private_name = "alloc-" + token
  let public_name = "stage-adopt-" + token
  let final_name = "object-adopt-" + token
  let writer = root.create_writer(private_name, 8L).unwrap()
  let ownership = writer.ownership()
  writer.append(b"ab").unwrap()
  // A foreign file at the public name is a conflict and is never replaced.
  let foreign = root.create_writer(public_name, 8L).unwrap()
  foreign.append(b"foreign").unwrap()
  let foreign_generation = root
    .inspect_generation(public_name)
    .unwrap()
    .unwrap()
  assert_true(writer.adopt_name(root, public_name) is Err(Conflict))
  assert_eq(
    root.inspect_generation(public_name).unwrap(),
    Some(foreign_generation),
  )
  assert_true(root.inspect_generation(private_name).unwrap() is Some(_))
  foreign.cancel().unwrap()
  // Without a conflict the same generation gains the public name and loses
  // the private one; writing and sealing continue under the public name.
  writer.adopt_name(root, public_name).unwrap()
  assert_eq(root.inspect_generation(private_name).unwrap(), None)
  let adopted = root.inspect_generation(public_name).unwrap().unwrap()
  assert_eq(adopted.device, ownership.device)
  assert_eq(adopted.inode, ownership.inode)
  writer.append(b"cd").unwrap()
  let generation = writer.seal(final_name).unwrap()
  assert_eq(generation.inode, ownership.inode)
  assert_eq(root.inspect_generation(public_name).unwrap(), None)
  assert_true(root.verify_generation(final_name, generation))
  writer.cancel().unwrap()
  assert_false(root.verify_generation(final_name, generation))
}

///|
test "native filesystem creates an allocation area exclusively and removes only its exact empty self" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let name = "area-" + token
  assert_eq(root.inspect_directory(name).unwrap(), None)
  let identity = root.create_directory(name).unwrap()
  // A second creation at the name is a conflict; the area is unchanged.
  assert_true(root.create_directory(name) is Err(Conflict))
  assert_eq(root.inspect_directory(name).unwrap(), Some(identity))
  // A file inside is created and later adopted into the parent root under
  // the same generation; the area is then empty and can go.
  let area = root.open_child(name).unwrap()
  let writer = area.create_writer("payload", 8L).unwrap()
  writer.append(b"ab").unwrap()
  let ownership = writer.ownership()
  assert_false(root.remove_directory(name, identity).unwrap())
  let public_name = "stage-area-" + token
  writer.adopt_name(root, public_name).unwrap()
  assert_eq(area.inspect_generation("payload").unwrap(), None)
  let adopted = root.inspect_generation(public_name).unwrap().unwrap()
  assert_eq(adopted.inode, ownership.inode)
  assert_true(root.remove_directory(name, identity).unwrap())
  assert_eq(root.inspect_directory(name).unwrap(), None)
  // Removing again is idempotent; another identity at the name is refused.
  assert_true(root.remove_directory(name, identity).unwrap())
  let other = root.create_directory(name).unwrap()
  assert_true(root.remove_directory(name, identity) is Err(GenerationMismatch))
  assert_true(root.remove_directory(name, other).unwrap())
  // A regular file at a directory name is neither a directory nor removed.
  let file = root.create_writer(name, 8L).unwrap()
  assert_true(root.inspect_directory(name) is Err(GenerationMismatch))
  assert_true(root.remove_directory(name, identity) is Err(GenerationMismatch))
  file.cancel().unwrap()
  writer.append(b"cd").unwrap()
  ignore(writer.seal("object-area-" + token).unwrap())
  writer.cancel().unwrap()
}

///|
test "native filesystem streaming SHA256 preserves original Reader before finish" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let vectors = [
    (
      Bytes::new(0),
      b"\xe3\xb0\xc4\x42\x98\xfc\x1c\x14\x9a\xfb\xf4\xc8\x99\x6f\xb9\x24\x27\xae\x41\xe4\x64\x9b\x93\x4c\xa4\x95\x99\x1b\x78\x52\xb8\x55",
    ),
    (
      b"abc", b"\xba\x78\x16\xbf\x8f\x01\xcf\xea\x41\x41\x40\xde\x5d\xae\x22\x23\xb0\x03\x61\xa3\x96\x17\x7a\x9c\xb4\x10\xff\x61\xf2\x00\x15\xad",
    ),
    (
      Bytes::make(32769, 97),
      b"\x94\xc9\x39\x4b\xd6\xee\x8f\xca\xd7\xb3\x73\x32\x52\x91\x86\xfd\x12\x35\x4d\xc3\x9b\x01\x09\xdb\x7e\x1b\xce\x51\x0e\x25\x04\x8d",
    ),
  ]
  for index, vector in vectors {
    let (body, expected) = vector
    let suffix = token + "-" + index.to_string()
    let writer = root
      .create_writer("digest-stage-" + suffix, body.length().to_int64())
      .unwrap()
    writer.append(body).unwrap()
    let name = "digest-object-" + suffix
    let generation = writer.seal(name).unwrap()
    let reader = root.open_reader(name, generation).unwrap()
    match reader.sha256() {
      Ok(actual) => {
        assert_eq(actual, expected)
        assert_true(reader_ready_ffi(reader))
        assert_true(reader.sha256() is Err(Read(_)))
        reader.finish().unwrap()
        assert_false(reader_ready_ffi(reader))
      }
      Err(UnsupportedTarget) => {
        // An unselected platform has not consumed even the first byte.
        assert_true(reader_ready_ffi(reader))
        let first = reader.next(1048576).unwrap()
        assert_eq(first.bytes, body)
        reader.finish().unwrap()
      }
      Err(_) => fail("streaming digest refused")
    }
    reader.close().unwrap()
    writer.cancel().unwrap()
  }
  root.close().unwrap()
}

///|
test "native filesystem streaming SHA256 refuses a partially consumed original" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(path) else {
    return
  }
  let root = open_root(path).unwrap()
  let suffix = @env.now().to_string()
  let writer = root.create_writer("digest-partial-stage-" + suffix, 3L).unwrap()
  writer.append(b"abc").unwrap()
  let name = "digest-partial-object-" + suffix
  let generation = writer.seal(name).unwrap()
  let reader = root.open_reader(name, generation).unwrap()
  assert_eq(reader.next(1).unwrap().bytes, b"a")
  match reader.sha256() {
    Err(Read(_)) | Err(UnsupportedTarget) => ()
    _ => fail("partially consumed digest was accepted")
  }
  assert_true(reader_ready_ffi(reader))
  assert_eq(reader.next(2).unwrap().bytes, b"bc")
  reader.finish().unwrap()
  assert_true(
    reader.sha256() is Err(ReaderClosed) ||
    reader.sha256() is Err(UnsupportedTarget),
  )
  writer.cancel().unwrap()
  root.close().unwrap()
}
