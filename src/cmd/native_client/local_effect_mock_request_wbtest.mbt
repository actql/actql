///|
// Independent literal six-field JSON preimage; not a target observation or ACK.
test "Native warm and saved Mock request projection preserves the complete original" {
  let actual = native_mock_effect_update_request_wire(
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    Json::string("row-1"),
    {
      "NextStep": Json::string("e\u{0301}\r\nnext"),
      "StageName": Json::string("Negotiation"),
    },
    {
      "Id": Json::string("row-1"),
      "NextStep": Json::null(),
      "StageName": Json::string("Proposal"),
    },
    "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  ).unwrap()
  assert_eq(
    actual, "{\"before\":{\"Id\":\"row-1\",\"NextStep\":null,\"StageName\":\"Proposal\"},\"binding\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"mapping\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"target\":\"row-1\",\"value\":{\"NextStep\":\"é\\r\\nnext\",\"StageName\":\"Negotiation\"},\"version\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\"}",
  )
  assert_eq(
    @sha.text_hex(actual).unwrap(),
    "fdbcec5d66a4062a94e1965de632b43f931d2586cb06a17f2a43fdc1edc8eca1",
  )
}

///|
test "Native Mock request projection preserves explicit null and omitted fields distinctly" {
  let present = native_mock_effect_update_request_wire(
    "binding",
    "mapping",
    Json::string("row"),
    { "field": Json::null() },
    {},
    "version",
  ).unwrap()
  let absent = native_mock_effect_update_request_wire(
    "binding",
    "mapping",
    Json::string("row"),
    {},
    {},
    "version",
  ).unwrap()
  assert_true(present != absent)
  assert_eq(
    present, "{\"before\":{},\"binding\":\"binding\",\"mapping\":\"mapping\",\"target\":\"row\",\"value\":{\"field\":null},\"version\":\"version\"}",
  )
}
