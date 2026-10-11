///|
test "retained producer lookup selects only the exact journal address" {
  let f = retained_cleanup_fixture()
  let consumer = @remote.dispatch_record_request(f.consumer)
  let revision = [
    @remote.dispatch_record_revision(f.producer),
    @remote.dispatch_record_revision(f.consumer),
  ]
  let producer = client_retained_task_producer_lookup(
    f.binding,
    consumer,
    100000,
  ).unwrap()
  assert_eq(
    @remote.dispatch_request_identity(producer),
    @remote.dispatch_request_identity(
      @remote.dispatch_record_request(f.producer),
    ),
  )
  assert_eq(
    @remote.dispatch_request_identity(producer),
    @remote.dispatch_request_identity(
      client_retained_task_route_producer_dispatch(retained_cleanup_route(f)),
    ),
  )
  assert_true(
    client_retained_task_producer_lookup(
      f.binding,
      @remote.dispatch_record_request(f.producer),
      100000,
    )
    is Err(InvalidBinding),
  )
  assert_true(
    client_retained_task_producer_lookup(f.binding, consumer, 1)
    is Err(InvalidBinding),
  )
  assert_eq(
    [
      @remote.dispatch_record_revision(f.producer),
      @remote.dispatch_record_revision(f.consumer),
    ],
    revision,
  )
}

///|
test "a journal lookup does not admit a foreign checked consumer port" {
  let f = retained_cleanup_fixture()
  let altered = @remote.prepare_remote_input_binding(
    @remote.remote_input_binding_body(f.binding).replace(
      old="\"consumer_input_port\":\"input\"",
      new="\"consumer_input_port\":\"other\"",
    ),
    100000,
  ).unwrap()
  assert_true(
    @remote.remote_input_binding_cid(altered) !=
    @remote.remote_input_binding_cid(f.binding),
  )
  let (run, task) = @remote.dispatch_request_task_scope(
    @remote.dispatch_record_request(f.consumer),
  )
  let (consumer, _, _) = retained_input_completed(
    run,
    task,
    1,
    1,
    client_retained_input_edge_schema_cid(f.edge),
    input_binding_cid=@remote.remote_input_binding_cid(altered),
  )
  let request = @remote.dispatch_record_request(consumer)
  assert_true(
    client_retained_task_producer_lookup(altered, request, 100000) is Ok(_),
  )
  assert_true(
    admit_client_retained_task_route(
      altered,
      f.edge,
      request,
      100000,
      4,
      4096,
      8L,
    )
    is Err(InvalidBinding),
  )
}
