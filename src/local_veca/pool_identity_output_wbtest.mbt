///|
test "Pool output identity hashing keeps independent control and stop boundaries" {
  let producer = pool_producer_owner(text_group=true)
  let limits = {
    // Fifteen structural slots plus 16+9+1+30 append slots.
    ..limits(workspace=72, work=20000),
    max_value_bytes: 40000,
    max_total_value_bytes: 40000,
    max_retained_value_bytes: 40000,
  }
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    limits,
    65536L,
    fn() { true },
  ).unwrap()
  let text = String::make(8096, 'g')
  let group = @value.checked_text_value(
    text,
    @contract.primitive(@contract.StringType, nullable=false),
  ).unwrap()
  @records.append_record(builder, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified("group"), group),
    (@schema.Unqualified("embedding"), vector("[1,2]")),
  ]).unwrap()
  let source = @records.finish_output(builder).unwrap()
  let owner = pool_owner(producer)
  let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // The scalar fixture needs 61 control units. An 8,096-unit group adds
  // 8,095 validation units and 127 wire polls (one Text setup and 127
  // chunks instead of one scalar poll, in both key and record emission).
  // Exact total: 61+8,095+254=8,410, independent of quantum. This key
  // also fits the standard installed Host's unchanged 10,000-byte ceiling.
  for quantum in [1, 7, 256] {
    for (limit, success) in [(8410, true), (8409, false)] {
      let active = start_pool_with_control_work_limit(
        @bounded.control(),
        sequence(owner),
        0,
        read,
        limits,
        65536L,
        fn() { true },
        limit,
      ).unwrap()
      let mut done = false
      for _ in 0..<17000 {
        if !done {
          match advance_pool(active, quantum).unwrap() {
            PoolContinue(..) => ()
            PoolComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, 8410L)
              let stored = @records.completed_storage(output).unwrap()
              assert_eq(@storage.construction_work(stored), 18)
              guard pool_field(stored, 0, "group").value is @value.Text(actual) else {
                fail("pooled group missing")
              }
              assert_eq(actual, text)
              assert_true(
                pool_field(stored, 0, "member_count").value
                is @value.Number(1.0),
              )
              assert_true(@records.discard_completed(output))
              done = true
            }
            PoolFailed(issue, work~, ..) => {
              assert_false(success)
              assert_eq(issue, PoolWorkLimit)
              assert_eq(work, 8409L)
              done = true
            }
            _ => fail("identity hashing had an unrelated terminal outcome")
          }
        }
      }
      assert_true(done)
      assert_eq(cleanup_pool(active), Ok(true))
      assert_eq(cleanup_pool(active), Ok(false))
    }
  }
  let control = @bounded.control()
  let active = start_pool_with_control_work_limit(
    control,
    sequence(owner),
    0,
    read,
    limits,
    65536L,
    fn() { true },
    8410,
  ).unwrap()
  // Before append: 30+8,095=8,125. Field/presence/identity phases
  // and BeginKey add 11; Text setup adds one. Key chunks occupy
  // 8,138..8,264, so the 32nd 256-unit quantum (8,192) is inside
  // identity hashing, not input validation or record output emission.
  for _ in 0..<32 {
    assert_true(advance_pool(active, 256).unwrap() is PoolContinue(..))
  }
  assert_true(active.state.phase is AppendOutput)
  assert_true(active.state.output_append is Some(_))
  let slots = @records.output_workspace_slots(active.state.output.unwrap())
  assert_true(slots > 0)
  assert_true(@bounded.request_cancel(control))
  assert_eq(cleanup_pool(active), Err(PoolExecutionIssue(@bounded.NotStopped)))
  assert_eq(
    @records.output_workspace_slots(active.state.output.unwrap()),
    slots,
  )
  assert_true(@records.producer_read_available(read))
  assert_true(
    advance_pool(active, 1).unwrap()
    is PoolStopped(@bounded.Cancelled, work=8192L, progress=1L),
  )
  assert_eq(cleanup_pool(active), Ok(true))
  assert_true(active.state.output is None)
  assert_true(active.state.output_append is None)
  assert_true(@records.producer_read_available(read))
  assert_true(@records.discard_completed(source))
}
