///|
// Independent fixed preimages are cross-checked with Node crypto in the DELETE
// corpus, never expectations derived from this product's identity issuer.
fn delete_selection_environment(
  delete_only? : Bool = false,
) -> @checked.CheckEnvironment {
  let wire =
    #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:430f124e4f1aebff56853581131874f5eafc2ade1bd01bfc1b97280dd4d71bec","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:465a0d7eccdd82e285949be3f3a3b84f76e0a06bbd4ee3cc0093bcd8a4f61ee0","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]},{"effect_kind":"update","permissions":["scope:write"],"selector_class":"id","write_fields":["value"]},{"effect_kind":"delete","permissions":["scope:delete"],"selector_class":"id","write_fields":[]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","command_contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let wire = if delete_only {
    wire
    .replace(
      old="{\"effect_kind\":\"update\",\"permissions\":[\"scope:write\"],\"selector_class\":\"id\",\"write_fields\":[\"value\"]},",
      new="",
    )
    .replace(
      old="sha256:465a0d7eccdd82e285949be3f3a3b84f76e0a06bbd4ee3cc0093bcd8a4f61ee0",
      new="sha256:55ce9265a5942f223738fdfed6eb65129613d2baf21df320789592e2f15f7244",
    )
    .replace(
      old="sha256:430f124e4f1aebff56853581131874f5eafc2ade1bd01bfc1b97280dd4d71bec",
      new="sha256:da9d078c4dd1b6c2651f509c35863bc8cd04936144dd00eb8fbc563d290bdcdb",
    )
  } else {
    wire
  }
  admit_client_check_environment(
    wire,
    if delete_only {
      "sha256:da9d078c4dd1b6c2651f509c35863bc8cd04936144dd00eb8fbc563d290bdcdb"
    } else {
      "sha256:430f124e4f1aebff56853581131874f5eafc2ade1bd01bfc1b97280dd4d71bec"
    },
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn delete_selection_prepare(
  update? : Bool = false,
  mixed? : Bool = false,
  delete_only? : Bool = false,
  foreign_publication? : Bool = false,
  member_limit? : Int = 3,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] {
  let environment = delete_selection_environment(delete_only~)
  let publication_environment = if foreign_publication {
    delete_selection_environment(delete_only~)
  } else {
    environment
  }
  let (_, _, base) = local_update_normalization_fixture()
  let limits = {
    ..base,
    max_members: member_limit,
    effects: { ..base.effects, max_members: member_limit, },
  }
  let mappings = @environment.check_mapping_contract_shapes(
    @checked.checking_environment_wire(publication_environment),
    limits.mapping,
    limits.max_mapping_work,
  ).unwrap()
  let aliases : Array[@update_targets.UpdateTargetAlias] = [
    {
      name: [{ value: "archive", quoted: false, }],
      target_ref: "connector://storage/archive",
      installation_binding_cid: "sha256:" + "8".repeat(64),
      installation_owner_cid: "sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca",
    },
  ]
  let publication = @update_targets.bind_update_target_publication(
    mappings, aliases, 1000,
  ).unwrap()
  let registry = @environment.check_contract_registry(
    @checked.checking_environment_wire(publication_environment),
    limits.mapping,
  ).unwrap()
  let catalogs = @environment.check_catalog_contents(registry, limits.mapping).unwrap()
  let stores = @update_targets.bind_store_target_publication(
    mappings, catalogs, aliases, 1000,
  ).unwrap()
  let document = if mixed {
    (
      #|{"version":"actql/0.1","id":"delete-selection","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"string","nullable":false}},"rows":[{"id":"one","value":"original"}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}},"effects":{"update":{"update":{"target":"connector://storage/archive","mapping":"mapping:fixture.archive.v1","from":{"result":"out"},"id":"id","set":{"value":{"field":"value"}}}},"save":{"command":{"contract":"command:fixture.upload.v1","from":{"result":"out"},"input":{"id":{"field":"id"},"value":{"field":"value"}},"target":{"published_store":{"mapping_ref":"mapping:fixture.archive.v1","target_ref":"connector://storage/archive"}}}},"remove":{"delete":{"target":"connector://storage/archive","mapping":"mapping:fixture.archive.v1","from":{"result":"out"},"id":"id"}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
    )
  } else if update {
    (
      #|{"version":"actql/0.1","id":"delete-selection","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"string","nullable":false}},"rows":[{"id":"one","value":"original"}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}},"effects":{"save":{"update":{"target":"connector://storage/archive","mapping":"mapping:fixture.archive.v1","from":{"result":"out"},"id":"id","set":{"value":{"field":"value"}}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
    )
  } else {
    (
      #|{"version":"actql/0.1","id":"delete-selection","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"string","nullable":false}},"rows":[{"id":"one","value":"original"}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}},"effects":{"save":{"delete":{"target":"connector://storage/archive","mapping":"mapping:fixture.archive.v1","from":{"result":"out"},"id":"id"}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
    )
  }
  prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
    update_targets=Some(publication),
    store_targets=Some(stores),
  )
}

