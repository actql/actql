///|
test "Common read codec preserves original Native key bytes and independent CID" {
  let wire = encode_client_local_read_preimage([
    ("account_configuration_cid", Text("ctx")),
    ("adoption_cid", Text("adoption")),
  ]).unwrap()
  assert_eq(
    wire, "{\"account_configuration_cid\":\"ctx\",\"adoption_cid\":\"adoption\"}",
  )
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(wire)),
    "sha256:407392a85e946d47afdce28c156c231dc242bdbc44d648707323571ccc0da8ce",
  )
}

///|
test "Common read codec keeps original ordered key and output refusals" {
  for
    fields in [
      [
        ("adoption_cid", Text("adoption")),
        ("account_configuration_cid", Text("ctx")),
      ],
      [("b", Text("x")), ("a", Text("y"))],
      [("a", Text("x")), ("a", Text("y"))],
      [(String::from_array([(0xd800).unsafe_to_char()]), Text("x"))],
    ] {
    assert_true(encode_client_local_read_preimage(fields) is Err(Encoding))
  }
  assert_true(
    encode_client_local_read_preimage([("a", Text("x".repeat(16384)))])
    is Err(CapacityExceeded),
  )
}

///|
test "Common read codec preserves SDK purpose sink Unicode CRLF and all value families" {
  let wire = encode_client_local_read_preimage([
    ("decisions", AllowedReads("answer")),
    ("domain", Text("python_local_read.egress_admission")),
    ("max_bytes", Quantity(65536)),
    ("policies", Texts(["sha256:" + "a".repeat(64)])),
    ("purpose", Text("python-local-read")),
    ("sink", Text("sdk-rows")),
    ("unicode", Text("e\u{0301}\r\n😀")),
  ]).unwrap()
  // Independently encoded/hashes of literal fixtures, not copied from Core.
  assert_eq(
    wire, "{\"decisions\":[{\"operation\":\"read\",\"outcome\":\"allow\",\"resource\":\"run\"},{\"operation\":\"read\",\"outcome\":\"allow\",\"resource\":\"result/answer\"}],\"domain\":\"python_local_read.egress_admission\",\"max_bytes\":65536,\"policies\":[\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"],\"purpose\":\"python-local-read\",\"sink\":\"sdk-rows\",\"unicode\":\"é\\r\\n😀\"}",
  )
  assert_eq(
    @sha.hex(@utf8.encode(wire)),
    "ce4d4467bafb2a9bee5f79e535486496d7ace3711e7bd738404c89f668c99ba9",
  )
}

///|
test "original read dependencies are saved metadata without replacing body or expiry" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  let original = admit_client_local_run_policy_original(
    @utf8.encode(local_run_policy_packet_fixture),
    profile,
    local_run_policy_packet_reference(),
    local_run_policy_packet_request(),
    local_run_policy_packet_definition(),
    "sha256:" + "a".repeat(64),
    "sha256:" + "f".repeat(64),
  ).unwrap()
  assert_eq(
    client_local_run_policy_original_read_dependencies(original).unwrap(),
    ("sha256:" + "a".repeat(64), "sha256:" + "f".repeat(64)),
  )
  assert_eq(
    client_local_run_policy_original_read_expires_at(original),
    "2026-10-14T00:00:00.001Z",
  )
  assert_eq(
    client_local_run_policy_original_body(original),
    @utf8.encode(local_run_policy_packet_fixture),
  )
}
