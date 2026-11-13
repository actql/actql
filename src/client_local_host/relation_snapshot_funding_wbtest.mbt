///|
test "metered snapshot tiny rows fit without configured-frame headroom and byte-short denies emission" {
  for short in [false, true] {
    let original = single_installed_prepared(
      document=(
        #|{"version":"actql/0.1","id":"snapshot-row-funding","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id >= 2"},{"derive":{}},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"finish","inputs":{"r":{"result":{"stage":"compute","result":"rows"}}},"steps":[{"filter":"id < 3"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"finish","result":"rows"}}}}
      ),
    )
    let value = captured_tasks_fixture(original=Some(original))
    let before = @resources.ledger_usage(value.ledger)
    let (run, dispatch) = metered_tail_dispatch(value)
    let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
    let tasks : Array[LocalValuesTaskExecution?] = Array::make(3, None)
    tasks[1] = Some({ operations, settled: false, completed: None, })
    (operations.execute)().unwrap()
    let original_work = (operations.cumulative_provider_work)().unwrap()
    let released = Ref(false)
    let snapshot = (operations.prepare_relation_snapshot)(() => released.val)
      .unwrap()
      .unwrap()
    // The same traversal measures one digit and the actual two-unit key.
    // Existing conservative row framing: 3 + 1 + 4 + 6*2 = 20 bytes;
    // its first pending array prefix adds 1. Three overlapping occurrences
    // use the existing 8-byte CanonicalWireBytes unit: 21*3*8 = 504.
    let available = if short { 503L } else { 600L }
    assert_true(snapshot.frames.maxFrameBytes.to_int64() * 8L > available)
    let remaining = @resources.ledger_limits(value.ledger).execution_bytes -
      @resources.ledger_usage(value.ledger).reserved_execution_bytes
    assert_true(remaining > available)
    let blocker = @resources.reserve_capacity(
      value.ledger,
      0L,
      remaining - available,
    ).unwrap()
    let initial_reserved = @resources.ledger_usage(value.ledger).reserved_execution_bytes
    let parts : Array[String] = []
    let mut completed = false
    let mut refused = false
    let mut prefix_work = 0L
    for _ in 0..<1000 {
      let before_poll = (operations.cumulative_provider_work)().unwrap()
      let before_bytes = @resources.ledger_usage(value.ledger).reserved_execution_bytes
      match (snapshot.advance_save)(1) {
        Err(@local_driver.Execution(Physical(ExecutionLimit))) => {
          assert_true(short)
          // Prior metadata measurement stays spent. This denied emission
          // transition constructs no row and adds no work/reservation.
          assert_eq(
            (operations.cumulative_provider_work)().unwrap(),
            before_poll,
          )
          assert_eq(
            @resources.ledger_usage(value.ledger).reserved_execution_bytes,
            before_bytes,
          )
          refused = true
          break
        }
        Err(_) => fail("unexpected metered snapshot failure")
        Ok(next) => {
          assert_true(next.work >= 0L && next.work <= 1L)
          prefix_work += next.work
          assert_eq(
            (operations.cumulative_provider_work)().unwrap(),
            original_work + prefix_work,
          )
          let part = (snapshot.take_output)().unwrap()
          if part != "" {
            parts.push(part)
          }
          if next.complete {
            completed = true
            break
          }
        }
      }
    }
    assert_true(prefix_work > 0L)
    if short {
      assert_true(refused && !completed)
      assert_eq(parts.length(), 0)
      assert_true((snapshot.content)() is Err(_))
    } else {
      assert_true(completed && !refused)
      // Observable growth on the SAME Ledger, not an internal mode Bool,
      // proves this uses actual-output metering rather than a prepaid path.
      assert_true(
        @resources.ledger_usage(value.ledger).reserved_execution_bytes >
        initial_reserved,
      )
      // A full configured frame cannot fit. Pure quota refusal flushes the
      // first completed row, and the same pending second row then proceeds.
      assert_eq(parts.length(), 3)
      assert_eq(parts.join(""), "[{\"id\":3},{\"id\":2}]")
      assert_eq((snapshot.content)().unwrap().bytes, 19)
    }
    // These test-owned chunks are the component backing, not a filesystem
    // or Site. Release their actual references before acknowledging only
    // that fixture debt; no process exit or whole Host ACK is substituted.
    parts.clear()
    released.val = true
    let mut closed = false
    for _ in 0..<10000 {
      if close_local_values_tasks(run, tasks) {
        closed = true
        break
      }
    }
    assert_true(closed)
    assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
    @resources.settle_capacity(value.ledger, blocker).unwrap()
    let after = @resources.ledger_usage(value.ledger)
    assert_eq(after.held_bytes, before.held_bytes)
    assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
    captured_tasks_close_source(value)
  }
}