///|
fn delete_selection_admit(
  wire : String,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
) -> Result[ClientEffectRunMaterials, ClientEffectRunMaterialsIssue] {
  let (_, _, base) = local_update_normalization_fixture()
  let limits = {
    ..base,
    max_members: 3,
    effects: { ..base.effects, max_members: 3, },
  }
  admit_client_effect_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    limits,
    expected_request=Some(request),
  )
}

///|
fn delete_selection_observations(update : Bool, delete : Bool) -> String raise {
  let installation = "{\"cid\":\"sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca\",\"wire\":" +
    target_original_quote(target_original_installation_wire()) +
    "}"
  let update = if update { "true" } else { "false" }
  let delete = if delete { "true" } else { "false" }
  "[{\"installation\":" +
  installation +
  ",\"update\":" +
  update +
  ",\"delete\":" +
  delete +
  ",\"store\":true,\"mappings\":[{\"target\":\"connector://storage/archive\",\"mappingRef\":\"mapping:fixture.archive.v1\",\"mappingCid\":\"sha256:465a0d7eccdd82e285949be3f3a3b84f76e0a06bbd4ee3cc0093bcd8a4f61ee0\",\"update\":" +
  update +
  ",\"delete\":" +
  delete +
  ",\"store\":true}]}]"
}

///|
test "DELETE selection binds independent bytes and restores without UPDATE capability" {
  let owner = delete_selection_prepare(delete_only=true).unwrap()
  let expected =
    #|[{"check_environment_cid":"sha256:da9d078c4dd1b6c2651f509c35863bc8cd04936144dd00eb8fbc563d290bdcdb","effect_id":"save","installation_binding_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","installation_owner_cid":"sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca","mapping_cid":"sha256:55ce9265a5942f223738fdfed6eb65129613d2baf21df320789592e2f15f7244","mapping_ref":"mapping:fixture.archive.v1","stage_index":0,"target_ref":"connector://storage/archive"}]
  assert_eq(prepared_client_effect_target_selections(owner), Some(expected))
  let original = client_effect_target_selection_original(owner)[0]
  assert_eq(
    client_effect_target_selection_cid(original),
    "sha256:5ae7ae2aa2e1dd56e2e8ced29766d9529ca42fbd33190c0c2af8e11a58f8ba6b",
  )
  let (allowed, definition, request) = published_selection_run(owner)
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let restored = delete_selection_admit(wire, definition, request).unwrap()
  assert_eq(
    restore_client_effect_run_target_selections(restored).unwrap(),
    Some(expected),
  )
  assert_eq(
    issue_prepared_client_effect_run_materials(
      restored.allowed,
      restored.run_definition,
      request=restored.request,
    ).unwrap(),
    wire,
  )
  assert_false(
    client_effect_target_selection_matches_prepared(original, restored.prepared),
  )
  assert_true(
    delete_selection_admit(
      wire.replace(
        old="connector://storage/archive",
        new="connector://storage/foreign",
      ),
      definition,
      request,
    )
    is Err(_),
  )
}

///|
test "DELETE selection purpose comes from original Header not equal eight-field bytes" {
  let removed = delete_selection_prepare().unwrap()
  let updated = delete_selection_prepare(update=true).unwrap()
  let delete_original = client_effect_target_selection_original(removed)[0]
  let update_original = client_effect_target_selection_original(updated)[0]
  assert_eq(
    client_effect_target_selection_wire(delete_original),
    client_effect_target_selection_wire(update_original),
  )
  assert_eq(
    client_effect_target_selection_cid(delete_original),
    "sha256:adec984b4b8f321c6c75d36dc4cc1265b7db59b2779bf4d078f53f25b2bafb44",
  )
  assert_true(
    client_effect_target_selection_current(
      delete_original,
      removed,
      delete_selection_observations(false, true),
    ),
  )
  assert_false(
    client_effect_target_selection_current(
      delete_original,
      removed,
      delete_selection_observations(true, false),
    ),
  )
  assert_true(
    client_effect_target_selection_current(
      update_original,
      updated,
      delete_selection_observations(true, false),
    ),
  )
  assert_false(
    client_effect_target_selection_current(
      update_original,
      updated,
      delete_selection_observations(false, true),
    ),
  )
  assert_false(
    client_effect_target_selection_matches_prepared(delete_original, updated),
  )
  assert_false(
    client_effect_target_selection_matches_prepared(update_original, removed),
  )
  let copied : ClientEffectUpdateTargetSelections = { ..delete_original, }
  assert_false(client_effect_target_selection_matches_prepared(copied, removed))
  let (delete_allowed, delete_run, _) = published_selection_run(removed)
  let (update_allowed, update_run, _) = published_selection_run(updated)
  assert_true(
    bind_client_effect_compiled_run(removed, delete_allowed, delete_run)
    is Ok(_),
  )
  assert_true(
    bind_client_effect_compiled_run(updated, update_allowed, update_run)
    is Ok(_),
  )
  // The full original Run admission is mandatory even for equal selection CIDs.
  assert_true(
    bind_prepared_client_effect_run(
      removed,
      update_allowed.admission,
      update_run,
    )
    is Err(Admission(_)),
  )
  assert_true(
    bind_prepared_client_effect_run(
      updated,
      delete_allowed.admission,
      delete_run,
    )
    is Err(Admission(_)),
  )
}

