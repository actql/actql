///|
// These original preimages are independently authored from the existing STORE
// and UPDATE corpora. Static test selection is not an installed physical grant.
fn published_selection_environment() -> @checked.CheckEnvironment raise {
  let wire =
    #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:3abdc285f8997b2d6e37abb4d407754d615391014d1884287bd868de38deaed2","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]},{"effect_kind":"update","permissions":["scope:write"],"selector_class":"id","write_fields":["value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","command_contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let admitted = @environment.read(
    @utf8.encode(wire),
    "sha256:3abdc285f8997b2d6e37abb4d407754d615391014d1884287bd868de38deaed2",
    { max_bytes: 65536, max_nodes: 4096, max_depth: 64, max_members: 256, },
  )
  assert_eq(admitted.map(_ => ()), Ok(()))
  admit_client_check_environment(
    wire,
    "sha256:3abdc285f8997b2d6e37abb4d407754d615391014d1884287bd868de38deaed2",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn published_selection_prepare(
  mixed? : Bool = false,
  selected? : Bool = true,
  foreign_publication? : Bool = false,
  member_limit? : Int = 2,
) -> Result[PreparedClientEffectComputation, ClientEffectComputationIssue] raise {
  let environment = published_selection_environment()
  let publication_environment = if foreign_publication {
    published_selection_environment()
  } else {
    environment
  }
  let (_, _, limits) = local_update_normalization_fixture()
  // The original single-member fixture remains unchanged. A two-occurrence
  // test explicitly selects two static member slots; this is not a product
  // policy change or authority, and its one-slot counter still refuses.
  let limits = if mixed {
    {
      ..limits,
      max_members: member_limit,
      effects: { ..limits.effects, max_members: member_limit, },
    }
  } else {
    limits
  }
  let mappings = @environment.check_mapping_contract_shapes(
    @checked.checking_environment_wire(publication_environment),
    limits.mapping,
    limits.max_mapping_work,
  ).unwrap()
  let registry = @environment.check_contract_registry(
    @checked.checking_environment_wire(publication_environment),
    limits.mapping,
  ).unwrap()
  let catalogs = @environment.check_catalog_contents(registry, limits.mapping).unwrap()
  let store_targets = if selected {
    Some(
      @update_targets.bind_store_target_publication(
        mappings,
        catalogs,
        [
          {
            name: [{ value: "archive", quoted: false, }],
            target_ref: "connector://storage/archive",
            installation_binding_cid: "sha256:" + "8".repeat(64),
            installation_owner_cid: "sha256:83a8d70240b5ff70509fe61c30e141a5ab8caf859a48e1ae9605dc69df4763c7",
          },
        ],
        1000,
      ).unwrap(),
    )
  } else {
    None
  }
  let update_targets = if mixed && selected {
    Some(
      @update_targets.bind_update_target_publication(
        mappings,
        [
          {
            name: [{ value: "archive", quoted: false, }],
            target_ref: "connector://storage/archive",
            installation_binding_cid: "sha256:" + "6".repeat(64),
            installation_owner_cid: "sha256:9fb1b923109be7230392d96d2dd4f3e62dc6ba6a661a8c218148e7858142d506",
          },
        ],
        1000,
      ).unwrap(),
    )
  } else {
    None
  }
  let document =
    #|{"version":"actql/0.1","id":"published-store-selection","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"string","nullable":false}},"rows":[{"id":"one","value":"original"}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}},"effects":{"save":{"command":{"contract":"command:fixture.upload.v1","from":{"result":"out"},"input":{"id":{"field":"id"},"value":{"field":"value"}},"target":{"published_store":{"mapping_ref":"mapping:fixture.archive.v1","target_ref":"connector://storage/archive"}}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let document = if mixed {
    document.replace(
      old="\"effects\":{\"save\":",
      new="\"effects\":{\"update\":{\"update\":{\"target\":\"connector://storage/archive\",\"mapping\":\"mapping:fixture.archive.v1\",\"from\":{\"result\":\"out\"},\"id\":\"id\",\"set\":{\"value\":{\"field\":\"value\"}}}},\"save\":",
    )
  } else {
    document
  }
  prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
    update_targets~,
    store_targets~,
  )
}

///|
fn published_selection_run(
  prepared : PreparedClientEffectComputation,
) -> (
  ClientEffectAllowedRun,
  @publication.PublicationContract,
  ClientRequestIdentity,
) {
  let bounds = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "store-selection-scope", "store-selection-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "store-selection-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  (allowed, definition, request)
}

