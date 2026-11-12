///|
// Actual checked Effect, two complete Direct Source inputs in one task, the
// existing admitted managed parent, two RowRuns and the same physical host.
#cfg(target="js")
test "Effect whole inputs keep distinct Source slots and execute their original same-stage task" {
  let plan = effect_operation_source_plan_fixture(whole_inputs=true)
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
  let sibling = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
  let sources = []
  let reads = []
  let rows = []
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
    sources.push(actual)
    reads.push(read)
    rows.push(capture)
  }
  assert_true(
    physical_equal(
      installed_effect_managed_sources_ledger(
        owner,
        plan.prepared,
        plan.request,
      ).unwrap(),
      ledger,
    ),
  )
  let bound = effect_parent_bound_run(plan.prepared)
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
  for capture in rows {
    @row_source_host.check_row_input_compute_binding(capture, dag, 0).unwrap()
  }
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap()
  let operations : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let output_live = Ref(true)
  let stop_on_output_check = Ref(false)
  let output_current = () => {
    if stop_on_output_check.val {
      stop_on_output_check.val = false
      @strategy.stop_captured_dag(dag)
    }
    output_live.val
  }
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
    (original.prepare_finalization)(
      task,
      original.storage_bytes,
      output_current,
    ).unwrap()
    let mut finalized = false
    for _ in 0..<10000 {
      if (original.advance_finalization)(256).unwrap().complete {
        finalized = true
        break
      }
    }
    assert_true(finalized)
    (original.settle)().unwrap()
    let completed = (original.complete)(
      task,
      original.storage_bytes,
      output_current,
    ).unwrap()
    assert_eq(@execution.managed_completed_output_row_count(completed), 1)
    assert_eq((original.output_row)(0).unwrap(), "{\"id\":3}")
    if task == 0 {
      // This actual Local completion has a managed slot, not a Cells view.
      let target = @lower.preparation_output_target(
        @lower.bound_preparation(
          @strategy.graph_task_owner(plan.graph, 0).unwrap(),
        ),
      ).unwrap()
      assert_true(@strategy.captured_task_output(dag, 0, target) is None)
      for source in sources {
        let read = @query.captured_source_original_input_read(source).unwrap()
        assert_true(
          @strategy.source_input_dag_retains_completed_read_at(dag, read, 0),
        )
        let receiver = @execution.supplied_relation_read_receiver(read)
        let input_index = @execution.supplied_relation_read_input_index(read)
        // Equal fresh row admission is no Source/custody substitute.
        let equal_rows = @execution.capture_input(
          receiver,
          input_index,
          [funded_value_cursor("{\"id\":3}")],
          max_rows=1,
          {
            max_nodes: 100,
            max_depth: 20,
            max_text_bytes: 100,
            max_work: 1000,
          },
        ).unwrap()
        let foreign = @execution.prepare_supplied_relation_read(
          receiver,
          input_index,
          equal_rows,
          () => true,
        ).unwrap()
        assert_true(
          @execution.supplied_relation_read_cell(read, 0, 0)
          is Some(@admitted.Number(3.0)),
        )
        assert_true(
          @execution.supplied_relation_read_cell(foreign, 0, 0)
          is Some(@admitted.Number(3.0)),
        )
        assert_false(
          @execution.supplied_relation_read_same_binding(read, foreign),
        )
        assert_false(
          @strategy.source_input_dag_retains_completed_read_at(dag, foreign, 0),
        )
        let retired = @execution.restrict_supplied_relation_read(read, () => {
          false
        })
        assert_false(
          @strategy.source_input_dag_retains_completed_read_at(dag, retired, 0),
        )
      }
    }
    operations.push(original)
    available = [@local_driver.local_managed_relation_output(completed)]
  }
  assert_true(@strategy.captured_task_completed(dag, 0))
  assert_true(@strategy.captured_task_completed(dag, 1))
  let source_read = @query.captured_source_original_input_read(sources[0]).unwrap()
  assert_false(
    @strategy.source_input_dag_retains_completed_read_at(dag, source_read, 1),
  )
  // Availability may synchronously stop this exact Run. The original slot
  // cannot remain custody-current after that callback, even if it returns true.
  stop_on_output_check.val = true
  assert_false(
    @strategy.source_input_dag_retains_completed_read_at(dag, source_read, 0),
  )
  assert_false(stop_on_output_check.val)
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
  for read in reads {
    retire_installed_source_read(read).unwrap()
  }
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
test "Effect whole read fences reentrant retirement without replacing its sibling input" {
  let plan = effect_operation_source_plan_fixture(whole_inputs=true)
  let selected_owner : Ref[ClientInstalledManagedRun?] = Ref(None)
  let retire_current = Ref(false)
  let retired = Ref(false)
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => {
      if retire_current.val &&
        selected_owner.val is Some(owner) &&
        owner.reads[0] is Some(read) {
        retire_installed_source_read(read).unwrap()
        retired.val = true
      }
    },
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  selected_owner.val = Some(owner)
  let declaration = plan.whole_sources[0].unwrap().0
  let (sibling, _, _, _) = begin_installed_effect_managed_whole_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    1,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  retire_current.val = true
  assert_true(
    begin_installed_effect_managed_whole_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      0,
    )
    is Err(ForeignOriginal),
  )
  retire_current.val = false
  assert_true(retired.val)
  assert_true(
    sibling.ledger is Some(original) && physical_equal(original, ledger),
  )
  assert_true(
    sibling.whole_input is Some(original) &&
    physical_equal(original, plan.whole_sources[1].unwrap().1),
  )
  assert_true(
    owner.reads[1] is Some(original) && physical_equal(original, sibling),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    begin_installed_effect_managed_whole_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      0,
    )
    is Err(AlreadyBound),
  )
  retire_installed_source_read(sibling).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
