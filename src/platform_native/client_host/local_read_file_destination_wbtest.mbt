///|
fn file_destination_fixture(
  name : String,
  maximum? : Int = 64,
) -> NativeLocalReadFileDestination {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let directory = "read-file-destination-" + name
  root.create_directory(directory).unwrap() |> ignore
  root.close().unwrap()
  let parent = path + "/" + directory
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
  assert_false(destination.finish())
  destination.close().unwrap()
  destination.close().unwrap()
  assert_eq(count, 9L)
  assert_eq(
    digest, "45fa679977289675167a1e277c1febba4c59b00c64853a8462116f46f1a5f4f7",
  )
  assert_true(
    destination.root is None &&
    destination.writer is None &&
    destination.reader is None,
  )
}

///|
test "File destination uses actual ordinary names without truncation or normalization" {
  let base = file_destination_fixture("ordinary")
  let name = "result " + "e\u{0301}é-data-".repeat(15) + ".json"
  let destination = local_read_file_destination(
    base.parent + "/" + name,
    base.parent,
    name,
    "private.stage",
    64,
  )
  destination.open_parent().unwrap()
  destination.create_writer().unwrap()
  let original = destination.original_data().unwrap()
  assert_eq(original.name, name)
  assert_true(
    destination.append(b"ordinary") is @result_access.SinkChunkConfirmed,
  )
  assert_true(destination.finish())
  let (count, digest) = destination.verify_completed(original).unwrap()
  destination.close().unwrap()
  assert_eq(count, 8L)
  assert_eq(
    digest, "03822375f2aca5e53d66838a3e803183e0c1a7921da8e4056d3341ea95777cd9",
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

///|
test "File read preimage binds every destination original and keeps stdout bytes" {
  let crypto = epoch_test_crypto()
  let fields = [
    ("domain", @host.Text("native_local_read.egress_admission")),
    ("sink", @host.Text("file")),
  ]
  let file : NativeLocalReadFileOriginal = {
    path: "/tmp/export/answer.json",
    name: "answer.json",
    staging_name: "private.stage",
    parent_device: "1",
    parent_inode: "2",
    writer_device: "1",
    writer_inode: "3",
  }
  let exact = local_read_preimage(crypto, fields.copy(), file=Some(file)).unwrap()
  assert_eq(
    exact.wire,
    "{\"destination_name\":\"answer.json\",\"destination_parent_device\":\"1\",\"destination_parent_inode\":\"2\",\"destination_path\":\"/tmp/export/answer.json\",\"destination_staging_name\":\"private.stage\",\"destination_writer_device\":\"1\",\"destination_writer_inode\":\"3\",\"domain\":\"native_local_read.egress_admission\",\"sink\":\"file\"}",
  )
  assert_eq(
    exact.cid,
    "sha256:b6e307b06e1b9722d8e65425c08df2dc25e88dc33d552a132dfe74a70a9006e1",
  )
  assert_true(
    read_local_file_destination_original(
      local_read_egress_fields(exact.wire).unwrap(),
    ).unwrap() ==
    file,
  )
  for
    changed in [
      { ..file, path: "/tmp/other/answer.json", },
      { ..file, name: "other.json", },
      { ..file, staging_name: "other.stage", },
      { ..file, parent_device: "9", },
      { ..file, parent_inode: "9", },
      { ..file, writer_device: "9", },
      { ..file, writer_inode: "9", },
    ] {
    assert_false(
      local_read_preimage(crypto, fields.copy(), file=Some(changed)).unwrap().cid ==
      exact.cid,
    )
  }
  let stdout = local_read_preimage(crypto, [("a", @host.Text("original"))]).unwrap()
  assert_eq(stdout.wire, "{\"a\":\"original\"}")
  crypto.close_checked().unwrap()
}