///|
fn published_selection_mixed_materials_admit(
  wire : String,
  run_cid : String,
  request : ClientRequestIdentity,
) -> Result[ClientEffectRunMaterials, ClientEffectRunMaterialsIssue] {
  let (_, _, original_limits) = local_update_normalization_fixture()
  let limits = {
    ..original_limits,
    max_members: 2,
    effects: { ..original_limits.effects, max_members: 2, },
  }
  admit_client_effect_run_materials(
    wire,
    run_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    limits,
    expected_request=Some(request),
  )
}

///|
test "published STORE selection preserves independent eight-field bytes and Plan Run projection" {
  let prepared = published_selection_prepare().unwrap()
  let expected =
    #|[{"check_environment_cid":"sha256:3abdc285f8997b2d6e37abb4d407754d615391014d1884287bd868de38deaed2","effect_id":"save","installation_binding_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","installation_owner_cid":"sha256:83a8d70240b5ff70509fe61c30e141a5ab8caf859a48e1ae9605dc69df4763c7","mapping_cid":"sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5","mapping_ref":"mapping:fixture.archive.v1","stage_index":0,"target_ref":"connector://storage/archive"}]
  assert_eq(prepared_client_effect_target_selections(prepared), Some(expected))
  let original = client_effect_target_selection_original(prepared)[0]
  assert_eq(
    client_effect_target_selection_cid(original),
    "sha256:8fa23700a333cfbd6da8a5a822baa12469c726b75bf852c9b06840a588030fcd",
  )
  let (allowed, definition, request) = published_selection_run(prepared)
  assert_eq(
    @publication.publication_contract_effect_target_selections_cid(definition),
    Some(
      "sha256:8fa23700a333cfbd6da8a5a822baa12469c726b75bf852c9b06840a588030fcd",
    ),
  )
  assert_true(
    client_effect_target_selection_matches_run(original, prepared, definition),
  )
  let material = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let restored = target_selection_materials_admit(
    material,
    @publication.publication_contract_identity(definition),
    Some(request),
  ).unwrap()
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
    material,
  )
  assert_false(
    client_effect_target_selection_matches_prepared(original, restored.prepared),
  )
}

///|
test "valid mixed UPDATE and published STORE keep ordered separate original occurrences" {
  let admitted = published_selection_prepare(mixed=true)
  assert_eq(
    admitted
    .map(_ => ())
    .map_err(issue => {
      match issue {
        Syntax(_) => "syntax"
        Candidate(_) => "candidate"
        RequestValuePolicies(_) => "request_value_policies"
        RequestValuePolicyConstruction => "request_value_policy_construction"
        Mapping(_) => "mapping"
        Static(_) => "static"
        Stage(_) => "stage"
        Graph(_) => "graph"
        TargetSelection(_) => "selection"
      }
    }),
    Ok(()),
  )
  let prepared = admitted.unwrap()
  let expected =
    #|[{"check_environment_cid":"sha256:3abdc285f8997b2d6e37abb4d407754d615391014d1884287bd868de38deaed2","effect_id":"save","installation_binding_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","installation_owner_cid":"sha256:83a8d70240b5ff70509fe61c30e141a5ab8caf859a48e1ae9605dc69df4763c7","mapping_cid":"sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5","mapping_ref":"mapping:fixture.archive.v1","stage_index":0,"target_ref":"connector://storage/archive"},{"check_environment_cid":"sha256:3abdc285f8997b2d6e37abb4d407754d615391014d1884287bd868de38deaed2","effect_id":"update","installation_binding_cid":"sha256:6666666666666666666666666666666666666666666666666666666666666666","installation_owner_cid":"sha256:9fb1b923109be7230392d96d2dd4f3e62dc6ba6a661a8c218148e7858142d506","mapping_cid":"sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5","mapping_ref":"mapping:fixture.archive.v1","stage_index":0,"target_ref":"connector://storage/archive"}]
  assert_eq(prepared_client_effect_target_selections(prepared), Some(expected))
  let original = client_effect_target_selection_original(prepared)[0]
  assert_eq(
    client_effect_target_selection_cid(original),
    "sha256:b5d29e9f6f601888bee4ac32962fdb718e431b408e6c259a9ad7f250905fe021",
  )
  assert_eq(
    admit_client_effect_target_selections(prepared.candidate, expected).unwrap().wire,
    expected,
  )
  let (allowed, definition, request) = published_selection_run(prepared)
  let material = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let restored = published_selection_mixed_materials_admit(
    material,
    @publication.publication_contract_identity(definition),
    request,
  ).unwrap()
  assert_eq(
    restore_client_effect_run_target_selections(restored).unwrap(),
    Some(expected),
  )
}

///|
test "mixed selection retains the explicit static member ceiling" {
  let bounded = published_selection_prepare(mixed=true, member_limit=1)
  assert_true(bounded is Err(Candidate(Headers(_))))
}

