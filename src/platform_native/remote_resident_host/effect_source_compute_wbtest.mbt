///|
fn resident_effect_bound_run_fixture() -> @host.PreparedClientEffectRun {
  let prepared = resident_effect_source_prepared()
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_effect_run_definition(
    allowed, "resident-effect", "original-effect-run", "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  @host.bind_client_effect_compiled_run(prepared, allowed, definition).unwrap()
}

///|
test "resident Effect Source uses the original bound two-task graph" {
  let bound = resident_effect_bound_run_fixture()
  let owner = Effect(bound)
  assert_true(resident_source_owner_supported(owner))
  let graph = resident_source_owner_graph(owner)
  assert_true(@strategy.graph_program_has_effects(graph))
  assert_false(resident_linear_graph(graph))
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_true(
    physical_equal(
      graph,
      @strategy.checked_effect_run_graph(
        @host.prepared_client_effect_run_graph(bound),
      ),
    ),
  )
  // This boundary has neither a physical Source nor an approval/write port.
  let prepared = @host.prepared_client_effect_run_computation(bound)
  let sequences = @local.prepare_client_effect_local_sequences(
    prepared,
    resident_effect_installed_contracts(),
    resident_effect_source_values,
    Some(resident_effect_source_fragment),
    None,
  ).unwrap()
  assert_eq(sequences.length(), 2)
}

///|
test "resident ordinary Source keeps the existing checked owner" {
  let (_, _, _, _, prepared) = resident_source_dispatch_fixture()
  let owner = Pure(prepared)
  assert_true(resident_source_owner_supported(owner))
  assert_true(
    physical_equal(
      resident_source_owner_graph(owner),
      @host.prepared_client_graph(prepared),
    ),
  )
}
