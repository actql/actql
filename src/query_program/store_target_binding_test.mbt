///|
// Independent SHA-256 preimages: scripts/fixtures/store-targets/identities.json.
// No production selector, ReferenceIssuer, installation or I/O is exercised.
fn store_target_fixture(
  kind : String,
) -> (@environment.MappingContractShapes, @environment.CatalogContents) {
  let (wire, expected) = match kind {
    "relation" =>
      (
        (
          #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:72bcd8da7d4e7e4b8bf2d9245d7ca27aa12ca830c8850b2ae2ff3ac1a8191a7a","commands":[],"connector_id":"storage","connector_version":"fixture-1","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:686a0c4b0f6c94a9727f0d3971d4898602c37f7e80eeffb4205d17711f30a987","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:0b87a8caf4ee5b16c681c989bd20f746342c787b6cd4fd5cc8354f7e8b3cce87","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:686a0c4b0f6c94a9727f0d3971d4898602c37f7e80eeffb4205d17711f30a987",
      )
    "object" =>
      (
        (
          #|{"command_contracts":[{"command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:2024e0f48c6f29f89e2c602a46923697183b70ff9fb2be1db847a1374c630c94","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:1442d63d3e52158944b356d5edd1c448628d4d277653c1a6d86d4906fe358ea7","commands":[{"command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:2024e0f48c6f29f89e2c602a46923697183b70ff9fb2be1db847a1374c630c94","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:e0d5277f49f58186ffc6f914421db46d284cfd9937d7ad31c90a29fba417f342","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:95de148023f83b5ef6a9a4f0e6453ef5a68b7bae5867d58b10feab0e6309d516","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:1442d63d3e52158944b356d5edd1c448628d4d277653c1a6d86d4906fe358ea7","command_contract_cid":"sha256:2024e0f48c6f29f89e2c602a46923697183b70ff9fb2be1db847a1374c630c94","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:e0d5277f49f58186ffc6f914421db46d284cfd9937d7ad31c90a29fba417f342",
      )
    "ambiguous" =>
      (
        (
          #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:72bcd8da7d4e7e4b8bf2d9245d7ca27aa12ca830c8850b2ae2ff3ac1a8191a7a","commands":[],"connector_id":"storage","connector_version":"fixture-1","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:e2d13ab4e22cee8b0f166b0cf17173ce057d6887e10dc77b4a0a24288be66c0b","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:868e9b1aa805bf2b9946396cc97134550e7a1179d35a22399a74c84cdb34e58a","mapping_ref":"mapping:fixture.other.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:other"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:e33336737c8eaa9a7b76efeb383cc72b102f5a19086ff6b047e393524a7b57a5","version":"fixture-1","writable_fields":["id","value"]},{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:0b87a8caf4ee5b16c681c989bd20f746342c787b6cd4fd5cc8354f7e8b3cce87","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:e2d13ab4e22cee8b0f166b0cf17173ce057d6887e10dc77b4a0a24288be66c0b",
      )
    "nonstore" =>
      (
        (
          #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:72bcd8da7d4e7e4b8bf2d9245d7ca27aa12ca830c8850b2ae2ff3ac1a8191a7a","commands":[],"connector_id":"storage","connector_version":"fixture-1","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:e98a039c5c6a01ac8e9d368505fcc635e5457fb02ee4611a02650ed480b289db","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:5f739f8eb6bfa7502bd465da1e972a0a90b3d1015beec45be11840cf12c4febe","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:e98a039c5c6a01ac8e9d368505fcc635e5457fb02ee4611a02650ed480b289db",
      )
    _ => abort("unknown independent STORE fixture")
  }
  let limits : @environment.Limits = {
    max_bytes: 40000,
    max_nodes: 4000,
    max_depth: 100,
    max_members: 100,
  }
  let environment = @environment.read(@utf8.encode(wire), expected, limits).unwrap()
  let shapes = @environment.check_mapping_contract_shapes(
    environment, limits, 1000,
  ).unwrap()
  let catalogs = @environment.check_catalog_contents(
    @environment.check_contract_registry(environment, limits).unwrap(),
    limits,
  ).unwrap()
  (shapes, catalogs)
}

///|
fn store_target_alias() -> UpdateTargetAlias {
  {
    name: [
      { value: "storage", quoted: false, },
      { value: "archive", quoted: false, },
    ],
    target_ref: "connector://storage/archive",
    installation_binding_cid: "sha256:" + "d".repeat(64),
    installation_owner_cid: "sha256:" + "e".repeat(64),
  }
}

///|
fn store_target_publication(kind : String) -> StoreTargetPublication {
  let (mappings, catalogs) = store_target_fixture(kind)
  bind_store_target_publication(
    mappings,
    catalogs,
    [store_target_alias()],
    1000,
  ).unwrap()
}

///|
test "STORE relation selection retains original environment and installation" {
  let (mappings, catalogs) = store_target_fixture("relation")
  let publication = bind_store_target_publication(
    mappings,
    catalogs,
    [store_target_alias()],
    1000,
  ).unwrap()
  let selected = resolve_store_target_binding(
    publication,
    store_target_alias().name,
    100,
  ).unwrap()
  assert_eq(
    resolved_store_target(selected),
    ("connector://storage/archive", "mapping:fixture.archive.v1"),
  )
  assert_eq(
    resolved_store_target_identity(selected),
    (
      "sha256:686a0c4b0f6c94a9727f0d3971d4898602c37f7e80eeffb4205d17711f30a987",
      "sha256:0b87a8caf4ee5b16c681c989bd20f746342c787b6cd4fd5cc8354f7e8b3cce87",
      store_target_alias().installation_binding_cid,
      store_target_alias().installation_owner_cid,
    ),
  )
  assert_true(resolved_store_target_command(selected) is None)
  assert_true(
    physical_equal(store_target_publication_catalogs(publication), catalogs),
  )
  assert_true(
    physical_equal(
      store_target_publication_environment(publication),
      @environment.mapping_shape_environment(mappings),
    ),
  )
  assert_true(
    physical_equal(
      resolved_store_target_mapping(selected),
      @environment.mapping_shape_at(mappings, 0).unwrap(),
    ),
  )
}

///|
test "STORE object selection retains the complete original Mapping Command pair" {
  let publication = store_target_publication("object")
  let selected = resolve_store_target_binding(
    publication,
    store_target_alias().name,
    100,
  ).unwrap()
  let pair = resolved_store_target_command(selected).unwrap()
  assert_true(
    physical_equal(
      @environment.store_command_mapping(pair),
      resolved_store_target_mapping(selected),
    ),
  )
  let target = @environment.store_command_target(pair)
  assert_eq(@environment.command_target_id(target), "command:fixture.upload.v1")
  assert_eq(@environment.command_target_resource_kind(target), "file")
  assert_eq(
    @environment.command_target_cid(target),
    "sha256:2024e0f48c6f29f89e2c602a46923697183b70ff9fb2be1db847a1374c630c94",
  )
  assert_eq(
    resolved_store_target_identity(selected),
    (
      "sha256:e0d5277f49f58186ffc6f914421db46d284cfd9937d7ad31c90a29fba417f342",
      "sha256:95de148023f83b5ef6a9a4f0e6453ef5a68b7bae5867d58b10feab0e6309d516",
      store_target_alias().installation_binding_cid,
      store_target_alias().installation_owner_cid,
    ),
  )
}

///|
test "STORE counts every structural Mapping before SET types or grants" {
  assert_eq(
    resolve_store_target_binding(
      store_target_publication("ambiguous"),
      store_target_alias().name,
      100,
    ).unwrap_err(),
    AmbiguousMapping,
  )
  assert_eq(
    resolve_store_target_binding(
      store_target_publication("nonstore"),
      store_target_alias().name,
      100,
    ).unwrap_err(),
    UnresolvedMapping,
  )
  let publication = store_target_publication("relation")
  let absent : Array[@query.NamePart] = [
    { value: "storage", quoted: false, },
    { value: "other", quoted: false, },
  ]
  assert_eq(
    resolve_store_target_binding(publication, absent, 100).unwrap_err(),
    UnresolvedTarget,
  )
}

///|
test "STORE publication owns alias arrays and refuses duplicate logical targets" {
  let (mappings, catalogs) = store_target_fixture("relation")
  let target_alias = store_target_alias()
  let aliases = [target_alias]
  let publication = bind_store_target_publication(
    mappings, catalogs, aliases, 1000,
  ).unwrap()
  aliases.clear()
  target_alias.name.clear()
  assert_true(
    resolve_store_target_binding(publication, store_target_alias().name, 100)
    is Ok(_),
  )
  let target_alias = store_target_alias()
  let duplicate = bind_store_target_publication(
    mappings,
    catalogs,
    [target_alias, target_alias],
    1000,
  ).unwrap()
  assert_eq(
    resolve_store_target_binding(duplicate, target_alias.name, 100).unwrap_err(),
    AmbiguousTarget,
  )
}

///|
test "STORE rejects a copied equal CID environment and malformed publication" {
  let (mappings, catalogs) = store_target_fixture("relation")
  let (_, copied_catalogs) = store_target_fixture("relation")
  assert_eq(
    bind_store_target_publication(
      mappings,
      copied_catalogs,
      [store_target_alias()],
      1000,
    ).unwrap_err(),
    ForeignEnvironment,
  )
  let invalid = { ..store_target_alias(), installation_owner_cid: "not-a-cid", }
  assert_eq(
    bind_store_target_publication(mappings, catalogs, [invalid], 1000).unwrap_err(),
    InvalidPublication,
  )
  assert_eq(
    bind_store_target_publication(
      mappings,
      catalogs,
      [store_target_alias()],
      -1,
    ).unwrap_err(),
    InvalidPublication,
  )
}

///|
test "STORE publication and resolution charge their complete bounded inventory" {
  let (mappings, catalogs) = store_target_fixture("object")
  let aliases = [store_target_alias()]
  let publication = bind_store_target_publication(
    mappings, catalogs, aliases, 1000,
  ).unwrap()
  let exact = store_target_publication_work(publication)
  assert_true(exact > 0)
  assert_true(
    bind_store_target_publication(mappings, catalogs, aliases, exact) is Ok(_),
  )
  assert_eq(
    bind_store_target_publication(mappings, catalogs, aliases, exact - 1).unwrap_err(),
    WorkLimit,
  )
  // Two name parts on each side, one comparison, and one candidate.
  assert_true(
    resolve_store_target_binding(publication, aliases[0].name, 6) is Ok(_),
  )
  assert_eq(
    resolve_store_target_binding(publication, aliases[0].name, 5).unwrap_err(),
    WorkLimit,
  )
  assert_true(
    resolve_concrete_store_target_binding(
      publication,
      aliases[0].target_ref,
      "mapping:fixture.archive.v1",
      2,
    )
    is Ok(_),
  )
  assert_eq(
    resolve_concrete_store_target_binding(
      publication,
      aliases[0].target_ref,
      "mapping:fixture.archive.v1",
      1,
    ).unwrap_err(),
    WorkLimit,
  )
}

///|
test "STORE concrete occurrence retains the original Mapping and installation" {
  let publication = store_target_publication("ambiguous")
  let selected = resolve_concrete_store_target_binding(
    publication, "connector://storage/archive", "mapping:fixture.archive.v1", 100,
  ).unwrap()
  assert_eq(
    resolved_store_target(selected),
    ("connector://storage/archive", "mapping:fixture.archive.v1"),
  )
  assert_eq(
    resolve_concrete_store_target_binding(
      publication, "connector://other/archive", "mapping:fixture.archive.v1", 100,
    ).unwrap_err(),
    UnresolvedTarget,
  )
  assert_eq(
    resolve_concrete_store_target_binding(
      publication, "connector://storage/archive", "mapping:fixture.missing.v1", 100,
    ).unwrap_err(),
    UnresolvedMapping,
  )
  let target_alias = store_target_alias()
  let equivalent = {
    ..target_alias,
    name: [{ value: "other", quoted: false, }],
  }
  let (mappings, catalogs) = store_target_fixture("object")
  let publication = bind_store_target_publication(
    mappings,
    catalogs,
    [target_alias, equivalent],
    1000,
  ).unwrap()
  assert_true(
    resolve_concrete_store_target_binding(
      publication,
      target_alias.target_ref,
      "mapping:fixture.archive.v1",
      100,
    )
    is Ok(_),
  )
  let foreign = {
    ..equivalent,
    installation_owner_cid: "sha256:" + "f".repeat(64),
  }
  let publication = bind_store_target_publication(
    mappings,
    catalogs,
    [target_alias, foreign],
    1000,
  ).unwrap()
  assert_eq(
    resolve_concrete_store_target_binding(
      publication,
      target_alias.target_ref,
      "mapping:fixture.archive.v1",
      100,
    ).unwrap_err(),
    AmbiguousTarget,
  )
}
