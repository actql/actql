///|
// Original compiler, invocation, module and Resource lifetime only. Factory
// and capture ports are explicit; no provider IO or physical ACK is observed.
struct RequestInvocationFixture {
  parent : ClientRequestPreparation[Array[Int]]
  input : Array[Int]
  prepared : @publication_host.PreparedClientProgram
  contracts : ClientInstalledSequenceContracts
  artifact : @publication_host.ClientRunCompilation
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  request : @publication_host.ClientRequestIdentity
  time : @publication_host.ClientQueryTimePreparation
  held : @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram]
  factory : (@execution.ExecutionCapacity) -> Array[@local.ManagedProvider]
  calls : Ref[Int]
  current_calls : Ref[Int]
}

///|
fn request_invocation_issue_run(
  prepared : @publication_host.PreparedClientProgram,
  artifact : @publication_host.ClientRunCompilation,
) -> @publication_host.ClientCompiledRun {
  match artifact {
    @publication_host.Values(value) =>
      @publication_host.issue_client_values_compiled_run(
        prepared, value, "sha256:" + "a".repeat(64), "sha256:" + "b".repeat(64),
        "2027-01-01T00:00:00.000Z",
      ).unwrap()
    @publication_host.Tasks(value) =>
      @publication_host.issue_client_task_compiled_run(
        prepared, value, "sha256:" + "a".repeat(64), "sha256:" + "b".repeat(64),
        "2027-01-01T00:00:00.000Z",
      ).unwrap()
    _ => abort("Pure original compilation required")
  }
}

///|
fn request_invocation_fixture(captured? : Bool = false) -> RequestInvocationFixture raise {
  let current_calls = Ref(0)
  let current = () => {
    current_calls.val += 1
    true
  }
  let source_free_document =
    #|{"version":"actql/0.1","id":"request-clock","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"stamp":"current_timestamp()"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","stamp"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let captured_document =
    #|{"version":"actql/0.1","id":"request-source-clock","stages":[{"id":"main","inputs":{"remote":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"filter":"current_timestamp() = current_timestamp()"},{"select":["id","amount"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let (parent, input, prepared) = if captured {
    request_capture_fixture(document=captured_document, current~)
  } else {
    let (parent, check, _, input) = registration_parent_fixture(text=source_free_document, current~)
    finish_program_check_preparation(check).unwrap() |> ignore
    let prepared = compile_program_check_preparation(
      check, @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    continue_request_program_preparation(parent, input).unwrap() |> ignore
    (parent, input, prepared)
  }
  assert_true(@publication_host.prepared_client_requires_query_time(
    prepared, 100000, 10000,
  ).unwrap())
  let held = borrow_request_program_plan_input(parent, input).unwrap()
  let contracts = if captured {
    prepare_installed_sequence_contracts(
      source_query_original_registry, source_query_original_values,
      Some(source_query_original_fragment), None,
    ).unwrap()
  } else {
    request_program_module_contracts()
  }
  let calls = Ref(0)
  let factory = (_ : @execution.ExecutionCapacity) => {
    calls.val += 1
    []
  }
  let artifact = prepare_request_program_compilation(
    parent, input, contracts, manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true, provider_factory=factory,
  ).unwrap()
  let compiled = request_invocation_issue_run(prepared, artifact)
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-invocation", "same-original", "2026-10-31T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared, "sha256:" + "a".repeat(64), "request-invocation",
  ).unwrap()
  let time = @publication_host.prepare_client_query_time(
    prepared, request, "2026-10-31T00:00:00.000Z",
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    time, prepared, compiled, definition, request,
  ).unwrap() |> ignore
  { parent, input, prepared, contracts, artifact, compiled, definition, request,
    time, held, factory, calls, current_calls, }
}

///|
fn request_invocation_capture_plan(
  f : RequestInvocationFixture,
) -> ClientInstalledManagedCapturePlan {
  let requirement = prepare_local_query_requirement_at_query_time(
    f.prepared, 0, 0, f.time, f.request, f.contracts,
    source_query_original_values, Some(source_query_original_fragment), None,
  ).unwrap()
  let capture = installed_row_capture_capacity(
    original_row_acquisition_fixture(requirement),
  ).unwrap()
  let plan = prepare_installed_managed_capture_plan(
    f.prepared, f.request, [capture], [4096L], [2048L], f.contracts,
    source_query_original_values, Some(source_query_original_fragment), None,
    retained_output=true, provider_factory=f.factory, query_time=Some(f.time),
  ).unwrap()
  plan
}

