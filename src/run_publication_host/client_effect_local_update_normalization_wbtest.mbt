///|
fn local_update_normalization_fixture() -> (
  String,
  @checked.CheckEnvironment,
  ClientEffectComputationLimits,
) {
  let document =
    #|{"version":"actql/0.1","id":"local-update","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"number","nullable":false}},"rows":[{"id":"original-id","value":1}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"},"id":"id","set":{"Name":{"field":"value"}}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let schema = "{\"additional_properties\":false,\"fields\":{\"Id\":{\"nullable\":false,\"type\":\"string\"},\"Name\":{\"nullable\":true,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}"
  let schema_cid = "sha256:" + @sha.hex(@utf8.encode(schema))
  let before = "{\"connector_manifest_cid\":\"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1\",\"conversions\":[],"
  let after = "\"mapping_ref\":\"mapping:crm.account.v1\",\"minimum_approval\":\"none\",\"permission_rules\":[{\"effect_kind\":\"update\",\"permissions\":[\"scope:update\"],\"selector_class\":\"id\",\"write_fields\":[\"Name\"]},{\"effect_kind\":\"update\",\"permissions\":[\"scope:update\"],\"selector_class\":\"ids\",\"write_fields\":[\"Name\"]}],\"primary_identity\":\"Id\",\"required_fields\":[],\"required_permissions\":[],\"resource_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"row_mapping\":{\"Name\":{\"field\":\"value\",\"null_behavior\":\"reject\"}},\"schema\":\"actql.mapping_contract/0.1\",\"target_ref\":\"connector://crm/account\",\"target_schema\":" +
    schema +
    ",\"target_schema_identity\":\"" +
    schema_cid +
    "\",\"version\":\"salesforce-v1\",\"writable_fields\":[\"Name\"]}"
  let mapping_cid = "sha256:" + @sha.hex(@utf8.encode(before + after))
  let mapping = before +
    "\"mapping_contract_cid\":\"" +
    mapping_cid +
    "\"," +
    after
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd\",\"commands\":[],\"connector_id\":\"crm\",\"connector_version\":\"fixture\",\"contracts\":[],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}],\"connector_manifest\":{\"connectors\":[{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\"}],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[" +
    mapping +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let wire = @environment.read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let environment = @checked.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let input : @syntax.Limits = {
    source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    tree: {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
    max_stages: 2,
  }
  let limits : ClientEffectComputationLimits = {
    program: {
      values_max_rows: None,
      checking: {
        input,
        compilation: {
          work: 10000000,
          artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
          structure: {
            stages: 2,
            steps: 10,
            results: 10,
            parameters: 1,
            bindings: 100,
            slots: 1000,
            references: 1000,
            requirements: 1000,
            tokens: 10000,
          },
          traversal: {
            nodes: 100000,
            depth: 100,
            text_bytes: 10000000,
            string_bytes: 100000,
            name_bytes: 1000000,
            pointer_units: 1000000,
            comparison_pairs: 1000000,
          },
          values: { nodes: 1000000, depth: 100, text_bytes: 100000, },
          policy: { bytes: 10000, nodes: 1000000, depth: 100, },
          patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
        },
      },
      lowering: {
        max_nodes: 100,
        max_references: 100,
        max_work: 100000,
        max_identifier_bytes: 10000,
      },
      max_parameters: 10,
      max_parameter_name_bytes: 1000,
      max_tasks: 2,
      max_graph_work: 10000,
      values_max_rows: None,
    },
    max_members: 1,
    max_header_work: 100,
    mapping: {
      max_bytes: 20000,
      max_nodes: 2000,
      max_depth: 100,
      max_members: 100,
    },
    max_mapping_work: 1000,
    effects: {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  }
  (document, environment, limits)
}

///|
test "original mapped update has a distinct completion-free normalization proof" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let owner = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    issue_prepared_client_effect_normalization(owner)
    is Err(Inventory(ProfileNotInstalled)),
  )
  let proof = issue_prepared_client_effect_local_update_normalization(owner).unwrap()
  let evidence = prepared_client_effect_normalization_evidence(owner, proof).unwrap()
  let preimage =
    #|{"entries":[],"rule_catalog_cid":"sha256:9ba6d5dff43cd54b0d61d6923fd4cb3143e1a5e238bad20b297133393d783468","version":"actql-normalization-journal/0.1"}
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(preimage)),
    "sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d",
  )
  let wire =
    #|{"entries":[],"journal_cid":"sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d","rule_catalog_cid":"sha256:9ba6d5dff43cd54b0d61d6923fd4cb3143e1a5e238bad20b297133393d783468","version":"actql-normalization-journal/0.1"}
  assert_eq(@publication.run_evidence_value_json(evidence), wire)
  assert_eq(
    @publication.run_evidence_value_identity(evidence),
    "sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d",
  )
  guard proof.inventory is LocalUpdate(inventory) else {
    fail("update profile")
  }
  assert_true(
    @checked.local_update_completion_free_inventory_work(inventory) > 0,
  )
  assert_true(
    physical_equal(
      proof,
      issue_prepared_client_effect_local_update_normalization(owner).unwrap(),
    ),
  )
  assert_true(
    issue_prepared_client_effect_normalization(owner)
    is Err(Inventory(ProfileNotInstalled)),
  )
  let restored = restore_prepared_client_effect_normalization(
    owner,
    proof,
    wire,
    client_effect_local_update_completion_free_catalog_cid(),
  ).unwrap()
  assert_eq(@publication.run_evidence_value_json(restored), wire)
  assert_true(physical_equal(owner.normalization.unwrap(), proof))
}

