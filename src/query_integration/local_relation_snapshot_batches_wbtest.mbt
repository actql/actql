///|
test "Local Relation physical batches keep original work owner and refuse unspent overrun" {
  let measured_export_work = Ref(0L)
  for mode in [0, 1, 2] {
    let refused = mode == 1
    let (run, issuer) = captured_graph_fixture(
      dag_two_consumers_of_compute_a=true,
      count=true,
      count_filter_chain=true,
      keyed_count_filter_chain=true,
    )
    let graph = @strategy.captured_dag_graph(run)
    let registry = search_registry()
    let limits = dispatch_test_limits()
    let allowance = if refused {
      0
    } else if mode == 2 {
      measured_export_work.val.to_int()
    } else {
      1000
    }
    let max_work = captured_keyed_count_chain_work() + allowance
    let execution = { ..limits.local_execution, max_work, }
    let installed = @local_driver.prepare_local_dispatch_module(
      @host_driver.open_dispatch_driver(run),
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      dispatch_test_generated(run),
      execution,
      limits.guards,
      limits.candidate_work,
    ).unwrap()
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values: execution.rows.input_values,
        wire: retained_attempt_wire_limits(),
        row: {
          max_bytes: 100,
          max_nodes: 20,
          max_depth: 4,
          max_text_bytes: 100,
        },
        max_batch_bytes: 256,
      },
      None,
    ).unwrap()
    let owner = @strategy.graph_task_owner(graph, 1).unwrap()
    let setup : @local_driver.LocalManagedDispatchConfiguration[Int] = @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed,
        [@local_driver.local_managed_captured_relation_input()],
        @execution.process_managed_obligations(owner),
        0L,
      )
      .unwrap()
      .unwrap()
    let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
    let mut complete = false
    for _ in 0..<1000 {
      if (operations.advance)(1).unwrap().complete {
        complete = true
        break
      }
    }
    assert_true(complete)
    let original_work = (operations.cumulative_provider_work)().unwrap()
    assert_eq(original_work, captured_keyed_count_chain_work().to_int64())
    let released = Ref(false)
    let snapshot = (operations.prepare_relation_snapshot)(fn() { released.val })
      .unwrap()
      .unwrap()
    let text = StringBuilder()
    let mut spent = 0L
    let mut parts = 0
    let mut saved = false
    let mut rejected = false
    for _ in 0..<1000 {
      match (snapshot.advance_save)(7) {
        Err(@local_driver.ControlWorkLimit(limit)) => {
          assert_true(refused)
          assert_eq(limit, max_work)
          rejected = true
          break
        }
        Err(_) => fail("unexpected snapshot failure")
        Ok(next) => {
          assert_false(refused)
          assert_true(next.work >= 0L && next.work <= 7L)
          spent += next.work
          assert_eq(
            (operations.cumulative_provider_work)().unwrap(),
            original_work + spent,
          )
          if next.progress > 0L {
            // A staged physical frame is borrowed until the adapter takes it;
            // another advance cannot allocate a second outstanding frame.
            assert_true(
              (snapshot.advance_save)(1) is Err(@local_driver.Configuration(_)),
            )
            assert_eq(
              (operations.cumulative_provider_work)().unwrap(),
              original_work + spent,
            )
          }
          let part = (snapshot.take_output)().unwrap()
          if part != "" {
            parts += 1
            text.write_string(part)
          }
          if next.complete {
            saved = true
            break
          }
        }
      }
    }
    if refused {
      assert_true(rejected && !saved)
      assert_eq((operations.cumulative_provider_work)().unwrap(), original_work)
      assert_true((snapshot.content)() is Err(_))
    } else {
      assert_true(saved && !rejected)
      assert_true(spent > 2L)
      if mode == 0 {
        measured_export_work.val = spent
      } else {
        assert_eq(spent, measured_export_work.val)
      }
      assert_eq(parts, 2)
      assert_eq(text.to_string(), "[{\"id\":2},{\"id\":3}]")
      let content = (snapshot.content)().unwrap()
      assert_eq(content.bytes, @utf8.encode(text.to_string()).length())
      assert_eq(
        content.cid,
        "sha256:c274ffec8cbb1b1361fa532c9f95243ee4fe16ef1907f39a1525e3f525128677",
      )
    }
    (operations.close)()
    for _ in 0..<1000 {
      if (operations.cleanup_refresh)() {
        break
      }
    }
    @strategy.stop_captured_dag(run)
    for task in 0..<4 {
      @strategy.close_captured_task_output(run, task)
    }
    @strategy.refresh_captured_retention(run)
    @mock.close_mock_query_issuer(issuer)
  }
}
