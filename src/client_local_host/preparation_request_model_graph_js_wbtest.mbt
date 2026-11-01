///|
// Reuse the existing independent execution-contract vector, without issuing
// a Graph before the Request's new construction reservation.
fn request_model_graph_inputs(
  prepared : @publication_host.PreparedClientProgram,
) -> (
  @publication_host.ClientInferOccurrence,
  @environment.ModelExecutionContract,
) {
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let execution_wire =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da","version":"actql-model-execution-contract/0.1"}
  let execution = @publication_host.read_client_infer_occurrence_model_execution(
    occurrence,
    @utf8.encode(execution_wire),
    "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  (occurrence, execution)
}

///|
test "Model Graph keeps the same Request capacity and original through sourcefree or two-capture compilation" {
  for captured in [false, true] {
    let (parent, input, prepared) = request_model_input_fixture(captured~)
    let holder = borrow_request_model_plan_input(parent, input).unwrap()
    let (occurrence, execution) = request_model_graph_inputs(prepared)
    let contracts = request_program_module_contracts()
    let manifests = request_program_module_manifests()
    let limits = @publication_host.client_standard_pure_compilation_limits()
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let graph = prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      contracts,
      manifests~,
      compilation_limits=limits,
    ).unwrap()
    assert_true(
      @publication_host.client_infer_occurrence_matches_plan(occurrence, graph),
    )
    let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    assert_true(after.0 > before.0 && after.1 > before.1)
    assert_true(
      parent.program_domain_compilation_inputs
      is Some(RequestModelGraph(_, _, _, original)) &&
      physical_equal(original, graph),
    )
    assert_true(
      prepare_request_model_graph(
        parent,
        input,
        occurrence,
        execution,
        contracts,
        manifests~,
        compilation_limits=limits,
      )
      is Err(Preparation(ForeignOriginal)),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
      after,
    )
    let compilation = prepare_request_model_compilation(
      parent,
      input,
      graph,
      contracts,
      manifests~,
      compilation_limits=limits,
    ).unwrap()
    assert_true(
      @publication_host.client_task_compilation_infer(compilation)
      is Some(original) &&
      physical_equal(original, graph),
    )
    assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Model Graph original-current refusal leaves no component and retains same Request cleanup" {
  let armed = Ref(false)
  let calls = Ref(0)
  let (parent, input, prepared) = request_model_input_fixture(current=() => {
    if armed.val {
      calls.val += 1
      false
    } else {
      true
    }
  })
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let contracts = request_program_module_contracts()
  let before = request_preparation_accounting(parent)
  armed.val = true
  assert_true(
    prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      contracts,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_true(
    calls.val > 0 &&
    parent.phase == ProgramBodyFailed &&
    parent.program_domain_compilation_inputs is None &&
    parent.program_compilation is None,
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