///|
test "DELETE selection preserves mixed UPDATE DELETE published STORE original ordering and bounds" {
  let owner = delete_selection_prepare(mixed=true).unwrap()
  let expected =
    #|[{"check_environment_cid":"sha256:430f124e4f1aebff56853581131874f5eafc2ade1bd01bfc1b97280dd4d71bec","effect_id":"remove","installation_binding_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","installation_owner_cid":"sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca","mapping_cid":"sha256:465a0d7eccdd82e285949be3f3a3b84f76e0a06bbd4ee3cc0093bcd8a4f61ee0","mapping_ref":"mapping:fixture.archive.v1","stage_index":0,"target_ref":"connector://storage/archive"},{"check_environment_cid":"sha256:430f124e4f1aebff56853581131874f5eafc2ade1bd01bfc1b97280dd4d71bec","effect_id":"save","installation_binding_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","installation_owner_cid":"sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca","mapping_cid":"sha256:465a0d7eccdd82e285949be3f3a3b84f76e0a06bbd4ee3cc0093bcd8a4f61ee0","mapping_ref":"mapping:fixture.archive.v1","stage_index":0,"target_ref":"connector://storage/archive"},{"check_environment_cid":"sha256:430f124e4f1aebff56853581131874f5eafc2ade1bd01bfc1b97280dd4d71bec","effect_id":"update","installation_binding_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","installation_owner_cid":"sha256:9ee844e04eda0aa8f6e901a0fdc3fcd2694aa4bf94ad053b2308a5ae3ef4a2ca","mapping_cid":"sha256:465a0d7eccdd82e285949be3f3a3b84f76e0a06bbd4ee3cc0093bcd8a4f61ee0","mapping_ref":"mapping:fixture.archive.v1","stage_index":0,"target_ref":"connector://storage/archive"}]
  assert_eq(prepared_client_effect_target_selections(owner), Some(expected))
  let original = client_effect_target_selection_original(owner)[0]
  assert_eq(
    client_effect_target_selection_cid(original),
    "sha256:2d01d86f679e391ce2b82b3b372310e7cb9c78c0b57f919420278d6413d798b8",
  )
  assert_true(
    client_effect_target_selection_current(
      original,
      owner,
      delete_selection_observations(true, true),
    ),
  )
  let (allowed, definition, request) = published_selection_run(owner)
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let restored = delete_selection_admit(wire, definition, request).unwrap()
  assert_eq(
    restore_client_effect_run_target_selections(restored).unwrap(),
    Some(expected),
  )
  assert_true(delete_selection_prepare(mixed=true, member_limit=2) is Err(_))
}

///|
test "DELETE selection refuses foreign environment copied occurrence and stale installation" {
  assert_true(
    delete_selection_prepare(foreign_publication=true)
    is Err(TargetSelection(ForeignEnvironment)),
  )
  let owner = delete_selection_prepare().unwrap()
  let original = client_effect_target_selection_original(owner)[0]
  let observations = delete_selection_observations(false, true)
  for
    changed in [
      observations.replace(
        old="mapping:fixture.archive.v1",
        new="mapping:fixture.archive.v2",
      ),
      observations.replace(
        old="\\\"continuation_binding\\\":\\\"sha256:" + "e".repeat(64),
        new="\\\"continuation_binding\\\":\\\"sha256:" + "f".repeat(64),
      ),
      observations.replace(old="\"delete\":true", new="\"delete\":false"),
    ] {
    assert_false(
      client_effect_target_selection_current(original, owner, changed),
    )
  }
  let foreign = delete_selection_prepare().unwrap()
  assert_false(
    client_effect_target_selection_current(original, foreign, observations),
  )
}
