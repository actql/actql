///|
fn plural_effect_infer_fixture() -> (
  PreparedClientEffectComputation,
  ClientEffectAllowedRun,
  @publication.PublicationContract,
  ClientRequestIdentity,
) raise {
  let (_, base, limits) = local_update_normalization_fixture()
  let environment = client_composed_effect_test_environment(base)
  let mappings = @environment.check_mapping_contract_shapes(
    @checked.checking_environment_wire(environment),
    limits.mapping,
    limits.max_mapping_work,
  ).unwrap()
  let publication = @update_targets.bind_update_target_publication(
    mappings,
    [
      {
        name: [
          { value: "crm", quoted: false, },
          { value: "account", quoted: false, },
        ],
        target_ref: "connector://crm/account",
        installation_binding_cid: "sha256:" + "8".repeat(64),
        installation_owner_cid: "sha256:" + "9".repeat(64),
      },
    ],
    1000,
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"plural-model-effect","stages":[{"id":"input","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true},"value":{"type":"number","nullable":false}},"rows":[{"id":"a","text":"hello","value":1},{"id":"b","text":"world","value":2}]},"as":"items"}],"results":{"rows":{"from":"items","fields":["id","text","value"]}}},{"id":"first","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}},{"id":"combine","inputs":{"first":{"result":{"stage":"first","result":"rows"}},"second":{"result":{"stage":"second","result":"rows"}},"seed":{"result":{"stage":"input","result":"rows"}}},"steps":[{"from":"first","join":{"with":"second","kind":"inner","cardinality":"one_to_one","max_output_rows":2,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id"}},"as":"joined"},{"join":{"with":"seed","kind":"inner","cardinality":"one_to_one","on":[{"left":"id","right":"id"}],"select":{"id":"right.id","value":"right.value"}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","value"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"value"}}}}}}],"results":{"rows":{"from":{"stage":"combine","result":"rows"}}}}
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    client_standard_effect_computation_limits(),
    update_targets=Some(publication),
  ).unwrap()
  assert_true(prepared_client_effect_infer_occurrence(prepared) is None)
  let occurrences = prepared_client_effect_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  let bounds = run_materials_limits()
  let graphs = occurrences.map(occurrence => {
    issue_installed_client_composed_infer_plan_graph(
      occurrence,
      client_infer_graph_test_execution(
        occurrence.owner,
        occurrence=Some(occurrence),
      ),
      bounds.sequence,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
    ).unwrap()
  })
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    infers=graphs,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "plural-effect-scope", "plural-effect-run", "2026-11-05T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "plural-effect-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  (prepared, allowed, definition, request)
}

///|
test "plural Effect compiler and materials keep both same-Task occurrences and complete Run" {
  let (prepared, allowed, definition, request) = plural_effect_infer_fixture()
  let originals = client_effect_compilation_infer_originals(allowed.compilation).unwrap()
  assert_eq(originals.length(), 2)
  assert_true(
    physical_equal(
      originals[0].1,
      allowed.compilation.compiled.infers[0].occurrence,
    ),
  )
  assert_eq(client_infer_occurrence_coordinates(originals[0].1), (1, 1, 1))
  assert_eq(client_infer_occurrence_coordinates(originals[1].1), (2, 2, 1))
  assert_eq(
    @environment.model_execution_cid(originals[0].0.execution),
    @environment.model_execution_cid(originals[1].0.execution),
  )
  originals.clear()
  assert_eq(
    client_effect_compilation_infer_originals(allowed.compilation)
    .unwrap()
    .length(),
    2,
  )
  let held = issue_client_effect_prepared_original(allowed.compilation).unwrap()
  let restored = plural_effect_original_admit(
    held,
    @publication.publication_contract_identity(
      allowed.compilation.compiled.compiled_plan,
    ),
  ).unwrap()
  assert_eq(
    client_effect_compilation_infer_originals(restored.compilation)
    .unwrap()
    .length(),
    2,
  )
  assert_eq(
    issue_client_effect_prepared_original(restored.compilation).unwrap(),
    held,
  )
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let run = plural_effect_materials_admit(
    wire,
    @publication.publication_contract_identity(definition),
    Some(request),
  ).unwrap()
  assert_eq(
    client_effect_compilation_infer_originals(run.compilation).unwrap().length(),
    2,
  )
  assert_eq(
    issue_prepared_client_effect_run_materials(
      run.allowed,
      run.run_definition,
      request=Some(request),
    ).unwrap(),
    wire,
  )
  assert_true(
    client_infer_occurrence_matches_effect(
      client_effect_compilation_infer_originals(run.compilation).unwrap()[0].1,
      run.prepared,
    ),
  )
  assert_true(
    !client_infer_occurrence_matches_effect(
      client_effect_compilation_infer_originals(run.compilation).unwrap()[0].1,
      prepared,
    ),
  )
}

///|
test "plural Effect refuses missing duplicate swapped foreign and corrupt original inventory" {
  let (_, allowed, definition, request) = plural_effect_infer_fixture()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let entries = plural_infer_run_materials_entries(wire)
  let foreign = @canonical.object_with_replaced_fields(entries[0], [
    ("task", parse_plan_identity_value("99", 16, 2, 2).unwrap()),
  ]).unwrap()
  let corrupt = @canonical.object_with_string_field(
    @canonical.object_without_field(entries[0], "execution_contract_cid").unwrap(),
    "execution_contract_cid",
    "sha256:" + "0".repeat(64),
  ).unwrap()
  for
    changed in [
      [],
      [entries[0]],
      [entries[0], entries[0]],
      [entries[1], entries[0]],
      [foreign, entries[1]],
      [corrupt, entries[1]],
    ] {
    assert_true(
      plural_effect_materials_admit(
        plural_infer_run_materials_with_entries(wire, changed),
        @publication.publication_contract_identity(definition),
        Some(request),
      )
      is Err(_),
    )
  }
  let graphs = allowed.compilation.compiled.infers
  let bounds = run_materials_limits()
  for changed in [[graphs[0]], [graphs[0], graphs[0]], [graphs[1], graphs[0]]] {
    assert_true(
      issue_prepared_client_effect_compilation(
        allowed.compilation.owner,
        run_materials_manifests(),
        bounds.sequence,
        bounds.max_sequence_steps,
        bounds.max_sequence_work,
        bounds.max_evidence_bytes,
        bounds.max_evidence_nodes,
        bounds.max_evidence_depth,
        infers=changed,
      )
      is Err(ForeignInferOwner),
    )
  }
}

///|
fn plural_effect_original_admit(
  wire : String,
  expected : String,
) -> Result[ClientEffectPreparedOriginal, ClientEffectRunMaterialsIssue] {
  admit_client_effect_prepared_original(
    wire,
    expected,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    client_standard_effect_computation_limits(),
  )
}

///|
fn plural_effect_materials_admit(
  wire : String,
  expected : String,
  request : ClientRequestIdentity?,
) -> Result[ClientEffectRunMaterials, ClientEffectRunMaterialsIssue] {
  admit_client_effect_run_materials(
    wire,
    expected,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    client_standard_effect_computation_limits(),
    expected_request=request,
  )
}
