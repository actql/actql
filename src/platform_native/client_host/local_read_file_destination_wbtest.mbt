///|
fn file_destination_fixture(
  name : String,
  maximum? : Int = 64,
) -> NativeLocalReadFileDestination raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_RESULT_FILES_ROOT") is Some(root) else {
    fail("selected File delivery requires its own canonical directory fixtures")
  }
  let parent = root + "/" + name
  local_read_file_destination(
    parent + "/output.json",
    parent,
    "output.json",
    "staging",
    maximum,
  )
}

///|
test "File destination acknowledges actual Writer and rechecks completed original bytes" {
  let destination = file_destination_fixture("complete")
  destination.open_parent().unwrap()
  assert_true(destination.writer is None)
  destination.create_writer().unwrap()
  let original = destination.original_data().unwrap()
  assert_true(
    destination.append(b"[{\"x\":1}]") is @result_access.SinkChunkConfirmed,
  )
  assert_true(destination.finish())
  let (count, digest) = destination.verify_completed(original).unwrap()
  assert_eq(count, 9L)
  assert_eq(digest, @sha.hex(@sha.digest(b"[{\"x\":1}]")))
  assert_false(destination.finish())
  destination.close().unwrap()
  destination.close().unwrap()
  assert_true(
    destination.root is None &&
    destination.writer is None &&
    destination.reader is None,
  )
}

///|
test "File destination never overwrites an existing final name" {
  let destination = file_destination_fixture("existing")
  destination.open_parent().unwrap()
  let root = destination.root.unwrap()
  let writer = root.create_writer("other.stage", 64L).unwrap()
  writer.append(b"original").unwrap()
  let generation = writer.seal("output.json").unwrap()
  writer.close_retaining_files().unwrap()
  assert_true(destination.create_writer() is Err(@filesystem.Conflict))
  assert_true(root.verify_generation("output.json", generation))
  destination.close().unwrap()
}

///|
test "File destination cancels only its unattempted staging original" {
  let destination = file_destination_fixture("cancel")
  destination.open_parent().unwrap()
  destination.create_writer().unwrap()
  destination.close().unwrap()
  let root = @filesystem.open_root(destination.parent).unwrap()
  assert_true(root.inspect_generation("staging") is Ok(None))
  assert_true(root.inspect_generation("output.json") is Ok(None))
  root.close().unwrap()
}

///|
test "File destination retains failed attempted output and refuses a replacement inode" {
  let partial = file_destination_fixture("partial", maximum=2)
  partial.open_parent().unwrap()
  partial.create_writer().unwrap()
  assert_true(
    partial.append(b"too large") is @result_access.SinkChunkFailed(_, _),
  )
  assert_false(partial.finish())
  partial.close().unwrap()
  let root = @filesystem.open_root(partial.parent).unwrap()
  assert_true(root.inspect_generation("staging") is Ok(Some(_)))
  assert_true(root.inspect_generation("output.json") is Ok(None))
  root.close().unwrap()

  let destination = file_destination_fixture("replacement")
  destination.open_parent().unwrap()
  destination.create_writer().unwrap()
  let original = destination.original_data().unwrap()
  assert_true(
    destination.append(b"same bytes") is @result_access.SinkChunkConfirmed,
  )
  assert_true(destination.finish())
  let root = destination.root.unwrap()
  root
  .reclaim_generation("output.json", destination.generation.unwrap())
  .unwrap()
  let foreign = root.create_writer("foreign.stage", 64L).unwrap()
  foreign.append(b"same bytes").unwrap()
  foreign.seal("output.json").unwrap() |> ignore
  foreign.close_retaining_files().unwrap()
  assert_true(
    destination.verify_completed(original)
    is Err(@filesystem.GenerationMismatch),
  )
  destination.close().unwrap()
}
