///|
fn keyed_wire_usage_fixture() -> (ClientKeyedLookupInput, () -> Bool) raise {
  let rows = "[" +
    ["é0", "é1"]
    .map(version => {
      "{\"path\":\"file.txt\",\"resource\":" +
      keyed_work_resource() +
      ",\"version\":\"" +
      version +
      "\"}"
    })
    .join(",") +
    "]"
  let (lookup, cleanup, _) = keyed_work_original_fixture(rows, 2, 1000000)
  (lookup, cleanup)
}

///|
test "planned Request history retains exact original encoder bytes and nodes without using byte count as nodes" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  start_client_keyed_lookup_request_plan(lookup).unwrap()
  for row in 0..<2 {
    let request = keyed_work_request(lookup, row)
    retain_client_keyed_lookup_planned_request(lookup, request).unwrap()
    let (wire, _, original) = lookup.known[row]
    let history = original.unwrap()
    assert_true(physical_equal(history.request, request))
    assert_eq(history.wire_bytes, @utf8.encode(wire).length())
    assert_eq(
      history.wire_nodes,
      source_dependency_json_nodes(@json.parse(wire)),
    )
    assert_true(history.wire_bytes > wire.length())
    assert_true(history.wire_nodes < history.wire_bytes)
    assert_eq(lookup.selected_wire_bytes, 0)
    assert_eq(lookup.selected_wire_nodes, 0)
  }
  assert_eq(lookup.known.length(), 2)
  assert_eq(lookup.max_work, 1000000)
}

///|
test "measured original Request facts keep full CID admission and cannot bless changed equal-size bytes" {
  let (lookup, cleanup) = keyed_wire_usage_fixture()
  defer assert_true(cleanup())
  start_client_keyed_lookup_request_plan(lookup).unwrap()
  let request = keyed_work_request(lookup, 0)
  retain_client_keyed_lookup_planned_request(lookup, request).unwrap()
  let (wire, _, original) = lookup.known[0]
  let history = original.unwrap()
  let cid = "sha256:" + @sha.text_hex(wire).unwrap()
  let observed = Ref((0, 0))
  let before = (bytes : Int, nodes : Int, _depth : Int) => {
    observed.val = (bytes, nodes)
    true
  }
  admit_client_effect_dependency_capture_body(
    "request_values",
    Some(cid),
    wire,
    1000000,
    10000,
    100,
    Some(before),
    () => !lookup.closed,
    wire_extent=Some((history.wire_bytes, history.wire_nodes)),
  ).unwrap()
  |> ignore
  assert_eq(observed.val, (history.wire_bytes, history.wire_nodes))
  let changed = wire.replace(old="é0", new="é1")
  assert_true(changed != wire)
  assert_eq(@utf8.encode(changed).length(), history.wire_bytes)
  assert_true(
    admit_client_effect_dependency_capture_body(
      "request_values",
      Some(cid),
      changed,
      1000000,
      10000,
      100,
      Some(before),
      () => !lookup.closed,
      wire_extent=Some((history.wire_bytes, history.wire_nodes)),
    )
    is Err(_),
  )
  assert_eq(lookup.max_work, 1000000)
}
