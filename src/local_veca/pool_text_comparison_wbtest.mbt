///|
fn pool_text_source(
  producer : @lower.BoundPrepared,
  text_identity? : Bool = true,
  width? : Int = 128,
) -> @records.Completed {
  let builder = @records.prepare_output(
    producer,
    @pipeline.Step(0),
    limits(work=10000),
    8192L,
    fn() { true },
  ).unwrap()
  let contract = @contract.primitive(@contract.StringType, nullable=false)
  let prefix = "x".repeat(width)
  // Reverse input order makes the expected group order independent of input.
  for suffix in ["b", "a"] {
    let key = @value.checked_text_value(prefix + suffix, contract).unwrap()
    @records.append_record(builder, [
      (
        @schema.Unqualified("id"),
        if text_identity {
          key
        } else {
          number(if suffix == "b" { 1.0 } else { 2.0 })
        },
      ),
      (@schema.Unqualified("group"), key),
      (@schema.Unqualified("embedding"), vector("[1,2]")),
    ]).unwrap()
  }
  @records.finish_output(builder).unwrap()
}

///|
test "pool public scan barrier retains its pending group key" {
  let producer = pool_producer_owner(text_group=true)
  let source = pool_text_source(producer, text_identity=false, width=512)
  let owner = pool_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  let control = @bounded.control()
  let execution = start_pool(
    control,
    sequence(owner),
    0,
    input,
    limits(work=10000),
    8192L,
    fn() { true },
  ).unwrap()
  assert_true(
    advance_pool(execution, 256).unwrap()
    is PoolContinue(progress=0L, work=256L),
  )
  assert_true(execution.state.phase is ValidateGroups)
  assert_true(execution.state.key_comparison is Some(_))
  assert_true(@bounded.request_cancel(control))
  assert_false(pool_stopped(execution))
  assert_true(@records.producer_read_available(input))
  assert_true(
    advance_pool(execution, 1).unwrap()
    is PoolStopped(@bounded.Cancelled, work=256L, ..),
  )
  assert_true(execution.state.key_comparison is Some(_))
  assert_eq(cleanup_pool(execution), Ok(true))
  assert_true(execution.state.key_comparison is None)
  assert_eq(cleanup_pool(execution), Ok(false))
  assert_true(@records.producer_read_available(input))
  assert_true(@records.discard_completed(source))
}

///|
test "pool charges every long key comparison independent of quantum" {
  let producer = pool_producer_owner(text_keys=true)
  let source = pool_text_source(producer)
  let owner = pool_owner(producer)
  // Two admissions: 546; scratch: 2; identity sort: 132;
  // duplicate checks: 130; group sort: 132; group boundaries: 131;
  // two output groups: 20. Each new append has 31 base polls plus
  // three additional 64-unit polls for the 129-unit identity and three for
  // its group value: 37 per group. Total: 1093 + 2 * 37 = 1167.
  // No successful-run measurement supplies this limit. Admission reserves
  // 16 ordering + 5 output + 2 keys + 1 name + 56 append = 80 slots.
  // Two retained three-field rows add 2*(3+2), so completion requires 90.
  let exact = 1167
  for quantum in [1, 7, 256] {
    let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
    let execution = start_pool_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(work=10000, workspace=90),
      8192L,
      fn() { true },
      exact,
    ).unwrap()
    let mut polls = 0
    let mut finished = false
    while !finished && polls < 1200 {
      polls += 1
      match advance_pool(execution, quantum).unwrap() {
        PoolContinue(..) => ()
        PoolComplete(output, work~, ..) => {
          assert_eq(work, exact.to_int64())
          let storage = @records.completed_storage(output).unwrap()
          assert_eq(@storage.record_count(storage), 2)
          // Two records retain the original 18 logical construction units each.
          assert_eq(@storage.construction_work(storage), 36)
          for (index, suffix) in [(0, "a"), (1, "b")] {
            assert_true(
              pool_field(storage, index, "group").value is @value.Text(text) &&
              text == "x".repeat(128) + suffix,
            )
            assert_true(
              pool_field(storage, index, "member_count").value
              is @value.Number(1.0),
            )
            guard pool_field(storage, index, "embedding").value
              is @value.Vector(elements) else {
              fail("pooled vector")
            }
            assert_eq(@value.element_at(elements, 0), Some(1.0))
            assert_eq(@value.element_at(elements, 1), Some(2.0))
          }
          assert_true(@records.discard_completed(output))
          finished = true
        }
        _ => fail("pool must complete at its independent exact limit")
      }
    }
    assert_true(finished)
    assert_eq(cleanup_pool(execution), Ok(true))
    assert_eq(cleanup_pool(execution), Ok(false))
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}

