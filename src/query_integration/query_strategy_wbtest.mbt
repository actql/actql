///|
fn strategy_test_owner() -> @query.QuerySequence raise {
  let (query, owner) = query_sequence_fixture()
  @query.prepare_query_sequence(query, query_generated(owner), 10000).unwrap()
}

///|
fn strategy_estimates(
  values : Array[Int64?],
) -> Array[@cost.SerialEstimateLine] {
  values.mapi((i, v) => { work_slots: [i], milliseconds: v, })
}

///|
fn strategy_offer(
  owner : @query.QuerySequence,
  route : @mock.QueryRealization,
  values : Array[Int64?],
) -> @mock.QueryOffer {
  @mock.offer_mock_query(
    owner,
    route,
    strategy_estimates(values),
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    1000,
  ).unwrap()
}

///|
fn strategy_for(
  owner : @query.QuerySequence,
  route : @mock.QueryRealization,
) -> @mock.QueryStrategy {
  let offer = strategy_offer(owner, route, [])
  let choice = @mock.choose_query_strategy(owner, [offer], Some([0]), 3).unwrap()
  guard choice is Proposed(strategy) else { abort("mock strategy fixture") }
  strategy
}

///|
fn mock_strategy_limits() -> @mock.MockQueryLimits {
  {
    source_rows: 10,
    received_rows: 10,
    received_cells: 100,
    source_admission: run_limits().input_values,
    computation: compute_test_limits(),
  }
}

///|
test "selected mock realization executes native before receipt and broad residual after receipt" {
  let owner = strategy_test_owner()
  let source = [
    input_cursor("{\"id\":3}"),
    input_cursor("{\"id\":1}"),
    input_cursor("{\"id\":2}"),
  ]
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let strategy = strategy_for(owner, route)
    let attempt = @mock.prepare_mock_query_attempt(strategy, source, 3).unwrap()
    assert_true(@mock.mock_query_computation(attempt) is Err(NotComputed))
    let result = @mock.execute_mock_query(attempt, mock_strategy_limits()).unwrap()
    assert_eq(@mock.mock_query_source_rows(result), 3)
    assert_eq(@mock.mock_query_output_rows(result), 2)
    assert_eq(@mock.mock_query_received_columns(result), 1)
    assert_eq(
      @mock.mock_query_received_rows(result),
      if route == @mock.NativeQuery {
        2
      } else {
        3
      },
    )
    assert_true(physical_equal(@mock.mock_query_strategy(result), strategy))
    assert_true(
      @mock.execute_mock_query(attempt, mock_strategy_limits())
      is Err(AlreadyStarted),
    )
    // Local success is still pending capture; cancellation withdraws this task.
    assert_true(@mock.cancel_mock_query(attempt))
    assert_true(@mock.mock_query_computation(attempt) is Err(Cancelled))
    assert_true(!@mock.cancel_mock_query(attempt))
    let tight = @mock.prepare_mock_query_attempt(strategy, source, 3).unwrap()
    let outcome = @mock.execute_mock_query(tight, {
      ..mock_strategy_limits(),
      received_rows: 2,
    })
    if route == @mock.NativeQuery {
      assert_true(outcome is Ok(_))
    } else {
      assert_true(outcome is Err(ReceiptRowsLimit))
    }
  }
}

///|
test "native mock never hides full-source admission failure and attempts do not fallback" {
  let (query, bound) = query_sequence_fixture(filter="1 / (id - id) > 0")
  let owner = @query.prepare_query_sequence(
    query,
    query_generated(bound),
    10000,
  ).unwrap()
  let source = [
    input_cursor("{\"id\":3}"),
    input_cursor("{\"id\":\"invalid\"}"),
  ]
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let strategy = strategy_for(owner, route)
    let attempt = @mock.prepare_mock_query_attempt(strategy, source, 2).unwrap()
    assert_true(
      @mock.execute_mock_query(attempt, mock_strategy_limits())
      is Err(Local(ReceiptAdmission(InputValue(1, _)))),
    )
    assert_true(
      @mock.mock_query_computation(attempt)
      is Err(Local(ReceiptAdmission(InputValue(1, _)))),
    )
    assert_true(
      @mock.execute_mock_query(attempt, mock_strategy_limits())
      is Err(AlreadyStarted),
    )
    let valid = @mock.prepare_mock_query_attempt(strategy, [source[0]], 1).unwrap()
    assert_true(
      @mock.execute_mock_query(valid, mock_strategy_limits())
      is Err(Local(Execution(Rows(_, _)))),
    )
  }
}

