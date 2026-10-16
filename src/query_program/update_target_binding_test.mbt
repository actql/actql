///|
// Independently authored preimages and SHA-256 pins are retained in
// scripts/fixtures/logical-update-targets/mapping-identities.json.
// These tests do not establish installation, authority, or runtime acceptance.
fn update_target_fixture(kind : String) -> @environment.MappingContractShapes {
  let wire = match kind {
    "one" =>
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:357b96a0a3689ea558d3954dd8d26b47b902dccaf6f103131e7efcf26d7494d3","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:8806f951f0eba711a67aa15619f5f892d505983e5d8c47479cf5798d60f75fcd","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      )
    "multiple" =>
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:a83cff2ebe24551e95feaef0a349233cec9f004930592b0a2b230cd3a6b2aac2","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:0fe75c286372d417d8822e982204b3766910cf97a17f69f05197751622df0b05","mapping_ref":"mapping:crm.account.other.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:other"],"selector_class":"id","write_fields":["Id"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Id":{"field":"id","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"fixture","writable_fields":["Id"]},{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:8806f951f0eba711a67aa15619f5f892d505983e5d8c47479cf5798d60f75fcd","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      )
    "foreign" =>
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:f4c5d041ca576d96601ac5e16054574e367b2c88f5a4f0f715312f704ebd1b02","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:8806f951f0eba711a67aa15619f5f892d505983e5d8c47479cf5798d60f75fcd","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]},{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:7927f7ba6e5fa0b16396b978b7df137300bfb2557cb8b00f847ff411c64f6578","mapping_ref":"mapping:crm.contact.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/contact","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      )
    "zero" =>
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:d8764bab723de5b255971098cbfbc45e84ee5fc91e3da4ed2857728308445149","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:15e7074560d6f2ec0730957b9e35369ef9df6fa7ba23d23a3b1bf53a9d75b2b9","mapping_ref":"mapping:crm.account.create.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:create"],"selector_class":"none","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      )
    "invalid" =>
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:f72bca0b1c0391a8060f8d4397ecb79218fa861aa9583ce8235357f02d55d39b","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:852f621405daa0adccefe0151d47b942663a6bd13aed1f52aeb6d4fa42a68fde","mapping_ref":"mapping:crm.account.invalid.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"invented","permissions":["scope:invented"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]},{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:8806f951f0eba711a67aa15619f5f892d505983e5d8c47479cf5798d60f75fcd","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"name","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bb7f22131b239944c4d7f01ddc3eaf675c34e38ca195527a90c6863668150e66","version":"fixture","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      )
    _ => abort("unknown fixed fixture")
  }
  let expected = match kind {
    "one" =>
      "sha256:357b96a0a3689ea558d3954dd8d26b47b902dccaf6f103131e7efcf26d7494d3"
    "multiple" =>
      "sha256:a83cff2ebe24551e95feaef0a349233cec9f004930592b0a2b230cd3a6b2aac2"
    "foreign" =>
      "sha256:f4c5d041ca576d96601ac5e16054574e367b2c88f5a4f0f715312f704ebd1b02"
    "zero" =>
      "sha256:d8764bab723de5b255971098cbfbc45e84ee5fc91e3da4ed2857728308445149"
    "invalid" =>
      "sha256:f72bca0b1c0391a8060f8d4397ecb79218fa861aa9583ce8235357f02d55d39b"
    _ => abort("unknown fixed fixture")
  }
  let limits : @environment.Limits = {
    max_bytes: 20000,
    max_nodes: 2000,
    max_depth: 100,
    max_members: 100,
  }
  let admitted = @environment.read(@utf8.encode(wire), expected, limits).unwrap()
  @environment.check_mapping_contract_shapes(admitted, limits, 100).unwrap()
}

///|
fn update_target_alias() -> UpdateTargetAlias {
  {
    name: [
      { value: "salesforce", quoted: false, },
      { value: "Account", quoted: false, },
    ],
    target_ref: "connector://crm/account",
    installation_binding_cid: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    installation_owner_cid: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
  }
}

