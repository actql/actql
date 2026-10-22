///|
fn runtime_digest_writer(
  root : @filesystem.Root,
  name : String,
  body : Bytes,
) -> @filesystem.Writer {
  let writer = root
    .create_writer(name + ".stage", body.length().to_int64())
    .unwrap()
  writer.append(body).unwrap()
  writer.seal(name).unwrap() |> ignore
  writer
}

///|
test "Native Runtime reads digest-only members and retains exact collected metadata" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let runtime = local_runtime_empty(None)
  runtime.roots.push(root)
  let binary = runtime_digest_writer(
    root,
    "runtime-digest-binary",
    Bytes::make(32769, 97),
  )
  let metadata = runtime_digest_writer(
    root, "runtime-digest-metadata", b"{\"ok\":true}\n",
  )
  let result = try {
    let image = local_runtime_read_member(
      runtime, root, "runtime-digest-binary", 32769L, "94c9394bd6ee8fcad7b37332529186fd12354dc39b0109db7e1bce510e25048d",
      false,
    )
    let text = local_runtime_read_member(
      runtime, root, "runtime-digest-metadata", 12L, "e5f1eb4d806641698a35efe20e098efd20d7d57a9b90ee69079d5bb650920726",
      true,
    )
    Ok((image, text))
  } catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  let (image, text) = result.unwrap()
  assert_eq(image, "")
  assert_eq(text, "{\"ok\":true}\n")
  assert_true(runtime.reader is None)
  assert_eq(runtime.witnesses.length(), 2)
  binary.cancel().unwrap()
  metadata.cancel().unwrap()
  runtime.close().unwrap()
  assert_true(runtime.closed)
}

///|
test "Native Runtime refuses a wrong member digest without accepting a witness" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let runtime = local_runtime_empty(None)
  runtime.roots.push(root)
  let writer = runtime_digest_writer(root, "runtime-digest-mismatch", b"abc")
  let result = Ok(
    local_runtime_read_member(
      runtime,
      root,
      "runtime-digest-mismatch",
      3L,
      "0".repeat(64),
      false,
    ),
  ) catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  assert_true(result is Err(Changed))
  assert_true(runtime.reader is None)
  assert_eq(runtime.witnesses.length(), 0)
  writer.cancel().unwrap()
  runtime.close().unwrap()
  assert_true(runtime.closed)
}
