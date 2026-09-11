///|
fn wire_environment(
  snapshots : String,
  mappings : String,
) -> @environment.WireEnvironment {
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":" +
    mappings +
    ",\"model_task_contracts\":[],\"schema_snapshots\":" +
    snapshots +
    ",\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  @environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 100, },
  ).unwrap()
}

///|
test "snapshot membership retains its exact wire environment and member" {
  let environment = wire_environment("[" + base() + "]", "[]")
  let entry = @environment.member_at(
    environment,
    @environment.SchemaSnapshots,
    0,
  ).unwrap()
  let attached = read_member(entry, caps()).unwrap()
  assert_true(physical_equal(environment_member(attached), entry))
  assert_true(
    physical_equal(
      @environment.member_environment(environment_member(attached)),
      environment,
    ),
  )
  let snapshot = environment_snapshot(attached)
  assert_eq(
    cid(snapshot),
    "sha256:9f0114feb3b5e8e946c3efc5b89ebe6a44559f13b7ec30809a0e42d173916bec",
  )
  assert_eq(cid(snapshot), @environment.member_cid(entry))
  let other = wire_environment("[" + base() + "]", "[]")
  assert_false(
    physical_equal(
      @environment.member_environment(environment_member(attached)),
      other,
    ),
  )
  let (bytes, nodes) = usage(snapshot)
  assert_true(
    read_member(entry, { max_bytes: bytes, max_nodes: nodes, max_depth: 3, })
    is Ok(_),
  )
  assert_true(
    read_member(entry, { max_bytes: bytes - 1, max_nodes: nodes, max_depth: 3, })
    is Err(BudgetExceeded),
  )
  assert_true(
    read_member(entry, { ..caps(), max_bytes: -1, })
    is Err(InvalidSnapshot(InvalidLimits)),
  )
}

///|
test "same body outside snapshot section is not a snapshot membership" {
  let environment = wire_environment("[]", "[" + base() + "]")
  let entry = @environment.member_at(
    environment,
    @environment.MappingContracts,
    0,
  ).unwrap()
  assert_true(read_member(entry, caps()) is Err(WrongSection))
  let malformed = wire_environment(
    "[{\"source_ref\":\"source:local/s/x\"}]", "[]",
  )
  let incomplete = @environment.member_at(
    malformed,
    @environment.SchemaSnapshots,
    0,
  ).unwrap()
  assert_true(read_member(incomplete, caps()) is Err(InvalidSnapshot(_)))
}