///|
fn update_target_publication(kind : String) -> UpdateTargetPublication {
  bind_update_target_publication(
    update_target_fixture(kind),
    [update_target_alias()],
    100,
  ).unwrap()
}

///|
test "logical UPDATE selects the sole authoritative structural Mapping" {
  let publication = update_target_publication("one")
  let selected = resolve_update_target_binding(
    publication,
    update_target_alias().name,
    None,
    100,
  ).unwrap()
  assert_eq(
    resolved_update_target(selected),
    ("connector://crm/account", "mapping:crm.account.v1"),
  )
  assert_eq(
    resolved_update_target_identity(selected),
    (
      "sha256:357b96a0a3689ea558d3954dd8d26b47b902dccaf6f103131e7efcf26d7494d3",
      "sha256:8806f951f0eba711a67aa15619f5f892d505983e5d8c47479cf5798d60f75fcd",
      update_target_alias().installation_binding_cid,
    ),
  )
}

///|
test "logical UPDATE zero and missing authoritative alias refuse" {
  assert_eq(
    resolve_update_target_binding(
      update_target_publication("zero"),
      update_target_alias().name,
      None,
      100,
    ).unwrap_err(),
    UnresolvedMapping,
  )
  let absent = bind_update_target_publication(
    update_target_fixture("one"),
    [],
    100,
  ).unwrap()
  assert_eq(
    resolve_update_target_binding(absent, update_target_alias().name, None, 100).unwrap_err(),
    UnresolvedTarget,
  )
  let name = [
    { value: "salesforce", quoted: false, },
    { value: "Accounts", quoted: false, },
  ]
  assert_eq(
    resolve_update_target_binding(
      update_target_publication("one"),
      name,
      None,
      100,
    ).unwrap_err(),
    UnresolvedTarget,
  )
}

///|
test "all structural candidates count despite different SET types or permissions" {
  let publication = update_target_publication("multiple")
  assert_eq(
    resolve_update_target_binding(
      publication,
      update_target_alias().name,
      None,
      100,
    ).unwrap_err(),
    AmbiguousMapping,
  )
  for mapping in ["mapping:crm.account.v1", "mapping:crm.account.other.v1"] {
    let selected = resolve_update_target_binding(
      publication,
      update_target_alias().name,
      Some({ value: mapping, quoted: true, }),
      100,
    ).unwrap()
    assert_eq(
      resolved_update_target(selected),
      ("connector://crm/account", mapping),
    )
  }
}

///|
test "explicit logical UPDATE Mapping must match the concrete target" {
  let publication = update_target_publication("foreign")
  for
    mapping in [
      "mapping:crm.contact.v1", "mapping:missing.v1", "Mapping:crm.account.v1",
    ] {
    assert_eq(
      resolve_update_target_binding(
        publication,
        update_target_alias().name,
        Some({ value: mapping, quoted: true, }),
        100,
      ).unwrap_err(),
      UnresolvedMapping,
    )
  }
}

///|
test "conflicting positive aliases do not choose the first installation" {
  let target_alias = update_target_alias()
  let publication = bind_update_target_publication(
    update_target_fixture("one"),
    [target_alias, target_alias],
    100,
  ).unwrap()
  assert_eq(
    resolve_update_target_binding(publication, target_alias.name, None, 100).unwrap_err(),
    AmbiguousTarget,
  )
}

///|
test "malformed hidden Mapping rules cannot disappear from candidate coverage" {
  assert_eq(
    bind_update_target_publication(
      update_target_fixture("invalid"),
      [update_target_alias()],
      100,
    ).unwrap_err(),
    InvalidPublication,
  )
}

