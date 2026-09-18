///|
fn run_local_managed_test_task(
  installed : @local_driver.LocalDispatchModule,
  run : @strategy.CapturedDAG,
  task : Int,
  inputs : Array[@execution.ManagedCompletedOutput[Int]],
  rows : Array[Array[String]],
  payload : Int,
  available : Ref[Bool],
) -> (
  @local_driver.LocalManagedDispatchOperations[Int],
  @execution.ManagedCompletedOutput[Int],
) raise {
  let owner = @strategy.graph_task_owner(
    @strategy.captured_dag_graph(run),
    task,
  ).unwrap()
  let setup = match
    @local_driver.prepare_local_managed_dispatch(
      installed,
      inputs,
      @execution.process_managed_obligations(owner),
      0L,
    ) {
    Ok(Some(value)) => value
    Ok(None) => fail("Local managed candidate was not applicable")
    Err(Configuration(_)) => fail("Local managed configuration failed")
    Err(Preparation(_)) => fail("Local managed preparation failed")
    Err(Dispatch(_)) => fail("Local managed dispatch setup failed")
    Err(Execution(_)) => fail("Local managed input setup failed")
    Err(Search(_)) => fail("Local managed search failed")
    Err(ManagedValues(_)) => fail("Local managed value setup failed")
    Err(ManagedCopy(_)) => fail("Local managed copy setup failed")
    Err(ManagedRetention(_)) => fail("Local managed retention setup failed")
    Err(ManagedCompletion(_)) => fail("Local managed completion setup failed")
  }
  let operations = match
    @local_driver.start_local_managed_dispatch_node(setup) {
    Ok(value) => value
    Err(Configuration(_)) => fail("Local managed start configuration failed")
    Err(Preparation(_)) => fail("Local managed start preparation failed")
    Err(Dispatch(_)) => fail("Local managed start dispatch failed")
    Err(Execution(NotReady)) => fail("Local managed start was not ready")
    Err(Execution(Stopped)) => fail("Local managed run was stopped")
    Err(Execution(MissingOutput)) => fail("Local managed start missed output")
    Err(Execution(ForeignCandidate)) =>
      fail("Local managed start had a foreign candidate")
    Err(Execution(UnsupportedGraph)) =>
      fail("Local managed start had an unsupported graph")
    Err(Execution(ForeignCapture)) =>
      fail("Local managed start had a foreign capture")
    Err(Execution(Capture(_))) => fail("Local managed start capture failed")
    Err(Execution(Binding(_))) => fail("Local managed start binding failed")
    Err(Execution(Read(_))) => fail("Local managed start read failed")
    Err(Execution(Compute(_))) => fail("Local managed start compute failed")
    Err(Execution(Implementation(_))) =>
      fail("Local managed start implementation failed")
    Err(Execution(Physical(_))) => fail("Local managed start physical failed")
    Err(Search(_)) => fail("Local managed start search failed")
    Err(ManagedValues(_)) => fail("Local managed start value setup failed")
    Err(ManagedCopy(_)) => fail("Local managed start copy setup failed")
    Err(ManagedRetention(_)) => fail("Local managed start retention failed")
    Err(ManagedCompletion(_)) => fail("Local managed start completion failed")
  }
  assert_eq(operations.inputs.length(), rows.length())
  for index, transfer in operations.inputs {
    for row in rows[index] {
      match (transfer.append)(row) {
        Ok(_) => ()
        Err(Configuration(_)) => fail("Local managed row configuration failed")
        Err(Preparation(_)) => fail("Local managed row preparation failed")
        Err(Dispatch(_)) => fail("Local managed row dispatch failed")
        Err(Execution(Physical(_))) =>
          fail("Local managed row transfer capacity failed")
        Err(Execution(NotReady)) => fail("Local managed row was not ready")
        Err(Execution(Stopped)) => fail("Local managed row was stopped")
        Err(Execution(_)) => fail("Local managed row execution failed")
        Err(Search(_)) => fail("Local managed row search failed")
        Err(ManagedValues(_)) => fail("Local managed row value setup failed")
        Err(ManagedCopy(_)) => fail("Local managed row copy setup failed")
        Err(ManagedRetention(_)) =>
          fail("Local managed row retention setup failed")
        Err(ManagedCompletion(_)) =>
          fail("Local managed row completion setup failed")
      }
    }
    (transfer.finish)().unwrap()
  }
  match (operations.execute)() {
    Ok(_) => ()
    Err(
      @local_driver.Configuration(
        @connector.Execution(@execution.Rows(_, @execution.RowLimit))
      )
    ) => fail("Local managed execution exceeded its row budget")
    Err(
      @local_driver.Configuration(
        @connector.Execution(
          @execution.Rows(_, @execution.MissingOrderedResourceContext)
        )
      )
    ) => fail("Local managed execution lacked an ordered resource context")
    Err(@local_driver.Configuration(@connector.Execution(InputOwnership))) =>
      fail("Local managed sequence rejected input ownership")
    Err(@local_driver.Configuration(@connector.Execution(InputSet))) =>
      fail("Local managed sequence rejected the input set")
    Err(@local_driver.Configuration(@connector.Execution(Wiring(_)))) =>
      fail("Local managed sequence rejected input wiring")
    Err(
      @local_driver.Configuration(@connector.Execution(Rows(_, InputMismatch)))
    ) => fail("Local managed sequence rejected aligned input fields")
    Err(
      @local_driver.Configuration(@connector.Execution(Rows(_, OwnerMismatch)))
    ) => fail("Local managed sequence rejected a row owner")
    Err(@local_driver.Configuration(@connector.Execution(InvalidLimits))) =>
      fail("Local managed sequence rejected its limits")
    Err(
      @local_driver.Configuration(
        @connector.Execution(InputExecutionEvidencePending(_))
      )
    ) => fail("Local managed sequence lacked execution evidence")
    Err(
      @local_driver.Configuration(
        @connector.Execution(InputRepresentationRequired(_))
      )
    ) => fail("Local managed sequence lacked an input representation")
    Err(@local_driver.Configuration(@connector.Execution(InputLimit))) =>
      fail("Local managed sequence exceeded an input limit")
    Err(@local_driver.Configuration(@connector.Execution(InputKey(_, _)))) =>
      fail("Local managed sequence rejected an input key")
    Err(@local_driver.Configuration(@connector.Execution(Capture(_, _)))) =>
      fail("Local managed sequence failed capture")
    Err(@local_driver.Configuration(@connector.Execution(Store(_)))) =>
      fail("Local managed sequence failed storage")
    Err(@local_driver.Configuration(@connector.Execution(OrderedContext(_, _)))) =>
      fail("Local managed sequence rejected ordered context")
    Err(
      @local_driver.Configuration(@connector.Execution(FragmentContext(_, _)))
    ) => fail("Local managed sequence rejected fragment context")
    Err(
      @local_driver.Configuration(
        @connector.Execution(MissingFragmentContext(_))
      )
    ) => fail("Local managed sequence missed fragment context")
    Err(
      @local_driver.Configuration(
        @connector.Execution(MixedExecutionConfiguration)
      )
    ) => fail("Local managed sequence mixed execution configuration")
    Err(
      @local_driver.Configuration(
        @connector.Execution(UnsupportedRowComparison(_, _))
      )
    ) => fail("Local managed sequence lacked row comparison support")
    Err(@local_driver.Preparation(_)) =>
      fail("Local managed execution failed preparation")
    Err(@local_driver.Dispatch(_)) =>
      fail("Local managed execution failed dispatch")
    Err(
      @local_driver.Execution(
        @strategy.Compute(@connector.Execution(UnsupportedRowComparison(_, _)))
      )
    ) => fail("Local managed runtime lacked row comparison support")
    Err(
      @local_driver.Execution(
        @strategy.Compute(@connector.Execution(Rows(_, Comparison(_))))
      )
    ) => fail("Local managed runtime failed scalar comparison")
    Err(@local_driver.Execution(@strategy.Compute(@connector.Execution(_)))) =>
      fail("Local managed runtime sequence failed")
    Err(@local_driver.Execution(@strategy.Compute(_))) =>
      fail("Local managed runtime compute failed")
    Err(@local_driver.Execution(@strategy.Physical(_))) =>
      fail("Local managed runtime physical accounting failed")
    Err(@local_driver.Execution(_)) => fail("Local managed runtime failed")
    Err(@local_driver.Search(_)) => fail("Local managed search failed")
    Err(@local_driver.ManagedValues(_)) =>
      fail("Local managed value setup failed")
    Err(@local_driver.ManagedCopy(_)) => fail("Local managed copy setup failed")
    Err(@local_driver.ManagedRetention(_)) =>
      fail("Local managed retention setup failed")
    Err(@local_driver.ManagedCompletion(_)) =>
      fail("Local managed completion setup failed")
    Err(_) => fail("Local managed dispatch failed")
  }
  (operations.settle)().unwrap()
  let completed = (operations.complete)(payload, operations.storage_bytes, fn() {
    available.val
  }).unwrap()
  assert_true(
    @strategy.captured_managed_task_output_matches(
      run,
      task,
      @strategy.captured_task_target(run, task).unwrap(),
      completed,
    ),
  )
  (operations, completed)
}

