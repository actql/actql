///|
fn infer_run_materials_fixture() -> (
  PreparedClientProgram,
  ClientCompiledRun,
  @publication.PublicationContract,
  String,
) raise {
  let prepared = client_infer_prefix_test_program()
  let (environment_wire, environment) = client_infer_prefix_test_environment()
  let bounds = run_materials_limits()
  let graph = issue_installed_client_infer_plan_graph(
    prepared,
    2,
    client_infer_graph_test_execution(prepared),
    bounds.sequence,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compilation = issue_prepared_client_infer_compilation(
    prepared,
    graph,
    run_materials_manifests(),
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "original-model-scope", "original-model-run", "2026-10-01T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let writer = @encode.writer(65536, 8192, 64)
  @syntax.emit_program_source(prepared.source, writer)
  let program = @encode.finish(writer)
  let materials = issue_client_infer_run_materials(
    compiled,
    definition,
    environment,
    environment_wire,
    program,
    None,
    bounds,
  ).unwrap()
  (prepared, compiled, definition, materials)
}

///|
fn infer_run_materials_admit(
  wire : String,
  definition : @publication.PublicationContract,
) -> Result[ClientTaskRunMaterials, ClientTaskRunMaterialsIssue] {
  admit_client_infer_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
  )
}

///|
test "saved INFER materials retain exact original Task settings and same Run" {
  let (prepared, original, definition, wire) = infer_run_materials_fixture()
  let restored = infer_run_materials_admit(wire, definition).unwrap()
  let compiled = client_task_run_materials_compiled_original(restored).unwrap()
  assert_eq(
    @publication.publication_contract_json(restored.run_definition),
    @publication.publication_contract_json(definition),
  )
  assert_eq(
    prepared_client_identity(restored.prepared),
    prepared_client_identity(prepared),
  )
  assert_false(physical_equal(restored.prepared, prepared))
  let original_graph = client_compiled_run_infer(original).unwrap()
  let restored_graph = client_compiled_run_infer(compiled).unwrap()
  assert_true(
    client_infer_plan_graph_matches(
      restored_graph,
      restored.prepared,
      restored_graph.execution,
    ),
  )
  assert_false(
    client_infer_plan_graph_matches(
      restored_graph,
      prepared,
      original_graph.execution,
    ),
  )
  assert_eq(
    client_infer_plan_graph_wire(restored_graph),
    client_infer_plan_graph_wire(original_graph),
  )
  assert_eq(
    @environment.model_task_identity(
      @environment.model_execution_task(restored_graph.execution),
    ),
    @environment.model_task_identity(
      @environment.model_execution_task(original_graph.execution),
    ),
  )
  assert_eq(
    @environment.model_execution_cid(restored_graph.execution),
    @environment.model_execution_cid(original_graph.execution),
  )
  assert_eq(client_compiled_run_infer_observation_policy(compiled), None)
  assert_true(
    issue_client_compiled_source_free_task_invocation(
      compiled,
      restored.run_definition,
      "sha256:" + "c".repeat(64),
      100000,
      10000,
      100,
    )
    is Err(_),
  )
}

///|
test "saved INFER materials refuse another Run and replaced original contract" {
  let (_, _, definition, wire) = infer_run_materials_fixture()
  let changed_run = wire.replace(
    old="original-model-run",
    new="foreign-model-run",
  )
  assert_true(changed_run != wire)
  assert_true(infer_run_materials_admit(changed_run, definition) is Err(_))
  for
    changed in [
      wire.replace(
        old="564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
        new="0".repeat(64),
      ),
      wire.replace(old="fixture-risk-model", new="current-other-model"),
      wire.replace(
        old="max_output_tokens\\\":32",
        new="max_output_tokens\\\":31",
      ),
      wire.replace(old="temperature\\\":0", new="temperature\\\":1"),
    ] {
    assert_true(changed != wire)
    assert_true(infer_run_materials_admit(changed, definition) is Err(_))
  }
}

///|
test "saved INFER materials do not enter legacy Values or ordinary Task readers" {
  let (_, _, definition, wire) = infer_run_materials_fixture()
  let cid = @publication.publication_contract_identity(definition)
  let expressions : @context.ExpressionProfiles = {
    text_time: false,
    veca: false,
  }
  let operations : @context.PureOperationProfiles = {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  }
  assert_true(
    admit_client_values_run_materials(
      wire,
      cid,
      expressions,
      operations,
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(MaterialsEvidence("infer_execution_contract")),
  )
  assert_true(
    admit_client_task_run_materials(
      wire,
      cid,
      expressions,
      operations,
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(Input(MaterialsEvidence("infer_execution_contract"))),
  )
  let missing = wire.replace(
    old="infer_execution_contract_cid",
    new="foreign_execution_contract_cid",
  )
  assert_true(
    infer_run_materials_admit(missing, definition)
    is Err(Input(MaterialsMalformed)),
  )
}

///|
test "saved INFER projection refuses foreign preparation and substituted Environment" {
  let (prepared, compiled, definition, _) = infer_run_materials_fixture()
  let (environment_wire, environment) = client_infer_prefix_test_environment()
  let writer = @encode.writer(65536, 8192, 64)
  @syntax.emit_program_source(prepared.source, writer)
  let program = @encode.finish(writer)
  let foreign = client_infer_prefix_test_program()
  assert_true(
    issue_client_infer_run_materials(
      { ..compiled, owner: foreign, },
      definition,
      environment,
      environment_wire,
      program,
      None,
      run_materials_limits(),
    )
    is Err(Binding(ForeignRun)),
  )
  let (changed_wire, changed) = client_infer_prefix_test_environment(
    host_items=999,
  )
  assert_true(
    issue_client_infer_run_materials(
      compiled,
      definition,
      changed,
      changed_wire,
      program,
      None,
      run_materials_limits(),
    )
    is Err(Input(MaterialsEnvironment)),
  )
}

///|
test "saved INFER projection refuses custom dependency graphs before material issuance" {
  let prepared = client_infer_prefix_test_program()
  let bounds = run_materials_limits()
  let custom = client_infer_material_test_graph(prepared)
  let compilation = issue_prepared_client_infer_compilation(
    prepared,
    custom,
    run_materials_manifests(),
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "original-model-scope", "original-model-run", "2026-10-01T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let (environment_wire, environment) = client_infer_prefix_test_environment()
  let writer = @encode.writer(65536, 8192, 64)
  @syntax.emit_program_source(prepared.source, writer)
  assert_true(
    issue_client_infer_run_materials(
      compiled,
      definition,
      environment,
      environment_wire,
      @encode.finish(writer),
      None,
      bounds,
    )
    is Err(Binding(UnsupportedProgram)),
  )
}
