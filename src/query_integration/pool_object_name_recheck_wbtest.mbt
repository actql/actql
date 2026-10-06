///|
test "Relation Pool Object names retain independent limits and stop custody" {
  let source = vector_input_recheck_owner(1, pooling=true, object_names=true)
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
    // Five declarations plus 1+2+3+4+5 exact column lookups.
    20,
    1000,
  ).unwrap()
  // The four-column Array fixture independently needs 592 polls. Replace its
  // 517-poll Array by a 112-item Array (227) plus one Object with
  // root+setup+3 names+child+end+finish=8. Extra field lookup costs 3:
  // 592-517+227+8+3=313. No allowance is inferred from a successful run.
  // Pool structural custody depends on records/roles, not unused field count:
  // the depth-three continuation/append plus one name offset total 67 slots.
  // This admission reservation stays live while retaining the output row:
  // three fields plus two links make completion 67+5=72.
  let limits = {
    ..direct_relation_pool_limits(72, 313),
    max_value_depth: 3,
    max_value_nodes: 113,
  }
  assert_true(
    @local_veca.start_relation_pool(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      read,
      { ..limits, max_workspace_slots: 66, },
      4096L,
      fn() { true },
    )
    is Err(@local_veca.PoolWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    for (work, success) in [(313, true), (312, false)] {
      let active = @local_veca.start_relation_pool(
        @bounded.control(),
        prepared_sequence(owner),
        0,
        read,
        { ..limits, max_work: work, },
        4096L,
        fn() { true },
      ).unwrap()
      let mut terminal = false
      for _ in 0..<330 {
        if !terminal {
          match @local_veca.advance_pool(active, quantum).unwrap() {
            @local_veca.PoolContinue(..) => ()
            @local_veca.PoolComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, 313L)
              let storage = @records.completed_storage(output).unwrap()
              assert_eq(@record_storage.record_count(storage), 1)
              let field = @record_storage.record_field_at(storage, 0, 0).unwrap()
              assert_eq(@schema.reference_name(field.0), "embedding")
              guard field.1.value is @admitted.Vector(vector) else {
                fail("Pool result must remain a typed Vector")
              }
              assert_eq(@admitted.element_at(vector, 0), Some(1.0))
              assert_eq(@admitted.element_at(vector, 1), Some(2.0))
              terminal = true
            }
            @local_veca.PoolFailed(issue, work~, ..) => {
              assert_false(success)
              assert_eq(issue, @local_veca.PoolWorkLimit)
              assert_eq(work, 312L)
              terminal = true
            }
            _ => fail("Object name fixture encountered an unrelated failure")
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
    4096L,
    fn() { true },
  ).unwrap()
  // Begin/groups/identity 3, Array field 1+227+2, Vector field 1+5+2,
  // group/id fields 2*(1+2+2) = 251. Object load/root/setup add 3.
  // Poll 255 checks only the first 64 name units, not its child.
  assert_true(
    @local_veca.advance_pool(active, 255).unwrap()
    is @local_veca.PoolContinue(work=255L, progress=0L),
  )
  assert_true(@bounded.request_cancel(control))
  assert_eq(
    @local_veca.cleanup_pool(active),
    Err(@local_veca.PoolExecutionIssue(@bounded.NotStopped)),
  )
  assert_true(@execution.producer_read_available(read))
  assert_true(
    @local_veca.advance_pool(active, 1).unwrap()
    is @local_veca.PoolStopped(@bounded.Cancelled, work=255L, progress=0L),
  )
  assert_eq(@local_veca.cleanup_pool(active), Ok(true))
  assert_eq(@local_veca.cleanup_pool(active), Ok(false))
  assert_true(@execution.producer_read_available(read))
}
