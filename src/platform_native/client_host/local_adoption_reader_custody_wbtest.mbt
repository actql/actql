///|
test "adoption propagates the original rejected Reader carrier without replacing its reason" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let writer = root.create_writer("adoption-read.stage", 32L).unwrap()
  writer.append(b"original\r\n").unwrap()
  let generation = writer.seal("adoption-read.json").unwrap()
  let refused = match
    root.open_reader_with_custody("adoption-read.json", {
      ..generation,
      size: generation.size - 1L,
    }) {
    Err(original) => original
    Ok(_) => {
      fail("wrong original generation was accepted")
      return
    }
  }
  let retained = match local_adoption_reader_result(Err(refused)) {
    Err(ReadAcquisitionFailure(original)) => original
    _ => {
      fail("adoption lost the original Reader acquisition carrier")
      return
    }
  }
  assert_true(physical_equal(retained, refused))
  assert_true(retained.issue() is @filesystem.GenerationMismatch)
  retained.retry_cleanup().unwrap()
  retained.retry_cleanup().unwrap()
  assert_true(retained.issue() is @filesystem.GenerationMismatch)
  writer.cancel().unwrap()
  root.close().unwrap()
}

///|
test "adoption reads exact bounded bytes and the original generation" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let writer = root.create_writer("adoption-exact.stage", 32L).unwrap()
  let expected = b"e\xcc\x81\r\n\xc3\xa9\n"
  writer.append(expected).unwrap()
  let generation = writer.seal("adoption-exact.json").unwrap()
  let (body, observed) = local_adoption_read(root, "adoption-exact.json", 32L).unwrap()
  assert_eq(body, expected)
  assert_eq(observed, generation)
  assert_true(
    local_adoption_read(root, "adoption-exact.json", 1L)
    is Err(ConfigurationLimit),
  )
  writer.cancel().unwrap()
  root.close().unwrap()
}

///|
#borrow(reader)
extern "C" fn adoption_reader_consumed_unknown(
  reader : @filesystem.Reader,
) -> Bool = "actql_native_filesystem_test_reader_consumed_unknown"

///|
// Keep the deliberately unacknowledged fixture original through process exit.
// Process disappearance is not a successful Reader/Session cleanup receipt.
let adoption_reader_pending_originals : Array[NativeLocalAdoptionSession] = []

///|
test "current refusal retains the same acquisition carrier until session cleanup acknowledges it" {
  let session = local_settings_fixture("adoption-reader-acquisition")
  let root = session.source_root
  let generation = root
    .inspect_generation(session.source_name)
    .unwrap()
    .unwrap()
  let failure = match
    root.open_reader_with_custody(session.source_name, {
      ..generation,
      size: generation.size - 1L,
    }) {
    Err(original) => original
    _ => {
      fail("wrong generation was accepted")
      return
    }
  }
  session.retain_read_issue(ReadAcquisitionFailure(failure)) |> ignore
  // A bool-only current consumer loses its returned issue, not Owner custody.
  assert_false(session.check_original() is Ok(_))
  assert_true(
    session.read_cleanup is Some(ReadAcquisitionFailure(retained)) &&
    physical_equal(retained, failure),
  )
  assert_false(session.lock_close_attempted)
  assert_true(session.close())
  assert_true(session.read_cleanup is None)
  assert_true(session.lock_close_attempted)
  assert_true(session.close())
  assert_true(session.check_original() is Err(Closed))
  assert_true(failure.issue() is @filesystem.GenerationMismatch)
}

///|
test "unknown Reader retirement keeps the original session lock and never retries the descriptor" {
  // This original deliberately stays pending through process exit. Its lock
  // belongs to this Session, not the namespace used by later independent tests.
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(path).unwrap()
  let state_name = "adoption-reader-unknown-parent"
  parent.create_directory(state_name).unwrap() |> ignore
  parent.close().unwrap()
  let session = local_settings_fixture(
    "adoption-reader-unknown",
    state_parent=Some(path + "/" + state_name),
  )
  let root = session.source_root
  let generation = root
    .inspect_generation(session.source_name)
    .unwrap()
    .unwrap()
  let reader = root
    .open_reader_with_custody(session.source_name, generation)
    .unwrap()
  assert_true(adoption_reader_consumed_unknown(reader))
  let primary = @filesystem.Cleanup("Original reader retirement is unconfirmed")
  session.retain_read_issue(ReadPending(reader, primary)) |> ignore
  assert_false(session.check_original() is Ok(_))
  for _ in 0..<2 {
    assert_false(session.close())
    assert_true(session.closed && session.close_pending)
    assert_false(session.lock_close_attempted)
    assert_true(
      session.read_cleanup is Some(ReadPending(retained, issue)) &&
      physical_equal(retained, reader) &&
      issue is @filesystem.Cleanup(message) &&
      message == "Original reader retirement is unconfirmed",
    )
  }
  let refused = match
    session.parent.acquire_lock_with_custody("local-adoption.lock") {
    Err(original) => original
    _ => {
      fail("pending reader cleanup released the original adoption lock")
      return
    }
  }
  refused.retry_cleanup().unwrap()
  assert_true(session.check_original() is Err(Closed))
  adoption_reader_pending_originals.push(session)
}

///|
test "adoption byte copies preserve empty exact and cross-chunk bounded originals" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  for length in [0, 1, 65535, 65536, 65537, 1048576] {
    let name = "adoption-copy-" + length.to_string()
    let expected = Bytes::makei(length, i => ((i * 37 + 23) % 256).to_byte())
    let writer = root.create_writer(name + ".stage", length.to_int64()).unwrap()
    writer.append(expected).unwrap()
    let generation = writer.seal(name + ".bin").unwrap()
    let (body, observed) = local_adoption_read(
      root,
      name + ".bin",
      length.to_int64(),
    ).unwrap()
    assert_eq(body, expected)
    assert_eq(observed, generation)
    assert_eq(body.length(), length)
    if length > 0 {
      assert_true(
        local_adoption_read(root, name + ".bin", length.to_int64() - 1L)
        is Err(ConfigurationLimit),
      )
    }
    writer.cancel().unwrap()
  }
  root.close().unwrap()
}

///|
test "adoption byte copies stay owned after another chunked read and Root close" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let first = Bytes::makei(65537, i => ((i * 19 + 3) % 256).to_byte())
  let second = Bytes::makei(65537, i => ((i * 53 + 201) % 256).to_byte())
  let writers : Array[@filesystem.Writer] = []
  for (name, original) in [("copy-first", first), ("copy-second", second)] {
    let writer = root.create_writer(name + ".stage", 65537L).unwrap()
    writer.append(original).unwrap()
    writer.seal(name + ".bin").unwrap() |> ignore
    writers.push(writer)
  }
  let (retained, _) = local_adoption_read(root, "copy-first.bin", 65537L).unwrap()
  let (next, _) = local_adoption_read(root, "copy-second.bin", 65537L).unwrap()
  assert_eq(retained, first)
  assert_eq(next, second)
  for writer in writers {
    writer.cancel().unwrap()
  }
  root.close().unwrap()
  assert_eq(retained, first)
  assert_eq(next, second)
}