///|
test "logical UPDATE candidate work is bounded before traversal" {
  let mappings = update_target_fixture("one")
  assert_eq(
    bind_update_target_publication(mappings, [update_target_alias()], 7).unwrap_err(),
    WorkLimit,
  )
  let publication = bind_update_target_publication(
    mappings,
    [update_target_alias()],
    8,
  ).unwrap()
  assert_eq(
    resolve_update_target_binding(
      publication,
      update_target_alias().name,
      None,
      5,
    ).unwrap_err(),
    WorkLimit,
  )
  assert_true(
    resolve_update_target_binding(
      publication,
      update_target_alias().name,
      None,
      6,
    )
    is Ok(_),
  )
}

///|
test "logical UPDATE publication owns alias arrays" {
  let target_alias = update_target_alias()
  let aliases = [target_alias]
  let publication = bind_update_target_publication(
    update_target_fixture("one"),
    aliases,
    100,
  ).unwrap()
  aliases.clear()
  target_alias.name.clear()
  let name = update_target_alias().name
  assert_true(
    resolve_update_target_binding(publication, name, None, 100) is Ok(_),
  )
}

///|
test "logical UPDATE lowers to the same explicit concrete Program" {
  let suffix = " FROM RESULT updates ID x SET (Name = y)"
  let prefix = "FROM pair |> RESULT updates |> EFFECT UPDATE "
  let full = compile(
    @query.parse_query(
      prefix +
      "TARGET 'connector://crm/account' MAPPING `mapping:crm.account.v1`" +
      suffix,
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","select":["x","y"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["x","y"]}},"effects":{"aql_update_effect":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"x","set":{"Name":{"field":"y"}}}}}}],"results":{"updates":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(full), semantic(expected))
  for
    target in [
      "salesforce.Account", "salesforce.Account MAPPING `mapping:crm.account.v1`",
    ] {
    let short = compile(
      @query.parse_query(prefix + target + suffix, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
      update_targets=Some(update_target_publication("one")),
    ).unwrap()
    assert_eq(semantic(short), semantic(full))
  }
  assert_true(
    compile(
      @query.parse_query(
        prefix + "salesforce.Account" + suffix,
        syntax_limits(),
      ).unwrap(),
      pair_context(),
      construction_limits(),
    )
    is Err(UpdateTargetBinding(UnresolvedTarget)),
  )
}

///|
test "common UPDATE publication rejects a foreign or replaced environment" {
  let mappings = update_target_fixture("one")
  let wire = @environment.mapping_shape_environment(mappings)
  let environment = @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let publication = "{\"aliases\":[],\"environmentCid\":\"" +
    @environment.cid(wire) +
    "\",\"updateTargets\":[{\"name\":\"salesforce.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"installationOwnerCid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"}]}"
  assert_true(
    @source_publication.published_update_targets(environment, publication).unwrap()
    is Some(_),
  )
  let foreign = publication.replace(
    old=@environment.cid(wire),
    new="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  assert_true(
    @source_publication.published_update_targets(environment, foreign) is Err(_),
  )
  let replaced = @check.checking_environment(
    @environment.mapping_shape_environment(update_target_fixture("multiple")),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  assert_true(
    @source_publication.published_update_targets(replaced, publication)
    is Err(_),
  )
}

///|
test "concrete UPDATE binding shares installed selection without alias lookup" {
  let mappings = update_target_fixture("multiple")
  let publication = bind_update_target_publication(
    mappings,
    [update_target_alias()],
    100,
  ).unwrap()
  let selected = resolve_concrete_update_target_binding(
    publication, "connector://crm/account", "mapping:crm.account.v1", 100,
  ).unwrap()
  let logical = resolve_update_target_binding(
    publication,
    update_target_alias().name,
    Some({ value: "mapping:crm.account.v1", quoted: true, }),
    100,
  ).unwrap()
  assert_eq(resolved_update_target(selected), resolved_update_target(logical))
  assert_eq(
    resolved_update_target_identity(selected),
    resolved_update_target_identity(logical),
  )
  assert_eq(
    resolved_update_target_owner_cid(selected),
    resolved_update_target_owner_cid(logical),
  )
  assert_true(
    physical_equal(
      update_target_publication_environment(publication),
      @environment.mapping_shape_environment(mappings),
    ),
  )
  assert_eq(
    resolve_concrete_update_target_binding(
      publication, "connector://other/account", "mapping:crm.account.v1", 100,
    ).unwrap_err(),
    UnresolvedTarget,
  )
  assert_eq(
    resolve_concrete_update_target_binding(
      publication, "connector://crm/account", "mapping:missing.v1", 100,
    ).unwrap_err(),
    UnresolvedMapping,
  )
}

///|
test "concrete UPDATE never chooses conflicting original installed owners" {
  let target_alias = update_target_alias()
  let equivalent = {
    ..target_alias,
    name: [
      { value: "other", quoted: false, },
      { value: "name", quoted: false, },
    ],
  }
  let publication = bind_update_target_publication(
    update_target_fixture("one"),
    [target_alias, equivalent],
    100,
  ).unwrap()
  assert_true(
    resolve_concrete_update_target_binding(
      publication,
      target_alias.target_ref,
      "mapping:crm.account.v1",
      100,
    )
    is Ok(_),
  )
  let conflicting = {
    ..equivalent,
    installation_owner_cid: "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  }
  let publication = bind_update_target_publication(
    update_target_fixture("one"),
    [target_alias, conflicting],
    100,
  ).unwrap()
  assert_eq(
    resolve_concrete_update_target_binding(
      publication,
      target_alias.target_ref,
      "mapping:crm.account.v1",
      100,
    ).unwrap_err(),
    AmbiguousTarget,
  )
  assert_eq(
    resolve_concrete_update_target_binding(
      publication,
      target_alias.target_ref,
      "mapping:crm.account.v1",
      1,
    ).unwrap_err(),
    WorkLimit,
  )
}

///|
test "logical UPDATE resolves authoritative target before private ID and SET capture" {
  let prefix = "FROM pair |> EFFECT UPDATE salesforce.Account ID missing SET (Name = missing + 1)"
  let parsed = @query.parse_query(prefix, syntax_limits()).unwrap()
  assert_true(
    compile(parsed, pair_context(), construction_limits())
    is Err(UpdateTargetBinding(UnresolvedTarget)),
  )
  assert_true(
    compile(
      parsed,
      pair_context(),
      construction_limits(),
      update_targets=Some(update_target_publication("multiple")),
    )
    is Err(UpdateTargetBinding(AmbiguousMapping)),
  )
}

///|
test "frontend retains the exact target publication for either authored form" {
  let publication = update_target_publication("one")
  let prefix = "FROM pair |> RESULT updates |> EFFECT UPDATE "
  let suffix = " FROM RESULT updates ID x SET (Name = y)"
  for
    target in [
      "salesforce.Account", "TARGET 'connector://crm/account' MAPPING `mapping:crm.account.v1`",
    ] {
    let lowered = @frontend.lower(
      prefix + target + suffix,
      @frontend.Text,
      Some(pair_context()),
      update_targets=Some(publication),
    ).unwrap()
    assert_true(physical_equal(lowered.update_targets.unwrap(), publication))
    assert_true(lowered.program is Some(_))
  }
  let legacy = @frontend.lower(
    prefix +
    "TARGET 'connector://crm/account' MAPPING `mapping:crm.account.v1`" +
    suffix,
    @frontend.Text,
    Some(pair_context()),
  ).unwrap()
  assert_true(legacy.update_targets is None)
}

///|
test "empty logical UPDATE publication retains absent-context semantics" {
  let wire = @environment.mapping_shape_environment(
    update_target_fixture("invalid"),
  )
  let environment = @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let publication = "{\"aliases\":[],\"environmentCid\":\"" +
    @environment.cid(wire) +
    "\",\"updateTargets\":[]}"
  assert_true(
    @source_publication.published_update_targets(environment, publication).unwrap()
    is None,
  )
}
