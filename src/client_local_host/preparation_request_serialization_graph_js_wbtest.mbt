///|
let request_graph_policy_cid : String = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"

///|
let request_graph_policy_wire : String =
  #|{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}

///|
fn request_content_graph_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
) raise {
  let (parent, child, _, input) = registration_parent_fixture(
    text=request_serialization_document,
    current~,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("authored Serialization must check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  (parent, input, prepared, holder)
}

///|
test "same Request reserves Content Graph before issuer and transfers original component into its compiler" {
  let (parent, input, prepared, holder) = request_content_graph_fixture()
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let graph = prepare_request_serialization_graph(
    parent,
    input,
    0,
    1,
    request_graph_policy_cid,
    request_graph_policy_wire,
    2,
    128,
    true,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(
    parent.program_domain_quote is None && parent.phase == ContentPlanReserved,
  )
  assert_true(
    parent.program_domain_compilation_inputs
    is Some(RequestSerializationGraph(_, _, _, original)) &&
    physical_equal(original, graph),
  )
  assert_true(physical_equal(graph.owner, prepared))
  // Once selected, even equal arguments cannot allocate a replacement Graph.
  assert_true(
    prepare_request_serialization_graph(
      parent,
      input,
      0,
      1,
      request_graph_policy_cid,
      request_graph_policy_wire,
      2,
      128,
      true,
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
  let compilation = prepare_request_serialization_compilation(
    parent,
    input,
    graph,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  assert_true(
    parent.program_invocation_quote is Some((r, e)) &&
    @resources.preparation_capacity_working_extents(capacity, input) ==
    Ok((r, e)),
  )
  assert_true(
    physical_equal(
      @publication_host.client_task_compilation_serialization(compilation).unwrap(),
      graph,
    ),
  )
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Content Graph current refusal fences reentry before policy and original Graph construction" {
  let armed = Ref(false)
  let observed = Ref(false)
  let original : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let again : Ref[
    (() -> Result[
      @publication_host.ClientSerializationPlanGraph,
      ClientRequestProgramPlanIssue,
    ])?,
  ] = Ref(None)
  let (parent, input, _, holder) = request_content_graph_fixture(current=() => {
    if armed.val {
      let owner = original.val.unwrap()
      observed.val = owner.phase == Selecting &&
        owner.program_domain_compilation_inputs is None &&
        again.val.unwrap()() is Err(Preparation(ForeignOriginal)) &&
        abort_request_preparation_after_cleanup(owner) is Err(WrongPhase)
      false
    } else {
      true
    }
  })
  original.val = Some(parent)
  let contracts = request_program_module_contracts()
  let run = () => {
    prepare_request_serialization_graph(
      parent,
      input,
      0,
      1,
      request_graph_policy_cid,
      request_graph_policy_wire,
      2,
      128,
      true,
      contracts,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    )
  }
  again.val = Some(run)
  let before = request_preparation_accounting(parent)
  armed.val = true
  assert_true(run() is Err(Preparation(Capacity(_))))
  armed.val = false
  assert_true(observed.val && parent.phase == ProgramBodyFailed)
  assert_true(
    parent.program_domain_compilation_inputs is None &&
    parent.program_compilation is None,
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_true(run() is Err(Preparation(ForeignOriginal)))
  again.val = None
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Content Graph foreign input cannot grow and invalid original policy retains only the same failed Request" {
  let (parent, input, _, holder) = request_content_graph_fixture()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let before = request_preparation_accounting(parent)
  assert_true(
    prepare_request_serialization_graph(
      parent,
      [1],
      0,
      1,
      request_graph_policy_cid,
      request_graph_policy_wire,
      2,
      128,
      true,
      contracts,
      manifests~,
      compilation_limits=limits,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_true(
    prepare_request_serialization_graph(
      parent,
      input,
      0,
      1,
      "sha256:" + "f".repeat(64),
      request_graph_policy_wire,
      2,
      128,
      true,
      contracts,
      manifests~,
      compilation_limits=limits,
    )
    is Err(SerializationGraph(Policy(_))),
  )
  assert_true(
    parent.phase == ProgramBodyFailed &&
    parent.program_compilation is None &&
    parent.program_domain_compilation_inputs is None,
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
