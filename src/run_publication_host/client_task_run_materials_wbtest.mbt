///|
test "task materials retain their actual prepared input and reject a copied owner" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = run_materials_limits()
  let prepared = prepare_effect_free_client_program(
    run_materials_document,
    Json,
    environment,
    None,
    limits.preparation,
  ).unwrap()
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_eq(client_compiled_run_has_infers(compiled), false)
  assert_eq(
    client_compiled_run_has_infers(compiled),
    !client_compiled_run_infers(compiled).is_empty(),
  )
  let definition = issue_client_compiled_run_definition(
    compiled, "retained-scope", "retained-run", "2026-11-01T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let wire = issue_client_task_run_materials(
    prepared,
    compilation,
    client_compiled_run_admission(compiled),
    definition,
    environment,
    run_materials_environment_wire,
    run_materials_document,
    None,
  ).unwrap()
  let admitted = admit_client_task_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    limits,
  ).unwrap()
  let input = client_task_run_materials_retained_input(admitted)
  assert_true(
    physical_equal(
      client_task_run_materials_retained_program(input),
      admitted.prepared,
    ),
  )
  assert_eq(input.materials_wire, wire)
  assert_eq(
    client_task_run_materials_retained_document(input),
    run_materials_document,
  )
  assert_eq(
    client_task_run_materials_retained_environment(input),
    run_materials_environment_wire,
  )
  assert_eq(client_task_run_materials_retained_parameters(input), None)
  assert_true(client_task_run_materials_compiled_original(admitted) is Ok(_))
  // The issuer's independently prepared equal identity is not the codec's
  // actual checked owner, even though its Program and parameters match.
  assert_eq(
    prepared_client_identity(prepared),
    prepared_client_identity(admitted.prepared),
  )
  assert_true(
    client_task_run_materials_compiled_original({ ..admitted, prepared, })
    is Err(ForeignOwner),
  )
}
