///|
// Reuse independently authored Source/Model contracts and Program input. The
// constructor derives a real checked QueryRequirement without provider I/O.
fn original_row_requirement(
  prepared : @publication_host.PreparedClientProgram,
) -> @planning.QueryRequirement {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  prepare_local_query_requirement(
    prepared,
    0,
    0,
    source_contracts,
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
  retained_bytes? : Int64 = 20L,
  execution_bytes? : Int64 = 12L,
  transfer_bytes? : Int64 = 0L,
) -> (@publication_host.ClientModelReadScope, @resources.Ledger) {
  // Independent small census/lifetime fixture, not a Node physical profile.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 1,
    transfer_bytes,
    retained_bytes,
    execution_bytes,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 3, 1, 0,
  ).unwrap()
  (scope, ledger)
}

///|
fn original_row_acquisition_fixture(
  requirement : @planning.QueryRequirement,
) -> @row_source_host.RowAcquisition {
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let view = @row_source_host.declared_row_view(
    "r",
    facts.source_ref,
    facts.source_contract_cid,
    ["id", "amount"],
    facts.carrier_schema_contract_cid,
    facts.source_data_policy_cid,
  )
  let source = @row_source_host.prepare_declared_row_source(
    requirement, "crm/main", view,
  ).unwrap()
  @row_source_host.prepare_declared_row_acquisition(
    source, "fixture-original-source", original_row_query_contract_fixture, original_row_evidence_contract_fixture,
  ).unwrap()
}

///|
test "original row acquisition authenticates the nominal checked Source before registration" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(
    source=true,
  )
  let (foreign, foreign_run, foreign_definition, foreign_plan) = original_prefix_execution_fixture(
    source=true,
  )
  let requirement = original_row_requirement(prepared)
  let copied = original_row_requirement(foreign)
  // Same logical bytes never substitute for the checked Program/sequence.
  assert_eq(
    @planning.query_requirement_cid(requirement),
    @planning.query_requirement_cid(copied),
  )
  let acquisition = original_row_acquisition_fixture(requirement)
  let retention = @row_source_host.row_acquisition_retained_capacity(
    acquisition,
  )
  let execution = @row_source_host.row_acquisition_execution_capacity(
    acquisition,
  )
  let (scope, ledger) = original_row_scope(
    compiled,
    definition,
    plan,
    retained_bytes=retention + 3L,
    execution_bytes=execution + 2L,
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    physical_equal(
      @publication_host.borrow_client_original_row_acquisition_ledger(
        scope, compiled, definition, plan, prepared, requirement,
      ).unwrap(),
      ledger,
    ),
  )
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, compiled, definition, plan, prepared, copied,
    )
    is Err(@publication_host.ForeignRun),
  )
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, compiled, definition, plan, foreign, requirement,
    )
    is Err(@publication_host.ForeignRun),
  )
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, foreign_run, foreign_definition, foreign_plan, foreign, copied,
    )
    is Err(@publication_host.ForeignRun),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let confirmations = Ref(0)
  let run = start_client_original_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    acquisition,
    "original-source-attempt",
    _ => {
      confirmations.val += 1
      true
    },
    0L,
    0L,
  ).unwrap()
  // The actual existing RowRun now owns the same Ledger reservation. No
  // provider read/admission has started, and transport is not acknowledged.
  assert_eq(confirmations.val, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    retention + 3L,
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    execution + 2L,
  )
  assert_true(
    start_client_original_row_acquisition(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      acquisition,
      "repeated-original-source",
      _ => true,
      0L,
      0L,
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 2L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
}

///|
test "original row acquisition cannot add a Source to a source-free Model scope" {
  let (_, compiled, definition, plan) = original_prefix_execution_fixture()
  let (source, _, _, _) = original_prefix_execution_fixture(source=true)
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope,
      compiled,
      definition,
      plan,
      source,
      original_row_requirement(source),
    )
    is Err(@publication_host.ForeignRun),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
}

///|
test "original row acquisition rejects descriptor read and retired scope before allocation" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(
    source=true,
  )
  let requirement = original_row_requirement(prepared)
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, compiled, definition, plan, prepared, requirement,
    )
    is Err(@publication_host.Resource(@resources.ChangedOriginalState)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, compiled, definition, plan, prepared, requirement,
    )
    is Err(@publication_host.Resource(@resources.ChangedOriginalState)),
  )
}

///|
test "original row acquisition keeps the same child reservation on pending cleanup and rejects reentry" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(
    source=true,
  )
  let requirement = original_row_requirement(prepared)
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let borrowed = @publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ).unwrap()
  let child = @resources.reserve_attempt(borrowed, 0L, 7L, 5L).unwrap()
  @resources.mark_cleanup_pending(borrowed, child).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, false,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@resources.reservation_open(child))
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, compiled, definition, plan, prepared, requirement,
    )
    is Err(@publication_host.Resource(@resources.ChangedOriginalState)),
  )
  @resources.settle_reservation(borrowed, child).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    @publication_host.borrow_client_original_row_acquisition_ledger(
      scope, compiled, definition, plan, prepared, requirement,
    )
    is Err(@publication_host.Resource(@resources.ChangedOriginalState)),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
}

///|
test "original row acquisition reserve failure leaves the original census retryable" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(
    source=true,
  )
  let requirement = original_row_requirement(prepared)
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let borrowed = @publication_host.borrow_client_original_row_acquisition_ledger(
    scope, compiled, definition, plan, prepared, requirement,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @resources.reserve_attempt(borrowed, 0L, 18L, 5L)
    is Err(@resources.RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    physical_equal(
      @publication_host.borrow_client_original_row_acquisition_ledger(
        scope, compiled, definition, plan, prepared, requirement,
      ).unwrap(),
      ledger,
    ),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  // The real Local -> accounted RowRun constructor also fails atomically at
  // one below its existing capture allowance, before any provider operation.
  let acquisition = original_row_acquisition_fixture(requirement)
  let retention = @row_source_host.row_acquisition_retained_capacity(
    acquisition,
  )
  let execution = @row_source_host.row_acquisition_execution_capacity(
    acquisition,
  )
  let (short_scope, short_ledger) = original_row_scope(
    compiled,
    definition,
    plan,
    retained_bytes=retention + 2L,
    execution_bytes=execution + 2L,
  )
  let short_before = @resources.ledger_usage(short_ledger)
  let confirmations = Ref(0)
  assert_true(
    start_client_original_row_acquisition(
      short_scope,
      compiled,
      definition,
      plan,
      prepared,
      acquisition,
      "short-original-source",
      _ => {
        confirmations.val += 1
        true
      },
      0L,
      0L,
    )
    is Err(Acquisition(@row_source_host.Physical(@resources.RetentionLimit))),
  )
  assert_eq(confirmations.val, 0)
  assert_eq(@resources.ledger_usage(short_ledger), short_before)
  assert_true(
    physical_equal(
      @publication_host.borrow_client_original_row_acquisition_ledger(
        short_scope, compiled, definition, plan, prepared, requirement,
      ).unwrap(),
      short_ledger,
    ),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      short_scope, compiled, definition, plan, true,
    ).unwrap(),
  )
}
