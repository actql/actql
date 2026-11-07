///|
// Actual checked Effect, two complete Direct Source inputs in one task, the
// existing admitted managed parent, two RowRuns and the same physical host.
#cfg(target="js")
test "Whole Source snapshots restore exact original Inputs and execute the same Effect host" {
  let plan = effect_operation_source_plan_fixture(whole_inputs=true)
  let bound = effect_parent_bound_run(plan.prepared)
  assert_eq(plan.captures.length(), 0)
  assert_eq(plan.whole_sources.length(), 2)
  assert_eq(@strategy.graph_captured_prefix(plan.graph), 0)
  let coordinates = plan.direct_occurrences.unwrap()
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_at(coordinates, 0),
    Some((0, 0, 0)),
  )
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_at(coordinates, 1),
    Some((0, 1, 0)),
  )
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  assert_true(
    installed_effect_managed_sources_ledger(owner, plan.prepared, plan.request)
    is Err(ForeignOriginal),
  )
  let snapshots = []
  for occurrence in 0..<2 {
    let (declaration, source) = plan.whole_sources[occurrence].unwrap()
    assert_true(source.provider is None)
    assert_eq(
      installed_effect_managed_source_input_kind(
        owner,
        plan.prepared,
        plan.request,
        occurrence,
      ).unwrap(),
      "whole-input",
    )
    let (read, original, acquisition, selected) = begin_installed_effect_managed_whole_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      occurrence,
    ).unwrap()
    assert_true(physical_equal(selected, source))
    assert_true(physical_equal(original, source.original))
    assert_true(read.requirement is None && read.acquisition is None)
    assert_true(
      begin_installed_effect_managed_whole_source_read(
        owner,
        plan.prepared,
        plan.request,
        declaration,
        occurrence,
      )
      is Err(AlreadyBound),
    )
    let run = match
      start_installed_whole_source_read_rows(
        read,
        acquisition,
        "effect-whole-" + occurrence.to_string(),
        _ => true,
        1024L,
        2048L,
      ) {
      Ok(value) => value
      Err(Acquisition(Physical(issue))) =>
        fail("WholeSource physical admission: " + @debug.to_string(issue))
      Err(Acquisition(_)) => fail("WholeSource row admission")
      Err(_) => fail("WholeSource managed read")
    }
    @row_source_host.begin_row_run_with_page_limits(
      run,
      { max_bytes: 128, max_nodes: 1000, max_depth: 20, max_rows: 3, },
      3,
    ).unwrap()
    let body = @utf8.encode("[{\"id\":3}]")
    let charge = @row_source_host.charge_row_run_page(run, body).unwrap()
    @row_source_host.accept_charged_row_run_page(run, charge, body).unwrap()
    |> ignore
    @row_source_host.finish_row_run(run).unwrap()
    @row_source_host.begin_row_capture(run).unwrap()
    let mut complete = false
    for _ in 0..<10000 {
      if @row_source_host.advance_row_capture(run, 256).unwrap().0 {
        complete = true
        break
      }
    }
    assert_true(complete)
    let capture = @row_source_host.capture_row_run(run).unwrap()
    let actual = @row_source_host.row_capture_source(capture).unwrap()
    assert_true(
      @query.captured_source_matches_input_acquisition(actual, original),
    )
    let binding = "same-run-source-" + occurrence.to_string()
    let (identity, schema, rows_cid, wires) = export_client_whole_source_capture(
      actual, source, binding,
    ).unwrap()
    assert_true(
      export_client_whole_source_capture(
        actual,
        plan.whole_sources[1 - occurrence].unwrap().1,
        binding,
      )
      is Err(BindingMismatch),
    )
    snapshots.push((identity, schema, rows_cid, wires))
    retire_installed_source_read(read).unwrap()
    assert_false(@query.captured_source_available(actual))
  }
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  // Cold receiving admission reuses the same checked Plan/Request and bound
  // Run, with no new acquisition, Check or source provider call.
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let sibling = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
  let sources = []
  let restored = []
  let custody = Ref(true)
  for occurrence in 0..<2 {
    let source = plan.whole_sources[occurrence].unwrap().1
    let binding = "same-run-source-" + occurrence.to_string()
    let (identity, schema, rows_cid, wires) = snapshots[occurrence]
    let before = @resources.ledger_usage(ledger)
    assert_true(
      restore_accounted_client_whole_source_capture(
        source,
        binding,
        "foreign",
        identity,
        schema,
        rows_cid,
        wires,
        ledger,
        () => true,
      )
      is Err(BindingMismatch),
    )
    assert_true(
      restore_accounted_client_whole_source_capture(
        plan.whole_sources[1 - occurrence].unwrap().1,
        binding,
        binding,
        identity,
        schema,
        rows_cid,
        wires,
        ledger,
        () => true,
      )
      is Err(BindingMismatch),
    )
    assert_true(
      restore_accounted_client_whole_source_capture(
        source,
        binding,
        binding,
        identity,
        schema,
        rows_cid,
        wires,
        ledger,
        () => false,
      )
      is Err(CustodyUnavailable),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    let saved = restore_accounted_client_whole_source_capture(
      source,
      binding,
      binding,
      identity,
      schema,
      rows_cid,
      wires,
      ledger,
      () => custody.val,
    ).unwrap()
    let restored_source = accounted_client_source_capture_source(saved).unwrap()
    let again = export_client_whole_source_capture(
      restored_source, source, binding,
    ).unwrap()
    assert_eq(again, (identity, schema, rows_cid, wires))
    sources.push(restored_source)
    restored.push(saved)
  }
  assert_true(
    open_installed_effect_managed_host(owner, bound, [sources[1], sources[0]])
    is Err(ForeignOriginal),
  )
  let (host, captured, _) = open_installed_effect_managed_host(
      owner, bound, sources,
    )
    .unwrap()
    .unwrap()
  let dag = @strategy.captured_effect_run_dag(captured)
  assert_false(@strategy.captured_task_completed(dag, 0))
  assert_eq(@strategy.next_captured_task(dag), Some(0))
  for value in restored {
    assert_true(
      retain_accounted_client_source_capture_task(value, dag, 0)
      is Err(BindingMismatch),
    )
    assert_true(
      retain_accounted_client_source_capture_input(value, dag, 1)
      is Err(BindingMismatch),
    )
    retain_accounted_client_source_capture_input(value, dag, 0).unwrap()
    assert_true(
      retain_accounted_client_source_capture_input(value, dag, 0)
      is Err(BindingMismatch),
    )
  }
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap()
  let operations : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let output_live = Ref(true)
  let mut available : Array[@local_driver.LocalManagedAvailableOutput[Int]] = [
    @local_driver.local_managed_supplied_relation_input(),
    @local_driver.local_managed_supplied_relation_input(),
  ]
  for task in 0..<2 {
    let dispatch = @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed,
        available,
        @execution.process_managed_obligations(
          @strategy.graph_task_owner(plan.graph, task).unwrap(),
        ),
        0L,
      )
      .unwrap()
      .unwrap()
    @strategy.select_captured_managed_registration(
      dag,
      task,
      @local_driver.local_dispatch_registration(installed),
    ).unwrap()
    let original = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
    if task == 0 {
      assert_true(original.inputs.is_empty())
    }
    for transfer in original.inputs {
      (transfer.append)((operations[task - 1].output_row)(0).unwrap()).unwrap()
      (transfer.finish)().unwrap()
    }
    match (original.execute)() {
      Ok(_) => ()
      Err(Configuration(InputUnavailable)) =>
        fail("Whole Source Compute input unavailable")
      Err(Configuration(ComputeUnsupported)) =>
        fail("Whole Source Compute unsupported")
      Err(Configuration(Execution(InputOwnership))) =>
        fail("Whole Source sequence input ownership")
      Err(Configuration(Execution(InputSet))) =>
        fail("Whole Source sequence input set")
      Err(Configuration(Execution(InputLimit))) =>
        fail("Whole Source sequence input limit")
      Err(Configuration(Execution(MixedExecutionConfiguration))) =>
        fail("Whole Source sequence mixed configuration")
      Err(Configuration(Execution(_))) => fail("Whole Source sequence other")
      Err(Configuration(_)) => fail("Whole Source Compute configuration")
      Err(Execution(Physical(issue))) =>
        fail("Whole Source Compute physical: " + @debug.to_string(issue))
      Err(_) => fail("Whole Source Compute other")
    }
    (original.prepare_finalization)(task, original.storage_bytes, () => {
      output_live.val
    }).unwrap()
    let mut finalized = false
    for _ in 0..<10000 {
      if (original.advance_finalization)(256).unwrap().complete {
        finalized = true
        break
      }
    }
    assert_true(finalized)
    (original.settle)().unwrap()
    let completed = (original.complete)(task, original.storage_bytes, () => {
      output_live.val
    }).unwrap()
    assert_eq(@execution.managed_completed_output_row_count(completed), 1)
    assert_eq((original.output_row)(0).unwrap(), "{\"id\":3}")
    operations.push(original)
    available = [@local_driver.local_managed_relation_output(completed)]
  }
  assert_true(@strategy.captured_task_completed(dag, 0))
  assert_true(@strategy.captured_task_completed(dag, 1))
  output_live.val = false
  for original in operations {
    (original.close)()
  }
  let mut retired = false
  for _ in 0..<10000 {
    for original in operations {
      (original.cleanup_refresh)() |> ignore
    }
    if retire_installed_effect_captured_consumers(owner).unwrap() {
      retired = true
      break
    }
  }
  assert_true(retired)
  let first = restored[0]
  assert_false(close_accounted_client_source_capture(first, quantum=1))
  assert_true(accounted_client_source_capture_cleanup_pending(first))
  assert_true(accounted_client_source_capture_source(first) is None)
  assert_true(accounted_client_source_original_read(first) is None)
  assert_true(accounted_client_source_capture_source(restored[1]) is Some(_))
  for value in restored {
    let mut closed = false
    for _ in 0..<10000 {
      if close_accounted_client_source_capture(value, quantum=1) {
        closed = true
        break
      }
    }
    assert_true(closed)
    assert_false(accounted_client_source_capture_cleanup_pending(value))
  }
  custody.val = false
  assert_true(
    installed_effect_managed_sources_ledger(owner, plan.prepared, plan.request)
    is Err(ForeignOriginal),
  )
  @resources.settle_capacity(ledger, sibling).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
