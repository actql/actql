///|
test "Effect run materials preserve original evidence and reject replaced identity" {
  let (document, environment, effect_limits) = client_composed_effect_base_fixture()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    effect_limits,
  ).unwrap()
  let limits = run_materials_limits()
  let manifests = run_materials_manifests()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "original-scope", "original-effect-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  // A zero-input Effect remains external uncertainty, not local stop proof.
  let compiled = client_effect_allowed_component_run(allowed, None)
  check_client_compiled_run_definition(compiled, definition).unwrap()
  assert_eq(prepared_client_acquisition_count(compiled.owner), 0)
  assert_false(client_compiled_local_execution_owner(compiled, definition))
  let environment_writer = @encode.writer(65536, 4096, 64)
  @environment.emit(
    @checked.checking_environment_wire(environment),
    environment_writer,
  )
  let environment_wire = @encode.finish(environment_writer)
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-effect-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let request_wire = client_request_identity_record_wire(request).unwrap()
  assert_eq(
    admit_client_request_identity_record_wire(request_wire).unwrap(),
    request,
  )
  let wire = issue_client_effect_run_materials(
    allowed,
    definition,
    environment,
    environment_wire,
    document,
    None,
    effect_limits,
    request=Some(request),
  ).unwrap()
  // Selection is syntactic, before semantic admission by the chosen Owner.
  assert_true(
    inspect_client_run_materials_execution_family(
      wire,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      limits.preparation,
    )
    is Ok(EffectComputation),
  )
  let definition_cid = @publication.publication_contract_identity(definition)
  let restored = admit_client_effect_run_materials(
    wire,
    definition_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    manifests,
    limits,
    effect_limits,
  ).unwrap()
  assert_eq(restored.request, Some(request))
  let receipt_bindings = client_effect_run_receipt_bindings(
    restored, 65536, 4096, 64,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(receipt_bindings),
    "sha256:5400e202cc7c63c3b757399f3a694b413f7b717ce58aa887cc156c6a39aab67f",
  )
  assert_eq(
    @publication.run_evidence_value_json(receipt_bindings),
    "{\"bindings\":{},\"invocation_bindings_cid\":\"sha256:5400e202cc7c63c3b757399f3a694b413f7b717ce58aa887cc156c6a39aab67f\",\"version\":\"actql-invocation-bindings/0.1\"}",
  )
  // Equal serialized Program bytes do not replace the original checked Owner.
  assert_true(
    client_effect_run_receipt_bindings(
      { ..restored, prepared, },
      65536,
      4096,
      64,
    )
    is Err(ForeignMaterials),
  )
  assert_true(
    client_effect_run_receipt_bindings(restored, 0, 4096, 64)
    is Err(Bindings(Evidence(_))),
  )
  assert_eq(
    issue_client_effect_run_materials(
      restored.allowed,
      restored.run_definition,
      environment,
      environment_wire,
      document,
      None,
      effect_limits,
      request=restored.request,
    ).unwrap(),
    wire,
  )
  for
    altered in [
      request_wire.replace(old="original-effect-caller", new="different-caller"),
      request_wire.replace(
        old="sha256:" + "c".repeat(64),
        new="sha256:" + "d".repeat(64),
      ),
      "{}",
      request_wire.unsafe_substring(start=0, end=request_wire.length() - 1) +
      ",\"extra\":true}",
    ] {
    assert_true(admit_client_request_identity_record_wire(altered) is Err(_))
  }
  assert_eq(
    @publication.publication_contract_json(restored.run_definition),
    @publication.publication_contract_json(definition),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      client_effect_allowed_run_prepared(restored.allowed),
    ),
    @publication.run_evidence_value_json(
      client_effect_allowed_run_prepared(allowed),
    ),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      client_effect_allowed_run_authorization(restored.allowed),
    ),
    @publication.run_evidence_value_json(
      client_effect_allowed_run_authorization(allowed),
    ),
  )
  assert_eq(
    prepared_client_effect_identity(restored.prepared),
    prepared_client_effect_identity(prepared),
  )
  assert_true(
    bind_client_effect_compiled_run(
      restored.prepared,
      restored.allowed,
      restored.run_definition,
    )
    is Ok(_),
  )
  // The receiving Owner is reconstructed, not the process-local sender handle.
  assert_false(physical_equal(restored.prepared, prepared))
  let changed = wire.replace(old="original-effect-run", new="other-effect-run")
  // Family selection does not turn a changed Run into an admitted Run.
  assert_true(
    inspect_client_run_materials_execution_family(
      changed,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      limits.preparation,
    )
    is Ok(EffectComputation),
  )

  assert_true(
    admit_client_effect_run_materials(
      changed,
      definition_cid,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      manifests,
      limits,
      effect_limits,
    )
    is Err(RunMismatch),
  )
  let changed_program = document.replace(old="\"save\":", new="\"other\":")
  assert_true(
    issue_client_effect_run_materials(
      allowed,
      definition,
      environment,
      environment_wire,
      changed_program,
      None,
      effect_limits,
    )
    is Err(RunMismatch),
  )
  assert_true(
    admit_client_effect_run_materials(
      "{}",
      definition_cid,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      manifests,
      limits,
      effect_limits,
    )
    is Err(Input(MaterialsMalformed)),
  )
}

///|
test "acquired Effect run materials retain the original two-task graph" {
  let document =
    #|{"version":"actql/0.1","id":"acquired-effect-materials","stages":[{"id":"source","inputs":{"table":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount"]}}},{"id":"apply","inputs":{"input":{"result":{"stage":"source","result":"rows"}}},"steps":[{"derive":{"value":{"literal":1}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"answer":{"from":{"stage":"apply","result":"out"}}}}
  let environment = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let (_, _, base_limits) = client_composed_effect_base_fixture()
  let effect_limits = {
    ..base_limits,
    program: client_standard_program_preparation_limits(),
  }
  let limits = run_materials_limits()
  let manifests = run_materials_manifests()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    effect_limits,
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "original-scope", "original-acquired-effect-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let wire = issue_client_effect_run_materials(
    allowed,
    definition,
    environment,
    local_normalization_environment_wire,
    document,
    None,
    effect_limits,
  ).unwrap()
  let restored = admit_client_effect_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    manifests,
    limits,
    effect_limits,
  ).unwrap()
  assert_true(restored.request is None)
  let graph = @strategy.checked_effect_computation_graph(
    prepared_client_effect_computation_graph(restored.prepared),
  )
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(
    prepared_client_effect_identity(restored.prepared),
    prepared_client_effect_identity(prepared),
  )
}