///|
test "metered empty snapshot funds both delimiters before zero-work finalization" {
  for short in [false, true] {
    let original = single_installed_prepared(
      document=(
        #|{"version":"actql/0.1","id":"snapshot-empty-tail-funding","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id > 99"},{"derive":{}},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"finish","inputs":{"r":{"result":{"stage":"compute","result":"rows"}}},"steps":[{"filter":"id < 3"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"finish","result":"rows"}}}}
      ),
    )
    let value = captured_tasks_fixture(original=Some(original))
    let before = @resources.ledger_usage(value.ledger)
    let (run, dispatch) = metered_tail_dispatch(value)
    let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
    let tasks : Array[LocalValuesTaskExecution?] = Array::make(3, None)
    tasks[1] = Some({ operations, settled: false, completed: None, })
    (operations.execute)().unwrap()
    let original_work = (operations.cumulative_provider_work)().unwrap()
    let released = Ref(false)
    let snapshot = (operations.prepare_relation_snapshot)(() => released.val)
      .unwrap()
      .unwrap()
    // Empty rows never drain the initial '['. The exact tail is '[]':
    // two canonical UTF-8 bytes, three overlapping aliases at eight bytes each.
    let available = if short { 47L } else { 48L }
    let remaining = @resources.ledger_limits(value.ledger).execution_bytes -
      @resources.ledger_usage(value.ledger).reserved_execution_bytes
    assert_true(remaining > available)
    let blocker = @resources.reserve_capacity(
      value.ledger,
      0L,
      remaining - available,
    ).unwrap()
    let initial_reserved = @resources.ledger_usage(value.ledger).reserved_execution_bytes
    let saved = (snapshot.advance_save)(1)
    assert_eq((operations.cumulative_provider_work)().unwrap(), original_work)
    if short {
      assert_true(
        saved is Err(@local_driver.Execution(Physical(ExecutionLimit))),
      )
      assert_eq(
        @resources.ledger_usage(value.ledger).reserved_execution_bytes,
        initial_reserved,
      )
      assert_true((snapshot.content)() is Err(_))
      // The failed phase cannot expose even an empty output frame.
      assert_true(
        (snapshot.take_output)() is Err(@local_driver.Execution(Stopped)),
      )
    } else {
      let next = saved.unwrap()
      assert_true(next.complete)
      assert_eq(next.work, 0L)
      assert_eq(next.progress, 2L)
      assert_eq((snapshot.take_output)().unwrap(), "[]")
      let content = (snapshot.content)().unwrap()
      assert_eq(content.bytes, 2)
      // Independent SHA-256 of the literal canonical empty array.
      assert_eq(
        content.cid,
        "sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
      )
      assert_eq(
        @resources.ledger_usage(value.ledger).reserved_execution_bytes,
        initial_reserved + 48L,
      )
    }
    // This component owns only the test chunk, not a physical file or Site ACK.
    released.val = true
    let mut closed = false
    for _ in 0..<10000 {
      if close_local_values_tasks(run, tasks) {
        closed = true
        break
      }
    }
    assert_true(closed)
    @resources.settle_capacity(value.ledger, blocker).unwrap()
    let after = @resources.ledger_usage(value.ledger)
    assert_eq(after.held_bytes, before.held_bytes)
    assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
    captured_tasks_close_source(value)
  }
}
