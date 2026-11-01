///|
fn restore_fixture(
  input : @input.LocalPreparedInput,
  original : LocalRunPlan,
  authority? : String = "sha256:" + "b".repeat(64),
  context? : String = context_cid(),
  policy? : String = "sha256:" + "c".repeat(64),
  current? : @authorization.AdmittedAccountConfiguration = account(Allow),
  allowed? : @authorization.DispatchAuthorization = permit(
    input,
    account(Allow),
  ),
) -> Result[LocalRunPlan, LocalRunIssue] {
  restore_source_free_local_run(
    input,
    export_local_run_materials(original, environment(), environment_wire, None).unwrap(),
    local_run_definition_cid(original),
    original.request,
    authority,
    allowed,
    current,
    tuple(),
    context,
    policy,
  )
}

///|
test "restoration retains the original execution Owner and separate authored provenance" {
  let text = "/*e\u0301/~😀*/\r\nWITH seed AS (SELECT 1 AS n) FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer"
  for original_input in [@input.Program(program), @input.Aql(text)] {
    let original = plan(prepared(original_input), "original-run")
    let fresh = prepared(original_input)
    let restored = restore_fixture(fresh, original).unwrap()
    assert_eq(
      local_run_definition_cid(restored),
      local_run_definition_cid(original),
    )
    assert_eq(
      @publication.publication_contract_json(restored.definition),
      @publication.publication_contract_json(original.definition),
    )
    assert_eq(
      @host.client_request_identity_relation(restored.request, original.request),
      @host.SameRequest,
    )
    assert_true(
      !physical_equal(restored.prepared, @input.local_prepared_program(fresh)),
    )
    assert_true(
      @host.bind_client_task_run(
        @input.local_prepared_program(fresh),
        restored.compilation,
        restored.admission,
        restored.definition,
      )
      is Err(@host.ForeignRun),
    )
    @host.bind_client_task_run(
      restored.prepared,
      restored.compilation,
      restored.admission,
      restored.definition,
    ).unwrap()
    |> ignore
    assert_eq(
      @host.client_task_compilation_result_names(restored.compilation),
      ["answer"],
    )
    match @input.local_prepared_original(restored.input) {
      Aql(original_text) => assert_eq(original_text, text)
      Program(original_json) => assert_eq(original_json, program)
    }
    let host = compute_host(restored)
    let run = local_compute_run(host)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
    assert_true(
      confirm_local_compute_start(
        host,
        restored.request,
        local_run_definition_cid(restored),
        false,
        true,
        false,
        false,
        permit(fresh, account(Allow)),
        account(Allow),
        tuple(),
        context_cid(),
      )
      is Err(StartNotPermitted),
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
    @strategy.stop_captured_dag(run)
    @strategy.refresh_captured_retention(run)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
      0L,
    )
  }
}

///|
test "restoration rejects current denial changed context policy and authority" {
  let input = prepared(@input.Program(program))
  let original = plan(input, "original-run")
  assert_true(
    restore_fixture(input, original, current=account(Deny))
    is Err(AuthorizationMismatch),
  )
  assert_true(
    restore_fixture(input, original, policy="sha256:" + "d".repeat(64))
    is Err(AuthorizationMismatch),
  )
  let changed_context = "sha256:" + "e".repeat(64)
  let allowed = @authorization.bind_dispatch_authorization(
    account(Allow),
    tuple(),
    Activation,
    @host.prepared_client_identity(@input.local_prepared_program(input)).program_definition_cid,
    changed_context,
  ).unwrap()
  assert_true(
    restore_fixture(input, original, context=changed_context, allowed~)
    is Err(AuthorizationMismatch),
  )
  assert_true(
    restore_fixture(input, original, authority="sha256:" + "f".repeat(64))
    is Err(Start(@host.DifferentRequest)),
  )
}

///|
test "foreign input and definition cannot replace the original restored Run" {
  let input = prepared(@input.Program(program))
  let original = plan(input, "original-run")
  let changed = prepared(
    @input.Program(
      program.replace(old="python.local.structured", new="other.program"),
    ),
  )
  assert_true(
    restore_fixture(changed, original, allowed=permit(changed, account(Allow)))
    is Err(Materials(@host.RunMismatch)),
  )
  let wire = export_local_run_materials(
    original,
    environment(),
    environment_wire,
    None,
  ).unwrap()
  assert_true(
    restore_source_free_local_run(
      input,
      wire,
      "sha256:" + "0".repeat(64),
      original.request,
      "sha256:" + "b".repeat(64),
      permit(input, account(Allow)),
      account(Allow),
      tuple(),
      context_cid(),
      "sha256:" + "c".repeat(64),
    )
    is Err(Materials(@host.RunMismatch)),
  )
}

///|
test "assembled material fields cannot substitute an equivalent checked Owner" {
  let input = prepared(@input.Program(program))
  let original = plan(input, "original-run")
  let wire = export_local_run_materials(
    original,
    environment(),
    environment_wire,
    None,
  ).unwrap()
  let owned = restore_local_run_materials(
    wire,
    local_run_definition_cid(original),
  ).unwrap()
  let assembled : @host.ClientTaskRunMaterials = {
    prepared: @input.local_prepared_program(input),
    compilation: owned.compilation,
    admission: owned.admission,
    run_definition: owned.run_definition,
    retained_input: @host.client_task_run_materials_retained_input(owned),
  }
  assert_true(
    restore_source_free_local_run_from_materials(
      input,
      assembled,
      local_run_definition_cid(original),
      original.request,
      "sha256:" + "b".repeat(64),
      permit(input, account(Allow)),
      account(Allow),
      tuple(),
      context_cid(),
      "sha256:" + "c".repeat(64),
    )
    is Err(Materials(@host.Binding(@host.ForeignRun))),
  )
  let changed = prepared(
    @input.Program(
      program.replace(old="python.local.structured", new="other.program"),
    ),
  )
  let changed_request = @host.prepare_source_free_client_request_identity(
    @input.local_prepared_program(changed),
    "sha256:" + "b".repeat(64),
    "original-submission",
  ).unwrap()
  assert_true(
    restore_source_free_local_run_from_materials(
      input,
      owned,
      local_run_definition_cid(original),
      changed_request,
      "sha256:" + "b".repeat(64),
      permit(input, account(Allow)),
      account(Allow),
      tuple(),
      context_cid(),
      "sha256:" + "c".repeat(64),
    )
    is Err(Start(@host.ChangedIntent)),
  )
}
