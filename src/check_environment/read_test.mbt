///|
fn caps() -> Limits {
  { max_bytes: 100000, max_nodes: 10000, max_depth: 2000, max_members: 100, }
}

///|
fn wire(policy : String, snapshots : String) -> (String, String) {
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":" +
    policy +
    ",\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":" +
    snapshots +
    ",\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  (prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix, cid)
}

///|
test "wire integrity rejects noncanonical bytes and foreign expected identity" {
  let (body, expected) = wire("{}", "[]")
  for changed in [" " + body, body + "\n", "\u{FEFF}" + body] {
    assert_true(
      read(@utf8.encode(changed), expected, caps()) is Err(NonCanonicalBytes),
    )
  }
  assert_true(
    read(@utf8.encode(body), "sha256:" + "0".repeat(64), caps())
    is Err(IdentityMismatch),
  )
  assert_true(
    read(@utf8.encode(body), expected, { ..caps(), max_members: -1, })
    is Err(InvalidLimits),
  )
  let (unsorted_keys, id) = wire("{\"z\":0,\"a\":1}", "[]")
  assert_true(
    read(@utf8.encode(unsorted_keys), id, caps()) is Err(NonCanonicalBytes),
  )
}

///|
test "item handles retain exact environment ownership without admitting their meaning" {
  let snapshot = "{\"source_ref\":\"source:local/s/x\",\"value\":[null,true,false,1,\"x\"]}"
  let (body, expected) = wire("{}", "[" + snapshot + "]")
  let environment = read(@utf8.encode(body), expected, caps()).unwrap()
  let item = member_at(environment, SchemaSnapshots, 0).unwrap()
  assert_true(physical_equal(member_environment(item), environment))
  assert_eq(member_section(item), SchemaSnapshots)
  assert_eq(member_index(item), 0)
  assert_eq(member_count(environment, SchemaSnapshots), 1)
  assert_eq(member_count(environment, ConnectorCatalogs), 0)
  assert_eq(member_cid(item), "sha256:" + @sha.hex(@utf8.encode(snapshot)))
  let writer = @encode.writer(10000, 1000, 100)
  emit_member(item, writer)
  assert_eq(@encode.finish(writer), snapshot)
  assert_true(member_at(environment, SchemaSnapshots, -1) is None)
  assert_true(member_at(environment, SchemaSnapshots, 1) is None)
  assert_true(@decode.object_length(host_policy(environment)) is Some(0))
  let other = read(@utf8.encode(body), expected, caps()).unwrap()
  assert_false(physical_equal(member_environment(item), other))
  assert_true(@decode.tree_index(host_policy(other), member_body(item)) is None)
  assert_true(
    read(@utf8.encode(body), expected, { ..caps(), max_members: 0, })
    is Err(BudgetExceeded),
  )
}

///|
test "deep evidence uses bounded nonrecursive canonical emission" {
  let policy = "{\"data\":" +
    "[".repeat(1000) +
    "[null,true,false,1,\"x\"]" +
    "]".repeat(1000) +
    "}"
  let (body, expected) = wire(policy, "[]")
  let environment = read(@utf8.encode(body), expected, caps()).unwrap()
  let writer = @encode.writer(100000, 10000, 2000)
  emit(environment, writer)
  assert_eq(@encode.finish(writer), body)
  assert_true(
    read(@utf8.encode(body), expected, { ..caps(), max_depth: 1000, })
    is Err(BudgetExceeded),
  )
}
