///|
fn source_extent_json(value : Json) -> (String, String) raise {
  let original = @canonical.from_json(value, 4000000, 64, 4000000)
  (
    @canonical.stringify_value(original, 4000000, 4000000, 64),
    @canonical.cid_value(original, 4000000, 4000000, 64),
  )
}

///|
fn source_extent_members(bodies : Array[String]) -> Array[Json] raise {
  let members = []
  for body in bodies {
    let original = @json.parse(body)
    let (_, cid) = source_extent_json(original)
    members.push((cid, original))
  }
  members.sort_by((left, right) => left.0.compare(right.0))
  members.map(value => value.1)
}

///|
fn source_extent_environment(
  malformed : Bool,
  count? : Int = 65,
) -> (String, String) raise {
  let views : Array[Json] = []
  for index in 0..<count {
    views.push({
      "resource": ("records_" + index.to_string()).to_json(),
      "resource_kind": "record",
      "fields": [{ "name": "id", "type": "number", "nullable": false }],
    })
  }
  let declaration = @row_host.restore_row_declaration(
    "extent",
    "fixture",
    "fixture/0.1",
    ({ "views": views } : Json).stringify(),
    None,
  ).unwrap()
  let (schemas, capabilities) = @row_host.row_declaration_evidence_members(
    declaration,
  )
  guard @json.parse(run_materials_environment_wire) is Object(body) else {
    abort("environment fixture")
  }
  body.remove("evidence_bundle_cid")
  body["schema_snapshots"] = source_extent_members(schemas).to_json()
  body["connector_capabilities"] = source_extent_members(capabilities).to_json()
  let source_views = source_extent_members(declaration.view_bodies)
  if malformed {
    // The unselected final member still belongs to the complete original.
    source_views[source_views.length() - 1] = []
  }
  body["source_views"] = source_views.to_json()
  body["contract_registry"] = source_extent_members(declaration.contracts).to_json()
  body["connector_catalogs"] = [@json.parse(declaration.catalog)].to_json()
  body["connector_manifest"] = {
    "version": "actql-connectors/0.1",
    "connectors": [@json.parse(declaration.manifest_entry)],
  }
  let (_, cid) = source_extent_json(Json::object(body))
  body["evidence_bundle_cid"] = cid.to_json()
  let (wire, _) = source_extent_json(Json::object(body))
  (wire, cid)
}

///|
test "Source default wire admission follows the complete original input extent" {
  let (body, cid) = source_extent_environment(false)
  let bytes = @utf8.encode(body)
  assert_true(bytes.length() > 65536)
  let original = admit_client_check_environment_wire(body, cid).unwrap()
  assert_eq(@environment.member_count(original, @environment.SourceViews), 65)
  assert_eq(
    @environment.member_count(original, @environment.SchemaSnapshots),
    65,
  )
  let checked = admit_client_check_environment_from_wire(
    original,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  assert_eq(@checked.checking_environment_cid(checked), cid)
  assert_true(
    @environment.read(bytes, cid, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    })
    is Err(@environment.BudgetExceeded),
  )
}

///|
test "Source extent admission preserves original identity and unused-section rejection" {
  let (body, cid) = source_extent_environment(false)
  assert_true(
    admit_client_check_environment_wire(body, "sha256:" + "0".repeat(64))
    is None,
  )
  let (malformed, malformed_cid) = source_extent_environment(true)
  assert_true(malformed_cid != cid)
  assert_true(
    admit_client_check_environment_wire(malformed, malformed_cid) is None,
  )
}
