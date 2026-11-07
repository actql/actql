///|
fn runtime_operator_fixture(wire : String) -> String raise {
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }).unwrap()
  let complete = @canonical.from_source(source, 8192, 64, 65536)
  let body = @canonical.object_without_field(complete, "evidence_bundle_cid").unwrap()
  let cid = @canonical.cid_value(body, 65536, 8192, 64)
  let issued = @canonical.object_with_string_field(
    body, "evidence_bundle_cid", cid,
  ).unwrap()
  @canonical.stringify_value(issued, 65536, 8192, 64)
}

///|
test "Runtime binding accepts explicit finite operator capacity without replacing installed policy" {
  let installed = @host.client_local_product_assets().environment
  let operator = runtime_operator_fixture(
    installed.replace(
      old="\"max_relation_output_rows\":1000",
      new="\"max_relation_output_rows\":100000",
    ),
  )
  assert_true(
    local_runtime_capacity_environment_compatible(operator, installed),
  )
  assert_true(
    local_runtime_capacity_environment_compatible(installed, operator),
  )
  assert_true(installed.contains("\"max_relation_output_rows\":1000"))
}

///|
test "Runtime binding rejects noncapacity Environment and policy changes" {
  let installed = @host.client_local_product_assets().environment
  for
    (old, new) in [
      ("\"command_contracts\":[]", "\"command_contracts\":[{}]"),
      ("\"max_input_codepoints\":4096", "\"max_input_codepoints\":4095"),
    ] {
    assert_true(installed.contains(old))
    let changed = runtime_operator_fixture(installed.replace(old~, new~))
    assert_false(
      local_runtime_capacity_environment_compatible(changed, installed),
    )
  }
}

///|
test "Runtime binding rejects stale Environment self identity" {
  let installed = @host.client_local_product_assets().environment
  let changed = installed.replace(
    old="\"max_relation_output_rows\":1000",
    new="\"max_relation_output_rows\":100000",
  )
  assert_false(
    local_runtime_capacity_environment_compatible(changed, installed),
  )
  assert_false(local_runtime_capacity_environment_compatible("{}", installed))
}

///|
test "Runtime binding rejects invalid finite capacities and unsupported capacity version" {
  let installed = @host.client_local_product_assets().environment
  for
    (old, new) in [
      ("\"max_relation_output_rows\":1000", "\"max_relation_output_rows\":-1"),
      ("\"max_relation_output_rows\":1000", "\"max_relation_output_rows\":0.5"),
      ("actql-capacity-host-policy/0.1", "actql-capacity-host-policy/other"),
    ] {
    let changed = runtime_operator_fixture(installed.replace(old~, new~))
    assert_false(
      local_runtime_capacity_environment_compatible(changed, installed),
    )
  }
}
