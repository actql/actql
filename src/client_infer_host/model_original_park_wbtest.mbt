///|
// Real original Model/Resource owners with the existing synthetic allowances.
// No Store, journal COMMIT, numerical profile or public startup is proved here.
test "Model original park keeps same owner token work and prepared inventory" {
  let (active, scope, _, compiled, definition, plan, ledger) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  let prepared = prepared_call_set(active).unwrap()
  let model = active.model.unwrap()
  let rows = active.rows.unwrap()
  let call_scope = active.call_scope.unwrap()
  assert_true(
    @model.model_original_park_candidate(model, rows, call_scope) is Some(same) &&
    physical_equal(same, model),
  )
  let work = active.work
  let usage = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  let request = @model.prepared_model_request(prepared, 0).unwrap()
  let park = park_original_model_resources(active, scope).unwrap()
  let observations = Ref(0)
  assert_false(
    @model.bind_prepared_model_observation(prepared, _ => observations.val += 1),
  )
  assert_eq(observations.val, 0)
  for _ in 0..<2 {
    assert_true(
      original_model_resource_park_current(active, scope, park) is Some(same) &&
      physical_equal(same, park),
    )
    assert_true(
      advance(active, 1) is Err(Model(@model.Ledger(@resources.ResourceParked))),
    )
    assert_true(
      @model.advance_model_execution(model, 1)
      is Err(@model.Ledger(@resources.ResourceParked)),
    )
    assert_true(
      @model.cleanup_model_execution(model)
      is Err(@model.Ledger(@resources.ResourceParked)),
    )
    assert_false(@model.request_model_cancel(model))
    assert_false(cancel(active))
    assert_true(active.phase is Model)
    assert_false(active.cancelled || active.reclaimed)
    assert_eq(active.work, work)
    assert_eq(@resources.ledger_usage(ledger), usage)
    assert_eq(@resources.quantity_usage(ledger), quantities)
    assert_eq(@model.prepared_model_call_count(prepared), Some(1))
    assert_true(
      physical_equal(
        @model.prepared_model_request(prepared, 0).unwrap(),
        request,
      ),
    )
  }
  assert_true(
    @publication_host.client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(same) &&
    physical_equal(same, park),
  )
  // No confirmed-COMMIT consumer exists yet: retain the original pending scope.
  assert_eq(
    @publication_host.retire_client_model_resource_park(park),
    Err(@publication_host.Resource(@resources.CleanupPending)),
  )
}

///|
test "Model original park refuses input phase and foreign original bindings" {
  let (active, scope, _, _, _, _, _) = model_resource_park_test_start()
  assert_true(
    park_original_model_resources(active, scope) is Err(InvalidAdvance),
  )
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  let model = active.model.unwrap()
  let rows = active.rows.unwrap()
  let call_scope = active.call_scope.unwrap()
  let (other, foreign_scope, _, _, _, _, _) = model_resource_park_test_start()
  require_model_call_entry(other).unwrap()
  assert_true(fixture_finish(other) is Waiting(..))
  prepared_call_set(other).unwrap() |> ignore
  assert_true(
    @model.model_original_park_candidate(model, other.rows.unwrap(), call_scope)
    is None,
  )
  assert_true(
    @model.model_original_park_candidate(model, rows, other.call_scope.unwrap())
    is None,
  )
  assert_true(
    park_original_model_resources(active, foreign_scope)
    is Err(OriginalCapacity(_)),
  )
  assert_true(@model.model_execution_mutation_current(model) is Ok(_))
  let park = park_original_model_resources(active, scope).unwrap()
  assert_true(
    original_model_resource_park_current(other, foreign_scope, park) is None,
  )
  assert_true(
    original_model_resource_park_current(active, foreign_scope, park) is None,
  )
  assert_true(
    original_model_resource_park_current(active, scope, park) is Some(_),
  )
  assert_true(
    park_original_model_resources(active, scope)
    is Err(Model(@model.Ledger(@resources.ResourceParked))),
  )
  assert_true(cancel(other))
  assert_true(fixture_finish(other, initial_work=other.work) is Stopped(..))
  for _ in 0..<10 {
    if cleanup(other).unwrap() {
      break
    }
  }
  assert_true(other.reclaimed)
}

///|
test "Model original park refuses pending physical response without changing its custody" {
  let calls = Ref(0)
  let polls = Ref(0)
  let ready = Ref(false)
  let release = Ref(false)
  let cancels = Ref(0)
  let cleaned : Array[Bool] = []
  let (active, prefix) = async_response_fixture(
    calls,
    polls,
    cancels,
    cleaned,
    ready,
    release,
    @model.PhysicalResponse(async_response_observation(None)),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("original physical response remains pending")
  }
  let model = active.model.unwrap()
  let before_polls = polls.val
  let (_, foreign_scope, _, _, _, _, _) = model_resource_park_test_start()
  assert_true(
    @model.model_original_park_candidate(
      model,
      active.rows.unwrap(),
      active.call_scope.unwrap(),
    )
    is None,
  )
  assert_true(
    park_original_model_resources(active, foreign_scope) is Err(InvalidAdvance),
  )
  assert_eq(calls.val, 1)
  assert_eq(polls.val, before_polls)
  assert_eq(cleaned.length(), 0)
  assert_eq(cancels.val, 0)
  assert_eq(active.work, work)
  assert_true(cancel(active))
  ready.val = true
  guard fixture_finish(active, initial_work=work) is Settling(0, work=settled) else {
    abort("the same late response still needs its original settlement")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  release.val = true
  assert_true(fixture_finish(active, initial_work=settled) is Stopped(_))
  assert_false(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
  assert_eq(cancels.val, 1)
}
