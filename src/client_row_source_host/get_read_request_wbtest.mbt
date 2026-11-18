///|
fn get_read_test_limits() -> RowSourceGetReadLimits {
  {
    max_bytes: 2048,
    max_nodes: 128,
    max_depth: 8,
    max_path_bytes: 256,
    max_query_pairs: 4,
    max_query_value_units: 128,
    max_header_name_bytes: 64,
    max_header_value_bytes: 128,
  }
}

///|
test "portable GET declaration retains original query header and nominal request DATA" {
  let wire =
    #|{"method":"GET","path":"/v1/users","query":[["select","id,name"],["fixed","é東京"]],"pageSize":{"parameter":"page_size","limit":100},"versionHeader":{"name":"notion-version","value":"2026-03-11"}}
  let input = @utf8.encode(wire)
  let read = admit_row_source_get_read(
    input,
    Some("start_cursor"),
    get_read_test_limits(),
  ).unwrap()
  assert_eq(row_source_get_read_original_wire(read).unwrap(), wire)
  let page = row_source_get_read_page(read, 9, 2, Some("")).unwrap()
  let frame = row_source_get_page_frame(page).unwrap()
  assert_eq(frame.0, "GET")
  assert_eq(frame.1, "/v1/users")
  assert_eq(frame.2, [
    ["select", "id,name"],
    ["fixed", "é東京"],
    ["page_size", "2"],
    ["start_cursor", ""],
  ])
  assert_eq(frame.3, [
    ["accept", "application/json"],
    ["notion-version", "2026-03-11"],
  ])
  // Neither public vector mutation nor another hint alters the original read
  // or the checked page. UTF-16 strings are not normalized/repaired.
  frame.2[1][1] = "changed"
  frame.3[1][1] = "changed"
  assert_eq(row_source_get_page_frame(page).unwrap().2[1][1], "é東京")
  assert_eq(row_source_get_page_frame(page).unwrap().3[1][1], "2026-03-11")
  let last = row_source_get_read_page(read, 1, 10, Some("é+東京")).unwrap()
  assert_eq(row_source_get_page_frame(last).unwrap().2[2], ["page_size", "1"])
  assert_eq(row_source_get_read_original_wire(read).unwrap(), wire)
  assert_true(
    row_source_get_read_page(read, 0, 1, None) is Err(InvalidPageSize),
  )
  let foreign = { ..read, origin: Ref(()), }
  assert_true(row_source_get_read_page(foreign, 1, 1, None) is Err(ForeignRead))
  assert_true(row_source_get_read_original_wire(foreign) is Err(ForeignRead))
}

///|
test "portable GET declaration refuses ambiguous or authority shaped request DATA" {
  let limits = get_read_test_limits()
  let refusals : Array[(String, RowSourceGetReadIssue)] = [
    ("{\"method\":\"POST\",\"path\":\"/x\"}", InvalidRead),
    ("{\"method\":\"GET\",\"path\":\"/x\",\"body\":{}}", InvalidRead),
    ("{\"method\":\"GET\",\"path\":\"//other/x\"}", InvalidPath),
    ("{\"method\":\"GET\",\"path\":\"/a%2Fb\"}", InvalidPath),
    ("{\"method\":\"GET\",\"path\":\"/a/../b\"}", InvalidPath),
    ("{\"method\":\"GET\",\"path\":\"/a/.\"}", InvalidPath),
    ("{\"method\":\"GET\",\"path\":\"/東京\"}", InvalidPath),
    ("{\"method\":\"GET\",\"path\":\"/x{y}\"}", InvalidPath),
    (
      "{\"method\":\"GET\",\"path\":\"/x\",\"query\":[[\"q\",\"a\"],[\"q\",\"b\"]]}",
      DuplicateParameter,
    ),
    (
      "{\"method\":\"GET\",\"path\":\"/x\",\"query\":[[\"after\",\"a\"]]}",
      DuplicateParameter,
    ),
    (
      "{\"method\":\"GET\",\"path\":\"/x\",\"pageSize\":{\"parameter\":\"after\",\"limit\":2}}",
      DuplicateParameter,
    ),
    (
      "{\"method\":\"GET\",\"path\":\"/x\",\"versionHeader\":{\"name\":\"authorization\",\"value\":\"Bearer secret\"}}",
      InvalidHeader,
    ),
    (
      "{\"method\":\"GET\",\"path\":\"/x\",\"versionHeader\":{\"name\":\"api-version\",\"value\":\"ok\\r\\nInjected:bad\"}}",
      InvalidHeader,
    ),
  ]
  for (wire, issue) in refusals {
    assert_true(
      admit_row_source_get_read(@utf8.encode(wire), Some("after"), limits)
      is Err(actual) &&
      actual == issue,
    )
  }
  // The cursor/page query slots belong to the SAME closed transport bound;
  // exact four is admitted above, one fewer cannot silently drop a pair.
  let one_short = { ..limits, max_query_pairs: 3, }
  let full =
    #|{"method":"GET","path":"/x","query":[["a","1"],["b","2"]],"pageSize":{"parameter":"size","limit":10}}
  assert_true(
    admit_row_source_get_read(@utf8.encode(full), Some("after"), one_short)
    is Err(InvalidQuery),
  )
  assert_true(
    admit_row_source_get_read(@utf8.encode(full), Some("after"), limits)
    is Ok(_),
  )
}

///|
test "portable GET original metadata carries exact path hint and vector counts without authority" {
  let wire =
    #|{"method":"GET","path":"/records","query":[["fixed","original"]],"pageSize":{"parameter":"size","limit":2},"versionHeader":{"name":"api-version","value":"2026-03-11"}}
  let read = admit_row_source_get_read(
    @utf8.encode(wire),
    Some("after"),
    get_read_test_limits(),
  ).unwrap()
  assert_eq(
    row_source_get_read_metadata(read).unwrap(),
    ("/records", true, 2, 3, 2),
  )
  let bare = admit_row_source_get_read(
    @utf8.encode("{\"method\":\"GET\",\"path\":\"/x\"}"),
    None,
    get_read_test_limits(),
  ).unwrap()
  assert_eq(row_source_get_read_metadata(bare).unwrap(), ("/x", false, 0, 0, 1))
  let foreign = { ..read, origin: Ref(()), }
  assert_true(row_source_get_read_metadata(foreign) is Err(ForeignRead))
}
