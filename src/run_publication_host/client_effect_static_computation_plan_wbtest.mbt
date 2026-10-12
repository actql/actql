// Reuse the existing checked Salesforce-update fixture and compilation Owner.
// This fixture creates no allowed Run, publication, capture or Provider call.

///|
fn effect_static_computation_fixture() -> (
  PreparedClientEffectComputation,
  ClientEffectCompilation,
) {
  let (document, environment, limits) = local_update_normalization_fixture()
  let original = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let bounds = run_materials_limits()
  let compiled = issue_prepared_client_effect_compilation(
    original,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  (original, compiled)
}

///|
test "Effect computation static map uses the retained original compiler without a Run" {
  let (original, compiled) = effect_static_computation_fixture()
  assert_true(original.normalization is None)
  assert_true(original.normalization_custody is None)
  let first = client_effect_static_computation_plan_view(
    original, compiled, 65536, 4096, 64,
  ).unwrap()
  let second = client_effect_static_computation_plan_view(
    original, compiled, 65536, 4096, 64,
  ).unwrap()
  assert_eq(first, second)
  assert_true(original.normalization is None)
  assert_true(original.normalization_custody is None)
  let value = @publication.parse_interactive_run_control_shape(
    "plan_view", first, 65536, 4096, 64,
  ).unwrap()
  let definition = prepared_client_effect_identity(original).program_definition_cid
  guard @canonical.object_field(value, "compiled_plan_cid")
    is Some(@canonical.String(actual_plan_cid)) else {
    fail("static computation component lacks compiled Plan identity")
  }
  assert_eq(
    actual_plan_cid,
    @publication.publication_contract_identity(compiled.compiled.compiled_plan),
  )
  let map = @canonical.object_field(value, "logical_map").unwrap()
  guard @canonical.object_field(map, "program_definition_cid")
    is Some(@canonical.String(actual_definition)) else {
    fail("static computation component lacks original Program identity")
  }
  assert_eq(actual_definition, definition)
  let capabilities = @canonical.object_field(value, "capabilities").unwrap()
  assert_true(
    @canonical.object_field(capabilities, "inspect")
    is Some(@canonical.Bool(false)),
  )
  assert_true(
    @canonical.object_field(capabilities, "durable_control")
    is Some(@canonical.Bool(false)),
  )
  assert_true(first.contains("\"operator\":\"values\""))
  assert_true(first.contains("\"provider_io\":0"))
  assert_true(!first.contains("\"preview\""))
  assert_true(!first.contains("\"run_ref\""))
}

///|
test "Effect computation static map refuses an equal document from another prepared Owner" {
  let (original, compiled) = effect_static_computation_fixture()
  let (foreign, _) = effect_static_computation_fixture()
  assert_eq(
    prepared_client_effect_identity(original),
    prepared_client_effect_identity(foreign),
  )
  assert_eq(
    client_effect_static_computation_plan_view(
      foreign, compiled, 65536, 4096, 64,
    ),
    Err(ClientInteractivePlanIssue::ForeignCompilation),
  )
}

///|
test "Effect computation static map preserves finite read limits" {
  let (original, compiled) = effect_static_computation_fixture()
  assert_eq(
    client_effect_static_computation_plan_view(original, compiled, 0, 4096, 64),
    Err(InvalidReadLimits),
  )
  assert_eq(
    client_effect_static_computation_plan_view(
      original, compiled, 65536, 4096, 0,
    ),
    Err(InvalidReadLimits),
  )
  assert_eq(
    client_effect_static_computation_plan_view(
      original, compiled, 65536, -1, 64,
    ),
    Err(InvalidReadLimits),
  )
  assert_true(
    client_effect_static_computation_plan_view(original, compiled, 65536, 1, 64)
    is Err(_),
  )
  assert_true(
    client_effect_static_computation_plan_view(original, compiled, 64, 4096, 64)
    is Err(_),
  )
  assert_true(original.normalization is None)
}
