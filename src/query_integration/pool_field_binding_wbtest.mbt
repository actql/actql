///|
fn pool_public_name_barrier(input_matching : Bool) -> Unit raise {
  let name = String::make(513, 'g')
  let exact = if input_matching { 382 } else { 330 }
  let expected_progress = if input_matching { 0L } else { 1L }
  let source = vector_input_recheck_owner(
    1,
    pooling=true,
    unused_items=if input_matching { 116 } else { 90 },
    unused_name=if input_matching { "aa_unused" } else { "zz_unused" },
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
  // adding 9*(9-1)=72 across name matching, retained binding and wire scans.
  // Exact cumulative control: 592-334+72=330. Three-field cursor custody
  // is 16+9+1+3*3=35, plus structural/recheck 31 and one name offset: 67.
  // Admission stays 67; completion retains one three-field row alongside
  // this conservative reservation, so it requires 67+(3+2)=72.
  // The input-matching variant moves Array-116 before the group. It adds
  // 2*(116-90)=52 polls: 382. Begin/group/identity initialization costs 3;
  // Array read/recheck/group/identity costs 1+(2*116+3)+1+1=238;
  // Vector costs 1+5+1+1=8; group read/scalar recheck costs 1+2=3.
  // The first group-name fragment is poll 253; poll 256 retains offset 256.
  let limits = {
    ..direct_relation_pool_limits(72, exact),
    max_value_depth: 3,
    max_value_nodes: if input_matching {
      117
    } else {
      91
    },
  }
  assert_true(
    @local_veca.start_relation_pool(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      read,
      { ..limits, max_workspace_slots: 66, },
      16384L,
      fn() { true },
    )
    is Err(@local_veca.PoolWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    for (work, success) in [(exact, true), (exact - 1, false)] {
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
      for _ in 0..<(exact + 10) {
        if !terminal {
          match @local_veca.advance_pool(active, quantum).unwrap() {
            @local_veca.PoolContinue(..) => ()
            @local_veca.PoolComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, exact.to_int64())
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
              assert_eq(work, (exact - 1).to_int64())
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
    is @local_veca.PoolContinue(work=256L, progress~) &&
    progress == expected_progress,
  )
  assert_true(@bounded.request_cancel(control))
  assert_eq(
    @local_veca.cleanup_pool(active),
    Err(@local_veca.PoolExecutionIssue(@bounded.NotStopped)),
  )
  assert_true(
    @local_veca.advance_pool(active, 1).unwrap()
    is @local_veca.PoolStopped(@bounded.Cancelled, work=256L, progress~) &&
    progress == expected_progress,
  )
  assert_eq(@local_veca.cleanup_pool(active), Ok(true))
  assert_eq(@local_veca.cleanup_pool(active), Ok(false))
  assert_true(@execution.producer_read_available(read))
}

///|
test "Relation Pool public field binding has independent limits and stop barrier" {
  pool_public_name_barrier(false)
}

///|
test "Relation Pool public input name matching has independent limits and stop barrier" {
  pool_public_name_barrier(true)
}
