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
fn upload_environment_details() -> (
  @environment.WireEnvironment,
  String,
  @gcs.ObjectCollectionBinding,
  String,
) raise {
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
  (
    @environment.read(@utf8.encode(wire), expected, caps()).unwrap(),
    wire,
    binding,
    declared_wire,
  )
}

///|
fn upload_environment() -> (@environment.WireEnvironment, String) raise {
  let (original, wire, _, _) = upload_environment_details()
  (original, wire)
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
    "sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2",
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

///|
test "GCS current full receiver matches independent Command-law preimages" {
  // Full literal preimages were independently hashed before executing this
  // receiver. The frozen723/af680 predecessor remains a separate input.
  let expected_wire =
    #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:exports.gcs.upload.v1","connector_id":"exports","contract_cid":"sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"input_schema":{"cid":"sha256:d15b2d1c7b0555836d28a967fa895f56ced810a056e4045c500e760181fa5fac","id":"exports.gcs.upload.command_input","version":"gcs/0.1"},"outcome":"synchronous","output_schema":{"cid":"sha256:57da33bdf9e0d3470e4c6436b26c9fb1162cc3200c0e0c331ee28d8ab2afe5ad","id":"exports.gcs.upload.command_output","version":"gcs/0.1"},"permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"gcs/0.1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:e1df4cb44a7b51bc5cd71ffb944c3835a2d3c1a1b78b875d0fd89524cddf8871","commands":[{"atomicity":"single_target","command_id":"command:exports.gcs.upload.v1","connector_id":"exports","contract_cid":"sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"input_schema":{"cid":"sha256:d15b2d1c7b0555836d28a967fa895f56ced810a056e4045c500e760181fa5fac","id":"exports.gcs.upload.command_input","version":"gcs/0.1"},"outcome":"synchronous","output_schema":{"cid":"sha256:57da33bdf9e0d3470e4c6436b26c9fb1162cc3200c0e0c331ee28d8ab2afe5ad","id":"exports.gcs.upload.command_output","version":"gcs/0.1"},"permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"gcs/0.1"}],"connector_id":"exports","connector_version":"gcs/0.1","contracts":[{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:57da33bdf9e0d3470e4c6436b26c9fb1162cc3200c0e0c331ee28d8ab2afe5ad","id":"exports.gcs.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"cid":"sha256:d15b2d1c7b0555836d28a967fa895f56ced810a056e4045c500e760181fa5fac","id":"exports.gcs.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"gcs/0.1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"gcs","connector_id":"exports","connector_version":"gcs/0.1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:57da33bdf9e0d3470e4c6436b26c9fb1162cc3200c0e0c331ee28d8ab2afe5ad","id":"exports.gcs.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"cid":"sha256:d15b2d1c7b0555836d28a967fa895f56ced810a056e4045c500e760181fa5fac","id":"exports.gcs.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"gcs/0.1"}],"evidence_bundle_cid":"sha256:47c870540667e91083753017e426b60b156efbcacbba23425d88267ebbec76cd","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:770110acd081a211ff71ba28f48fcd784e388ca4d5207e9a7a43402c1bd3e6a0","conversions":[],"mapping_contract_cid":"sha256:3f164c301754fb37b0efef76361d77db57fb131466ef6da6eaf033093bcda2dc","mapping_ref":"mapping:exports.gcs.objects.upload.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","name"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","content_type","name"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","name","overwrite"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","content_type","name","overwrite"]}],"primary_identity":null,"required_fields":["content","name"],"required_permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"resource_identity_cid":"sha256:0cc33aa75bec736618d7e8130c52aa04c2f9228e9952da1a0988965f3931b81b","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"content_type":{"field":"content_type","null_behavior":"reject"},"name":{"field":"name","null_behavior":"reject"},"overwrite":{"field":"overwrite","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:e1df4cb44a7b51bc5cd71ffb944c3835a2d3c1a1b78b875d0fd89524cddf8871","command_contract_cid":"sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2","command_ref":"command:exports.gcs.upload.v1"},"target_ref":"connector://exports/objects","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:3420afa3b6d4a946a3858dde773d70f9ffd4491f083775b06009637a8d2bcf08","version":"gcs/0.1","writable_fields":["content","content_type","name","overwrite"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let (original, actual_wire) = upload_environment()
  assert_eq(actual_wire, expected_wire)
  assert_eq(
    @environment.cid(original),
    "sha256:47c870540667e91083753017e426b60b156efbcacbba23425d88267ebbec76cd",
  )
  let target = @environment.select_command_target(
    catalogs(original),
    "command:exports.gcs.upload.v1",
    100000,
  ).unwrap()
  assert_eq(
    @environment.command_target_cid(target),
    "sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2",
  )
  let command = @decode.open_object(
    @environment.member_body(@environment.command_target_member(target)),
  ).unwrap()
  assert_true(@decode.lookup(command, "minimum_approval") is None)
  let mapping = @environment.member_at(
    original,
    @environment.MappingContracts,
    0,
  ).unwrap()
  let mapping_body = @decode.open_object(@environment.member_body(mapping)).unwrap()
  assert_true(@decode.lookup(mapping_body, "minimum_approval") is Some(_))
  let checked = @environment.check_mapping_contract_shapes(
    original,
    caps(),
    100000,
  ).unwrap()
  let bound = @environment.bind_store_command(
    @environment.mapping_shape_at(checked, 0).unwrap(),
    catalogs(original),
    100000,
  ).unwrap()
  assert_eq(
    @environment.command_target_cid(@environment.store_command_target(bound)),
    "sha256:faa1d52507efc3722752d36a72aef759e84fedfa14ddcd9528ace59d9ba4ace2",
  )
}
