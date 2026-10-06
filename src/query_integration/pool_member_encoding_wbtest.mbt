///|
fn long_pool_member_source() -> @lower.BoundPrepared {
  direct_nearest_bind(
    @pipeline.check(
      input_cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"string\",\"nullable\":false}," +
        "\"code\":{\"type\":\"number\",\"nullable\":false}," +
        "\"group\":{\"type\":\"number\",\"nullable\":false}," +
        "\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}}," +
        "\"rows\":[{\"id\":\"" +
        String::make(129, 'x') +
        "\",\"code\":1,\"group\":1,\"embedding\":[1,2]}]},\"as\":\"source\"}," +
        "{\"from\":\"source\",\"assert_rows\":{\"unique_by\":[\"id\",\"code\"]},\"as\":\"keyed\"}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
test "Relation Pool member encoding has independent work workspace and stop boundaries" {
  let source = long_pool_member_source()
  let owner = direct_relation_pool_owner(source)
  guard @lower.sequence_step(prepared_sequence(owner), 0)
    is Some(@lower.VectorStep(pool)) else {
    fail("Pool step missing")
  }
  // The canonical key evidence orders the numeric code before the Text id.
  assert_eq(@lower.vector_pool_identity_at(pool, 0), Some("code"))
  assert_eq(@lower.vector_pool_identity_at(pool, 1), Some("id"))
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
  // Start from the independent one-record numeric fixture's 72 polls.
  // The second key adds one initialization, seven field scans, one key
  // validation, two scalar rechecks and one encoding poll: twelve polls.
  // A 129-unit Text identity adds 128 comparison polls and three input
  // recheck polls. Encoding adds four measure polls, three copy polls and
  // five final recheck polls: 72+12+128+3+4+3+5 = 227.
  // 21 structural + 20 recheck + 45 append slots = 86; the scalar
  // cursor reuses input recheck custody after all fields have been bound.
  assert_true(
    @local_veca.start_relation_pool(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      read,
      direct_relation_pool_limits(85, 227),
      4096L,
      fn() { true },
    )
    is Err(@local_veca.PoolWorkspaceLimit),
  )
  for quantum in [1, 7, 256] {
    for (work, success) in [(227, true), (226, false)] {
      let active = @local_veca.start_relation_pool(
        @bounded.control(),
        prepared_sequence(owner),
        0,
        read,
        direct_relation_pool_limits(86, work),
        4096L,
        fn() { true },
      ).unwrap()
      let mut terminal = false
      for _ in 0..<230 {
        if !terminal {
          match @local_veca.advance_pool(active, quantum).unwrap() {
            @local_veca.PoolContinue(..) => ()
            @local_veca.PoolComplete(output, work~, ..) => {
              assert_true(success)
              assert_eq(work, 227L)
              let stored = @records.completed_storage(output).unwrap()
              assert_eq(@record_storage.record_count(stored), 1)
              assert_eq(@record_storage.record_field_count(stored, 0), Some(3))
              guard @record_storage.record_field_at(stored, 0, 0)
                is Some(
                  (
                    @schema.Unqualified("embedding"),
                    { value: @admitted.Vector(vector), .. },
                  )
                ) else {
                fail("Pool output vector missing")
              }
              assert_eq(@admitted.element_count(vector), 2)
              assert_eq(@admitted.element_at(vector, 0), Some(1.0))
              assert_eq(@admitted.element_at(vector, 1), Some(2.0))
              assert_true(
                @record_storage.record_field_at(stored, 0, 1)
                is Some(
                  (
                    @schema.Unqualified("group"),
                    { value: @admitted.Number(1.0), .. },
                  )
                ),
              )
              assert_true(
                @record_storage.record_field_at(stored, 0, 2)
                is Some(
                  (
                    @schema.Unqualified("member_count"),
                    { value: @admitted.Number(1.0), .. },
                  )
                ),
              )
              assert_true(@records.discard_completed(output))
              terminal = true
            }
            @local_veca.PoolFailed(issue, work~, ..) => {
              assert_false(success)
              assert_eq(issue, @local_veca.PoolWorkLimit)
              assert_eq(work, 226L)
              terminal = true
            }
            _ => fail("member encoding exposed an unrelated terminal outcome")
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
    direct_relation_pool_limits(86, 227),
    4096L,
    fn() { true },
  ).unwrap()
  // Encoding begins after 23+11+128+3=165. Numeric code uses poll 166,
  // Text measurement ends at 171; poll 172 copies only the first 64 units.
  for _ in 0..<172 {
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
  assert_true(
    @local_veca.advance_pool(active, 1).unwrap()
    is @local_veca.PoolStopped(@bounded.Cancelled, work=172L, progress=0L),
  )
  assert_eq(@local_veca.cleanup_pool(active), Ok(true))
  assert_eq(@local_veca.cleanup_pool(active), Ok(false))
  assert_true(@execution.producer_read_available(read))
  // The encoded tuple is exactly "1:1|129:" + 129 x's + "|": 138
  // bytes. The 129-byte input remains valid when only this encoding is short.
  for (bytes, success) in [(138, true), (137, false)] {
    let active = @local_veca.start_relation_pool(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      read,
      { ..direct_relation_pool_limits(86, 227), max_value_bytes: bytes, },
      4096L,
      fn() { true },
    ).unwrap()
    let mut terminal = false
    for _ in 0..<230 {
      if !terminal {
        match @local_veca.advance_pool(active, 1).unwrap() {
          @local_veca.PoolContinue(..) => ()
          @local_veca.PoolComplete(output, ..) => {
            assert_true(success)
            assert_true(@records.discard_completed(output))
            terminal = true
          }
          @local_veca.PoolFailed(issue, work~, progress~) => {
            assert_false(success)
            assert_eq(issue, @local_veca.InvalidPoolIdentity(0))
            // Numeric code used 166; Text is measured at 167..171. The
            // aggregate byte guard rejects before any Text copy at 172.
            assert_eq(work, 171L)
            assert_eq(progress, 0L)
            terminal = true
          }
          _ => fail("member byte limit exposed an unrelated failure")
        }
      }
    }
    assert_true(terminal)
    assert_eq(@local_veca.cleanup_pool(active), Ok(true))
    assert_true(@execution.producer_read_available(read))
  }
}
