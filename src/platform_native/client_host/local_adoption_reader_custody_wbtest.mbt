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