///|
test "ordinary invocation binds the same compiler Request time and module through Run retirement" {
  for captured in [false, true] {
    let f = request_invocation_fixture(captured~)
    let spent = f.parent.program_artifact_work_spent
    assert_eq(f.calls.val, 0)
    let invocation = Some((f.time, f.request, f.compiled, f.definition))
    let plan = if captured {
      let plan = request_invocation_capture_plan(f)
      prepare_request_capture_module_body(
        f.parent, f.input, plan, manifests=request_program_module_manifests(),
        compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
        provider_factory=f.factory, invocation~,
      ).unwrap()
      Some(plan)
    } else {
      assert_true(@publication_host.client_query_time_preparation_context(f.time) is Some(_))
      prepare_request_program_module_body(
        f.parent, f.input, f.contracts, manifests=request_program_module_manifests(),
        compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
        retained_output=true, provider_factory=f.factory, invocation~,
      ).unwrap()
      None
    }
    let expected = @publication_host.client_query_time_preparation_context(f.time).unwrap()
    let sequences = match plan {
      Some(value) => value.sequences
      None => f.parent.program_source_free.unwrap().sequences
    }
    for sequence in sequences {
      assert_true(@execution.generated_sequence_query_time(sequence) is Some(actual) &&
        physical_equal(actual, expected))
    }
    assert_eq(f.calls.val, 1)
    assert_eq(f.parent.program_artifact_work_spent, spent)
    if !captured {
      let copied = @publication_host.prepare_source_free_client_request_identity(
        f.prepared, "sha256:" + "a".repeat(64), "request-invocation",
      ).unwrap()
      assert_true(begin_request_program_managed_run(f.parent, copied) is Err(ForeignOriginal))
    }
    let run = if captured {
      begin_request_capture_managed_run(f.parent, f.request).unwrap()
    } else {
      begin_request_program_managed_run(f.parent, f.request).unwrap()
    }
    assert_true(physical_equal(
      installed_managed_run_compilation_original(run, f.prepared).unwrap(), f.artifact,
    ))
    let observed_current = f.current_calls.val
    for _ in 0..<4 {
      guard installed_managed_run_invocation_original(run, f.prepared)
        is Some((time, request, compiled, definition)) else {
        fail("Expected the original timed invocation")
      }
      assert_true(physical_equal(time, f.time))
      assert_true(physical_equal(request, f.request))
      assert_true(physical_equal(compiled, f.compiled))
      assert_true(physical_equal(definition, f.definition))
    }
    assert_eq(f.current_calls.val, observed_current)
    assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
    let retiring_current = f.current_calls.val
    assert_true(installed_managed_run_invocation_original(run, f.prepared) is None)
    assert_eq(f.current_calls.val, retiring_current)
    // This already retained invocation does not authorize another Run borrow.
    assert_true(@publication_host.client_query_time_preparation_context_for_run(
      f.time, f.prepared, f.compiled, f.definition, f.request,
    ) is Ok(_))
    @resources.return_preparation_body_borrow(f.held).unwrap() |> ignore
    retire_installed_managed_run(run).unwrap()
    assert_true(installed_managed_run_invocation_original(run, f.prepared) is None)
    assert_eq(f.parent.program_artifact_work_spent, spent)
    assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  }
}

