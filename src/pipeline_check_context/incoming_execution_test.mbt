///|
test "prepared Local Program retains every activation prerequisite without observed success" {
  let (identity, _, _) = prepared_identity_fixture()
  let expressions = close_program_expressions(identity, 10000000, 100).unwrap()
  let profiles = resolution_profiles(
    collect_program_operation_requirements(expressions, 10000000, 100).unwrap(),
  )
  let limits : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 3,
  }
  let incoming = collect_program_incoming(identity, limits).unwrap()
  let linked = link_program_incoming(profiles, incoming, limits).unwrap()
  let publications = close_program_publications(linked, 10000000, 2).unwrap()
  assert_true(physical_equal(publication_closure_owner(publications), linked))
  assert_eq(publication_closure_count(publications), 2)
  let publication_work = publication_closure_work(publications)
  assert_true(publication_work > incoming_links_work(linked) + 7)
  assert_true(close_program_publications(linked, publication_work, 2) is Ok(_))
  assert_true(
    close_program_publications(linked, publication_work - 1, 2)
    is Err(BudgetExceeded),
  )
  assert_true(
    close_program_publications(linked, publication_work, 1)
    is Err(BudgetExceeded),
  )
  assert_true(close_program_publications(linked, -1, 2) is Err(InvalidLimits))
  assert_true(
    close_program_publications(linked, publication_work, -1)
    is Err(InvalidLimits),
  )
  for stage in 0..<2 {
    let entry = publication_closure_at(publications, stage).unwrap()
    assert_eq(entry.stage, stage)
    assert_eq(entry.result_index, 0)
    assert_eq(entry.obligation, @results.TotalDeterministicOrder)
    assert_true(
      physical_equal(
        @results.port_orders(entry.port),
        checked_orders(entry.context),
      ),
    )
    let order = @results.port_order(entry.port)
    assert_eq(@results.publication_result_index(order), 0)
    assert_true(
      physical_equal(
        @results.publication_results(order),
        @results.publication_orders_results(
          @results.checked_publication_orders(checked_orders(entry.context)),
        ),
      ),
    )
  }
  for invalid in [-2147483648, -1, 2, 2147483647] {
    assert_true(publication_closure_at(publications, invalid) is None)
  }
  let closed = close_program_incoming(linked, 10000000, 3).unwrap()
  assert_true(physical_equal(incoming_closure_owner(closed), linked))
  assert_eq(incoming_closure_count(closed), 3)
  let work = incoming_closure_work(closed)
  assert_true(work > incoming_links_work(linked) + 4)
  assert_true(close_program_incoming(linked, work, 3) is Ok(_))
  assert_true(
    close_program_incoming(linked, work - 1, 3) is Err(BudgetExceeded),
  )
  assert_true(close_program_incoming(linked, work, 2) is Err(BudgetExceeded))
  assert_true(close_program_incoming(linked, -1, 3) is Err(InvalidLimits))
  assert_true(close_program_incoming(linked, work, -1) is Err(InvalidLimits))
  assert_eq(program_incoming_count(incoming), 3)
  for i in 0..<3 {
    guard incoming_execution_at(linked, i) is Some(Connected(check)) else {
      fail("missing local activation requirement")
    }
    assert_true(
      physical_equal(check.site, program_incoming_at(incoming, i).unwrap()),
    )
    let retained = incoming_closure_at(closed, i).unwrap()
    assert_true(physical_equal(retained.site, check.site))
    assert_eq(retained.kind, check.kind)
    assert_true(
      physical_equal(
        check.site.consumer,
        program_identity_stage_at(identity, 1).unwrap(),
      ),
    )
    assert_eq(
      check.kind,
      if i == 0 {
        StageSuccess(Completed)
      } else {
        ResultAvailable
      },
    )
    assert_eq(incoming_execution_phase(check), BeforeStageActivation)
    assert_eq(incoming_execution_missing(check), AwaitPredecessor)
    assert_eq(incoming_execution_unknown(check), AwaitReconciliation)
    assert_eq(incoming_execution_failure(check), PreventDownstreamActivation)
  }
  // Repeated imports are two prerequisites, not deduplicated by producer/type.
  guard incoming_execution_at(linked, 1) is Some(Connected(a)) else {
    fail("first import")
  }
  guard incoming_execution_at(linked, 2) is Some(Connected(b)) else {
    fail("second import")
  }
  assert_false(physical_equal(a.site, b.site))
  for invalid in [-2147483648, -1, 3, 2147483647] {
    assert_true(incoming_execution_at(linked, invalid) is None)
    assert_true(incoming_closure_at(closed, invalid) is None)
  }
}

///|
test "accepted gate does not erase independently required Result availability" {
  for accepted in [false, true] {
    let identity = incoming_fixture(accepted~)
    let profiles = resolution_profiles(
      collect_program_operation_requirements(
        close_program_expressions(identity, 10000000, 100).unwrap(),
        10000000,
        100,
      ).unwrap(),
    )
    let limits : IncomingLimits = {
      max_work: 10000000,
      max_name_units: 10000,
      max_requirements: 2,
    }
    let incoming = collect_program_incoming(identity, limits).unwrap()
    let linked = link_program_incoming(profiles, incoming, limits).unwrap()
    let closed = close_program_incoming(linked, 10000000, 2).unwrap()
    assert_eq(incoming_closure_count(closed), 2)
    guard incoming_execution_at(linked, 0) is Some(Connected(gate)) else {
      fail("gate")
    }
    assert_eq(
      gate.kind,
      StageSuccess(if accepted { Accepted } else { Completed }),
    )
    guard incoming_execution_at(linked, 1) is Some(Connected(data)) else {
      fail("data")
    }
    assert_eq(data.kind, ResultAvailable)
    assert_eq(incoming_execution_missing(data), AwaitPredecessor)
    assert_true(physical_equal(gate.site.consumer, data.site.consumer))
  }
}