#cfg(target="js")
fn whole_source_saved_input_fixture() -> (
  ClientInstalledEffectManagedPlan,
  (Array[String], String, String, Array[String]),
) raise {
  let policy = installed_row_input_policy(128, 2097152, 10000, 32, 128)
  let plan = effect_operation_source_plan_fixture(
    whole_inputs=true,
    whole_policy=Some(policy),
  )
  let declaration = plan.whole_sources[0].unwrap().0
  let over_rows = false
  let mut snapshot : (Array[String], String, String, Array[String])? = None
  {
    let (input, initial, ledger, capacity) = effect_parent_test_preparation(
      plan,
      prepared_installed_effect_managed_requirements(plan),
    )
    let owner = begin_preparation_owned_installed_effect_managed_run(
      initial,
      input,
      capacity,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
    let (read, _, acquisition, _) = begin_installed_effect_managed_whole_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      0,
    ).unwrap()
    assert_eq(@row_source_host.row_input_acquisition_max_rows(acquisition), 128)
    let run = start_installed_whole_source_read_rows(
      read,
      acquisition,
      "configured-whole-policy",
      _ => true,
      2097152L,
      2097152L,
    ).unwrap()
    assert_true(
      @row_source_host.begin_row_run_with_page_limits(run, policy.page, 129)
      is Err(Source(InvalidPage)),
    )
    assert_true(
      @row_source_host.begin_row_run_with_page_limits(
        run,
        { ..policy.page, max_bytes: 2097153, },
        128,
      )
      is Err(Source(InvalidPage)),
    )
    @row_source_host.begin_row_run_with_page_limits(run, policy.page, 128).unwrap()
    let count = if over_rows { 129 } else { 128 }
    let body = @utf8.encode(
      "[" +
      Array::makei(count, index => "{\"id\":" + (index + 1).to_string() + "}").join(
        ",",
      ) +
      "]",
    )
    let charge = @row_source_host.charge_row_run_page(run, body).unwrap()
    let received = @row_source_host.accept_charged_row_run_page(
      run, charge, body,
    )
    if over_rows {
      assert_true(received is Err(_))
      assert_true(@row_source_host.capture_row_run(run) is Err(_))
    } else {
      assert_eq(received.unwrap(), 128)
      @row_source_host.finish_row_run(run).unwrap()
      @row_source_host.begin_row_capture(run).unwrap()
      let mut complete = false
      for _ in 0..<10000 {
        if @row_source_host.advance_row_capture(run, 256).unwrap().0 {
          complete = true
          break
        }
      }
      assert_true(complete)
      let source = @row_source_host.row_capture_source(
        @row_source_host.capture_row_run(run).unwrap(),
      ).unwrap()
      assert_eq(@query.captured_source_row_count(source), Some(128))
      snapshot = Some(
        export_client_whole_source_capture(
          source,
          plan.whole_sources[0].unwrap().1,
          "same-cold-capture",
        ).unwrap(),
      )
    }
    let mut retired = false
    for _ in 0..<10000 {
      match retire_installed_source_read(read) {
        Ok(_) => {
          retired = true
          break
        }
        Err(CleanupPending) => ()
        Err(_) => fail("configured original Source cleanup failed")
      }
    }
    assert_true(retired)
    retire_installed_managed_run(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
  (plan, snapshot.unwrap())
}

///|
#cfg(target="js")
test "Whole restoration preserves configured 128 rows and revokes only its receiving custody" {
  let (plan, (identity, schema, rows_cid, rows)) = whole_source_saved_input_fixture()
  assert_eq(rows.length(), 128)
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let selected = plan.whole_sources[0].unwrap().1
  let current = Ref(true)
  let sibling = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
  let restored = restore_accounted_client_whole_source_capture(
    selected,
    "same-cold-capture",
    "same-cold-capture",
    identity,
    schema,
    rows_cid,
    rows,
    ledger,
    () => current.val,
  ).unwrap()
  let source = accounted_client_source_capture_source(restored).unwrap()
  let read = accounted_client_source_original_read(restored).unwrap()
  assert_eq(@query.captured_source_row_count(source), Some(128))
  assert_eq(@execution.supplied_relation_read_row_count(read), 128)
  assert_eq(
    export_client_whole_source_capture(source, selected, "same-cold-capture").unwrap(),
    (identity, schema, rows_cid, rows),
  )
  current.val = false
  assert_true(accounted_client_source_capture_source(restored) is None)
  assert_true(accounted_client_source_original_read(restored) is None)
  assert_false(@query.captured_source_available(source))
  assert_false(@execution.supplied_relation_read_available(read))
  assert_false(close_accounted_client_source_capture(restored, quantum=1))
  assert_true(accounted_client_source_capture_cleanup_pending(restored))
  assert_true(@resources.capacity_reservation_open(sibling))
  let mut closed = false
  for _ in 0..<10000 {
    if close_accounted_client_source_capture(restored, quantum=1) {
      closed = true
      break
    }
  }
  assert_true(closed)
  assert_false(accounted_client_source_capture_cleanup_pending(restored))
  assert_true(@resources.capacity_reservation_open(sibling))
  @resources.settle_capacity(ledger, sibling).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
#cfg(target="js")
test "Whole restoration rejects altered rows schema expired policy and retired receiving parent" {
  let (plan, (identity, schema, rows_cid, rows)) = whole_source_saved_input_fixture()
  let selected = plan.whole_sources[0].unwrap().1
  for variant in 0..<6 {
    let current = Ref(true)
    let (input, initial, ledger, capacity) = effect_parent_test_preparation(
      plan,
      prepared_installed_effect_managed_requirements(plan),
      current=() => effect_parent_test_require_current(current.val),
    )
    let owner = begin_preparation_owned_installed_effect_managed_run(
      initial,
      input,
      capacity,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
    if variant == 4 {
      current.val = false
    }
    if variant == 5 {
      retire_installed_managed_run(owner).unwrap()
    }
    let result = restore_accounted_client_whole_source_capture(
      selected,
      "same-cold-capture",
      "same-cold-capture",
      identity,
      if variant == 1 {
        "sha256:" + "a".repeat(64)
      } else {
        schema
      },
      rows_cid,
      if variant == 0 {
        ["{\"id\":999}"]
      } else if variant == 2 {
        Array::make(129, rows[0])
      } else if variant == 3 {
        [" ".repeat(1000001)]
      } else {
        rows
      },
      ledger,
      () => true,
    )
    if variant >= 4 {
      assert_true(result is Err(Physical(_)))
    } else {
      assert_true(result is Err(Original(InvalidBinding)))
    }
    assert_eq(@resources.ledger_usage(ledger).holdings, 0)
    assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
    current.val = true
    if variant != 5 {
      retire_installed_managed_run(owner).unwrap()
    }
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
}
