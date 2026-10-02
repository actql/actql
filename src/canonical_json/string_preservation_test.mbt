///|
test "string values survive canonical serialization and source reload without identity collapse" {
  let values = ["\r", "\n", "\r\n", "é", "e\u{0301}", "\\n"]
  let spellings = [
    "\"\\r\"", "\"\\n\"", "\"\\r\\n\"", "\"é\"", "\"e\u{0301}\"", "\"\\\\n\"",
  ]
  let cids : Array[String] = []
  for i in 0..<values.length() {
    let v = @canonical_json.from_json(Json::string(values[i]), 1, 0, 8)
    let wire = @canonical_json.stringify_value(v, 40, 1, 0)
    assert_eq(wire, spellings[i])
    let parsed = @source.parse_json(wire, {
      max_input_bytes: 40,
      max_nodes: 1,
      max_depth: 0,
    }).unwrap()
    assert_true(parsed.value is @source.String(text) && text == values[i])
    let reloaded = @canonical_json.from_source(parsed, 1, 0, 8)
    assert_eq(@canonical_json.stringify_value(reloaded, 40, 1, 0), wire)
    let cid = @canonical_json.cid_value(v, 40, 1, 0)
    assert_eq(cid, @canonical_json.cid_value(reloaded, 40, 1, 0))
    assert_true(!cids.contains(cid))
    cids.push(cid)
  }
}