///|
test "published STORE refuses equivalent foreign Environment publication and missing original context" {
  assert_true(
    published_selection_prepare(foreign_publication=true)
    is Err(TargetSelection(ForeignEnvironment)),
  )
  let absent = published_selection_prepare(selected=false).unwrap()
  assert_eq(prepared_client_effect_target_selections(absent), None)
  let present = published_selection_prepare().unwrap()
  let original = client_effect_target_selection_original(present)[0]
  assert_false(
    client_effect_target_selection_matches_prepared(original, absent),
  )
}

///|
test "published STORE restore rejects substituted occurrence Mapping environment and original Run" {
  let prepared = published_selection_prepare().unwrap()
  let selection = prepared_client_effect_target_selections(prepared).unwrap()
  for
    replacement in [
      selection.replace(
        old="\"effect_id\":\"save\"",
        new="\"effect_id\":\"other\"",
      ),
      selection.replace(old="\"stage_index\":0", new="\"stage_index\":1"),
      selection.replace(
        old="connector://storage/archive",
        new="connector://storage/other",
      ),
      selection.replace(
        old="mapping:fixture.archive.v1",
        new="mapping:fixture.other.v1",
      ),
      selection.replace(
        old="sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5",
        new="sha256:" + "f".repeat(64),
      ),
      selection.replace(
        old="sha256:3abdc285f8997b2d6e37abb4d407754d615391014d1884287bd868de38deaed2",
        new="sha256:" + "f".repeat(64),
      ),
    ] {
    assert_true(
      admit_client_effect_target_selections(prepared.candidate, replacement)
      is Err(_),
    )
  }
  let (allowed, definition, request) = published_selection_run(prepared)
  let material = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  for
    replacement in [
      None,
      Some("[]"),
      Some(
        selection.replace(
          old="sha256:83a8d70240b5ff70509fe61c30e141a5ab8caf859a48e1ae9605dc69df4763c7",
          new="sha256:" + "f".repeat(64),
        ),
      ),
      Some(
        selection.replace(
          old="sha256:" + "8".repeat(64),
          new="sha256:" + "f".repeat(64),
        ),
      ),
    ] {
    let changed = target_selection_replace_field(
      material, "effect_target_selections_json", replacement,
    )
    assert_true(
      target_selection_materials_admit(
        changed,
        @publication.publication_contract_identity(definition),
        Some(request),
      )
      is Err(_),
    )
  }
  assert_true(
    target_selection_materials_admit(
      material,
      "sha256:" + "f".repeat(64),
      Some(request),
    )
    is Err(RunMismatch),
  )
}

///|
test "published STORE saved preparation retains original selection without current alias resolution" {
  let prepared = published_selection_prepare().unwrap()
  let (allowed, _, _) = published_selection_run(prepared)
  let wire = issue_client_effect_prepared_original(allowed.compilation).unwrap()
  let cid = @publication.publication_contract_identity(
    client_effect_compilation_compiled_plan(allowed.compilation),
  )
  let (_, _, effect_limits) = local_update_normalization_fixture()
  let restored = admit_client_effect_prepared_original(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    effect_limits,
  ).unwrap()
  assert_eq(
    prepared_client_effect_target_selections(restored.prepared),
    prepared_client_effect_target_selections(prepared),
  )
  assert_eq(
    issue_client_effect_prepared_original(restored.compilation).unwrap(),
    wire,
  )
}

///|
test "published STORE current facts refuse UPDATE purpose foreign original and changed generation" {
  let prepared = published_selection_prepare().unwrap()
  let original = client_effect_target_selection_original(prepared)[0]
  let current =
    #|[{"installation":{"cid":"sha256:83a8d70240b5ff70509fe61c30e141a5ab8caf859a48e1ae9605dc69df4763c7","wire":"{\"binding_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"connection\":\"fixture\",\"connector_registration\":\"store_target_fixture\",\"connector_revision\":\"store_target_fixture/0.1\",\"continuation_binding\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"profile\":{\"continuation\":\"actql-installed-row-effect-continuation/0.1\",\"continuationBinding\":\"binding_cid\",\"dispatch\":\"actql-installed-row-effect-dispatch/0.1\",\"recovery\":\"actql-installed-row-effect-recovery/0.1\",\"source\":\"actql-installed-row-effect-source/0.1\",\"targetCheck\":\"actql-installed-row-effect-check/0.1\",\"unit\":\"actql-installed-row-effect-unit/0.1\"},\"runtime_bundle_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}"},"store":true,"mappings":[{"target":"connector://storage/archive","mappingRef":"mapping:fixture.archive.v1","mappingCid":"sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5","store":true}]}]
  assert_true(
    client_effect_target_selection_current(original, prepared, current),
  )
  assert_false(
    client_effect_target_selection_current(
      original,
      prepared,
      current.replace(old="\"store\":true", new="\"update\":true"),
    ),
  )
  let foreign = published_selection_prepare().unwrap()
  assert_false(
    client_effect_target_selection_current(original, foreign, current),
  )
  assert_false(
    client_effect_target_selection_current(
      original,
      prepared,
      current.replace(
        old="sha256:83a8d70240b5ff70509fe61c30e141a5ab8caf859a48e1ae9605dc69df4763c7",
        new="sha256:" + "f".repeat(64),
      ),
    ),
  )
  assert_false(
    client_effect_target_selection_current(
      original,
      prepared,
      current.replace(
        old="store_target_fixture/0.1",
        new="store_target_fixture/other",
      ),
    ),
  )
  assert_false(client_effect_target_selection_current(original, prepared, "[]"))
}

