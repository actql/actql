///|
test "Relation Pool retains caller reservation through exact output completion" {
  // Numeric identity encoding, a two-part identity with long Text, and an
  // unused nested input exercise distinct Relation-only reservation setup.
  for fixture in 0..<3 {
    let source = if fixture == 0 {
      direct_relation_pool_source_owner()
    } else if fixture == 1 {
      long_pool_member_source()
    } else {
      vector_input_recheck_owner(1, pooling=true)
    }
    let owner = direct_relation_pool_owner(source)
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
      14,
      1000,
    ).unwrap()
    // Numeric source: 2*(1+2+2)+3+2+(1+2)+(10+10)+1=39 caller,
    // 16+9+1+30=56 append. Two source identity parts add three caller slots.
    // Depth-three recheck instead uses 13 slots and append uses 35.
    // Admission is 95/98/67; one retained output row adds 3+2=5.
    let admission = if fixture == 0 {
      95
    } else if fixture == 1 {
      98
    } else {
      67
    }
    let exact = admission + 5
    let work = if fixture == 0 { 72 } else if fixture == 1 { 227 } else { 592 }
    let base_limits = {
      ..direct_relation_pool_limits(exact, work),
      max_value_nodes: 258,
      max_value_depth: if fixture == 2 {
        3
      } else {
        10
      },
    }
    for quantum in [1, 7, 256] {
      for slots in [admission, exact - 1, exact] {
        let active = @local_veca.start_relation_pool(
          @bounded.control(),
          prepared_sequence(owner),
          0,
          read,
          { ..base_limits, max_workspace_slots: slots, },
          4096L,
          fn() { true },
        ).unwrap()
        let mut terminal = false
        let mut refused = false
        for _ in 0..<610 {
          if !terminal {
            match @local_veca.advance_pool(active, quantum).unwrap() {
              @local_veca.PoolContinue(..) => ()
              @local_veca.PoolFailed(issue, ..) => {
                assert_eq(
                  issue,
                  @local_veca.PoolOutput(
                    @records.Storage(@record_storage.WorkspaceLimit),
                  ),
                )
                refused = true
                terminal = true
              }
              @local_veca.PoolComplete(output, work=charged, ..) => {
                assert_eq(charged, work.to_int64())
                let storage = @records.completed_storage(output).unwrap()
                assert_eq(@record_storage.record_count(storage), 1)
                assert_eq(@record_storage.retained_workspace_slots(storage), 5)
                assert_eq(@record_storage.construction_work(storage), 18)
                guard @record_storage.record_field_at(storage, 0, 0)
                  is Some(
                    (
                      @schema.Unqualified("embedding"),
                      { value: @admitted.Vector(vector), .. },
                    )
                  ) else {
                  fail("Relation Pool output must retain its vector")
                }
                assert_eq(@admitted.element_count(vector), 2)
                assert_eq(@admitted.element_at(vector, 0), Some(1.0))
                assert_eq(@admitted.element_at(vector, 1), Some(2.0))
                assert_true(@records.discard_completed(output))
                terminal = true
              }
              _ =>
                fail(
                  "Relation caller reservation selected an unrelated terminal",
                )
            }
          }
        }
        assert_true(terminal)
        assert_eq(refused, slots < exact)
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
      base_limits,
      4096L,
      fn() { true },
    ).unwrap()
    // The final 31 append polls and terminal group boundary are unchanged.
    // This barrier is within output append, after Relation input rechecks
    // and member identity encoding have finished.
    let barrier = work - 20
    for _ in 0..<barrier {
      assert_true(
        @local_veca.advance_pool(active, 1).unwrap()
        is @local_veca.PoolContinue(..),
      )
    }
    assert_true(@bounded.request_cancel(control))
    assert_eq(
      @local_veca.cleanup_pool(active),
      Err(@local_veca.PoolExecutionIssue(@bounded.NotStopped)),
    )
    assert_true(@execution.producer_read_available(read))
    guard @local_veca.advance_pool(active, 1).unwrap()
      is @local_veca.PoolStopped(@bounded.Cancelled, work=charged, progress=1L) else {
      fail("Relation Pool must stop without publishing pending output")
    }
    assert_eq(charged, barrier.to_int64())
    assert_eq(@local_veca.cleanup_pool(active), Ok(true))
    assert_eq(@local_veca.cleanup_pool(active), Ok(false))
    assert_true(@execution.producer_read_available(read))
  }
}