///|
test "ordinary invocation refuses a copied Request before its factory and keeps spent work" {
  let f = request_invocation_fixture()
  let copied = @publication_host.prepare_source_free_client_request_identity(
    f.prepared, "sha256:" + "a".repeat(64), "request-invocation",
  ).unwrap()
  let spent = f.parent.program_artifact_work_spent
  assert_true(prepare_request_program_module_body(
    f.parent, f.input, f.contracts, manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true, provider_factory=f.factory,
    invocation=Some((f.time, copied, f.compiled, f.definition)),
  ) is Err(QueryTime(ForeignRequest)))
  assert_eq(f.calls.val, 0)
  assert_true(f.parent.program_compilation is Some(_))
  assert_eq(f.parent.program_artifact_work_spent, spent)
  @resources.return_preparation_body_borrow(f.held).unwrap() |> ignore
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(f.parent.program_artifact_work_spent, spent)
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "ordinary invocation refuses another Definition and never binds an unbound time" {
  for unbound in [false, true] {
    let f = request_invocation_fixture()
    let time = if unbound {
      @publication_host.prepare_client_query_time(
        f.prepared, f.request, "2026-10-31T00:00:00.000Z",
      ).unwrap()
    } else {
      f.time
    }
    let definition = if unbound {
      f.definition
    } else {
      @publication_host.issue_client_compiled_run_definition(
        f.compiled, "request-invocation", "different-original",
        "2026-10-31T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
      ).unwrap()
    }
    assert_true(prepare_request_program_module_body(
      f.parent, f.input, f.contracts, manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true, provider_factory=f.factory,
      invocation=Some((time, f.request, f.compiled, definition)),
    ) is Err(QueryTime(ForeignRun)))
    assert_eq(f.calls.val, 0)
    if unbound {
      assert_true(@publication_host.client_query_time_preparation_context(time) is None)
    }
    @resources.return_preparation_body_borrow(f.held).unwrap() |> ignore
    abort_request_preparation_after_cleanup(f.parent).unwrap()
    assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  }
}

///|
test "ordinary invocation refuses independently compiled equal Plan bytes" {
  let f = request_invocation_fixture()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let manifests = request_program_module_manifests()
  let sequence = @publication_host.prepared_client_values_sequence_limits(f.prepared)
  let independent = match f.artifact {
    @publication_host.Values(_) => @publication_host.Values(
      @publication_host.issue_prepared_client_values_compilation(
        f.prepared, manifests, sequence, limits.max_facts, limits.max_witnesses,
        limits.max_wire_bytes, limits.max_nodes, limits.max_depth,
      ).unwrap(),
    )
    @publication_host.Tasks(_) => @publication_host.Tasks(
      @publication_host.issue_prepared_client_task_compilation(
        f.prepared, manifests, sequence, limits.max_facts, limits.max_witnesses,
        limits.max_wire_bytes, limits.max_nodes, limits.max_depth,
      ).unwrap(),
    )
    _ => abort("Pure original required")
  }
  let wire = (artifact : @publication_host.ClientRunCompilation) => match artifact {
    @publication_host.Values(original) => @publication_host.client_values_executable_plan_wire(
      @publication_host.client_values_compilation_plan(original),
    )
    @publication_host.Tasks(original) => @publication_host.client_task_executable_plan_wire(
      @publication_host.client_task_compilation_plan(original),
    )
    _ => abort("Pure original required")
  }
  assert_eq(wire(independent), wire(f.artifact))
  let compiled = request_invocation_issue_run(f.prepared, independent)
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-invocation", "same-original", "2026-10-31T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let time = @publication_host.prepare_client_query_time(
    f.prepared, f.request, "2026-10-31T00:00:00.000Z",
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    time, f.prepared, compiled, definition, f.request,
  ).unwrap() |> ignore
  assert_false(@publication_host.client_compiled_run_matches_pure_compilation(
    compiled, f.prepared, f.artifact,
  ))
  assert_true(prepare_request_program_module_body(
    f.parent, f.input, f.contracts, manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=true, provider_factory=f.factory,
    invocation=Some((time, f.request, compiled, definition)),
  ) is Err(Preparation(ForeignOriginal)))
  assert_eq(f.calls.val, 0)
  @resources.return_preparation_body_borrow(f.held).unwrap() |> ignore
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "captured bound invocation cannot use an omitted module handoff" {
  let f = request_invocation_fixture(captured=true)
  let plan = request_invocation_capture_plan(f)
  let spent = f.parent.program_artifact_work_spent
  assert_eq(f.calls.val, 1)
  assert_true(prepare_request_capture_module_body(
    f.parent, f.input, plan, manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    provider_factory=f.factory,
  ) is Err(Preparation(WrongPhase)))
  assert_eq(f.calls.val, 1)
  assert_eq(f.parent.program_artifact_work_spent, spent)
  @resources.return_preparation_body_borrow(f.held).unwrap() |> ignore
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}
