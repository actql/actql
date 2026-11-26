///|
// Independent literal six-field JSON preimage; not a target observation or ACK.
test "Native warm and saved Mock request projection preserves the complete original" {
  let actual = native_mock_effect_file_request_wire(
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
  let present = native_mock_effect_file_request_wire(
    "binding",
    "mapping",
    Json::string("row"),
    { "field": Json::null() },
    {},
    "version",
  ).unwrap()
  let absent = native_mock_effect_file_request_wire(
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

///|
test "Native saved Mock outcomes retain the ordered file key as an array" {
  let key = @canonical.from_json(
    ["west", "9223372036854775807"],
    64,
    8,
    4096,
    data_keys=true,
  )
  let limits : @row_host.RowPageLimits = {
    max_bytes: 4096,
    max_nodes: 64,
    max_depth: 8,
    max_rows: 1,
  }
  let expected =
    #|{"result":{"id":["west","9223372036854775807"]},"state":"applied"}
  let identity = "[\"west\",\"9223372036854775807\"]"
  assert_eq(
    saved_effect_file_outcome_wire(identity, Some(key), limits),
    Some(expected),
  )
  assert_eq(
    saved_effect_file_outcome_wire(identity, Some(key), {
      ..limits,
      max_bytes: expected.length() - 1,
    }),
    None,
  )
  assert_eq(
    saved_effect_file_outcome_wire("west", None, limits),
    Some("{\"result\":{\"id\":\"west\"},\"state\":\"applied\"}"),
  )
}

///|
test "Native UPSERT request differentiates completed absence from the guarded original row" {
  let identity : Json = ["west", "9223372036854775807"]
  let value : Json = { "Name": "After" }
  let absent = native_mock_effect_file_request_wire(
    "binding",
    "mapping",
    identity,
    value,
    Json::null(),
    "",
    inserting=true,
  ).unwrap()
  assert_eq(
    absent, "{\"binding\":\"binding\",\"mapping\":\"mapping\",\"target\":[\"west\",\"9223372036854775807\"],\"value\":{\"Name\":\"After\"}}",
  )
  let present = native_mock_effect_file_request_wire(
    "binding",
    "mapping",
    identity,
    value,
    { "Name": "Before" },
    "version",
  ).unwrap()
  assert_eq(
    present, "{\"before\":{\"Name\":\"Before\"},\"binding\":\"binding\",\"mapping\":\"mapping\",\"target\":[\"west\",\"9223372036854775807\"],\"value\":{\"Name\":\"After\"},\"version\":\"version\"}",
  )
  assert_true(
    native_mock_effect_file_request_wire(
      "binding",
      "mapping",
      identity,
      value,
      Json::null(),
      "version",
      inserting=true,
    )
    is Err(_),
  )
  assert_true(
    native_mock_effect_file_request_wire(
      "binding",
      "mapping",
      Json::string("west"),
      value,
      Json::null(),
      "",
      inserting=true,
    )
    is Err(_),
  )
}