///|
fn prepared_local_update_normalization_fixture(
  document : String,
) -> PreparedClientEffectComputation {
  let (_, environment, limits) = local_update_normalization_fixture()
  prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
}

///|
test "update selector and scalar changes retain the actual closed owners" {
  let (base, _, _) = local_update_normalization_fixture()
  for literal in ["7", "null"] {
    let document = base.replace(
      old="\"field\":\"value\"",
      new="\"literal\":" + literal,
    )
    assert_true(document != base)
    let owner = prepared_local_update_normalization_fixture(document)
    let proof = issue_prepared_client_effect_local_update_normalization(owner).unwrap()
    assert_eq(
      client_effect_normalization_catalog_cid(proof),
      client_effect_local_update_completion_free_catalog_cid(),
    )
  }
}

///|
test "update proof rejects copied preparation and cross-profile readback" {
  let (base, _, _) = local_update_normalization_fixture()
  let owner = prepared_local_update_normalization_fixture(base)
  let proof = issue_prepared_client_effect_local_update_normalization(owner).unwrap()
  let foreign = prepared_local_update_normalization_fixture(base)
  assert_true(
    prepared_client_effect_normalization_evidence(foreign, proof)
    is Err(ForeignPreparation),
  )
  let copied : ClientEffectNormalization = {
    owner: proof.owner,
    inventory: proof.inventory,
    journal: proof.journal,
  }
  assert_true(
    prepared_client_effect_normalization_evidence(owner, copied)
    is Err(ForeignPreparation),
  )
  let wire = @publication.run_evidence_value_json(proof.journal)
  assert_true(
    restore_prepared_client_effect_normalization(
      owner,
      proof,
      wire,
      client_effect_completion_free_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
  let create = normalization_fixture()
  let create_proof = issue_prepared_client_effect_normalization(create).unwrap()
  assert_true(
    issue_prepared_client_effect_local_update_normalization(create)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(
    restore_prepared_client_effect_normalization(
      create,
      create_proof,
      @publication.run_evidence_value_json(create_proof.journal),
      client_effect_local_update_completion_free_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    restore_prepared_client_effect_normalization(
      owner,
      proof,
      @publication.run_evidence_value_json(create_proof.journal),
      client_effect_local_update_completion_free_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  assert_true(physical_equal(owner.normalization.unwrap(), proof))
}

///|
test "observed template completion and unaudited processing do not become empty update journals" {
  let (base, _, _) = local_update_normalization_fixture()
  for
    (step, completion) in [
      (
        "{\"filter\":{\"eq\":[{\"template\":\"{id}\"},{\"literal\":\"original-id\"}]}}",
        true,
      ),
      ("{\"take\":1}", false),
    ] {
    let document = base.replace(
      old="\"as\":\"selected\"}],",
      new="\"as\":\"selected\"}," + step + "],",
    )
    assert_true(document != base)
    let owner = prepared_local_update_normalization_fixture(document)
    let issue = issue_prepared_client_effect_local_update_normalization(owner)
    if completion {
      assert_true(issue is Err(Inventory(CompletionObserved)))
    } else {
      assert_true(issue is Err(Inventory(ProfileNotInstalled)))
    }
    assert_true(owner.normalization is None)
  }
}

///|
test "update journal selects its own typed compiler profile instead of mapped-create" {
  let (base, _, _) = local_update_normalization_fixture()
  let owner = prepared_local_update_normalization_fixture(base)
  let proof = issue_prepared_client_effect_local_update_normalization(owner).unwrap()
  let limits = run_materials_limits()
  let compiled = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
    normalization=Some(proof),
  )
  let compiled = compiled.unwrap()
  assert_true(compiled.normalization_profile is Some(LocalUpdate(_)))
  let template = @publication.run_evidence_value_json(
    client_effect_compilation_template(compiled),
  )
  assert_true(template.contains("actql-local-update-completion-free/0.1"))
  assert_false(template.contains("actql-resident-effect-completion-free/0.1"))
  assert_true(physical_equal(owner.normalization.unwrap(), proof))
}

///|
test "a valid but uninstalled update selector is refused without an empty proof" {
  let (base, _, _) = local_update_normalization_fixture()
  let document = base
    .replace(
      old="\"from\":{\"result\":\"out\"},\"id\":\"id\"",
      new="\"ids\":[\"original-id\"]",
    )
    .replace(old="\"field\":\"value\"", new="\"literal\":7")
  assert_true(document != base)
  let owner = prepared_local_update_normalization_fixture(document)
  assert_true(
    issue_prepared_client_effect_local_update_normalization(owner)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(owner.normalization is None)
}

///|
test "missing original selector or changes fields are rejected by the existing static checker" {
  let (base, environment, limits) = local_update_normalization_fixture()
  for
    document in [
      base.replace(
        old="\"id\":\"id\",\"set\"",
        new="\"id\":\"missing\",\"set\"",
      ),
      base.replace(old="\"field\":\"value\"", new="\"field\":\"missing\""),
    ] {
    assert_true(document != base)
    assert_true(
      prepare_client_effect_computation(
        document,
        Json,
        environment,
        None,
        [],
        limits,
      )
      is Err(Static(_)),
    )
  }
}

///|
test "update proof cannot be grafted onto a foreign original Run or transported create materials" {
  let (base, _, _) = local_update_normalization_fixture()
  let owner = prepared_local_update_normalization_fixture(base)
  let proof = issue_prepared_client_effect_local_update_normalization(owner).unwrap()
  let (_, allowed, definition) = original_effect_materials_fixture(
    normalized=true,
  )
  assert_true(
    issue_prepared_client_effect_normalization_materials(
      allowed, definition, proof,
    )
    is Err(Normalization(ForeignPreparation)),
  )
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    normalization=Some(
      issue_prepared_client_effect_normalization(
        client_effect_compilation_owner(allowed.compilation),
      ).unwrap(),
    ),
  ).unwrap()
  let grafted = normalization_materials_replace(
    wire,
    @publication.run_evidence_value_json(proof.journal),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      grafted,
      @publication.publication_contract_identity(definition),
    )
    is Err(Normalization(SubstitutedJournal)),
  )
}
