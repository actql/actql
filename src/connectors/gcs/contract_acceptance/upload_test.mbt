///|
// Actual Common contract admission, not an installed ReferenceIssuer or grant.
fn canonical(value : Json) -> String raise {
  @canonical.stringify_value(
    @canonical.from_json(value, 20000, 64, 100000),
    100000,
    20000,
    64,
  )
}

///|
fn cid(value : Json) -> String raise {
  "sha256:" + @sha.hex(@utf8.encode(canonical(value)))
}

///|
fn caps() -> @environment.Limits {
  { max_bytes: 100000, max_nodes: 20000, max_depth: 64, max_members: 100, }
}

///|
fn value_caps() -> @value.Limits {
  { max_nodes: 1000, max_depth: 32, max_text_bytes: 32768, }
}

///|
fn body_sorted(values : Array[Json]) -> Array[Json] raise {
  let keyed = values.map(value => (cid(value), value))
  keyed.sort_by((left, right) => left.0.compare(right.0))
  keyed.map(pair => pair.1)
}

///|
fn upload_environment() -> (@environment.WireEnvironment, String) raise {
  // Independent valid empty Catalog: no fake Source, Values or issued Ref.
  let old_catalog =
    #|{"catalog_cid":"sha256:74765512d8f6e59d807f87de33f97bf1bea07b40a7719731d6bbe33347e7786a","commands":[],"connector_id":"exports","connector_version":"gcs/0.1","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}
  let manifest =
    #|{"connector":"gcs","connector_id":"exports","connector_version":"gcs/0.1"}
  let original : Json = {
    "connector_id": "exports",
    "connector_registration": "gcs",
    "connector_version": "gcs/0.1",
    "catalog": old_catalog,
    "catalog_cid": "sha256:74765512d8f6e59d807f87de33f97bf1bea07b40a7719731d6bbe33347e7786a",
    "contracts": [],
    "views": [],
    "view_bodies": [],
    "manifest_entry": manifest,
    "manifest_entry_cid": "sha256:770110acd081a211ff71ba28f48fcd784e388ca4d5207e9a7a43402c1bd3e6a0",
    "evidence_schemas": [],
    "evidence_capabilities": [],
  }
  let limits : @gcs.ObjectUploadDeclarationLimits = {
    max_bytes: 32768,
    max_nodes: 4096,
    max_depth: 32,
  }
  let declared_wire = @gcs.object_upload_catalog_json(
    canonical(original),
    "exports",
    limits,
  ).unwrap()
  guard @json.parse(declared_wire) is Object(declared) &&
    declared["catalog"] is String(catalog_wire) &&
    declared["catalog_cid"] is String(catalog_cid) &&
    declared["contracts"] is Array(contracts) &&
    declared["command_bodies"] is Array(commands) else {
    abort("GCS declaration")
  }
  let binding = @gcs.prepare_object_collection_binding(
    "project",
    "bucket",
    "exports/",
    "connector://exports/objects",
    "file_collection",
    catalog_cid,
    "sha256:" + "b".repeat(64),
    { max_bytes: 32768, max_nodes: 4096, max_depth: 32, },
  ).unwrap()
  let mapping = @json.parse(
    @gcs.object_upload_mapping_json(binding, declared_wire, "exports", limits).unwrap(),
  )
  let roles = contracts.map(item => {
    guard item is String(wire) else { abort("role wire") }
    @json.parse(wire)
  })
  let command_bodies = commands.map(item => {
    guard item is String(wire) else { abort("Command wire") }
    @json.parse(wire)
  })
  let body : Json = {
    "version": "actql-check-environment/0.1",
    "schema_snapshots": [],
    "connector_capabilities": [],
    "mapping_contracts": [mapping],
    "source_views": [],
    "command_contracts": body_sorted(command_bodies),
    "model_task_contracts": [],
    "contract_registry": body_sorted(roles),
    "connector_catalogs": [@json.parse(catalog_wire)],
    "host_policy_profile": {},
    "connector_manifest": {
      "version": "actql-connectors/0.1",
      "connectors": [@json.parse(manifest)],
    },
  }
  let expected = cid(body)
  guard body is Object(fields) else { abort("environment") }
  fields["evidence_bundle_cid"] = expected.to_json()
  let wire = canonical(body)
  (@environment.read(@utf8.encode(wire), expected, caps()).unwrap(), wire)
}

///|
fn catalogs(
  original : @environment.WireEnvironment,
) -> @environment.CatalogContents {
  @environment.check_catalog_contents(
    @environment.check_contract_registry(original, caps()).unwrap(),
    caps(),
  ).unwrap()
}

///|
fn references(
  contents : @environment.CatalogContents,
) -> @environment.CatalogReferences {
  @environment.check_catalog_references(contents, {
    max_work: 100000,
    max_references: 100,
  }).unwrap()
}

