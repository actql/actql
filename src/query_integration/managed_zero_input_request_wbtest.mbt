///|
test "managed request binds a checked zero-input owner explicitly" {
  let owner = zero_input_request_owner(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":7}]},\"as\":\"seed\"}]",
  )
  let inputs : Array[@execution.ManagedProducerRead[Unit]] = []
  let capacity = dispatch_test_limits().capacity
  let obligations = @execution.process_managed_obligations(owner)
  assert_true(
    @connector.prepare_managed_fixed_compute_request(
      inputs, capacity, obligations,
    )
    is Err(UnsupportedInputShape),
  )
  let request = @connector.prepare_managed_fixed_compute_request_for_owner(
    owner, inputs, capacity, obligations,
  ).unwrap()
  assert_true(
    physical_equal(
      @connector.managed_fixed_compute_request_owner(request),
      owner,
    ),
  )
  assert_eq(@connector.managed_fixed_compute_request_input_count(request), 0)

  let foreign = zero_input_request_owner(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":8}]},\"as\":\"seed\"}]",
  )
  assert_true(
    @connector.prepare_managed_fixed_compute_request_for_owner(
      owner,
      inputs,
      capacity,
      @execution.process_managed_obligations(foreign),
    )
    is Err(ForeignPreparation),
  )
}

///|
fn zero_input_request_owner(source : String) -> @lower.BoundPrepared {
  let pipeline = @pipeline.check(input_cursor(source), [], None, None, {
    max_steps: 100,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}