///|
fn local_managed_test_rows(
  operations : @local_driver.LocalManagedDispatchOperations[Int],
) -> Array[String] {
  Array::makei((operations.output_rows)(), index => {
    (operations.output_row)(index).unwrap()
  })
}

///|
fn run_local_managed_group_case(
  variant : String,
  input_expected : Array[String],
  group_expected : Array[String],
  second_expected : Array[String],
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_group_chain=true,
    local_values_group_variant=variant,
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  let expanded = variant == "direct" ||
    variant == "ordered" ||
    variant == "collections"
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: if expanded {
          512
        } else {
          100
        },
        max_nodes: if expanded {
          100
        } else {
          20
        },
        max_columns: if expanded {
          6
        } else {
          4
        },
      },
      row: {
        max_bytes: if expanded {
          1000
        } else {
          100
        },
        max_nodes: if expanded {
          100
        } else {
          20
        },
        max_depth: 4,
        max_text_bytes: if expanded {
          1000
        } else {
          100
        },
      },
      max_batch_bytes: if expanded {
        512
      } else {
        64
      },
    },
    None,
  ).unwrap()

  let value_live = Ref(true)
  let (value_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    value_live,
  )
  let value_rows = local_managed_test_rows(value_ops)
  assert_eq(value_rows, input_expected)

  let group_live = Ref(true)
  let (group_ops, groups) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [value_rows],
    2,
    group_live,
  )
  let group_rows = local_managed_test_rows(group_ops)
  assert_eq(group_rows, group_expected)

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [groups],
    [group_rows],
    3,
    first_live,
  )
  assert_eq(local_managed_test_rows(first_ops), group_rows)

  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [groups],
    [group_rows],
    4,
    second_live,
  )
  assert_eq(local_managed_test_rows(second_ops), second_expected)
  assert_true(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))

  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(groups))

  second_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  group_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (group_ops.close)()
  (group_ops.cleanup_refresh)() |> ignore
  value_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (value_ops.close)()
  (value_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "Local managed group count orders nullable keys for two consumers" {
  run_local_managed_group_case(
    "keyed",
    ["{\"id\":null}", "{\"id\":1}", "{\"id\":1}"],
    ["{\"id\":null,\"n\":1}", "{\"id\":1,\"n\":2}"],
    ["{\"n\":1,\"id\":null}", "{\"n\":2,\"id\":1}"],
  )
}

///|
test "Local managed group count preserves compound canonical order" {
  run_local_managed_group_case(
    "compound",
    [
      "{\"a\":1,\"b\":\"b\"}", "{\"a\":null,\"b\":\"a\"}", "{\"a\":1,\"b\":\"a\"}",
      "{\"a\":null,\"b\":\"a\"}",
    ],
    [
      "{\"a\":null,\"b\":\"a\",\"n\":2}", "{\"a\":1,\"b\":\"a\",\"n\":1}", "{\"a\":1,\"b\":\"b\",\"n\":1}",
    ],
    [
      "{\"n\":2,\"b\":\"a\",\"a\":null}", "{\"n\":1,\"b\":\"a\",\"a\":1}", "{\"n\":1,\"b\":\"b\",\"a\":1}",
    ],
  )
}

///|
test "Local managed keyed group emits no group for empty input" {
  run_local_managed_group_case("empty_keyed", [], [], [])
}

///|
test "Local managed global group emits zero for empty input" {
  run_local_managed_group_case("empty_global", [], ["{\"n\":0}"], ["{\"n\":0}"])
}

///|
test "Local managed group distinguishes row and field counts" {
  run_local_managed_group_case(
    "counts",
    ["{\"id\":null}", "{\"id\":1}", "{\"id\":1}"],
    ["{\"id\":null,\"n\":1,\"present\":0}", "{\"id\":1,\"n\":2,\"present\":2}"],
    ["{\"present\":0,\"n\":1,\"id\":null}", "{\"present\":2,\"n\":2,\"id\":1}"],
  )
}

///|
test "Local managed direct aggregates reach two independent consumers" {
  run_local_managed_group_case(
    "direct",
    [
      "{\"amount\":\"1.25\",\"flag\":true,\"k\":2,\"label\":\"b\"}", "{\"amount\":\"-0.25\",\"flag\":true,\"k\":null,\"label\":\"a\"}",
      "{\"amount\":null,\"flag\":null,\"k\":1,\"label\":null}", "{\"amount\":\"2.00\",\"flag\":false,\"k\":2,\"label\":\"a\"}",
      "{\"amount\":\"0.50\",\"flag\":false,\"k\":null,\"label\":\"c\"}",
    ],
    [
      "{\"distinct_labels\":2,\"highest\":\"c\",\"hits\":1,\"k\":null,\"lowest\":\"a\",\"total\":\"0.25\"}",
      "{\"distinct_labels\":0,\"highest\":null,\"hits\":0,\"k\":1,\"lowest\":null,\"total\":null}",
      "{\"distinct_labels\":2,\"highest\":\"b\",\"hits\":1,\"k\":2,\"lowest\":\"a\",\"total\":\"3.25\"}",
    ],
    [
      "{\"total\":\"0.25\",\"lowest\":\"a\",\"k\":null,\"hits\":1,\"highest\":\"c\",\"distinct_labels\":2}",
      "{\"total\":null,\"lowest\":null,\"k\":1,\"hits\":0,\"highest\":null,\"distinct_labels\":0}",
      "{\"total\":\"3.25\",\"lowest\":\"a\",\"k\":2,\"hits\":1,\"highest\":\"b\",\"distinct_labels\":2}",
    ],
  )
}

///|
test "Local managed ordered aggregates reach two independent consumers" {
  run_local_managed_group_case(
    "ordered",
    [
      "{\"id\":1,\"k\":1,\"label\":null}", "{\"id\":2,\"k\":1,\"label\":\"low\"}",
      "{\"id\":3,\"k\":1,\"label\":\"high\"}", "{\"id\":1,\"k\":2,\"label\":null}",
    ],
    [
      "{\"first_asc\":\"low\",\"first_desc\":\"high\",\"k\":1,\"last_asc\":\"high\",\"last_desc\":\"low\"}",
      "{\"first_asc\":null,\"first_desc\":null,\"k\":2,\"last_asc\":null,\"last_desc\":null}",
    ],
    [
      "{\"last_desc\":\"low\",\"last_asc\":\"high\",\"k\":1,\"first_desc\":\"high\",\"first_asc\":\"low\"}",
      "{\"last_desc\":null,\"last_asc\":null,\"k\":2,\"first_desc\":null,\"first_asc\":null}",
    ],
  )
}

///|
test "Local managed collection aggregates reach two independent consumers" {
  run_local_managed_group_case(
    "collections",
    [
      "{\"id\":1,\"k\":1,\"label\":\"a\"}", "{\"id\":2,\"k\":1,\"label\":null}",
      "{\"id\":3,\"k\":1,\"label\":\"b\"}",
    ],
    ["{\"items\":[\"a\",\"b\"],\"k\":1,\"n\":3,\"text\":\"b|a\"}"],
    ["{\"text\":\"b|a\",\"n\":3,\"k\":1,\"items\":[\"a\",\"b\"]}"],
  )
}
