///|
test "native retained task file seals before a fresh verified read" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let occurrence = "task-file-success-" + @env.now().to_string()
  let file = begin_native_retained_task_file(root, occurrence, 7L).unwrap()
  assert_false(file.available())
  file.append("[1,").unwrap()
  file.append("2,3]").unwrap()
  assert_true(file.append("x") is Err(Filesystem(@filesystem.CapacityExceeded)))
  assert_true(file.seal("sha256:wrong", 7) is Err(ContentMismatch))
  assert_false(file.available())
  let cid = "sha256:" + @sha256.hex(b"[1,2,3]")
  file.seal(cid, 7).unwrap()
  assert_true(file.available())
  assert_eq(file.stored_bytes(), Some(7L))
  let reader = file.open_reader().unwrap()
  assert_true(file.release() is Err(InvalidState))
  assert_true(file.available())
  assert_true(reader.finish() is Err(InvalidState))
  let mut encoded = ""
  let mut done = false
  while !done {
    let chunk = reader.next(2).unwrap()
    encoded += @utf8.decode(chunk.bytes) catch { _ => abort("ASCII fixture") }
    done = chunk.eof
  }
  assert_eq(encoded, "[1,2,3]")
  reader.finish().unwrap()
  assert_true(reader.next(1) is Err(InvalidState))
  let fresh = file.open_reader().unwrap()
  assert_eq(fresh.next(7).unwrap().bytes, b"[1,2,3]")
  assert_true(fresh.next(7).unwrap().eof)
  fresh.finish().unwrap()
  file.release().unwrap()
  assert_false(file.available())
  assert_true(file.open_reader() is Err(InvalidState))
  file.release().unwrap()
}

///|
test "native retained task owner reclaims a stopped reader before unlink" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let occurrence = "task-file-reader-cleanup-" + @env.now().to_string()
  let file = begin_native_retained_task_file(root, occurrence, 3L).unwrap()
  file.append("abc").unwrap()
  file.seal("sha256:" + @sha256.hex(b"abc"), 3).unwrap()
  let reader = file.open_reader().unwrap()
  assert_eq(reader.next(1).unwrap().bytes, b"a")
  assert_true(file.release() is Err(InvalidState))
  file.reclaim_readers().unwrap()
  assert_true(reader.next(1) is Err(InvalidState))
  file.release().unwrap()
  assert_true(file.release_confirmed())
}

///|
test "native retained task file cannot admit incomplete or mismatched content" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(root) else {
    return
  }
  let occurrence = "task-file-reject-" + @env.now().to_string()
  let file = begin_native_retained_task_file(root, occurrence, 3L).unwrap()
  file.append("abc").unwrap()
  let wrong = "sha256:" + @sha256.hex(b"abd")
  assert_true(file.seal(wrong, 2) is Err(ContentMismatch))
  file.seal(wrong, 3).unwrap()
  let reader = file.open_reader().unwrap()
  assert_true(file.release() is Err(InvalidState))
  assert_eq(reader.next(3).unwrap().bytes, b"abc")
  assert_true(reader.next(3).unwrap().eof)
  assert_true(reader.finish() is Err(ContentMismatch))
  reader.close().unwrap()
  file.release().unwrap()
  assert_false(file.available())
}
