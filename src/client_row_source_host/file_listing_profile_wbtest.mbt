///|
// The protocol-only fixtures below use their own row schema. Their ceiling is
// nevertheless obtained from an actual declared and checked listing Catalog,
// not a fabricated facts CID or a test-only resolver.
fn listing_profile_fixture(
  maximum : Int64?,
) -> @environment.FileListProfile raise {
  let fields : Json = {
    "resource": {
      "type": "resource_ref",
      "resource_kind": "file",
      "nullable": false,
    },
    "name": { "type": "string", "nullable": false },
    "version": { "type": "string", "nullable": false },
    "path": { "type": "string", "nullable": true },
    "media_type": { "type": "string", "nullable": true },
    "size_bytes": { "type": "number", "nullable": true },
    "modified_at": { "type": "timestamp", "nullable": true },
  }
  let canonical = @identity.from_json(fields, 1000, 32, 100000)
  let spec : RowRelationViewSpec = {
    resource: "files",
    resource_kind: "file",
    schema_wire: @identity.stringify_value(canonical, 100000, 1000, 32),
    schema_cid: @identity.cid_value(canonical, 100000, 1000, 32),
    request_schema_wire: Some(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"paths":{"type":"array","nullable":true,"items":{"type":"string","nullable":false}},"glob":{"type":"string","nullable":true}}}
      ),
    ),
    facts_wire: None,
    acquisition_wire: None,
  }
  let first = generate_relation_row_declaration(
    "listing-fixture",
    "fixture",
    "fixture/0.1",
    [spec],
    declaration_limits,
  ).unwrap()
  let profile : Json = {
    "version": "actql-file-list/0.1",
    "kind": "file_listing",
    "selectable": ["paths", "glob"],
    "allow_unfiltered_listing": true,
    "admitted_scope_contract_cid": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "listing_schema_contract_cid": first.views[0].carrier_schema_cid,
    "version_capability": {
      "contract_cid": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "required_nonnull": true,
    },
  }
  if maximum is Some(maximum) {
    guard profile is Object(fields) else { abort("profile fixture") }
    fields["max_listing_items"] = Json::number(maximum.to_double())
  }
  let declaration = generate_relation_row_declaration(
    "listing-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        ..spec,
        facts_wire: Some(({ "file_listing": profile } : Json).stringify()),
      },
    ],
    declaration_limits,
  ).unwrap()
  let sorted = (values : Array[String]) => {
    let bodies = values.map(text => {
      let body = @identity.from_json(@json.parse(text), 10000, 100, 100000)
      (@identity.cid_value(body, 100000, 10000, 100), @json.parse(text))
    })
    bodies.sort_by((a, b) => a.0.compare(b.0))
    Json::array(bodies.map(value => value.1))
  }
  let body : Json = {
    "version": "actql-check-environment/0.1",
    "connector_capabilities": [],
    "command_contracts": [],
    "connector_catalogs": [@json.parse(declaration.catalog)],
    "contract_registry": sorted(declaration.contracts),
    "host_policy_profile": {},
    "mapping_contracts": [],
    "model_task_contracts": [],
    "schema_snapshots": [],
    "source_views": sorted(declaration.view_bodies),
  }
  let canonical = @identity.from_json(body, 10000, 100, 100000)
  let cid = @identity.cid_value(canonical, 100000, 10000, 100)
  let sealed_body = @identity.object_with_string_field(
    canonical, "evidence_bundle_cid", cid,
  ).unwrap()
  let caps : @environment.Limits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_members: 100,
  }
  let raw = @environment.read(
    @utf8.encode(@identity.stringify_value(sealed_body, 100000, 10000, 100)),
    cid,
    caps,
  ).unwrap()
  let registry = @environment.check_contract_registry(raw, caps).unwrap()
  let catalogs = @environment.check_catalog_contents(registry, caps).unwrap()
  let references = @environment.check_catalog_references(catalogs, {
    max_work: 1000000,
    max_references: 1000,
  }).unwrap()
  let policies = @environment.check_source_data_policies(references, {
    max_work: 1000000,
    max_policies: 100,
  }).unwrap()
  let values = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 100,
    contracts: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
  }).unwrap()
  let shapes = @environment.check_source_view_shapes(values, {
    max_views: 100,
    max_work: 1000000,
  }).unwrap()
  let modes = @environment.check_source_read_modes(shapes, 1000000).unwrap()
  let carriers = @environment.check_carrier_schemas(modes, {
    max_work: 1000000,
    max_schemas: 100,
    bodies: { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  }).unwrap()
  let requests = @environment.check_source_request_contracts(carriers, {
    max_work: 1000000,
    max_roles: 1000,
  }).unwrap()
  @environment.source_request_file_listing(
    @environment.source_request_at(requests, 0).unwrap(),
  ).unwrap()
}

///|
fn listing_rows_fixture(
  maximum : Int64?,
  policy : @capacity.Policy?,
) -> RowListingRows? {
  let profile = listing_profile_fixture(maximum) catch {
    _ => abort("admitted listing fixture")
  }
  @environment.resolve_file_listing_rows(
    profile, policy, "file-listing:fixture",
  )
  .map(resolved => { resolved, })
  .to_option()
}