///|
test "pool long keys enforce exact control and structural workspace limits" {
  let producer = pool_producer_owner(text_keys=true)
  let source = pool_text_source(producer)
  let owner = pool_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // Two sort buffers of two four-slot records, five output slots,
  // and two collected key slots: 16 + 5 + 2 = 23. Pending append adds
  // fixed 16, three slots for each of three fields (9), one identity (1),
  // and three depth-ten stacks (30): 56. One name offset makes admission 80.
  // Keep that reservation during append; two retained rows add 2*(3+2)=10,
  // making completion 90. The one-short admission check remains 79.
  assert_true(
    start_pool_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(work=10000, workspace=79),
      8192L,
      fn() { true },
      1167,
    )
    is Err(PoolWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    let execution = start_pool_with_control_work_limit(
      @bounded.control(),
      sequence(owner),
      0,
      input,
      limits(work=10000, workspace=90),
      8192L,
      fn() { true },
      1166,
    ).unwrap()
    let mut failed = false
    let mut polls = 0
    while !failed && polls < 1200 {
      polls += 1
      match advance_pool(execution, quantum).unwrap() {
        PoolContinue(..) => ()
        PoolFailed(PoolWorkLimit, work=1166L, ..) => failed = true
        _ => fail("one-short must fail with the typed control work limit")
      }
    }
    assert_true(failed)
    assert_true(pool_stopped(execution))
    assert_true(pool_cleanup_pending(execution))
    assert_eq(cleanup_pool(execution), Ok(true))
    assert_eq(cleanup_pool(execution), Ok(false))
    assert_false(pool_cleanup_pending(execution))
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}

///|
test "pool retains borrowed keys through scan cancellation and cleanup" {
  let producer = pool_producer_owner(text_keys=true)
  let source = pool_text_source(producer)
  let owner = pool_owner(producer)
  let input = @records.prepare_producer_read(owner, 0, producer, source).unwrap()
  // 40 is inside the first key validation; 600, 750, 900 and 1000
  // are inside identity sort, duplicate, group sort and boundary scans.
  for barrier in [40, 600, 750, 900, 1000] {
    let control = @bounded.control()
    let execution = start_pool_with_control_work_limit(
      control,
      sequence(owner),
      0,
      input,
      limits(work=10000, workspace=80),
      8192L,
      fn() { true },
      1167,
    ).unwrap()
    for _ in 0..<barrier {
      assert_true(advance_pool(execution, 1).unwrap() is PoolContinue(..))
    }
    assert_true(execution.state.key_comparison is Some(_))
    assert_true(
      execution.state.phase is ValidateGroups ||
      execution.state.phase is CompareIdentity ||
      execution.state.phase is CheckDuplicate ||
      execution.state.phase is CompareGroup ||
      execution.state.phase is FindGroupEnd,
    )
    assert_eq(
      cleanup_pool(execution),
      Err(PoolExecutionIssue(@bounded.NotStopped)),
    )
    assert_true(@bounded.request_cancel(control))
    assert_false(pool_stopped(execution))
    assert_true(@records.producer_read_available(input))
    guard advance_pool(execution, 1).unwrap()
      is PoolStopped(@bounded.Cancelled, work~, ..) else {
      fail("scan must stop before publication")
    }
    assert_eq(work, barrier.to_int64())
    assert_true(pool_stopped(execution))
    assert_true(pool_cleanup_pending(execution))
    assert_true(execution.state.key_comparison is Some(_))
    assert_true(@records.producer_read_available(input))
    assert_eq(cleanup_pool(execution), Ok(true))
    assert_eq(cleanup_pool(execution), Ok(false))
    assert_false(pool_cleanup_pending(execution))
    assert_true(execution.state.key_comparison is None)
    assert_eq(execution.state.records.length(), 0)
    assert_eq(execution.state.scratch.length(), 0)
    assert_true(execution.state.output is None)
    assert_true(@records.producer_read_available(input))
  }
  assert_true(@records.discard_completed(source))
}
