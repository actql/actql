///|
// Reuse independently authored Source/Model contracts and Program input. The
// constructor derives a real checked QueryRequirement without provider I/O.
fn original_row_requirement(
  prepared : @publication_host.PreparedClientProgram,
) -> @planning.QueryRequirement {
  prepare_local_query_requirement(
    prepared,
    0,
    0,
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
}

///|
fn original_row_scope(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> (@publication_host.ClientModelReadScope, @resources.Ledger) {
  // Independent small census/lifetime fixture, not a Node physical profile.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 20L,
    execution_bytes: 12L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 3, 1, 0,
  ).unwrap()
  (scope, ledger)
}

///|
test "original row acquisition authenticates the nominal checked Source before registration" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(source=true)
  let (foreign, foreign_run, foreign_definition, foreign_plan) = original_prefix_execution_fixture(source=true)
  let requirement = original_row_requirement(prepared)
  let copied = original_row_requirement(foreign)
  // Same logical bytes never substitute for the checked Program/sequence.
  assert_eq(@planning.query_requirement_cid(requirement), @planning.query_requirement_cid(copied))
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let before = @resources.ledger_usage(ledger)
  assert_true(physical_equal(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, compiled, definition, plan, prepared, requirement,
    ).unwrap(), ledger,
  ))
  assert_true(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, copied,
  ) is Err(@publication_host.ForeignRun))
  assert_true(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, foreign, requirement,
  ) is Err(@publication_host.ForeignRun))
  assert_true(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, foreign_run, foreign_definition, foreign_plan, foreign, copied,
  ) is Err(@publication_host.ForeignRun))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@publication_host.finish_client_model_read_scope(
    scope, compiled, definition, plan, true,
  ).unwrap())
}

///|
test "original row acquisition cannot add a Source to a source-free Model scope" {
  let (_, compiled, definition, plan) = original_prefix_execution_fixture()
  let (source, _, _, _) = original_prefix_execution_fixture(source=true)
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let before = @resources.ledger_usage(ledger)
  assert_true(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, source, original_row_requirement(source),
  ) is Err(@publication_host.ForeignRun))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@publication_host.finish_client_model_read_scope(
    scope, compiled, definition, plan, true,
  ).unwrap())
}

///|
test "original row acquisition rejects descriptor read and retired scope before allocation" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(source=true)
  let requirement = original_row_requirement(prepared)
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ) is Err(@publication_host.Resource(@resources.ChangedOriginalState)))
  assert_eq(@resources.ledger_usage(ledger), before)
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(@publication_host.finish_client_model_read_scope(
    scope, compiled, definition, plan, true,
  ).unwrap())
  assert_true(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ) is Err(@publication_host.Resource(@resources.ChangedOriginalState)))
}

///|
test "original row acquisition keeps the same child reservation on pending cleanup and rejects reentry" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(source=true)
  let requirement = original_row_requirement(prepared)
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let borrowed = @publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ).unwrap()
  let child = @resources.reserve_attempt(borrowed, 0L, 7L, 5L).unwrap()
  @resources.mark_cleanup_pending(borrowed, child).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_false(@publication_host.finish_client_model_read_scope(
    scope, compiled, definition, plan, false,
  ).unwrap())
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@resources.reservation_open(child))
  assert_true(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ) is Err(@publication_host.Resource(@resources.ChangedOriginalState)))
  @resources.settle_reservation(borrowed, child).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ) is Err(@publication_host.Resource(@resources.ChangedOriginalState)))
  assert_true(@publication_host.finish_client_model_read_scope(
    scope, compiled, definition, plan, true,
  ).unwrap())
}

///|
test "original row acquisition reserve failure leaves the original census retryable" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(source=true)
  let requirement = original_row_requirement(prepared)
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let borrowed = @publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(@resources.reserve_attempt(borrowed, 0L, 18L, 5L) is Err(@resources.RetentionLimit))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(physical_equal(@publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ).unwrap(), ledger))
  assert_true(@publication_host.finish_client_model_read_scope(
    scope, compiled, definition, plan, true,
  ).unwrap())
}
