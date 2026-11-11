///|
fn selected_infer_original_fixture() -> (
  PreparedClientEffectComputation,
  ClientEffectAllowedRun,
  @publication.PublicationContract,
  ClientRequestIdentity,
) raise {
  let (document, base, limits) = local_update_normalization_fixture()
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
  let document = document.replace(
    old="\"as\":\"selected\"}]",
    new="\"as\":\"input\"},{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"joined\"},{\"infer\":{\"contract\":\"model-task:risk-score.v1\",\"key\":\"id\",\"input\":{\"text\":{\"field\":\"id\"}}},\"as\":\"inferred\"},{\"join\":{\"with\":\"joined\",\"kind\":\"inner\",\"cardinality\":\"one_to_one\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"right.id\",\"value\":\"right.value\"}},\"as\":\"selected\"}]",
  )
  // The checked component retains the terminal prefix, not every prior
  // alias. Join the same original rows after their existing uniqueness check;
  // do not replace the Model/UPDATE fixture or add another producer edge.
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
    update_targets=Some(publication),
  ).unwrap()
  let occurrence = prepared_client_effect_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let bounds = run_materials_limits()
  let component = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    bounds.sequence,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  )
  let component = match component {
    Ok(value) => value
    Err(UnsupportedProgram) =>
      fail("selected Model original component: UnsupportedProgram")
    Err(ForeignExecution) =>
      fail("selected Model original component: ForeignExecution")
    Err(InvalidDependency) =>
      fail("selected Model original component: InvalidDependency")
    Err(Execution(_)) => fail("selected Model original component: Execution")
    Err(Input(_)) => fail("selected Model original component: Input")
    Err(Mapping(_)) => fail("selected Model original component: Mapping")
    Err(Result(_)) => fail("selected Model original component: Result")
    Err(Encoding) => fail("selected Model original component: Encoding")
    Err(ItemLimit(_)) => fail("selected Model original component: ItemLimit")
    Err(Serialization(_)) =>
      fail("selected Model original component: Serialization")
  }
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    infer=Some(component),
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-16T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "selected-model-scope", "selected-model-run", "2026-10-15T00:00:00.000Z",
    "2026-10-16T00:00:00.000Z",
  ).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "selected-model-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  (prepared, allowed, definition, request)
}

///|
fn selected_infer_original_admit(
  wire : String,
  expected : String,
) -> Result[ClientEffectPreparedOriginal, ClientEffectRunMaterialsIssue] {
  let (_, _, effect_limits) = local_update_normalization_fixture()
  admit_client_effect_prepared_original(
    wire,
    expected,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    effect_limits,
  )
}

///|
test "selected Model originals restore the exact compilation graph and nominal occurrence" {
  let (owner, allowed, definition, request) = selected_infer_original_fixture()
  let compilation = allowed.compilation
  let original = issue_client_effect_prepared_original(compilation).unwrap()
  let plan_cid = @publication.publication_contract_identity(
    compilation.compiled.compiled_plan,
  )
  let held = selected_infer_original_admit(original, plan_cid).unwrap()
  let materials = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let run_cid = @publication.publication_contract_identity(definition)
  let restored = target_selection_materials_admit(
    materials,
    run_cid,
    Some(request),
  ).unwrap()
  assert_eq(
    issue_client_effect_prepared_original(held.compilation).unwrap(),
    original,
  )
  assert_eq(
    issue_prepared_client_effect_run_materials(
      restored.allowed,
      restored.run_definition,
      request=Some(request),
    ).unwrap(),
    materials,
  )
  for current in [compilation, held.compilation, restored.compilation] {
    let (graph, occurrence) = client_effect_compilation_infer_original(current).unwrap()
    assert_true(physical_equal(graph, current.compiled.infer.unwrap()))
    assert_true(client_infer_occurrence_matches_plan(occurrence, graph))
    assert_true(
      client_infer_occurrence_matches_effect(occurrence, current.owner),
    )
    assert_eq(
      @publication.publication_contract_identity(current.compiled.compiled_plan),
      plan_cid,
    )
    assert_eq(
      prepared_client_effect_target_selections(current.owner),
      prepared_client_effect_target_selections(owner),
    )
    // A new private Program view is not this graph's nominal owner.
    assert_false(
      client_infer_occurrence_matches_plan(
        prepared_client_effect_infer_occurrence(current.owner).unwrap(),
        graph,
      ),
    )
  }
  let bounds = run_materials_limits()
  assert_true(
    issue_prepared_client_effect_compilation(
      held.prepared,
      run_materials_manifests(),
      bounds.sequence,
      bounds.max_sequence_steps,
      bounds.max_sequence_work,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
      infer=compilation.compiled.infer,
    )
    is Err(ForeignInferOwner),
  )
  let forged = { ..compilation, owner: held.prepared, }
  assert_true(client_effect_compilation_infer_original(forged) is None)
  assert_true(
    client_effect_original_infer_input(forged)
    is Err(Compilation(ForeignInferOwner)),
  )
  assert_true(
    selected_infer_original_admit(original, "sha256:" + "f".repeat(64))
    is Err(TargetSelection(ForeignSelection)),
  )
  assert_true(
    target_selection_materials_admit(
      materials,
      "sha256:" + "f".repeat(64),
      Some(request),
    )
    is Err(RunMismatch),
  )
  let foreign_request = prepare_client_effect_request_identity(
    owner,
    "sha256:" + "a".repeat(64),
    "another-model-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  assert_true(
    target_selection_materials_admit(materials, run_cid, Some(foreign_request))
    is Err(Request(IdentityMismatch)),
  )
  assert_true(
    target_selection_materials_admit(materials, run_cid, None)
    is Err(Request(IdentityMismatch)),
  )
}