///|
test "mixed current selection checks each original purpose without UPDATE spoofing" {
  let prepared = published_selection_prepare(mixed=true).unwrap()
  let original = client_effect_target_selection_original(prepared)[0]
  let current =
    #|[{"installation":{"cid":"sha256:83a8d70240b5ff70509fe61c30e141a5ab8caf859a48e1ae9605dc69df4763c7","wire":"{\"binding_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"connection\":\"fixture\",\"connector_registration\":\"store_target_fixture\",\"connector_revision\":\"store_target_fixture/0.1\",\"continuation_binding\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"profile\":{\"continuation\":\"actql-installed-row-effect-continuation/0.1\",\"continuationBinding\":\"binding_cid\",\"dispatch\":\"actql-installed-row-effect-dispatch/0.1\",\"recovery\":\"actql-installed-row-effect-recovery/0.1\",\"source\":\"actql-installed-row-effect-source/0.1\",\"targetCheck\":\"actql-installed-row-effect-check/0.1\",\"unit\":\"actql-installed-row-effect-unit/0.1\"},\"runtime_bundle_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}"},"store":true,"mappings":[{"target":"connector://storage/archive","mappingRef":"mapping:fixture.archive.v1","mappingCid":"sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5","store":true}]},{"installation":{"cid":"sha256:9fb1b923109be7230392d96d2dd4f3e62dc6ba6a661a8c218148e7858142d506","wire":"{\"binding_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"connection\":\"fixture\",\"connector_registration\":\"update_target_fixture\",\"connector_revision\":\"update_target_fixture/0.1\",\"continuation_binding\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"profile\":{\"continuation\":\"actql-installed-row-effect-continuation/0.1\",\"continuationBinding\":\"binding_cid\",\"dispatch\":\"actql-installed-row-effect-dispatch/0.1\",\"recovery\":\"actql-installed-row-effect-recovery/0.1\",\"source\":\"actql-installed-row-effect-source/0.1\",\"targetCheck\":\"actql-installed-row-effect-check/0.1\",\"unit\":\"actql-installed-row-effect-unit/0.1\"},\"runtime_bundle_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}"},"update":true,"mappings":[{"target":"connector://storage/archive","mappingRef":"mapping:fixture.archive.v1","mappingCid":"sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5","update":true}]}]
  let only_store =
    #|[{"installation":{"cid":"sha256:83a8d70240b5ff70509fe61c30e141a5ab8caf859a48e1ae9605dc69df4763c7","wire":"{\"binding_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"connection\":\"fixture\",\"connector_registration\":\"store_target_fixture\",\"connector_revision\":\"store_target_fixture/0.1\",\"continuation_binding\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"profile\":{\"continuation\":\"actql-installed-row-effect-continuation/0.1\",\"continuationBinding\":\"binding_cid\",\"dispatch\":\"actql-installed-row-effect-dispatch/0.1\",\"recovery\":\"actql-installed-row-effect-recovery/0.1\",\"source\":\"actql-installed-row-effect-source/0.1\",\"targetCheck\":\"actql-installed-row-effect-check/0.1\",\"unit\":\"actql-installed-row-effect-unit/0.1\"},\"runtime_bundle_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}"},"store":true,"mappings":[{"target":"connector://storage/archive","mappingRef":"mapping:fixture.archive.v1","mappingCid":"sha256:1c815d61a8df2721d953fb92f1559d5f1e15d6181f241f5cc61d67c2fe0febe5","store":true}]}]
  assert_true(
    client_effect_target_selection_current(original, prepared, current),
  )
  assert_false(
    client_effect_target_selection_current(original, prepared, only_store),
  )
  assert_false(
    client_effect_target_selection_current(
      original,
      prepared,
      current.replace(old="\"store\":true", new="\"update\":true"),
    ),
  )
}
