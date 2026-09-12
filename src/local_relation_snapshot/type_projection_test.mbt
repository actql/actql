///|
test "type projection retains the source slot but excludes observation evidence" {
  let expected = "sha256:9f0114feb3b5e8e946c3efc5b89ebe6a44559f13b7ec30809a0e42d173916bec"
  for
    prefix in [
      "",
      "\"completeness\":\"partial\",\"input_cid\":\"sha256:" +
      "0".repeat(64) +
      "\",",
      "\"completeness\":\"complete\",\"input_cid\":\"sha256:" +
      "1".repeat(64) +
      "\",\"integration_binding_cid\":\"sha256:" +
      "2".repeat(64) +
      "\",",
    ] {
    let body = "{" + prefix + base()[1:].to_owned()
    let bytes = @utf8.encode(body)
    let snapshot = read(bytes, "sha256:" + @sha.hex(bytes), caps()).unwrap()
    let writer = @encode.writer(10000, 1000, 100)
    emit_type_projection(snapshot, writer)
    assert_eq(@encode.finish(writer), base())
    let hash = @encode.hashing_writer(10000, 1000, 100)
    emit_type_projection(snapshot, hash)
    assert_eq("sha256:" + @encode.finish_hash(hash), expected)
    let measure = @encode.measuring_writer(10000, 1000, 100)
    emit_type_projection(snapshot, measure)
    assert_eq(
      @encode.finish_measurement(measure),
      @utf8.encode(base()).length(),
    )
  }
}

///|
test "type projection enforces output limits and cannot expose a failed prefix" {
  let bytes = @utf8.encode(base())
  let snapshot = read(bytes, "sha256:" + @sha.hex(bytes), caps()).unwrap()
  let writer = @encode.hashing_writer(10000, 1000, 100)
  emit_type_projection(snapshot, writer)
  let (_, size, nodes) = @encode.finish_hash_usage(writer)
  for
    (byte_limit, node_limit, depth_limit) in [
      (size - 1, nodes, 3),
      (size, nodes - 1, 3),
      (size, nodes, 2),
    ] {
    let writer = @encode.hashing_writer(byte_limit, node_limit, depth_limit)
    try emit_type_projection(snapshot, writer) catch {
      e => assert_true(e is @encode.OutputLimit)
    } noraise {
      _ => fail("expected output limit")
    }
    try @encode.finish_hash(writer) catch {
      e => assert_true(e is @encode.ClosedWriter)
    } noraise {
      _ => fail("failed prefix must not be finalized")
    }
  }
  let exact = @encode.hashing_writer(size, nodes, 3)
  emit_type_projection(snapshot, exact)
  assert_eq(@encode.finish_hash(exact), @sha.hex(bytes))
}

///|
test "type projection distinguishes source slots and actual row contracts" {
  // Fixed canonical bytes and digests independently computed with Node crypto.
  for
    (body, cid) in [
      (
        "{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"source_ref\":\"source:local/s/other\",\"version\":\"actql-local-input-schema/0.1\"}",
        "sha256:2578fb7a866311dd33bf271376f9f7d45b0dee4ba5ab97dd5a4f24fe14514f5b",
      ),
      (
        "{\"output_carrier\":\"relation\",\"schema\":{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"source_ref\":\"source:local/s/rows\",\"version\":\"actql-local-input-schema/0.1\"}",
        "sha256:6346ac92176db3295166e9eaa39913ea535173ee5a5f79f761bb3006db05a005",
      ),
    ] {
    let snapshot = read(@utf8.encode(body), cid, caps()).unwrap()
    let writer = @encode.writer(10000, 1000, 100)
    emit_type_projection(snapshot, writer)
    assert_eq(@encode.finish(writer), body)
    let hash = @encode.hashing_writer(10000, 1000, 100)
    emit_type_projection(snapshot, hash)
    assert_eq("sha256:" + @encode.finish_hash(hash), cid)
  }
}
