///|
test "async provider without original durable preflight refuses before Model begin" {
  let calls = Ref(0)
  let active = contract_capacity_start(calls, 2, 133072L, asynchronous=true)
  assert_true(
    fixture_finish(active) is Failed(Model(@model.InvalidProvider), ..),
  )
  assert_eq(calls.val, 0)
  assert_true(active.model is None)
  assert_true(cleanup(active).unwrap())
}

///|
test "async registration never supplies the synchronous fixture callback" {
  assert_true(
    @model.install_async_model_provider("") is Err(@model.InvalidProvider),
  )
  let asynchronous = @model.install_async_model_provider("models/fixture").unwrap()
  assert_true(@model.model_provider_synchronous_invoke(asynchronous) is None)
  let calls = Ref(0)
  let synchronous = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Err(@model.ProviderError)
  }).unwrap()
  assert_true(@model.model_provider_synchronous_invoke(synchronous) is Some(_))
  assert_eq(calls.val, 0)
}

///|
test "physical preflight mode mismatch refuses before Entry and either transport" {
  for asynchronous in [true, false] {
    let calls = Ref(0)
    let active = contract_capacity_start(calls, 2, 133072L, asynchronous~)
    bind_quantity_capacity(active, fixture_quantity_capacity(66L, 1000L)).unwrap()
    bind_physical_preflight(active, request => {
      Ok({
        advance: () => {
          let quantities : @resources.QuantityAmounts = {
            tokens: 33L,
            cost_units: 0L,
            duration_ms: 500L,
          }
          let plan = if asynchronous {
            @model.model_physical_request_plan(request, 1000L, quantities, () => {
              calls.val += 1
              Err(@model.ProviderError)
            })
          } else {
            @model.model_async_physical_request_plan(
              request,
              1000L,
              quantities,
              async_response_profile(),
              async_response_installation(),
              _ => {
                calls.val += 1
                None
              },
            )
          }
          plan.map(value => Some(value))
        },
        cleanup: () => true,
      })
    }).unwrap()
    require_model_call_entry(active).unwrap()
    assert_true(
      fixture_finish(active) is Failed(Model(@model.InvalidProvider), ..),
    )
    assert_true(prepared_call_set(active) is None)
    assert_eq(
      @model.stopped_model_attempt_count(active.model.unwrap()),
      Some(0),
    )
    assert_eq(calls.val, 0)
    let mut cleaned = false
    for _ in 0..<10 {
      if cleanup(active).unwrap() {
        cleaned = true
        break
      }
    }
    assert_true(cleaned)
  }
}