#cfg(target="js")
test "Effect whole input consumes the installed row and page policy without an extra clamp" {
  let policy = installed_row_input_policy(128, 2097152, 10000, 32, 128)
  let plan = effect_operation_source_plan_fixture(
    whole_inputs=true,
    whole_policy=Some(policy),
  )
  let declaration = plan.whole_sources[0].unwrap().0
  for over_rows in [false, true] {
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
}

///|
test "Effect whole input refuses an absent installed policy rather than selecting defaults" {
  let plan = effect_operation_source_plan_fixture(whole_inputs=true)
  let declaration = plan.whole_sources[0].unwrap().0
  let input = prepare_installed_effect_row_source_input(declaration, None).unwrap()
  assert_true(
    prepare_installed_effect_managed_source_plan(
      plan.prepared,
      plan.request,
      [input, input],
      original_row_query_contract_fixture,
      original_row_evidence_contract_fixture,
      plan.transport_bytes,
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      plan.operations,
      provider_factory=_ => [],
    )
    is Err(Unsupported),
  )
}

///|
test "Source and Compute attempt inventory refuses checked Int overflow" {
  assert_eq(installed_source_compute_count(2147483645, 2), Some(2147483647))
  assert_eq(installed_source_compute_count(2147483646, 2), None)
  assert_eq(installed_source_compute_count(2147483647, 1), None)
  assert_eq(installed_source_compute_count(-1, 1), None)
  assert_eq(installed_source_compute_count(1, -1), None)
}

///|
// Actual checked Effect, two complete Direct Source inputs in one task, the
// existing admitted managed parent, two RowRuns and the same physical host.
#cfg(target="js")
fn retained_effect_whole_source_export_control(
  export_results? : Bool = false,
  export_public? : Bool = false,
  verify_provenance? : Bool = false,
) -> Unit raise {
  let plan = effect_operation_source_plan_fixture(whole_inputs=true)
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
  let sibling = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
  let sources = []
  let identities : Array[@query.CapturedSourceRelationIdentity] = []
  let original_reads : Array[@execution.SuppliedRelationRead] = []
  let reads = []
  let rows = []
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
    if verify_provenance {
      let original = @query.identify_captured_source_relation(
        actual,
        3,
        {
          max_nodes: 1000,
          max_depth: 20,
          max_text_bytes: 10000,
          max_work: 10000,
        },
        {
          max_columns: 10,
          max_order_work: 10000,
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 20,
        },
        {
          max_columns: 10,
          max_order_work: 10000,
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 20,
        },
        { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
        128,
      ).unwrap()
      identities.push(original)
      original_reads.push(
        @query.captured_source_original_input_read(actual).unwrap(),
      )
    }
    sources.push(actual)
    reads.push(read)
    rows.push(capture)
  }
  assert_true(
    physical_equal(
      installed_effect_managed_sources_ledger(
        owner,
        plan.prepared,
        plan.request,
      ).unwrap(),
      ledger,
    ),
  )
  let bound = effect_parent_bound_run(plan.prepared)
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
  for capture in rows {
    @row_source_host.check_row_input_compute_binding(capture, dag, 0).unwrap()
  }
  let execution = execute_retained_effect_local_tasks_guarded(
    host,
    captured,
    256,
    10000,
    () => true,
  ).unwrap()
  assert_true(@strategy.captured_task_completed(dag, 0))
  assert_true(@strategy.captured_task_completed(dag, 1))
  assert_true(@strategy.next_captured_task(dag) is None)
  assert_eq(execution.rows().unwrap(), ["{\"id\":3}"])
  if export_results || export_public || verify_provenance {
    assert_eq(
      @strategy.graph_result_task(@strategy.captured_dag_graph(dag), 0),
      Some(1),
    )
    let inputs = @strategy.pin_captured_effect_sources(captured, 10).unwrap()
    assert_eq(@strategy.captured_effect_local_result_count(inputs), 2)
    let originals : Array[@strategy.CapturedEffectLocalResultExport] = []
    if verify_provenance {
      for index, original in identities {
        assert_true(
          @query.captured_source_relation_identity_has_input_binding(
            original,
            original_reads[index],
          ),
        )
        assert_false(
          @query.captured_source_relation_identity_has_input_binding(
            original,
            original_reads[1 - index],
          ),
        )
        assert_true(
          @strategy.captured_effect_inputs_acquired_source_matches(
            inputs, 0, original,
          ),
          msg="Same whole Source original refused by its computed input slot",
        )
        assert_false(
          @strategy.captured_effect_inputs_acquired_source_matches(
            inputs, 1, original,
          ),
        )
      }
    }
    let row : @execution.RetainedRowDecodeLimits = {
      max_bytes: 1024,
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1024,
    }
    let wire : @execution.RowWireLimits = {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    }
    let export_limits : @publication_host.PublicationOutputExportLimits = {
      max_result_fields: 10,
      max_result_mapping_work: 10000,
      max_result_order_work: 10000,
      max_result_workspace_entries: 1000,
      max_rows: 100,
      values: {
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 10000,
      },
      payload_wire: wire,
      logical_wire: wire,
      schema: {
        max_fields: 10,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      max_batch_bytes: 128,
    }
    if export_results || verify_provenance {
      for index in 0..<2 {
        let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
        assert_eq(@strategy.captured_effect_local_result_task(result), index)
        let owned = match
          execution.prepare_effect_result_export(
            captured, inputs, index, row, 1000, 10000, export_limits,
          ) {
          Ok(value) => value
          Err(ForeignInput) =>
            fail("Exact original producer Result refused as ForeignInput")
          Err(_) =>
            fail("Original managed export refused before Result conversion")
        }
        let exported = owned.captured_export().unwrap()
        if verify_provenance {
          originals.push(exported)
          let computation = @publication_host.prepared_client_effect_computation_graph(
            plan.prepared,
          )
          let unit = @strategy.captured_effect_local_result_stage(result)
          assert_true(
            @strategy.captured_effect_local_result_export_matches_computed_unit(
              exported, computation, unit,
            ),
          )
          assert_false(
            @strategy.captured_effect_local_result_export_matches_computed_unit(
              exported,
              computation,
              1 - unit,
            ),
          )
          let foreign = effect_operation_source_plan_fixture(whole_inputs=true)
          assert_false(
            @strategy.captured_effect_local_result_export_matches_computed_unit(
              exported,
              @publication_host.prepared_client_effect_computation_graph(
                foreign.prepared,
              ),
              unit,
            ),
          )
        }
        let preparation = @strategy.captured_effect_local_result_export_preparation(
          exported,
        )
        while !@execution.advance_completed_result_relation_export(
                preparation, 31,
              ).unwrap().0 {
          continue
        }
        let stream = @execution.finish_completed_result_relation_export_preparation(
          preparation,
        ).unwrap()
        let actual = StringBuilder()
        while @execution.next_completed_output_export_canonical_row(
                stream, 1000, 20, 10000,
              ).unwrap()
              is Some((_, wire, _)) {
          actual.write_string(wire)
        }
        let (receipt, tail) = @execution.finish_completed_relation_export(
          stream,
        ).unwrap()
        actual.write_string(tail)
        assert_eq(actual.to_string(), "[{\"id\":3}]")
        @execution.cancel_completed_relation_export_receipt(receipt)
        @execution.cancel_completed_output_export(stream)
        owned.close()
        assert_true(owned.captured_export() is None)
      }
    }
    if export_public {
      // Refusal closes only its partial bridge. The original completion and
      // exact Result are still available for the funded caller below.
      let calls = Ref(0)
      assert_true(
        execution.prepare_captured_result_export(
          dag,
          0,
          row,
          1000,
          10000,
          export_limits,
          before_row=Some(_ => {
            calls.val += 1
            false
          }),
        )
        is Err(MissingOutput),
      )
      assert_eq(calls.val, 1)
      assert_eq(execution.rows().unwrap(), ["{\"id\":3}"])
      let owned = execution
        .prepare_captured_result_export(
          dag,
          0,
          row,
          1000,
          10000,
          export_limits,
          before_row=Some(_ => {
            calls.val += 1
            true
          }),
        )
        .unwrap()
      assert_eq(calls.val, 2)
      let output = owned.output_export()
      let actual = StringBuilder()
      while output.next().unwrap() is Some(wire) {
        actual.write_string(wire)
      }
      actual.write_string(output.finish().unwrap())
      assert_eq(actual.to_string(), "[{\"id\":3}]")
      owned.close()
    }
    assert_true(@strategy.release_captured_effect_inputs(inputs))
    if verify_provenance {
      for original in originals {
        let result = @strategy.captured_effect_local_result_export_result(
          original,
        )
        assert_false(
          @strategy.captured_effect_local_result_export_matches_computed_unit(
            original,
            @publication_host.prepared_client_effect_computation_graph(
              plan.prepared,
            ),
            @strategy.captured_effect_local_result_stage(result),
          ),
        )
      }
    }
  }
  assert_true(execution.close())
  assert_true(retire_installed_effect_captured_consumers(owner).unwrap())
  for read in reads {
    retire_installed_source_read(read).unwrap()
  }
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
test "Retained Effect dispatcher preserves whole Source originals through managed Result completion" {
  retained_effect_whole_source_export_control()
}

///|
#cfg(target="js")
test "managed Effect exports exact producer Results independently of the public Result task" {
  retained_effect_whole_source_export_control(export_results=true)
}

///|
#cfg(target="js")
test "managed Effect public Result keeps its captured pin after a refused bridge row" {
  retained_effect_whole_source_export_control(export_public=true)
}

///|
#cfg(target="js")
test "whole Source Effect provenance keeps original supplied inputs outside completed Source slots" {
  retained_effect_whole_source_export_control(verify_provenance=true)
}
