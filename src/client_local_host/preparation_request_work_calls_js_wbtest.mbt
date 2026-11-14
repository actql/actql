///|
test "Request actual work calls distinguish checking compilation getters and retired scalar history" {
  let (environment, publication) = request_query_publication_fixture()
  let (owner, input) = native_driver_parent("SELECT 1 AS n")
  assert_eq(request_preparation_work_calls(owner), (0L, 0L, 0L, 0L))
  prepare_request_native_document_check(
    owner,
    input,
    "SELECT 1 AS n",
    @frontend.Sql,
    None,
    None,
    environment,
    publication,
  ).unwrap()
  assert_eq(request_preparation_work_calls(owner), (1L, 1L, 1L, 0L))
  let child = owner.program_check.unwrap()
  assert_true(finish_program_check_preparation(child) is Err(WrongPhase))
  assert_eq(request_preparation_work_calls(owner), (1L, 1L, 1L, 0L))
  assert_true(
    finish_request_checked_computation(owner, input, environment, publication)
    is Ok(Pure),
  )
  assert_eq(request_preparation_work_calls(owner), (1L, 1L, 1L, 1L))
  assert_true(request_prepared_computation_kind(owner, input) is Ok(Pure))
  assert_eq(request_preparation_work_calls(owner), (1L, 1L, 1L, 1L))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(request_preparation_work_calls(owner), (1L, 1L, 1L, 1L))
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "Request actual work calls exclude foreign and declined parse work but count a consumed failed prefix" {
  let input = [1]
  let current = Ref(0)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      current.val += 1
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  assert_true(
    parse_request_query_syntax(owner, [1], "SELECT (", @frontend.Sql)
    is Err(Request(ForeignOriginal)),
  )
  let before = @resources.ledger_usage(owner.ledger)
  let limits = @resources.ledger_limits(owner.ledger)
  let blocker = @resources.reserve_capacity(
    owner.ledger,
    limits.retained_bytes - before.reserved_retention_bytes,
    limits.execution_bytes - before.reserved_execution_bytes,
  ).unwrap()
  assert_true(
    parse_request_query_syntax(owner, input, "SELECT (", @frontend.Sql)
    is Err(Request(Capacity(_))),
  )
  assert_eq(request_preparation_work_calls(owner), (0L, 0L, 0L, 0L))
  @resources.settle_capacity(owner.ledger, blocker).unwrap()
  assert_true(
    parse_request_query_syntax(owner, input, "SELECT (", @frontend.Sql)
    is Err(_),
  )
  assert_eq(request_preparation_work_calls(owner), (1L, 0L, 0L, 0L))
  let calls = current.val
  assert_eq(request_preparation_work_calls(owner), (1L, 0L, 0L, 0L))
  assert_eq(current.val, calls)
  assert_true(
    parse_request_query_syntax(owner, input, "SELECT (", @frontend.Sql)
    is Err(Request(WrongPhase)),
  )
  assert_eq(request_preparation_work_calls(owner), (1L, 0L, 0L, 0L))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(request_preparation_work_calls(owner), (1L, 0L, 0L, 0L))
}

///|
test "Request actual work calls exclude declined semantic and compiler grows and survive child clearing" {
  let (parent, child, _, _) = registration_parent_fixture()
  let limits = @resources.ledger_limits(parent.ledger)
  let usage = @resources.ledger_usage(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - usage.reserved_retention_bytes,
    limits.execution_bytes - usage.reserved_execution_bytes,
  ).unwrap()
  assert_true(finish_program_check_preparation(child) is Err(Capacity(_)))
  assert_eq(request_preparation_work_calls(parent), (0L, 0L, 0L, 0L))
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  assert_true(
    finish_program_check_preparation(child).unwrap() is @checked.Checked(_),
  )
  assert_eq(request_preparation_work_calls(parent), (0L, 0L, 1L, 0L))
  let usage = @resources.ledger_usage(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - usage.reserved_retention_bytes,
    limits.execution_bytes - usage.reserved_execution_bytes,
  ).unwrap()
  let compilation = @publication_host.client_standard_program_preparation_limits()
  assert_true(
    compile_program_check_preparation(child, compilation) is Err(Capacity(_)),
  )
  assert_eq(request_preparation_work_calls(parent), (0L, 0L, 1L, 0L))
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  compile_program_check_preparation(child, compilation).unwrap() |> ignore
  assert_eq(request_preparation_work_calls(parent), (0L, 0L, 1L, 1L))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(request_preparation_work_calls(parent), (0L, 0L, 1L, 1L))
}

///|
test "observed query calls exclude inner format and declaration refusals before real work" {
  let calls = Ref(0L)
  let (rejected, _, _) = @frontend.observe_parse_query(
    "{}",
    @frontend.Json,
    calls_out=Some(calls),
  )
  assert_true(rejected is Err(InvalidFormat))
  assert_eq(calls.val, 0L)
  let (environment, publication) = request_query_publication_fixture()
  let (parsed, _, _) = @frontend.observe_parse_query(
    "SELECT 1 AS n",
    @frontend.Sql,
    calls_out=Some(calls),
  )
  let query = parsed.unwrap()
  assert_eq(calls.val, 1L)
  calls.val = 0L
  assert_true(
    @source_publication.lower_prepared_published_parsed_query(
      publication,
      environment,
      query,
      Some("{"),
      calls_out=Some(calls),
    )
    is Err(_),
  )
  assert_eq(calls.val, 0L)
  @source_publication.lower_prepared_published_parsed_query(
    publication,
    environment,
    query,
    None,
    calls_out=Some(calls),
  ).unwrap()
  |> ignore
  assert_eq(calls.val, 1L)
}

///|
test "observed semantic and compiler calls exclude consumed registries and Effect preflight refusal" {
  let (parent, child, _, _) = registration_parent_fixture()
  let registry = child.check_registry.unwrap()
  let calls = Ref(0L)
  @checked.observe_finish_parsed_check_registry(registry, calls_out=Some(calls)).unwrap()
  |> ignore
  assert_eq(calls.val, 1L)
  assert_true(
    @checked.observe_finish_parsed_check_registry(
      registry,
      calls_out=Some(calls),
    )
    is Err(AlreadyConsumed),
  )
  assert_eq(calls.val, 1L)
  abort_request_preparation_after_cleanup(parent).unwrap()
  let (parent, child, _, _) = request_effect_fixture()
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  let checked = @checked.effect_computation_checked_program(
    child.effect_candidate.unwrap(),
  )
  let limits = @publication_host.client_standard_program_preparation_limits()
  let calls = Ref(0L)
  let (result, _) = @publication_host.observe_prepare_checked_effect_free_client_program(
    checked,
    limits.lowering,
    max_parameters=limits.max_parameters,
    max_parameter_name_bytes=limits.max_parameter_name_bytes,
    max_tasks=limits.max_tasks,
    max_graph_work=limits.max_graph_work,
    calls_out=Some(calls),
  )
  assert_true(result is Err(EffectNotSupported(_)))
  assert_eq(calls.val, 0L)
  abort_request_preparation_after_cleanup(parent).unwrap()
}
