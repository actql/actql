///|
fn metadata_selection_fixture(wire : String) -> Bytes? {
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 1048576,
    max_nodes: 16384,
    max_depth: 64,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 16384,
    max_depth: 64,
    max_string_bytes: 1048576,
    max_total_string_bytes: 1048576,
  }).unwrap()
  let object = @decode.closed_object(cursor, ["files", "managed_root"]).unwrap()
  original_configuration_selection_body(object)
}

///|
test "original metadata selection emits the existing empty and one-file preimages" {
  assert_eq(
    metadata_selection_fixture("{\"files\":[],\"managed_root\":null}"),
    Some(
      b"{\"files\":[],\"managed_root\":null,\"version\":\"actql-native-local-configuration-selection/0.1\"}",
    ),
  )
  let body = metadata_selection_fixture(
    "{\"files\":[{\"name\":\"a.json\",\"body\":\"{}\",\"device\":\"1\",\"inode\":\"2\",\"size\":\"2\"}],\"managed_root\":null}",
  ).unwrap()
  assert_eq(
    body, b"{\"files\":[{\"content_cid\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"device\":\"1\",\"inode\":\"2\",\"name\":\"a.json\",\"size\":\"2\"}],\"managed_root\":null,\"version\":\"actql-native-local-configuration-selection/0.1\"}",
  )
}

///|
test "original metadata selection refuses changed byte length and foreign fields" {
  for
    file in [
      "{\"name\":\"a.json\",\"body\":\"{}\",\"device\":\"1\",\"inode\":\"2\",\"size\":\"3\"}",
      "{\"name\":\"a.json\",\"body\":\"{}\",\"device\":\"1\",\"inode\":\"2\",\"size\":\"2\",\"foreign\":true}",
    ] {
    assert_true(
      metadata_selection_fixture(
        "{\"files\":[" + file + "],\"managed_root\":null}",
      )
      is None,
    )
  }
  assert_true(metadata_selection_fixture("{\"files\":[]}") is None)
}

///|
test "original metadata selection retains an observed managed root with exact file identity" {
  assert_eq(
    metadata_selection_fixture(
      "{\"files\":[{\"name\":\"a.json\",\"body\":\"{}\",\"device\":\"1\",\"inode\":\"2\",\"size\":\"2\"}],\"managed_root\":{\"device\":\"3\",\"inode\":\"4\",\"path\":\"/original/results\"}}",
    ),
    Some(
      b"{\"files\":[{\"content_cid\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"device\":\"1\",\"inode\":\"2\",\"name\":\"a.json\",\"size\":\"2\"}],\"managed_root\":{\"device\":\"3\",\"inode\":\"4\",\"path\":\"/original/results\"},\"version\":\"actql-native-local-configuration-selection/0.1\"}",
    ),
  )
}

///|
test "original metadata selection covers eight files and a large original body" {
  let body = String::make(45173, 'x')
  let files = [
    "{\"name\":\"compute.json\",\"body\":\"" +
    body +
    "\",\"device\":\"16777234\",\"inode\":\"377981420\",\"size\":\"45173\"}",
  ]
  for
    name in [
      "environment.json", "result-policy.json", "retention-policy.json", "retention.json",
      "run-policy-profile.json", "sdk-read.json", "store.json",
    ] {
    files.push(
      "{\"name\":\"" +
      name +
      "\",\"body\":\"{}\",\"device\":\"16777234\",\"inode\":\"377981420\",\"size\":\"2\"}",
    )
  }
  let wire = "{\"files\":[" +
    files.join(",") +
    "],\"managed_root\":{\"device\":\"16777234\",\"inode\":\"377981423\",\"path\":\"/original/results\"}}"
  let result = metadata_selection_fixture(wire).unwrap()
  let source = @source.parse_json_bytes_preserving(result, {
    max_input_bytes: 8192,
    max_nodes: 128,
    max_depth: 4,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 128,
    max_depth: 4,
    max_string_bytes: 1024,
    max_total_string_bytes: 8192,
  }).unwrap()
  let object = @decode.closed_object(cursor, [
    "files", "managed_root", "version",
  ]).unwrap()
  let selected = @decode.elements(@decode.required(object, "files").unwrap()).unwrap()
  assert_eq(selected.length(), 8)
  let first = @decode.open_object(selected[0]).unwrap()
  assert_eq(required_text(first, "name"), Some("compute.json"))
  assert_eq(required_text(first, "size"), Some("45173"))
  assert_eq(
    required_text(first, "content_cid"),
    Some(
      "sha256:36d88b4624d19e9694b51c22be9475ccda469b2c9c1a98b608517540b53534b5",
    ),
  )
}

///|
test "original metadata selection requires lexical order and refuses duplicates" {
  let short = "{\"name\":\"z.json\",\"body\":\"{}\",\"device\":\"1\",\"inode\":\"2\",\"size\":\"2\"}"
  let long = "{\"name\":\"aa.json\",\"body\":\"{}\",\"device\":\"1\",\"inode\":\"2\",\"size\":\"2\"}"
  assert_true(
    metadata_selection_fixture(
      "{\"files\":[" + long + "," + short + "],\"managed_root\":null}",
    )
    is Some(_),
  )
  for files in [short + "," + long, long + "," + long] {
    assert_true(
      metadata_selection_fixture(
        "{\"files\":[" + files + "],\"managed_root\":null}",
      )
      is None,
    )
  }
}
