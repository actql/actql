///|
test "original Graph constructor inventory retains actual labels schema instances and ASCII identities" {
  let root = read_source(property_body())
  let q = @graph_contract.observe_graph_read_construction(root)
  let peak = @graph_contract.graph_read_construction_extent(q)
  let held = @graph_contract.graph_read_retained_extent(q)
  let text = @graph_contract.graph_read_construction_text(q)
  // Literal definitions N/E, labels Node/Person/R, property name, endpoints N/N:
  // 1+1+4+6+1+4+1+1 =19 identifier units plus the retained CID's71 units.
  // Borrowed JSON/enum text is not another owned String backing.
  assert_eq(text.0, 90L)
  assert_true(text.1 >= text.0 && text.2 > 0L)
  assert_true(peak.record_headers >= held.record_headers)
  assert_true(@graph_contract.graph_read_construction_work(q) > 0L)
  let original = @graph_contract.read_cursor(root, caps()).unwrap()
  assert_eq(
    @graph_contract.cid(original),
    "sha256:df3a17807922ac2f939372e0cd59b31ecc7e6c860bc22c985aa8acf05971f166",
  )
  assert_eq(@graph_contract.stringify(original, caps()), property_body())
  // An opaque enum DATA value is not a Graph name or an NFC input. Its
  // occurrence remains represented by the original ValueContract inventory.
  let large = property_body().replace(
    old="\"nullable\":true,\"type\":\"string\"",
    new="\"enum\":[\"" +
      "x".repeat(10000) +
      "\"],\"nullable\":true,\"type\":\"string\"",
  )
  let q2 = @graph_contract.observe_graph_read_construction(read_source(large))
  assert_eq(@graph_contract.graph_read_construction_text(q2).0, 90L)
  assert_eq(@graph_contract.graph_read_construction_text(q2).1, text.1)
  assert_true(
    @graph_contract.read_cursor(read_source(large), {
      max_bytes: 20000,
      max_nodes: 1000,
      max_depth: 100,
    })
    is Ok(_),
  )
}

///|
test "Graph observation preserves the original typed comparison refusal and its charged prefix" {
  let root = read_source(property_body())
  let (_, full_work) = @graph_contract.read_cursor_usage(
    root,
    caps(),
    max_contract_work=100000,
  ).unwrap()
  assert_true(full_work > 0)
  let limit = full_work - 1
  let expected = @graph_contract.read_cursor_usage(
    root,
    caps(),
    max_contract_work=limit,
  ).unwrap_err()
  let (result, used) = @graph_contract.observe_read_cursor_usage(
    root,
    caps(),
    max_contract_work=limit,
  )
  assert_eq(result.unwrap_err(), expected)
  assert_eq(expected, @graph_contract.BudgetExceeded)
  assert_true(used >= 0 && used <= limit)
}
