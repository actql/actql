///|
fn selector_construction_environment(
  body : String,
) -> Result[WireEnvironment, Issue] {
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[" +
    body +
    "],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let bytes = @utf8.encode(
    prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix,
  )
  read(bytes, cid, {
    max_bytes: bytes.length(),
    max_nodes: 10000,
    max_depth: 20,
    max_members: 10,
  })
}

///|
fn selector_construction_member(body : String) -> Member {
  member_at(
    selector_construction_environment(body).unwrap(),
    SchemaSnapshots,
    0,
  ).unwrap()
}

///|
fn selector_construction_body() -> String {
  "{\"carrier_schema_contract_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"data_classification\":\"internal\",\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"source_contract_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"source_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"source_ref\":\"connector://duckdb/local/orders#snapshot\",\"source_view_contract_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"}"
}

///|
test "snapshot selector borrows original closed fields and preserves independent typed roles" {
  let original = selector_construction_member(selector_construction_body())
  let body = member_body(original)
  let checked = @decode.closed_object(body, connector_snapshot_member_fields()).unwrap()
  let classification = evidence_object_text(checked, "data_classification").unwrap()
  let cursor = @decode.required(checked, "data_classification").unwrap()
  assert_true(physical_equal(classification, @decode.text(cursor).unwrap()))
  assert_true(
    connector_source_snapshot_selector(original) ==
    Ok(
      Some({
        source_ref: "connector://duckdb/local/orders#snapshot",
        source_contract_cid: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        source_view_contract_cid: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
        carrier_schema_contract_cid: "sha256:3333333333333333333333333333333333333333333333333333333333333333",
        source_data_policy_cid: "sha256:4444444444444444444444444444444444444444444444444444444444444444",
        data_classification: "internal",
      }),
    ),
  )
  for
    (key, bad) in [
      ("data_classification", "null"),
      ("data_classification", "\"unrecognized\""),
      ("output_carrier", "null"),
      ("output_carrier", "\"scalar\""),
      ("read_mode", "null"),
      ("read_mode", "\"incremental\""),
    ] {
    let expected = match key {
      "data_classification" => "\"internal\""
      "output_carrier" => "\"relation\""
      _ => "\"snapshot\""
    }
    let changed = selector_construction_body().replace(
      old="\"" + key + "\":" + expected,
      new="\"" + key + "\":" + bad,
    )
    assert_true(
      connector_source_snapshot_selector(selector_construction_member(changed))
      is Err(InvalidMember),
    )
  }
}

///|
test "snapshot selector construction follows actual malformed width without granting acceptance" {
  let small = selector_construction_member("{\"source_ref\":\"connector://x\"}")
  let many = StringBuilder()
  many.write_string("{\"source_ref\":\"connector://x\"")
  for i in 0..<100 {
    many.write_string(",\"x" + (i + 1000).to_string() + "\":null")
  }
  many.write_string("}")
  let wide = selector_construction_member(many.to_string())
  let a = connector_source_snapshot_selector_construction(small)
  let b = connector_source_snapshot_selector_construction(wide)
  assert_true(b.record_headers > a.record_headers)
  assert_true(b.reference_slots > a.reference_slots)
  assert_true(b.scalar_words > a.scalar_words)
  assert_true(connector_source_snapshot_selector(small) is Err(InvalidMember))
  assert_true(connector_source_snapshot_selector(wide) is Err(InvalidMember))
  for text in ["null", "{\"source_ref\":null}", "{\"source_ref\":17}"] {
    // These are rejected before an original SchemaSnapshots Member exists.
    // Never forge one to turn a quantity descriptor into semantic admission.
    assert_true(selector_construction_environment(text) is Err(InvalidEnvelope))
  }
  let local_member = selector_construction_member(
    "{\"source_ref\":\"source:local/s/b\"}",
  )
  assert_true(connector_source_snapshot_selector(local_member) is Ok(None))
}