///|
test "mock preparation owns its source container and cancellation does not poison another attempt" {
  let owner = strategy_test_owner()
  let strategy = strategy_for(owner, @mock.BroadWithResidual)
  let source = [input_cursor("{\"id\":2}")]
  assert_true(
    @mock.prepare_mock_query_attempt(strategy, source, 0)
    is Err(PreparationLimit),
  )
  let first = @mock.prepare_mock_query_attempt(strategy, source, 1).unwrap()
  let second = @mock.prepare_mock_query_attempt(strategy, source, 1).unwrap()
  source.clear()
  assert_true(@mock.cancel_mock_query(first))
  assert_true(
    @mock.execute_mock_query(first, mock_strategy_limits()) is Err(Cancelled),
  )
  let result = @mock.execute_mock_query(second, mock_strategy_limits()).unwrap()
  assert_eq(@mock.mock_query_output_rows(result), 1)
  assert_eq(@mock.mock_query_source_rows(result), 1)
  let failed = @mock.prepare_mock_query_attempt(
    strategy,
    [input_cursor("{\"id\":2}")],
    1,
  ).unwrap()
  assert_true(
    @mock.execute_mock_query(failed, {
      ..mock_strategy_limits(),
      received_cells: 0,
    })
    is Err(ReceiptCellsLimit),
  )
}

///|
test "equal query estimates follow fixed Host preference across enumeration changes" {
  let owner = strategy_test_owner()
  let native = strategy_offer(owner, NativeQuery, Array::make(6, Some(7L)))
  let broad = strategy_offer(owner, BroadWithResidual, Array::make(7, Some(6L)))
  for (offers, order) in [([native, broad], [1, 0]), ([broad, native], [0, 1])] {
    let selected = @mock.choose_query_strategy(owner, offers, Some(order), 6).unwrap()
    guard selected is Proposed(strategy) else { fail("tied choice") }
    assert_eq(
      @mock.query_offer_realization(@mock.query_strategy_offer(strategy)),
      @mock.BroadWithResidual,
    )
    assert_true(physical_equal(@mock.query_strategy_owner(strategy), owner))
    assert_true(
      @mock.query_strategy_choice(strategy) is @cost.EstimatedFastest(_, 42L),
    )
  }
}

///|
test "query candidates include transfer residual capture and retention without changing meaning" {
  let owner = strategy_test_owner()
  let native = strategy_offer(owner, NativeQuery, [
    Some(10L),
    Some(1L),
    Some(1L),
    Some(1L),
    Some(2L),
    Some(1L),
  ])
  let broad = strategy_offer(owner, BroadWithResidual, [
    Some(3L),
    Some(1L),
    Some(1L),
    Some(10L),
    Some(9L),
    Some(2L),
    Some(1L),
  ])
  assert_eq(@mock.query_offer_duration(native), @cost.Complete(16L))
  assert_eq(@mock.query_offer_duration(broad), @cost.Complete(27L))
  let offers = [native, broad]
  let selected = @mock.choose_query_strategy(owner, offers, None, 4).unwrap()
  guard selected is Proposed(strategy) else { fail("known choice") }
  offers.clear()
  assert_eq(
    @mock.query_offer_realization(@mock.query_strategy_offer(strategy)),
    @mock.NativeQuery,
  )
  assert_true(physical_equal(@mock.query_strategy_owner(strategy), owner))
  assert_true(
    physical_equal(
      @query.query_sequence_requirement(@mock.query_strategy_owner(strategy)),
      @query.query_sequence_requirement(owner),
    ),
  )
  assert_eq(@mock.query_strategy_task_count(strategy), 2)
  assert_eq(@mock.query_strategy_task_at(strategy, 0), Some(@mock.RealizeQuery))
  assert_eq(
    @mock.query_strategy_task_at(strategy, 1),
    Some(@mock.CaptureObservation),
  )
  assert_eq(@mock.query_strategy_task_at(strategy, 2), None)
  assert_eq(@mock.query_strategy_pending_count(strategy), 8)
  assert_eq(
    @mock.query_strategy_pending_at(strategy, 1),
    Some(@acquisition.WholeScanAdmission),
  )
  assert_eq(@mock.query_strategy_pending_at(strategy, 8), None)
  let expensive = strategy_offer(owner, NativeQuery, [
    Some(30L),
    Some(1L),
    Some(1L),
    Some(1L),
    Some(2L),
    Some(1L),
  ])
  let changed = @mock.choose_query_strategy(owner, [expensive, broad], None, 4).unwrap()
  guard changed is Proposed(changed) else { fail("changed choice") }
  assert_eq(
    @mock.query_offer_realization(@mock.query_strategy_offer(changed)),
    @mock.BroadWithResidual,
  )
  assert_true(physical_equal(@mock.query_strategy_owner(changed), owner))
}

