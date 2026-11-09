///|
let local_codec_intent : String = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

///|
test "shared original codec preserves the Native custody body and its independent CID" {
  let fields = [
    ("device", "18446744073709551615"),
    ("inode", "2"),
    ("intent_cid", local_codec_intent),
    ("size", "17"),
    ("version", "actql-native-local-configuration-custody/0.1"),
  ]
  let body = client_local_original_record_body(fields).unwrap()
  assert_eq(
    body, b"{\"device\":\"18446744073709551615\",\"inode\":\"2\",\"intent_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"size\":\"17\",\"version\":\"actql-native-local-configuration-custody/0.1\"}",
  )
  // Independently hashed literal preimages, not generated product expectations.
  assert_eq(
    @sha.hex(body),
    "ed8eaffad01212cb2b143da2a11d19b8154a2e45cb98b530831cca55c747f3d0",
  )
  assert_eq(
    client_local_original_record_fields(body, fields.map(field => field.0)).unwrap(),
    fields.map(field => field.1),
  )
}

///|
test "shared original codec preserves decomposed text and literal CRLF and NUL" {
  for
    (principal, expected) in [
      (
        "e\u{0301}", "a76e0762968fbb23a638fbda86c378ee60bac4a9c486936ae8ca284d6360d290",
      ),
      ("é", "8d5669c9f7dbe975595cb2113f478ec18cfc835fb092befc73ef59d19f4d9a62"),
    ] {
    let fields = [("principal", principal), ("text", "a\r\nb\u{0000}")]
    let body = client_local_original_record_body(fields).unwrap()
    assert_eq(@sha.hex(body), expected)
    assert_eq(
      client_local_original_record_fields(body, ["principal", "text"]).unwrap(),
      [principal, "a\r\nb\u{0000}"],
    )
  }
}

///|
test "shared original codec rejects repaired ordering duplicate missing NULL and unknown fields" {
  assert_eq(
    client_local_original_record_fields(b"{\"a\":\"x\",\"b\":\"y\"}", ["a", "b"]),
    Ok(["x", "y"]),
  )
  for
    body in [
      b"{\"b\":\"y\",\"a\":\"x\"}", b"{\"a\": \"x\",\"b\":\"y\"}", b"{\"a\":\"x\",\"a\":\"x\",\"b\":\"y\"}",
      b"{\"a\":\"x\"}", b"{\"a\":\"x\",\"b\":null}", b"{\"a\":\"x\",\"b\":1}", b"{\"a\":\"x\",\"b\":\"y\",\"unknown\":\"z\"}",
      b"{\"a\":\"\\u0078\",\"b\":\"y\"}",
    ] {
    assert_true(
      client_local_original_record_fields(body, ["a", "b"])
      is Err(InvalidOriginal),
    )
  }
}

///|
test "shared original codec retains original byte node and string budgets" {
  assert_true(
    client_local_original_record_body([("a", "x".repeat(8193))])
    is Err(Encoding),
  )
  assert_true(
    client_local_original_record_body(Array::makei(65, i => ("field\{i}", "x")))
    is Err(Encoding),
  )
  let body = client_local_original_record_body([("a", "x".repeat(4097))]).unwrap()
  assert_true(
    client_local_original_record_fields(body, ["a"]) is Err(InvalidOriginal),
  )
  assert_true(
    client_local_original_record_fields(@utf8.encode("x".repeat(8193)), ["a"])
    is Err(InvalidOriginal),
  )
}

///|
test "shared selection codec preserves NULL managed root and the exact unsigned physical facts" {
  let empty = client_local_configuration_selection_body([], None).unwrap()
  assert_eq(
    empty, b"{\"files\":[],\"managed_root\":null,\"version\":\"actql-native-local-configuration-selection/0.1\"}",
  )
  assert_eq(
    @sha.hex(empty),
    "e49c9c59f294288b9683c5ce6b57ce577df5eafd5ffed2619e48e86846006e1c",
  )
  let body = client_local_configuration_selection_body(
    [
      {
        content_cid: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        device: 7UL,
        inode: 18446744073709551615UL,
        name: "e\u{0301}.json",
        size: 11L,
      },
    ],
    Some({ device: 9UL, inode: 10UL, path: "/private/e\u{0301}/line\r\n", }),
  ).unwrap()
  assert_eq(
    @sha.hex(body),
    "47fed844d13e92c5b85ab964e4b0e22753414797cc36eccc9ecb0bf85ce99610",
  )
}

///|
test "shared selection codec preserves the ten selected files bound and original order" {
  let first : ClientLocalOriginalConfigurationFile = {
    content_cid: local_codec_intent,
    device: 1UL,
    inode: 2UL,
    name: "z.json",
    size: 3L,
  }
  let second = { ..first, name: "a.json", }
  let forward = client_local_configuration_selection_body([first, second], None).unwrap()
  let reverse = client_local_configuration_selection_body([second, first], None).unwrap()
  assert_true(forward != reverse)
  assert_true(
    client_local_configuration_selection_body(Array::make(8, first), None)
    is Ok(_),
  )
  assert_true(
    client_local_configuration_selection_body(Array::make(9, first), None)
    is Ok(_),
  )
  assert_true(
    client_local_configuration_selection_body(Array::make(10, first), None)
    is Ok(_),
  )
  assert_true(
    client_local_configuration_selection_body(Array::make(11, first), None)
    is Err(ConfigurationLimit),
  )
  assert_true(
    client_local_configuration_selection_body(
      [first],
      Some({ device: 1UL, inode: 2UL, path: "x".repeat(8193), }),
    )
    is Err(Encoding),
  )
}

///|
test "selection codec retains one distinct Host original without widening the ten implementation inputs" {
  let first : ClientLocalOriginalConfigurationFile = {
    content_cid: local_codec_intent,
    device: 1UL,
    inode: 2UL,
    name: "input.json",
    size: 3L,
  }
  let files = Array::make(10, first)
  files.push({ ..first, name: "host.json", })
  assert_true(client_local_configuration_selection_body(files, None) is Ok(_))
  files.push({ ..first, name: "foreign.json", })
  assert_true(
    client_local_configuration_selection_body(files, None)
    is Err(ConfigurationLimit),
  )
  assert_true(
    client_local_configuration_selection_body(Array::make(11, first), None)
    is Err(ConfigurationLimit),
  )
}
