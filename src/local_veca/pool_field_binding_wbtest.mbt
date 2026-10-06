///|
test "Pool retained field binding keeps independent limits across quantum and stop" {
  let name = String::make(8096, 'g')
  let producer = pool_producer_owner(group_name=name)
  let owner = pool_owner(producer, group_name=name)
  let prepared = sequence(owner, name_bytes=100000)
  let limits = {
    ..limits(workspace=71, work=20000),
    max_value_bytes: 10000,
    max_total_value_bytes: 30000,
    max_retained_value_bytes: 30000,
  }
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    limits,
    65536L,
    fn() { true },
  ).unwrap()
  @records.append_record(builder, [
    (@schema.Unqualified("id"), number(1.0)),
    (@schema.Unqualified(name), number(1.0)),
    (@schema.Unqualified("embedding"), vector("[1,2]")),
  ]).unwrap()
  let source = @records.finish_output(builder).unwrap()
  let read = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // The scalar fixture takes 61 control units. This name has 127 fragments.
  // Field hash + schema lookup, required hash + exact bucket comparison,
  // and identity hash + exact bucket comparison each add 2*(127-1).
  // Record name emission adds 127-1. Total: 61+7*126=943.
  // Logical canonical construction stays 18; workspace is 15+16+9+1+30=71.
  assert_true(
    start_pool_with_control_work_limit(
      @bounded.control(),
      prepared,
      0,
      read,
      { ..limits, max_workspace_slots: 70, },
      65536L,
      fn() { true },
      943,
    )
    is Err(PoolWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    for (work, success) in [(943, true), (942, false)] {
      let active = start_pool_with_control_work_limit(
        @bounded.control(),
        prepared,
        0,
        read,
        limits,
        65536L,
        fn() { true },
        work,
      ).unwrap()
      let mut terminal = false
      for _ in 0..<950 {
        if !terminal {
          match advance_pool(active, quantum).unwrap() {
            PoolContinue(..) => ()
            PoolComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, 943L)
              let storage = @records.completed_storage(output).unwrap()
              assert_eq(@storage.construction_work(storage), 18)
              assert_true(
                pool_field(storage, 0, name).value is @value.Number(1.0),
              )
              assert_true(
                pool_field(storage, 0, "member_count").value
                is @value.Number(1.0),
              )
              assert_true(@records.discard_completed(output))
              terminal = true
            }
            PoolFailed(PoolWorkLimit, work~, ..) => {
              assert_false(success)
              assert_eq(work, 942L)
              terminal = true
            }
            _ => fail("field binding reached an unrelated terminal outcome")
          }
        }
      }
      assert_true(terminal)
      assert_eq(cleanup_pool(active), Ok(true))
      assert_eq(cleanup_pool(active), Ok(false))
      assert_true(@records.producer_read_available(read))
    }
  }
  let control = @bounded.control()
  let active = start_pool_with_control_work_limit(
    control,
    prepared,
    0,
    read,
    limits,
    65536L,
    fn() { true },
    943,
  ).unwrap()
  // Input and the first field bind before the 253-poll long-field admission.
  // The following required-name hash/comparison spans the 512 boundary;
  // record writing has not begun. Reduction progress is one, not publication.
  guard advance_pool(active, 256).unwrap() is PoolContinue(work~, progress~) else {
    fail("record admission cannot complete in the first quantum")
  }
  assert_eq(work, 256L)
  assert_eq(progress, 1L)
  guard advance_pool(active, 256).unwrap() is PoolContinue(work~, progress~) else {
    fail("required-name comparison must yield in the second quantum")
  }
  assert_eq(work, 512L)
  assert_eq(progress, 1L)
  assert_true(active.state.output_append is Some(_))
  assert_true(@bounded.request_cancel(control))
  assert_eq(cleanup_pool(active), Err(PoolExecutionIssue(@bounded.NotStopped)))
  assert_true(
    advance_pool(active, 1).unwrap()
    is PoolStopped(@bounded.Cancelled, work=512L, progress=1L),
  )
  assert_eq(cleanup_pool(active), Ok(true))
  assert_eq(cleanup_pool(active), Ok(false))
  assert_true(@records.producer_read_available(read))
  assert_true(@records.discard_completed(source))
}
