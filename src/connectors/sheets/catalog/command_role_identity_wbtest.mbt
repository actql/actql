///|
// The ordinary checker owns identity uniqueness; a different CID is not a
// second meaning for the same (id, version) in the combined role registry.
fn sheets_role_registry(entries : Array[Json]) -> @environment.WireEnvironment {
  let wires = entries.map(value => {
    range_canonical(value, owned_limits()).unwrap()
  })
  wires.sort_by((a, b) => {
    @sha.hex(@utf8.encode(a)).compare(@sha.hex(@utf8.encode(b)))
  })
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[" +
    wires.join(",") +
    "],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  @environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    { max_bytes: 300000, max_nodes: 200000, max_depth: 32, max_members: 8, },
  ).unwrap()
}

///|
test "Sheets clear and update original roles coexist in the same checked registry" {
  let update_wire = range_command_json(
    "sheets-book",
    clear_columns_wire(),
    clear_range_wire(),
    owned_limits(),
  ).unwrap()
  let clear_wire = clear_command_json(
    "sheets-book",
    clear_columns_wire(),
    clear_range_wire(),
    owned_limits(),
  ).unwrap()
  let update = @json.parse(update_wire) catch { _ => abort("update bundle") }
  let clear = @json.parse(clear_wire) catch { _ => abort("clear bundle") }
  guard update is Object(update) &&
    update.get("contracts") is Some(Array(update_roles)) &&
    clear is Object(clear) &&
    clear.get("contracts") is Some(Array(clear_roles)) else {
    abort("original role arrays")
  }
  let roles = []
  for role in update_roles {
    roles.push(role)
  }
  for role in clear_roles {
    roles.push(role)
  }
  let registry = sheets_role_registry(roles)
  assert_eq(
    @environment.check_contract_registry(registry, {
      max_bytes: 300000,
      max_nodes: 200000,
      max_depth: 32,
      max_members: 8,
    }).map(_ => true),
    Ok(true),
  )
  assert_eq(
    range_contract_cid(update_roles[0]),
    "sha256:78db59086c6c4c9465fb3056c990d3fb01272730b035cefe01c26acfd726f299",
  )
  assert_eq(
    range_contract_cid(update_roles[1]),
    "sha256:055d991819365174d58a40e0ae5a108d6fd165273ec970fc174da5a21c99f4b9",
  )
  for index, kind in ["command_input", "command_output"] {
    guard clear_roles[index] is Object(role) else { abort("clear role") }
    assert_eq(
      role.get("id"),
      Some(("sheets-book.sheets.clear_range." + kind).to_json()),
    )
  }
}