///|
test "unknown work never bypasses admission or becomes a zero cost" {
  let owner = strategy_test_owner()
  let known = strategy_offer(owner, NativeQuery, [
    Some(10L),
    Some(1L),
    Some(1L),
    Some(1L),
    Some(2L),
    Some(1L),
  ])
  // Missing capture/retention/cleanup estimates are not free work.
  let missing = strategy_offer(owner, BroadWithResidual, [
    Some(3L),
    Some(10L),
    Some(9L),
    Some(2L),
  ])
  assert_eq(@mock.query_offer_duration(missing), @cost.Unknown)
  assert_true(
    @mock.choose_query_strategy(owner, [known, missing], None, 4).unwrap()
    is Deferred,
  )
  let selected = @mock.choose_query_strategy(
    owner,
    [known, missing],
    Some([1, 0]),
    6,
  ).unwrap()
  guard selected is Proposed(strategy) else { fail("explicit preference") }
  assert_true(@mock.query_strategy_choice(strategy) is @cost.HostPreferred(1))
  assert_eq(@mock.query_strategy_pending_count(strategy), 8)
  assert_true(
    @mock.choose_query_strategy(owner, [known, missing], Some([1, 1]), 6)
    is Err(Cost(InvalidPreference)),
  )
}

///|
test "query strategy rejects foreign ownership duplicate costs and physical preparation overruns" {
  let owner = strategy_test_owner()
  let foreign = strategy_test_owner()
  let native = strategy_offer(owner, NativeQuery, [
    Some(1L),
    Some(1L),
    Some(1L),
    Some(1L),
    Some(1L),
    Some(1L),
  ])
  assert_true(
    @mock.choose_query_strategy(foreign, [native], None, 2)
    is Err(ForeignQuery(0)),
  )
  assert_true(
    @mock.choose_query_strategy(owner, [native], None, 1)
    is Err(Cost(PlanningLimit)),
  )
  let quantities : @connector.QueryQuantities = {
    transfer_bytes: Some(2L),
    retained_bytes: Some(9L),
    money_units: None,
  }
  let duplicated : Array[@cost.SerialEstimateLine] = [
    { work_slots: [0, 1], milliseconds: Some(3L), },
    { work_slots: [1], milliseconds: Some(1L), },
  ]
  assert_true(
    @mock.offer_mock_query(owner, NativeQuery, duplicated, quantities, 20)
    is Err(Cost(DuplicateSlot(1))),
  )
  assert_true(
    @mock.offer_mock_query(
      owner,
      NativeQuery,
      [],
      { ..quantities, retained_bytes: Some(-1L), },
      10,
    )
    is Err(NegativeQuantity),
  )
  let entries = strategy_estimates([
    Some(1L),
    Some(1L),
    Some(1L),
    Some(1L),
    Some(1L),
    Some(1L),
  ])
  assert_true(
    @mock.offer_mock_query(owner, NativeQuery, entries, quantities, 18) is Ok(_),
  )
  assert_true(
    @mock.offer_mock_query(owner, NativeQuery, entries, quantities, 17)
    is Err(Cost(PlanningLimit)),
  )
  entries.clear()
  assert_eq(@mock.query_offer_duration(native), @cost.Complete(6L))
  assert_eq(@mock.query_work_count(@mock.BroadWithResidual), 7)
  assert_eq(
    @mock.query_work_at(@mock.BroadWithResidual, 3),
    Some(LocalResidual),
  )
  assert_eq(@mock.query_work_at(@mock.NativeQuery, 3), Some(ObservationCapture))
  assert_eq(@mock.query_work_at(@mock.NativeQuery, -1), None)
  assert_eq(@mock.query_work_at(@mock.NativeQuery, 6), None)
}
