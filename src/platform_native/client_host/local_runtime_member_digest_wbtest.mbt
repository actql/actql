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
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
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
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
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

///|
// Independent SHA-256 vectors, not expectations computed by the product Hasher.
// The binary case crosses sixteen 64 KiB reads, including a final short read.
test "Native Runtime shared digest handles empty binary and chunk-boundary members repeatedly" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let runtime = local_runtime_empty(None)
  runtime.roots.push(root)
  let vectors = [
    (b"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    (b"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    (
      Bytes::makei(256, i => i.to_byte()),
      "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880",
    ),
    (
      Bytes::make(65535, 97),
      "6e1bebca6a8229364a162a72ef064826c4cd7457bf54f190ef782bd9deff3e42",
    ),
    (
      Bytes::make(65536, 97),
      "bf718b6f653bebc184e1479f1935b8da974d701b893afcf49e701f3e2f9f9c5a",
    ),
    (
      Bytes::make(65537, 97),
      "008ffc88d3c96a9f307524eb361e47c5222a887fc45fa0c1fb8d429c5c23b430",
    ),
    (
      Bytes::makei(1048832, i => (i % 256).to_byte()),
      "dd7e5c49d123e860c8bb7016bada722b5d0baa37ef8b19d5e270cf2a3000c31d",
    ),
  ]
  for index, vector in vectors {
    let (body, digest) = vector
    let name = "shared-digest-vector-" + index.to_string()
    let writer = runtime_digest_writer(root, name, body)
    for repeat = 0; repeat < 2; repeat = repeat + 1 {
      let result = Ok(
        local_runtime_read_member(
          runtime,
          root,
          name,
          body.length().to_int64(),
          digest,
          false,
          allow_empty=true,
        ),
      ) catch {
        LocalRuntimeStop(issue) => Err(issue)
      }
      assert_eq(result.unwrap(), "")
      assert_true(runtime.reader is None)
      assert_true(runtime.reader_open_failure is None)
      assert_eq(runtime.witnesses.length(), index * 2 + repeat + 1)
      runtime.witnesses[index * 2 + repeat].check_current().unwrap()
    }
    writer.cancel().unwrap()
  }
  runtime.close().unwrap()
  runtime.close().unwrap()
  assert_true(runtime.closed)
}

///|
test "Native Runtime shared digest preserves empty and metadata collection limits" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let runtime = local_runtime_empty(None)
  runtime.roots.push(root)
  let empty = runtime_digest_writer(root, "shared-digest-empty", b"")
  let metadata = runtime_digest_writer(
    root,
    "shared-digest-metadata-limit",
    Bytes::make(65536, 97),
  )
  let too_large = runtime_digest_writer(
    root,
    "shared-digest-metadata-over-limit",
    Bytes::make(65537, 97),
  )
  let rejected_empty = Ok(
    local_runtime_read_member(
      runtime, root, "shared-digest-empty", 0L, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      false,
    ),
  ) catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  assert_true(rejected_empty is Err(Limit))
  assert_true(runtime.reader is None)
  assert_eq(runtime.witnesses.length(), 0)
  let result = try {
    let empty_text = local_runtime_read_member(
      runtime,
      root,
      "shared-digest-empty",
      0L,
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      true,
      allow_empty=true,
    )
    let text = local_runtime_read_member(
      runtime, root, "shared-digest-metadata-limit", 65536L, "bf718b6f653bebc184e1479f1935b8da974d701b893afcf49e701f3e2f9f9c5a",
      true,
    )
    Ok((empty_text, text))
  } catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  let (empty_text, text) = result.unwrap()
  assert_eq(empty_text, "")
  assert_eq(text, "a".repeat(65536))
  assert_eq(runtime.witnesses.length(), 2)
  let oversized = Ok(
    local_runtime_read_member(
      runtime, root, "shared-digest-metadata-over-limit", 65537L, "008ffc88d3c96a9f307524eb361e47c5222a887fc45fa0c1fb8d429c5c23b430",
      true,
    ),
  ) catch {
    LocalRuntimeStop(issue) => Err(issue)
  }
  assert_true(oversized is Err(Limit))
  assert_true(runtime.reader is None)
  assert_eq(runtime.witnesses.length(), 2)
  empty.cancel().unwrap()
  metadata.cancel().unwrap()
  too_large.cancel().unwrap()
  runtime.close().unwrap()
}

///|
test "Native Runtime shared digest rejects wrong length and digest without witnesses" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @filesystem.open_private_root(path).unwrap()
  let runtime = local_runtime_empty(None)
  runtime.roots.push(root)
  let writer = runtime_digest_writer(root, "shared-digest-refused", b"abc")
  for bytes in [2L, 4L] {
    let result = Ok(
      local_runtime_read_member(
        runtime, root, "shared-digest-refused", bytes, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        false,
      ),
    ) catch {
      LocalRuntimeStop(issue) => Err(issue)
    }
    assert_true(result is Err(Limit))
    assert_true(runtime.reader is None)
    assert_eq(runtime.witnesses.length(), 0)
  }
  for collect in [false, true] {
    let result = Ok(
      local_runtime_read_member(
        runtime,
        root,
        "shared-digest-refused",
        3L,
        "0".repeat(64),
        collect,
      ),
    ) catch {
      LocalRuntimeStop(issue) => Err(issue)
    }
    assert_true(result is Err(Changed))
    assert_true(runtime.reader is None)
    assert_eq(runtime.witnesses.length(), 0)
  }
  writer.cancel().unwrap()
  runtime.close().unwrap()
  assert_true(runtime.closed)
}