///|
test "both Model original readers refuse missing malformed and changed execution material" {
  let (_, allowed, definition, request) = selected_infer_original_fixture()
  let compilation = allowed.compilation
  let original = issue_client_effect_prepared_original(compilation).unwrap()
  let plan_cid = @publication.publication_contract_identity(
    compilation.compiled.compiled_plan,
  )
  let materials = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let run_cid = @publication.publication_contract_identity(definition)
  let (execution_cid, execution_wire) = client_effect_original_infer_input(
      compilation,
    )
    .unwrap()
    .unwrap()
  let mutate = fn(wire : String) -> Array[String] raise @encode.EncodeFailure {
    let missing_cid = target_selection_replace_field(
      wire,
      "infer_execution_contract_cid",
      None,
    )
    [
      missing_cid,
      target_selection_replace_field(
        wire,
        "infer_execution_contract_json",
        None,
      ),
      target_selection_replace_field(
        missing_cid,
        "infer_execution_contract_json",
        None,
      ),
      target_projection_replace_raw_field(
        wire,
        "infer_execution_contract_json",
        Some("null"),
      ),
      target_projection_replace_raw_field(
        wire,
        "infer_execution_contract_cid",
        Some("1"),
      ),
      target_selection_replace_field(
        wire,
        "infer_execution_contract_cid",
        Some("sha256:" + "f".repeat(64)),
      ),
      target_selection_replace_field(
        wire,
        "infer_execution_contract_json",
        Some(
          execution_wire.replace(
            old="\"max_total_duration_ms\":1000",
            new="\"max_total_duration_ms\":999",
          ),
        ),
      ),
      target_selection_replace_field(
        wire,
        "infer_execution_contract_json",
        Some(
          execution_wire.replace(
            old="\"model_task_contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\"",
            new="\"model_task_contract_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"",
          ),
        ),
      ),
      target_selection_replace_field(
        wire,
        "infer_execution_contract_json",
        Some(
          target_projection_replace_raw_field(
            execution_wire,
            "extra",
            Some("true"),
          ),
        ),
      ),
      target_selection_replace_field(
        wire,
        "infer_execution_contract_json",
        Some(" " + execution_wire),
      ),
    ]
  }
  for candidate in mutate(original) {
    assert_true(selected_infer_original_admit(candidate, plan_cid) is Err(_))
  }
  for candidate in mutate(materials) {
    assert_true(
      target_selection_materials_admit(candidate, run_cid, Some(request))
      is Err(_),
    )
  }
  // Independently mutate and reidentify a valid contract. Local self-CID
  // consistency cannot replace the held Plan or independently selected Run.
  let unsigned = target_projection_replace_raw_field(
    execution_wire,
    "self_cid",
    None,
  )
  let changed = target_projection_replace_raw_field(
    unsigned,
    "max_total_duration_ms",
    Some("999"),
  )
  let changed_cid = "sha256:" + @sha.hex(@utf8.encode(changed))
  assert_true(changed_cid != execution_cid)
  let changed_body = target_projection_replace_raw_field(
    changed,
    "self_cid",
    Some("\"" + changed_cid + "\""),
  )
  assert_true(
    restore_client_effect_original_infer(
      compilation.owner,
      Some((changed_cid, changed_body)),
      run_materials_limits(),
    )
    is Ok(Some(_)),
  )
  let replace_execution = fn(
    wire : String,
  ) -> String raise @encode.EncodeFailure {
    target_selection_replace_field(
      target_selection_replace_field(
        wire,
        "infer_execution_contract_cid",
        Some(changed_cid),
      ),
      "infer_execution_contract_json",
      Some(changed_body),
    )
  }
  assert_true(
    selected_infer_original_admit(replace_execution(original), plan_cid)
    is Err(TargetSelection(ForeignSelection)),
  )
  assert_true(
    target_selection_materials_admit(
      replace_execution(materials),
      run_cid,
      Some(request),
    )
    is Err(_),
  )
  // A self-consistent foreign Task contract still cannot bind this checked
  // occurrence. This reaches the Task-reference check after hash admission.
  let foreign = target_projection_replace_raw_field(
    unsigned,
    "model_task_contract_cid",
    Some("\"sha256:" + "f".repeat(64) + "\""),
  )
  let foreign_cid = "sha256:" + @sha.hex(@utf8.encode(foreign))
  let foreign_body = target_projection_replace_raw_field(
    foreign,
    "self_cid",
    Some("\"" + foreign_cid + "\""),
  )
  assert_true(
    restore_client_effect_original_infer(
      compilation.owner,
      Some((foreign_cid, foreign_body)),
      run_materials_limits(),
    )
    is Err(Input(MaterialsEvidence("infer_execution_contract"))),
  )
}

