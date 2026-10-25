///|
test "compiled Run original definition projection never binds or accepts same CID replacement" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = run_materials_limits()
  let issuer_prepared = prepare_effect_free_client_program(
    run_materials_document,
    Json,
    environment,
    None,
    limits.preparation,
  ).unwrap()
  let issuer_compilation = issue_prepared_client_values_compilation(
    issuer_prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let execution_context = "sha256:" + "a".repeat(64)
  let host_policy = "sha256:" + "b".repeat(64)
  let allowed = issue_client_values_compiled_run(
    issuer_prepared, issuer_compilation, execution_context, host_policy, "2099-01-01T00:00:00.000Z",
  ).unwrap()

  let unbound = issue_client_values_compiled_run(
    issuer_prepared, issuer_compilation, execution_context, host_policy, "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let issued = issue_client_compiled_run_definition(
    allowed, "cloud-scope", "cloud-run-1", "2026-09-30T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(unbound.definition_binding is None)
  assert_false(client_compiled_run_has_original_definition(unbound, issued))
  assert_true(unbound.definition_binding is None)
  assert_true(client_compiled_run_has_original_definition(allowed, issued))
  let copied = @publication.admit_publication_contract(
    "run_definition",
    @publication.publication_contract_json(issued),
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(copied),
    @publication.publication_contract_identity(issued),
  )
  assert_false(physical_equal(copied, issued))
  assert_false(client_compiled_run_has_original_definition(allowed, copied))
  assert_true(client_compiled_run_has_original_definition(allowed, issued))
}
