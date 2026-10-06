///|
test "Pool output Vector encoding yields with exact work and confirmed stop" {
  let producer = pool_producer_owner(dimensions=257)
  let output = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    { ..limits(), max_value_nodes: 270, max_value_bytes: 2000, max_work: 2000, },
    8192L,
    fn() { true },
  ).unwrap()
  let contract = @contract.vector_contract(257.0, nullable=false).unwrap()
  let vector = @value.prepare_vector_value(257).unwrap()
  for _ in 0..<257 {
    assert_true(@value.append_vector_component(vector, 1.0))
  }
  @records.append_record(output, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("group"), number(1.0)),
    (
      @schema.Unqualified("embedding"),
      @value.finish_checked_vector_value(vector, contract).unwrap(),
    ),
  ]).unwrap()
  let source = @records.finish_output(output).unwrap()
  let owner = pool_owner(producer)
  let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Two-dimensional fixture is 61. Each additional dimension adds one input
  // validation, three fold phases and one output wire poll: 5*255.
  // Total 61+1275=1336. Base workspace 15+255, append cursor 45: 315.
  // Record wire has 267 nodes, key has two and width overhead four: 273.
  let limits = {
    ..limits(workspace=315),
    max_value_nodes: 267,
    max_value_bytes: 2000,
    max_work: 2000,
  }
  assert_true(
    start_pool_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      read,
      { ..limits, max_workspace_slots: 314, },
      8192L,
      fn() { true },
      1336,
    )
    is Err(PoolWorkspaceLimit),
  )
  for (work, success) in [(273, true), (272, false)] {
    let active = start_pool_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      read,
      { ..limits, max_work: work, },
      8192L,
      fn() { true },
      1336,
    ).unwrap()
    let mut done = false
    for _ in 0..<1350 {
      if !done {
        match advance_pool(active, 7).unwrap() {
          PoolContinue(..) => ()
          PoolComplete(output, ..) => {
            assert_true(success)
            assert_eq(
              @storage.construction_work(
                @records.completed_storage(output).unwrap(),
              ),
              273,
            )
            assert_true(@records.discard_completed(output))
            done = true
          }
          PoolFailed(issue, ..) => {
            assert_false(success)
            assert_eq(issue, PoolOutput(@records.Storage(@storage.WorkLimit)))
            assert_true(active.state.output_append is Some(_))
            assert_true(
              @records.output_workspace_slots(active.state.output.unwrap()) > 0,
            )
            done = true
          }
          _ => fail("Pool logical construction limit had an unrelated outcome")
        }
      }
    }
    assert_true(done)
    assert_eq(cleanup_pool(active), Ok(true))
    assert_true(active.state.output is None)
    assert_true(active.state.output_append is None)
    assert_true(@records.producer_read_available(read))
  }
  for quantum in [1, 7, 256] {
    for (limit, success) in [(1336, true), (1335, false)] {
      let active = start_pool_with_control_work_limit(
        @bounded.control(),
        sequence(owner),
        0,
        read,
        limits,
        8192L,
        fn() { true },
        limit,
      ).unwrap()
      let mut done = false
      for _ in 0..<1350 {
        if !done {
          match advance_pool(active, quantum).unwrap() {
            PoolContinue(..) => ()
            PoolComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, 1336L)
              let stored = @records.completed_storage(output).unwrap()
              assert_eq(@storage.record_count(stored), 1)
              assert_eq(@storage.construction_work(stored), 273)
              guard pool_field(stored, 0, "embedding").value
                is @value.Vector(values) else {
                fail("Pool output vector missing")
              }
              assert_eq(@value.element_count(values), 257)
              for index in 0..<257 {
                assert_eq(@value.element_at(values, index), Some(1.0))
              }
              assert_true(@records.discard_completed(output))
              done = true
            }
            PoolFailed(issue, work~, ..) => {
              assert_false(success)
              assert_eq(issue, PoolWorkLimit)
              assert_eq(work, 1335L)
              done = true
            }
            _ => fail("Pool output encoding had an unrelated outcome")
          }
        }
      }
      assert_true(done)
      assert_eq(cleanup_pool(active), Ok(true))
      assert_eq(cleanup_pool(active), Ok(false))
      assert_true(@records.producer_read_available(read))
    }
  }
  let control = @bounded.control()
  let active = start_pool_with_control_work_limit(
    control,
    sequence(owner),
    0,
    read,
    limits,
    8192L,
    fn() { true },
    1336,
  ).unwrap()
  // Input validation and folding are finished before the fourth quantum.
  // At 1280 the shared append cursor is emitting the 257-component vector.
  for _ in 0..<5 {
    assert_true(advance_pool(active, 256).unwrap() is PoolContinue(..))
  }
  assert_true(active.state.phase is AppendOutput)
  assert_true(active.state.output_append is Some(_))
  let retained = @records.output_workspace_slots(active.state.output.unwrap())
  assert_true(retained > 0)
  assert_true(@bounded.request_cancel(control))
  assert_eq(cleanup_pool(active), Err(PoolExecutionIssue(@bounded.NotStopped)))
  assert_eq(
    @records.output_workspace_slots(active.state.output.unwrap()),
    retained,
  )
  assert_true(@records.producer_read_available(read))
  assert_true(
    advance_pool(active, 1).unwrap()
    is PoolStopped(@bounded.Cancelled, work=1280L, progress=1L),
  )
  assert_eq(cleanup_pool(active), Ok(true))
  assert_eq(cleanup_pool(active), Ok(false))
  assert_true(active.state.output_append is None)
  assert_true(active.state.output is None)
  assert_true(@records.producer_read_available(read))
  assert_true(@records.discard_completed(source))
}
