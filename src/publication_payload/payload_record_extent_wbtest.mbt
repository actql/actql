///|
test "bounded payload transport fits both admitted records with maximal scalar widths" {
  let cid = "sha256:" + "f".repeat(64)
  let maximum = 9223372036854775807L
  let request = prepare_publication_payload_request(
    cid, cid, cid, cid, cid, cid, cid, cid, maximum, maximum,
  ).unwrap()
  let pair = { device: 18446744073709551615UL, inode: 18446744073709551615UL, }
  let native = emit_payload_record(
    request,
    2147483647,
    Sealed,
    Some(pair),
    Some({ device: pair.device, inode: pair.inode, size: maximum, }),
    None,
    None,
    maximum,
    cid,
  ).unwrap()
  let opaque_wire = emit_payload_record(
    request,
    2147483647,
    Sealed,
    None,
    None,
    Some(cid),
    Some(cid),
    maximum,
    cid,
  ).unwrap()
  for wire in [request.body, native, opaque_wire] {
    assert_true(
      @utf8.encode(wire).length() <= publication_payload_record_transport_bytes,
    )
  }
  for wire in [native, opaque_wire] {
    let original = admit_durable_publication_payload_record(@utf8.encode(wire)).unwrap()
    assert_eq(original.body, wire)
  }
}
