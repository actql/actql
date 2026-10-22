///|
fn source_free_composed_infer_materials_fixture() -> (
  ClientCompiledRun,
  @publication.PublicationContract,
  @checked.CheckEnvironment,
  String,
) raise {
  let prepared = client_infer_prefix_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let bounds = run_materials_limits()
  let component = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    client_infer_graph_test_execution(prepared, occurrence=Some(occurrence)),
    bounds.sequence,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compilation = issue_prepared_client_multi_infer_compilation(
    prepared,
    [component],
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  assert_true(compilation.infer is None)
  assert_eq(prepared_client_infer_step(prepared), Some(2))
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "source-free-original-scope", "source-free-composed-run", "2026-10-01T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let (environment_wire, environment) = client_infer_prefix_test_environment()
  let writer = @encode.writer(65536, 8192, 64)
  @syntax.emit_program_source(prepared.source, writer)
  let program = @encode.finish(writer)
  let writer = @encode.writer(65536, 4096, 64)
  @syntax.emit_admitted_source_value(
    @environment.model_execution_source(component.execution),
    writer,
  )
  // The existing input codec records these actual original compiled materials.
  // This avoids relying on the issuer under test to prepare the reader case.
  let wire = issue_client_run_materials_input(
    prepared,
    compiled.admission,
    definition,
    environment,
    environment_wire,
    program,
    None,
    infer_input=Some(
      (
        @environment.model_execution_cid(component.execution),
        @encode.finish(writer),
      ),
    ),
  ).unwrap()
  (compiled, definition, environment, wire)
}

///|
test "source-free composed INFER materials preserve the actual compiler mode on issuance" {
  let (compiled, definition, environment, expected) = source_free_composed_infer_materials_fixture()
  let wire = issue_prepared_client_infer_run_materials(
    compiled,
    definition,
    environment,
    None,
    run_materials_limits(),
  ).unwrap()
  assert_eq(wire, expected)
}

///|
test "source-free composed INFER materials restore only the original complete Run" {
  let (compiled, definition, _, wire) = source_free_composed_infer_materials_fixture()
  let restored = infer_run_materials_admit(wire, definition).unwrap()
  let inverse = client_task_run_materials_compiled_original(restored).unwrap()
  guard inverse.compilation is Tasks(compilation) else {
    fail("saved task compiler original")
  }
  assert_true(compilation.infer is None)
  assert_eq(
    client_compiled_run_infers(inverse)[0].graph.wire,
    client_compiled_run_infers(compiled)[0].graph.wire,
  )
  assert_eq(
    @publication.publication_contract_json(restored.run_definition),
    @publication.publication_contract_json(definition),
  )
  assert_false(physical_equal(restored.prepared, compiled.owner))
  for
    changed in [
      wire.replace(old="source-free-composed-run", new="foreign-composed-run"),
      wire.replace(old="hello", new="foreign-input"),
      wire.replace(old="fixture-risk-model", new="foreign-model"),
    ] {
    assert_true(changed != wire)
    assert_true(infer_run_materials_admit(changed, definition) is Err(_))
  }
}
