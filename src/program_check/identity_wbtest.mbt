///|
test "contract set preimages match independent registered corpus identities" {
  for
    (values, expected) in [
      ([], "edd4c2c78bec6f0e400283c9538413848ff4ea5fde29e50ed1135c8fc3280b5f"),
      (
        ["sha256:" + "0".repeat(64)],
        "695bf2be6d575d8d857ddd035ba7d3d2fc28ed5584b6cf30577859dcf6376553",
      ),
      (
        ["sha256:" + "0".repeat(64), "sha256:" + "f".repeat(64)],
        "288bf236d5774b06563c3bfc8976c5920ccb4e5f6193c8cdaab25ceb12052905",
      ),
    ] {
    let writer = @encode.hashing_writer(1000, 100, 10)
    emit_contract_set(values, writer)
    assert_eq(@encode.finish_hash(writer), expected)
  }
}

///|
test "Result interface preimages retain producer identity and consumer alias" {
  for
    (name, expected) in [
      (
        "rows", "e7300cc0f600893f4dc01cfd77fa5aa90d600e2dd48599058cd2104bf1bf7db0",
      ),
      (
        "again", "b8443848fe290cb4e08747ef841570658faf72933fa4e34d9a0d8a50d20423f0",
      ),
    ] {
    let writer = @encode.hashing_writer(1000, 100, 10)
    emit_result_interface(
      name,
      "p",
      "first",
      "sha256:" + "a".repeat(64),
      "out",
      "sha256:" + "c".repeat(64),
      writer,
    )
    assert_eq(@encode.finish_hash(writer), expected)
  }
}

///|
test "Unit preimage preserves explicit empty imports and gates" {
  let value : UnitIdentityMaterial = {
    program_id: "p",
    node_id: "first",
    local_body: "sha256:" + "a".repeat(64),
    declarations: "sha256:" + "b".repeat(64),
    contracts: "sha256:" + "c".repeat(64),
    imports: [],
    gates: [],
  }
  let writer = @encode.writer(1000, 100, 10)
  emit_unit_preimage(value, writer)
  let text = @encode.finish(writer)
  assert_true(
    text.has_prefix(
      "{\"import_interface_cids\":[],\"incoming_gate_contract_cids\":[],",
    ),
  )
  assert_false(text.contains("self_cid"))
  let hash = @encode.hashing_writer(1000, 100, 10)
  emit_unit_preimage(value, hash)
  let (digest, bytes, nodes) = @encode.finish_hash_usage(hash)
  // Independently serialized and hashed with Node crypto, not product output.
  assert_eq(
    digest, "5e0e71e394630bac86e2e69b4916d7a0bd895fd0c4d52687fcdb816de372cb18",
  )
  assert_eq(bytes, 463)
  for
    (cap_bytes, cap_nodes, cap_depth) in [
      (bytes - 1, nodes, 2),
      (bytes, nodes - 1, 2),
      (bytes, nodes, 1),
    ] {
    let writer = @encode.hashing_writer(cap_bytes, cap_nodes, cap_depth)
    try emit_unit_preimage(value, writer) catch {
      e => assert_true(e is @encode.OutputLimit)
    } noraise {
      _ => fail("expected limit failure")
    }
    try @encode.finish_hash(writer) catch {
      e => assert_true(e is @encode.ClosedWriter)
    } noraise {
      _ => fail("partial identity escaped")
    }
  }
}
