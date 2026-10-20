///|
// Independent fixed JSON/SHA256 vectors. No product issuer builds expectations.
let delivery_container_legacy : String = "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":4,\"delivered_sha256\":\"8888888888888888888888888888888888888888888888888888888888888888\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:1b672f923a8f34e603d8246a3541922ccb1eedb4be8d1691f9a290d14fe1e2ea\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"answer\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"version\":\"actql-result-delivery-receipt/0.1\"}"

///|
let delivery_container_first : String = "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":4,\"delivered_sha256\":\"3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:653b739f7a85f39a048ed77fe1d38f8fc5e1edcf1ab50a867a83216e76a1d146\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"answer\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"version\":\"actql-result-delivery-receipt/0.1\"}"

///|
let delivery_container_equal_bytes : String = "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":4,\"delivered_sha256\":\"3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:18ac1e0d8d953ef2f6de009ebab351f57701ce6bf8396f277b8f8d8443df0403\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"other\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"version\":\"actql-result-delivery-receipt/0.1\"}"

///|
let delivery_container_csv : String = "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":5,\"delivered_sha256\":\"6667b2d1aab6a00caa5aee5af8ad9f1465e567abf1c209d15727d57b3e8f6e5f\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:659f0bcd37039369f9188ac716ca7435ba03ad98d3d0fd357d6a0196bc8a3f85\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"csv\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-result-delivery-receipt/0.1\"}"

///|
test "CLI receipt singleton export preserves canonical bytes and self identity" {
  assert_eq(
    client_result_delivery_receipt_file([delivery_container_legacy], 1),
    Ok(delivery_container_legacy),
  )
  let admitted = admit_client_result_delivery_receipts(
    delivery_container_legacy,
  ).unwrap()
  assert_eq(admitted.count(), 1)
  assert_false(admitted.is_collection())
  assert_eq(
    admitted.matching_identities(4L, "8".repeat(64)),
    Ok([
      "sha256:1b672f923a8f34e603d8246a3541922ccb1eedb4be8d1691f9a290d14fe1e2ea",
    ]),
  )
}

///|
test "CLI receipt collections report every equal-byte identity without select-first" {
  let members = [
    delivery_container_first, delivery_container_equal_bytes, delivery_container_first,
    delivery_container_csv,
  ]
  let wire = client_result_delivery_receipt_file(members, 4).unwrap()
  assert_eq(wire, "[" + members.join(",") + "]")
  let admitted = admit_client_result_delivery_receipts(wire).unwrap()
  assert_true(admitted.is_collection())
  assert_eq(admitted.count(), 4)
  assert_eq(
    admitted.matching_identities(
      4L, "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
    ),
    Ok([
      "sha256:653b739f7a85f39a048ed77fe1d38f8fc5e1edcf1ab50a867a83216e76a1d146",
      "sha256:18ac1e0d8d953ef2f6de009ebab351f57701ce6bf8396f277b8f8d8443df0403",
    ]),
  )
  assert_eq(
    admitted.matching_identities(
      5L, "6667b2d1aab6a00caa5aee5af8ad9f1465e567abf1c209d15727d57b3e8f6e5f",
    ),
    Ok([
      "sha256:659f0bcd37039369f9188ac716ca7435ba03ad98d3d0fd357d6a0196bc8a3f85",
    ]),
  )
}

///|
test "CLI multiple-request partial collections remain arrays with zero or one receipt" {
  assert_eq(client_result_delivery_receipt_file([], 2), Ok("[]"))
  assert_eq(
    client_result_delivery_receipt_file([delivery_container_first], 2),
    Ok("[" + delivery_container_first + "]"),
  )
  assert_eq(
    admit_client_result_delivery_receipts("[]")
    .unwrap()
    .matching_identities(0L, "0".repeat(64)),
    Err(OutputMismatch),
  )
  assert_true(client_result_delivery_receipt_file([], 1) is Err(_))
  assert_true(
    client_result_delivery_receipt_file(
      [delivery_container_first, delivery_container_csv],
      1,
    )
    is Err(_),
  )
}

///|
test "CLI receipt admission rejects malformed unrelated members and tampered self CIDs" {
  for
    invalid in [
      "{}",
      "null",
      "[]",
      "{\"version\":\"actql-run-receipt/0.1\"}",
      delivery_container_csv.replace(old="\"csv\"", new="\"changed\""),
    ] {
    assert_true(
      admit_client_result_delivery_receipts(
        "[" + delivery_container_first + "," + invalid + "]",
      )
      is Err(_),
    )
  }
  let duplicate = delivery_container_first.replace(
    old="{", new="{\"result_name\":\"answer\",",
  )
  assert_true(admit_client_result_delivery_receipts(duplicate) is Err(_))
  let extra = delivery_container_first.replace(old="{", new="{\"extra\":true,")
  assert_true(admit_client_result_delivery_receipts(extra) is Err(_))
}

///|
test "CLI receipt verification requires both observed byte count and SHA" {
  let receipt = admit_client_result_delivery_receipts(delivery_container_first).unwrap()
  assert_eq(
    receipt.matching_identities(
      5L, "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
    ),
    Err(OutputMismatch),
  )
  assert_eq(
    receipt.matching_identities(4L, "0".repeat(64)),
    Err(OutputMismatch),
  )
  assert_eq(
    receipt.matching_identities(-1L, "0".repeat(64)),
    Err(InvalidOutputDigest),
  )
  assert_eq(
    receipt.matching_identities(4L, "A".repeat(64)),
    Err(InvalidOutputDigest),
  )
}

///|
test "CLI receipt container preserves finite whole-input and member-count bounds" {
  let sixteen = Array::make(16, delivery_container_first)
  assert_eq(
    admit_client_result_delivery_receipts("[" + sixteen.join(",") + "]")
    .unwrap()
    .count(),
    16,
  )
  assert_true(
    admit_client_result_delivery_receipts(
      "[" + Array::make(17, delivery_container_first).join(",") + "]",
    )
    is Err(_),
  )
  assert_true(
    admit_client_result_delivery_receipts(
      " ".repeat(65537) + delivery_container_first,
    )
    is Err(_),
  )
  assert_true(admit_client_result_delivery_receipts("true") is Err(_))
  assert_true(client_result_delivery_receipt_file(sixteen, 17) is Err(_))
}
