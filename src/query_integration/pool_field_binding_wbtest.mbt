///|
test "Relation Pool public field binding has independent limits and stop barrier" {
  let name = String::make(513, 'g')
  let source = vector_input_recheck_owner(
    1,
    pooling=true,
    unused_items=90,
    group_name=name,
  )
  let owner = direct_relation_pool_owner(source, group_name=name)
  let completed = @execution.execute_generated_sequence(
    task_test_generated(source),
    [],
    compute_test_limits(),
  ).unwrap()
  let read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(
      owner,
      0,
      source,
      @execution.completed_output(completed, @pipeline.Step(1)).unwrap(),
    ).unwrap(),
    // Four declarations plus 1+2+3+4 exact column lookups.
    14,
    10000,
  ).unwrap()
  // The existing Array-257 Relation fixture is independently 592 polls.
  // Array-90 removes 2*(257-90)=334. A 513-unit name has nine fragments,
  // adding 7*(9-1)=56 across field, required, identity and wire scans.
  // Exact cumulative control: 592-334+56=314. Three-field cursor custody
  // is 16+9+1+3*3=35, plus structural/recheck 31: workspace 66.
  let limits = {
    ..direct_relation_pool_limits(66, 314),
    max_value_depth: 3,
    max_value_nodes: 91,
  }
  assert_true(
    @local_veca.start_relation_pool(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      read,
      { ..limits, max_workspace_slots: 65, },
      16384L,
      fn() { true },
    )
    is Err(@local_veca.PoolWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    for (work, success) in [(314, true), (313, false)] {
      let active = @local_veca.start_relation_pool(
        @bounded.control(),
        prepared_sequence(owner),
        0,
        read,
        { ..limits, max_work: work, },
        16384L,
        fn() { true },
      ).unwrap()
      let mut terminal = false
      for _ in 0..<320 {
        if !terminal {
          match @local_veca.advance_pool(active, quantum).unwrap() {
            @local_veca.PoolContinue(..) => ()
            @local_veca.PoolComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, 314L)
              let storage = @records.completed_storage(output).unwrap()
              assert_eq(@record_storage.record_count(storage), 1)
              assert_true(
                @record_storage.record_field_at(storage, 0, 1).unwrap()
                is (
                  @schema.Unqualified(field),
                  { value: @admitted.Number(1.0), .. },
                ) &&
                field == name,
              )
              assert_true(@records.discard_completed(output))
              terminal = true
            }
            @local_veca.PoolFailed(issue, work~, ..) => {
              assert_false(success)
              assert_eq(issue, @local_veca.PoolWorkLimit)
              assert_eq(work, 313L)
              terminal = true
            }
            _ =>
              fail("public field fixture reached an unrelated terminal outcome")
          }
        }
      }
      assert_true(terminal)
      assert_eq(@local_veca.cleanup_pool(active), Ok(true))
      assert_eq(@local_veca.cleanup_pool(active), Ok(false))
      assert_true(@execution.producer_read_available(read))
    }
  }
  let control = @bounded.control()
  let active = @local_veca.start_relation_pool(
    control,
    prepared_sequence(owner),
    0,
    read,
    limits,
    16384L,
    fn() { true },
  ).unwrap()
  assert_true(
    @local_veca.advance_pool(active, 256).unwrap()
    is @local_veca.PoolContinue(work=256L, progress=1L),
  )
  assert_true(@bounded.request_cancel(control))
  assert_eq(
    @local_veca.cleanup_pool(active),
    Err(@local_veca.PoolExecutionIssue(@bounded.NotStopped)),
  )
  assert_true(
    @local_veca.advance_pool(active, 1).unwrap()
    is @local_veca.PoolStopped(@bounded.Cancelled, work=256L, progress=1L),
  )
  assert_eq(@local_veca.cleanup_pool(active), Ok(true))
  assert_eq(@local_veca.cleanup_pool(active), Ok(false))
  assert_true(@execution.producer_read_available(read))
}