///|
test "GCS complete upload role is admitted by original Common with exact presence" {
  let (original, _) = upload_environment()
  let contents = catalogs(original)
  let references = references(contents)
  let target = @environment.select_command_target(
    contents, "command:exports.gcs.upload.v1", 100000,
  ).unwrap()
  assert_eq(
    @environment.command_target_cid(target),
    "sha256:01b4437a23e585b15309e958d28d7069d58f3f9002ec6fffe8458dc24b58fa39",
  )
  let (input, work) = @environment.command_target_input_contract(
    target,
    references,
    value_caps(),
    100000,
  ).unwrap()
  assert_true(work > 0)
  assert_eq(@environment.command_input_contract_field_count(input), 4)
  for name in ["content", "name"] {
    assert_true(@environment.command_input_contract_field_required(input, name))
  }
  for name in ["content_type", "overwrite"] {
    assert_false(
      @environment.command_input_contract_field_required(input, name),
    )
  }
  let content = @environment.command_input_contract_field_type(input, "content").unwrap()
  assert_true(content.shape is @value.ContentRef(media_type=None))
  assert_false(content.nullable)
  let protocols = @environment.check_protocol_value_contracts(
    @environment.check_source_data_policies(references, {
      max_work: 100000,
      max_policies: 100,
    }).unwrap(),
    { max_envelopes: 100, contracts: value_caps(), },
  ).unwrap()
  let mut found = false
  for index in 0..<@environment.protocol_value_usage(protocols).2 {
    let item = @environment.protocol_value_at(protocols, index).unwrap()
    if @environment.contract_role(@environment.protocol_value_envelope(item)) ==
      "command_input" {
      found = true
      assert_true(@environment.protocol_value_type(item) is None)
      assert_eq(
        @environment.command_input_contract_field_count(
          @environment.protocol_command_input_type(item).unwrap(),
        ),
        4,
      )
    }
  }
  assert_true(found)
}

///|
test "GCS Mapping selects the same original Command with create-none not a grant" {
  let (original, _) = upload_environment()
  let contents = catalogs(original)
  let mapping = @environment.mapping_shape_at(
    @environment.check_mapping_contract_shapes(original, caps(), 100000).unwrap(),
    0,
  ).unwrap()
  let bound = @environment.bind_store_command(mapping, contents, 100000).unwrap()
  assert_eq(
    @environment.store_command_mapping_operation(bound),
    ("create", "none"),
  )
  assert_true(
    physical_equal(@environment.store_command_mapping(bound), mapping),
  )
  assert_true(
    physical_equal(
      @environment.member_environment(
        @environment.command_target_member(
          @environment.store_command_target(bound),
        ),
      ),
      original,
    ),
  )
}

///|
test "GCS equal wire in another environment cannot replace original Command or Mapping custody" {
  let (original, wire) = upload_environment()
  let copied = @environment.read(
    @utf8.encode(wire),
    @environment.cid(original),
    caps(),
  ).unwrap()
  let contents = catalogs(original)
  let target = @environment.select_command_target(
    contents, "command:exports.gcs.upload.v1", 100000,
  ).unwrap()
  assert_true(
    @environment.command_target_input_contract(
      target,
      references(catalogs(copied)),
      value_caps(),
      100000,
    )
    is Err(@environment.ForeignCommandInputOwner),
  )
  let mapping = @environment.mapping_shape_at(
    @environment.check_mapping_contract_shapes(original, caps(), 100000).unwrap(),
    0,
  ).unwrap()
  assert_true(
    @environment.bind_store_command(mapping, catalogs(copied), 100000)
    is Err(@environment.StoreCommandIssue::ForeignEnvironment),
  )
}

///|
test "GCS original input admission budgets every child and exact comparison work" {
  let (original, _) = upload_environment()
  let contents = catalogs(original)
  let refs = references(contents)
  let target = @environment.select_command_target(
    contents, "command:exports.gcs.upload.v1", 100000,
  ).unwrap()
  let (input, work) = @environment.command_target_input_contract(
    target,
    refs,
    value_caps(),
    100000,
  ).unwrap()
  let (nodes, text) = @environment.command_input_contract_usage(input)
  assert_true(nodes > 0 && text > 0)
  assert_true(
    @environment.command_target_input_contract(
      target,
      refs,
      { ..value_caps(), max_nodes: nodes, max_text_bytes: text, },
      work,
    )
    is Ok(_),
  )
  assert_true(
    @environment.command_target_input_contract(
      target,
      refs,
      { ..value_caps(), max_nodes: nodes - 1, },
      100000,
    )
    is Err(_),
  )
  assert_true(
    @environment.command_target_input_contract(
      target,
      refs,
      { ..value_caps(), max_text_bytes: text - 1, },
      100000,
    )
    is Err(_),
  )
  assert_true(
    @environment.command_target_input_contract(
      target,
      refs,
      value_caps(),
      work - 1,
    )
    is Err(_),
  )
}