///|
test "non-Model originals remain absent and generic materials cannot discard Model fields" {
  let (_, allowed, definition, request) = target_selection_fixture()
  let original = issue_client_effect_prepared_original(allowed.compilation).unwrap()
  let materials = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  assert_true(
    client_effect_compilation_infer_original(allowed.compilation) is None,
  )
  assert_false(original.contains("infer_execution_contract"))
  assert_false(materials.contains("infer_execution_contract"))
  let (_, model, model_definition, model_request) = selected_infer_original_fixture()
  let wire = issue_prepared_client_effect_run_materials(
    model,
    model_definition,
    request=Some(model_request),
  ).unwrap()
  let generic = target_selection_replace_field(
    wire,
    "effect_target_selections_json",
    None,
  )
  assert_true(
    read_client_run_materials_input(
      generic,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_limits(),
    )
    is Err(MaterialsEvidence("infer_execution_contract")),
  )
  let (cid, body) = client_effect_original_infer_input(model.compilation)
    .unwrap()
    .unwrap()
  assert_true(
    restore_client_effect_original_infer(
      allowed.compilation.owner,
      Some((cid, body)),
      run_materials_limits(),
    )
    is Err(Input(MaterialsEvidence("infer_execution_contract"))),
  )
}

///|
test "serialized Model original reconstruction retains the Content component" {
  let owner = client_effect_serialized_infer_fixture(keep=true)
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let bounds = {
    ..run_materials_limits(),
    max_sequence_steps: 1000,
    max_sequence_work: 10000,
    max_evidence_bytes: 1000000,
    max_evidence_nodes: 100000,
  }
  let component = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    bounds.sequence,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    infer=Some(component),
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-16T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "serialized-original", "serialized-run", "2026-10-15T00:00:00.000Z",
    "2026-10-16T00:00:00.000Z",
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(allowed, definition).unwrap()
  let (_, _, effect_limits) = client_composed_effect_base_fixture()
  let construction : Ref[ClientEffectCompilationConstruction?] = Ref(None)
  let calls = Ref(0)
  let refused = admit_client_effect_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    bounds,
    { ..effect_limits, program: client_standard_program_preparation_limits(), },
    before_compilation=Some(_ => {
      calls.val += 1
      Err(Binding(ForeignCompilation))
    }),
  )
  assert_true(refused is Err(Binding(ForeignCompilation)))
  assert_eq(calls.val, 1)
  let restored = admit_client_effect_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    bounds,
    { ..effect_limits, program: client_standard_program_preparation_limits(), },
    before_compilation=Some(input => {
      calls.val += 1
      let codec = {
        max_facts: bounds.max_sequence_steps,
        max_witnesses: bounds.max_sequence_work,
        max_wire_bytes: bounds.max_evidence_bytes,
        max_nodes: bounds.max_evidence_nodes,
        max_depth: bounds.max_evidence_depth,
      }
      // The component's original owner funds observation/measurement first;
      // the opaque callback exposes actual originals rather than caller counts.
      match prepared_client_effect_measurement_storage(input, codec) {
        Err(_) => return Err(Compilation(Encoding))
        Ok(_) => ()
      }
      match
        measure_prepared_client_effect_compilation_construction(
          input,
          run_materials_manifests(),
          bounds.sequence,
          codec,
        ) {
        Err(_) => Err(Compilation(Encoding))
        Ok(value) => {
          construction.val = Some(value)
          Ok(())
        }
      }
    }),
  ).unwrap()
  assert_eq(calls.val, 2)
  let measured = construction.val.unwrap()
  assert_true(
    client_effect_compilation_construction_matches(measured, restored.prepared),
  )
  let capacity = @local_query_time.request_model_recovery_effect_compiler_capacity(
    measured,
  ).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(capacity) > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) >
    @execution.execution_capacity_retained_bytes(capacity),
  )
  assert_false(client_effect_compilation_construction_matches(measured, owner))
  let (graph, restored_occurrence) = client_effect_compilation_infer_original(
    restored.compilation,
  ).unwrap()
  assert_true(client_infer_occurrence_matches_plan(restored_occurrence, graph))
  assert_eq(graph.graph.wire, component.graph.wire)
  assert_true(
    physical_equal(
      graph.serialization.unwrap(),
      restored.compilation.compiled.serialization.unwrap(),
    ),
  )
  assert_eq(
    issue_prepared_client_effect_run_materials(
      restored.allowed,
      restored.run_definition,
    ).unwrap(),
    wire,
  )
}
