///|
// Closed numeric constructor path only; no diagnostic String/body/key fields.
extern "js" fn dependency_boundary_failure_codes(
  issue : LocalValuesExecutionIssue,
) -> FixedArray[Int] =
  #|(issue) => { const out=[]; let value=issue; for(let i=0;i<6;i++){out.push(Number.isSafeInteger(value?.$tag)?value.$tag:-1); value=value?._0;} return out; }

///|
// Finite explicit TEST graph policy only. All intake, check, Plan, Source and
// adopted Run controls are the existing originals. No ordinary Account/I/O or
// physical ACK claim is made by these semantic component ports.
struct DependencyBoundaryOriginal {
  parent : ClientRequestPreparation[Array[Int]]
  plan : ClientInstalledEffectManagedPlan
  run : ClientInstalledManagedRun
  document : String
  environment : @checked.CheckEnvironment
}

///|
fn dependency_boundary_document(
  document : String,
  count : Int,
  program_id_width? : Int = 0,
) -> String {
  let document = document.replace(
    old="\"id\":\"apply\",\"inputs\":{\"i0\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}},\"i1\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}}},\"from\":\"i0\",\"steps\":",
    new="\"id\":\"apply\",\"inputs\":{\"input\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}}},\"steps\":",
  )
  let inputs = StringBuilder()
  for index in 0..<count {
    if index > 0 {
      inputs.write_string(",")
    }
    inputs.write_string(
      "\"i" +
      index.to_string() +
      "\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}}",
    )
  }
  let document = document.replace(
    old="\"id\":\"apply\",\"inputs\":{\"input\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}}},\"steps\":",
    new="\"id\":\"apply\",\"inputs\":{" +
      inputs.to_string() +
      "},\"from\":\"i0\",\"steps\":",
  )
  // Keep the same Result rows and imports on the existing bounded relation
  // chain. Its steps select their exact receiving ports; do not ask the
  // single-Row provider to consume every unused declared import at once.
  let document = document.replace(
    old="\"steps\":[{\"filter\":\"id > 2\",\"as\":\"selected\"}]",
    new="\"steps\":[{\"select\":[\"id\"],\"as\":\"imported\"},{\"from\":\"imported\",\"filter\":\"id > 2\",\"as\":\"selected\"}]",
  )
  if program_id_width > 0 {
    document.replace(
      old="\"id\":\"source-effect-operation-plan\"",
      new="\"id\":\"" + "p".repeat(program_id_width) + "\"",
    )
  } else {
    document
  }
}

///|
fn dependency_boundary_check(
  document : String,
  environment : @checked.CheckEnvironment,
  graph_work : Int,
  wide? : Bool = false,
  failure? : Ref[ClientRequestTerminalIssue?]? = None,
  selected_memory? : Int64? = None,
) -> (ClientRequestPreparation[Array[Int]], Array[Int]) {
  let memory = selected_memory.unwrap_or(
    if wide {
      1073741824L
    } else {
      536870912L
    },
  )
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(memory),
    execution_bytes=Some(memory),
  ).unwrap()
  let (parent, input) = native_driver_parent(
    document,
    initial_limits=Some(limits),
  )
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let original = @publication_host.client_standard_effect_computation_limits()
  let compilation = original.program.checking.compilation
  let checking = if wide {
    // Explicit finite TEST compilation resource selection before construction:
    // 2050 genuine interfaces contain the contract-valid 8192-unit Program ID.
    // Keep identifier/grammar limits and ordinary defaults unchanged.
    {
      ..original.program.checking,
      compilation: {
        ..compilation,
        work: 32000000,
        artifacts: { ..compilation.artifacts, bytes: 32000000, },
      },
    }
  } else {
    original.program.checking
  }
  let selected = {
    ..original,
    program: { ..original.program, max_graph_work: graph_work, checking, },
  }
  let checked = prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    selected,
  )
  if checked is Err(issue) && failure is Some(retained) {
    retained.val = Some(issue)
  } else {
    checked.unwrap()
  }
  (parent, input)
}

///|
fn dependency_boundary_original(
  count : Int,
  program_id_width? : Int = 0,
  selected_memory? : Int64? = None,
) -> DependencyBoundaryOriginal raise {
  let parent : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let input : Ref[Array[Int]?] = Ref(None)
  let text = Ref("")
  let environment : Ref[@checked.CheckEnvironment?] = Ref(None)
  let plan = effect_operation_source_plan_fixture(
    runtime_admission=true,
    document_for=Some(document => {
      dependency_boundary_document(document, count, program_id_width~)
    }),
    prepare_original=Some((document, selected_environment) => {
      text.val = document
      environment.val = Some(selected_environment)
      let (owner, original_input) = dependency_boundary_check(
        document,
        selected_environment,
        4000000,
        wide=program_id_width > 0,
        selected_memory~,
      )
      finish_request_computation_preparation(owner, original_input).unwrap()
      let prepared = owner.compiled_effect.unwrap()
      reserve_request_effect_plan(owner, original_input).unwrap()
      parent.val = Some(owner)
      input.val = Some(original_input)
      prepared
    }),
  )
  let parent = parent.val.unwrap()
  let input = input.val.unwrap()
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let run = begin_request_effect_managed_run(parent, plan.request).unwrap()
  assert_true(physical_equal(run.ledger.unwrap(), parent.ledger))
  let memory = selected_memory.unwrap_or(
    if program_id_width > 0 {
      1073741824L
    } else {
      536870912L
    },
  )
  assert_eq(@resources.ledger_limits(parent.ledger).retained_bytes, memory)
  assert_eq(@resources.ledger_limits(parent.ledger).execution_bytes, memory)
  retain_installed_effect_operation_controls_before_construction(
    run,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  |> ignore
  {
    parent,
    plan,
    run,
    document: text.val,
    environment: environment.val.unwrap(),
  }
}

///|
fn dependency_boundary_capture(
  original : DependencyBoundaryOriginal,
) -> (
  ClientInstalledSourceRead,
  @row_source_host.RowSourceCapture,
  @query.CapturedInputSource,
) raise {
  let plan = original.plan
  let (read, _, acquisition, _) = begin_installed_effect_managed_source_read(
    original.run,
    plan.declarations[0],
    0,
  ).unwrap()
  let rows = start_installed_source_read_rows(
    read,
    acquisition,
    "dependency-boundary-original",
    _ => true,
    1024L,
    2048L,
  ).unwrap()
  @row_source_host.begin_row_run(rows, 128, 3, 3).unwrap()
  assert_eq(
    @row_source_host.accept_row_run_page(
      rows,
      @utf8.encode("[{\"id\":3},{\"id\":5}]"),
    ).unwrap(),
    2,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut done = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      done = true
      break
    }
  }
  assert_true(done)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  (read, capture, @row_source_host.row_capture_source(capture).unwrap())
}

///|
fn dependency_boundary_execute_static(
  count : Int,
  complete? : Bool = false,
  program_id_width? : Int = 0,
  expect_execution_refusal? : Bool = false,
  selected_memory? : Int64? = None,
  duplicate_root? : Bool = false,
) -> Unit raise {
  // The 2050-port component retains its original Request/Source alongside
  // the materializing Compute quote. Complete variants additionally retain
  // fresh and cold inventories. Select the existing finite TEST ceiling at
  // intake. Explicit512MiB also succeeds with the actual managed bindings;
  // a separate same-input control leaves its real startup quote one byte short.
  let selected_memory = if selected_memory is Some(_) {
    selected_memory
  } else if count == 2050 {
    Some(if expect_execution_refusal { 536870912L } else { 1073741824L })
  } else {
    None
  }
  let original = dependency_boundary_original(
    count,
    program_id_width~,
    selected_memory~,
  )
  let plan = original.plan
  let (read, source, captured_input) = dependency_boundary_capture(original)
  let (compilation, allowed, definition, bound) = effect_publication_binding_materials(
    plan.prepared,
  )
  let (host, captured, _) = open_installed_effect_managed_host(
      original.run,
      bound,
      [captured_input],
    )
    .unwrap()
    .unwrap()
  // Actual existing issuer, bound to this exact Request/Plan/DAG before
  // Compute. These are real typed semantic ports, not Account/provider ACKs.
  let limits = original_keyed_content_workspace().export_limits
  let identity = @query.identify_captured_source_relation(
    captured_input,
    3,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
    retain_body_bytes=1024,
  ).unwrap()
  let requirement = plan.captures[0].requirement
  let logical = @publication_host.issue_captured_source_input_logical(
    plan.graph,
    captured_input,
    identity,
    requirement,
  ).unwrap()
  let facts = @planning.query_source_evidence_fact_values(
    @planning.query_requirement_source_evidence_facts(requirement).unwrap(),
  )
  let authority = "sha256:" + "c".repeat(64)
  let evidence = @row_source_host.issue_row_source_evidence(
    plan.acquisitions[0],
    source,
    identity,
    logical,
    authority,
    facts[3],
    "2026-11-15T00:00:01.000Z",
  ).unwrap()
  let issued = issue_installed_effect_captured_invocation(
    original.run,
    plan.prepared,
    plan.request,
    plan,
    bound,
    captured,
    compilation,
    @publication_host.client_effect_allowed_run_admission(allowed),
    definition,
    captured_input,
    @publication.run_evidence_value_json(evidence),
    @publication.run_evidence_value_json(logical),
    facts[0],
    facts[1],
    authority,
    facts[3],
    "2026-11-15T00:00:00.000Z",
    "2026-11-15T00:00:01.000Z",
    1000000,
    100000,
    64,
  ).unwrap()
  assert_true(
    physical_equal(original.run.publication_definition.unwrap(), definition),
  )
  assert_true(
    physical_equal(original.run.publication_invocation.unwrap(), issued.1),
  )
  let dag = @strategy.captured_effect_run_dag(captured)
  @row_source_host.retain_row_capture_task(source, dag, 0).unwrap()
  if complete && count == 2 && program_id_width == 0 {
    let installed = @builtin.configured_local_module(
      @builtin.configured_host_modules(host),
    ).unwrap()
    let task = @strategy.next_captured_task(dag).unwrap()
    let visits = @local_driver.local_dispatch_preparation_input_scan_work(
      plan.configuration.dispatch,
      task,
    ).unwrap()
    assert_true(visits > 0)
    let invalid_index = @strategy.graph_data_count(plan.graph) - 1
    let invalid_edge = @strategy.graph_data_at(plan.graph, invalid_index).unwrap()
    assert_true(invalid_edge.consumer != task || invalid_edge.input != 0)
    assert_true(
      @strategy.captured_task_input(
        dag,
        task,
        10000,
        10000,
        input_index=0,
        data_index=invalid_index,
      )
      is Err(NotReady),
    )
    let before = @resources.ledger_usage(original.parent.ledger)
    assert_true(before.planning_work > 0)
    assert_true(
      @local_driver.estimate_local_dispatch_offer(
        installed,
        task,
        [{ work_slots: [0, 1, 2, 3, 4], milliseconds: None, }],
        visits - 1,
      )
      is Err(Configuration(InvalidLimits)),
    )
    assert_eq(@resources.ledger_usage(original.parent.ledger), before)
    @local_driver.estimate_local_dispatch_offer(
      installed,
      task,
      [{ work_slots: [0, 1, 2, 3, 4], milliseconds: None, }],
      @resources.ledger_admission_limits(original.parent.ledger).planning_work,
    ).unwrap()
    |> ignore
    assert_true(
      @strategy.captured_task_input(
        dag,
        task,
        10000,
        10000,
        input_index=0,
        data_index=invalid_index,
      )
      is Err(NotReady),
    )
    let io = if plan.configuration.retained_output { 2 } else { 1 }
    let slots = @local_driver.local_dispatch_work_slots() + io
    assert_eq(
      @resources.ledger_usage(original.parent.ledger).planning_work -
      before.planning_work,
      visits + 2 * slots + 1 + io,
    )
  }
  // Quote the SAME supported managed candidate using its actual original
  // input bindings. The legacy whole-materializing offer is not this startup.
  // Another live fixture reservation consumes the original Ledger's remaining
  // execution capacity; no production policy or byte ceiling changes.
  let execution_block = if expect_execution_refusal {
    let installed = @builtin.configured_local_module(
      @builtin.configured_host_modules(host),
    ).unwrap()
    let inputs : Array[@local_driver.LocalManagedAvailableOutput[Int]] = @strategy.captured_next_managed_producers(
      dag,
    ).map(producer => {
      if producer == -1 {
        @local_driver.local_managed_supplied_relation_input()
      } else {
        @local_driver.local_managed_captured_relation_input()
      }
    })
    let obligations = @strategy.captured_next_managed_obligations(
      dag,
      @host_driver.compute_host_max_entries(
        @builtin.configured_host_runtime(host),
      ),
    ).unwrap()
    let candidate = @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed, inputs, obligations, 0L,
      )
      .unwrap()
      .unwrap()
    let (_, execution) = @local_driver.local_managed_dispatch_site_capacity(
      candidate,
    ).unwrap()
    let ledger = original.parent.ledger
    let remaining = @resources.ledger_limits(ledger).execution_bytes -
      @resources.ledger_usage(ledger).reserved_execution_bytes
    assert_true(execution > 0L && execution <= remaining)
    let block = @resources.reserve_capacity(
      ledger,
      0L,
      remaining - execution + 1L,
    ).unwrap()
    assert_eq(
      @resources.ledger_limits(ledger).execution_bytes -
      @resources.ledger_usage(ledger).reserved_execution_bytes,
      execution - 1L,
    )
    Some(block)
  } else {
    None
  }
  let execution = match
    execute_retained_effect_local_tasks_guarded(host, captured, 256, 100000, () => {
      true
    }) {
    Ok(value) => value
    Err(failure) => {
      let codes = dependency_boundary_failure_codes(
        local_values_execution_failure_issue(failure),
      )
      let reports = []
      for index in 0..<@strategy.strategy_report_count(dag) {
        let report = @strategy.strategy_report_at(dag, index).unwrap()
        reports.push(
          "R=" +
          report.retained_bytes.to_string() +
          ";E=" +
          report.execution_bytes.to_string() +
          ";reject=" +
          @debug.to_string(report.rejection),
        )
      }
      let selected = @resources.ledger_admission_limits(original.parent.ledger)
      let live = @resources.ledger_usage(original.parent.ledger)
      if expect_execution_refusal {
        assert_eq(count, 2050)
        assert_eq(
          (selected.retained_bytes, selected.execution_bytes),
          (536870912L, 536870912L),
        )
        assert_true(
          local_values_execution_failure_issue(failure)
          is Driver(
            @local_driver.Execution(
              @strategy.Physical(@resources.ExecutionLimit)
            )
          ),
        )
        assert_true(
          physical_equal(
            installed_effect_managed_operation_plan(
              original.run,
              plan.prepared,
              plan.request,
            ).unwrap(),
            plan,
          ),
        )
        assert_eq(live.attempts, 1)
        assert_false(original.run.publication_started)
        assert_true(original.run.publication is None)
      }
      for _ in 0..<10000 {
        if retry_local_values_execution_failure_cleanup(failure) {
          break
        }
      }
      assert_false(local_values_execution_failure_cleanup_pending(failure))
      if execution_block is Some(block) {
        @resources.settle_capacity(original.parent.ledger, block).unwrap()
      }
      retire_installed_source_read(read).unwrap()
      retire_installed_managed_run(original.run).unwrap()
      if expect_execution_refusal {
        let cleaned = @resources.ledger_usage(original.parent.ledger)
        assert_eq(cleaned.attempts, 1)
        assert_eq(cleaned.live_reservations, 0)
        assert_eq(
          (
            cleaned.reserved_retention_bytes,
            cleaned.reserved_execution_bytes,
            cleaned.held_bytes,
          ),
          (0L, 0L, 0L),
        )
        println(
          "DependencyBoundary.ExecutionRefusal same2050 imports; actualmanagedquote one byte short on sameLedger; final_live_reservations=0",
        )
        return
      }
      fail(
        "DependencyBoundary.ExecutionConstructors=" +
        codes.to_json().stringify() +
        ";reports=" +
        reports.to_json().stringify() +
        ";selected=" +
        @debug.to_string(selected) +
        ";live=" +
        @debug.to_string(live),
      )
    }
  }
  if expect_execution_refusal {
    let mut closed = execution.close()
    for _ in 0..<10000 {
      if closed {
        break
      }
      closed = execution.close()
    }
    assert_true(closed)
    @resources.settle_capacity(original.parent.ledger, execution_block.unwrap()).unwrap()
    retire_installed_source_read(read).unwrap()
    retire_installed_managed_run(original.run).unwrap()
    fail(
      "the original managed startup must refuse its actual quote one byte short",
    )
  }
  assert_eq(execution.rows().unwrap(), ["{\"id\":3}", "{\"id\":5}"])
  let inputs = pin_installed_effect_sources(
    original.run,
    plan.prepared,
    plan.request,
    plan,
    captured,
    64,
  ).unwrap()
  let bodies = prepare_installed_effect_dependency_bodies(
    original.run,
    plan.prepared,
    plan.request,
    plan,
    inputs,
    1,
    1000000,
    100000,
    64,
  ).unwrap()
  if complete {
    dependency_boundary_complete_inventory(
      original,
      inputs,
      captured_input,
      identity,
      logical,
      evidence,
      facts[3],
      authority,
      allowed,
      definition,
      issued,
      execution,
      captured,
      bodies,
      if program_id_width > 0 {
        16777216L
      } else {
        0L
      },
      duplicate_root~,
    )
  }
  let interfaces = bodies
    .filter(value => value.0 == "result_import_interface")
    .length()
  let types = bodies.filter(value => value.0 == "result_import_type").length()
  let body_count = bodies.length()
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  let mut closed = execution.close()
  for _ in 0..<10000 {
    if closed {
      break
    }
    closed = execution.close()
  }
  assert_true(closed)
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(original.run).unwrap()
  assert_eq(
    @resources.ledger_usage(original.parent.ledger).live_reservations,
    0,
  )
  assert_eq(interfaces, count)
  // The explicit projection adds its actual selected type to the old filter
  // profile; this is an observed semantic inventory, not alias-count credit.
  assert_eq(types, count)
  assert_true(body_count > interfaces)
  println(
    "DependencyBoundary.Static imports=" +
    count.to_string() +
    "; interfaces=" +
    interfaces.to_string() +
    "; types=" +
    types.to_string() +
    "; actual_bodies=" +
    body_count.to_string() +
    "; final_live_reservations=0",
  )
}

///|
test "two alias original Source issuer and actual Compute reach retained static dependency export" {
  dependency_boundary_execute_static(2)
}

///|
test "2050 actual imports compile and Compute under finite TEST graph4M without changing default1M" {
  dependency_boundary_execute_static(2050)
}

///|
test "2050 actual imports succeed at512MiB and refuse actual managed startup one byte short" {
  dependency_boundary_execute_static(2050, selected_memory=Some(536870912L))
  dependency_boundary_execute_static(2050, expect_execution_refusal=true)
}

///|
test "explicit finite test graph profile retains production graph refusal and one original Request Run" {
  let original = dependency_boundary_original(2)
  let document = dependency_boundary_document(original.document, 2050)
  // The transform anchor is consumed in the actual two-input control; use
  // the same producer and replace its exact original two-input inventory.
  let document = if document == original.document {
    let source = original.document.replace(
      old="\"id\":\"apply\",\"inputs\":{\"i0\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}},\"i1\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}}},\"from\":\"i0\",\"steps\":",
      new="\"id\":\"apply\",\"inputs\":{\"input\":{\"result\":{\"stage\":\"acquire\",\"result\":\"rows\"}}},\"steps\":",
    )
    dependency_boundary_document(source, 2050)
  } else {
    document
  }
  let (parent, input) = dependency_boundary_check(
    document,
    original.environment,
    1000000,
  )
  assert_true(
    finish_request_computation_preparation(parent, input)
    is Err(Preparation(ProgramCheck(EffectCompilation(Graph(WorkLimit))))),
  )
  assert_true(parent.compiled_effect is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  retire_installed_managed_run(original.run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(
    @resources.ledger_usage(original.parent.ledger).live_reservations,
    0,
  )
}

///|
fn dependency_boundary_export(
  inputs : @strategy.CapturedEffectInputs,
  index : Int,
  exact_export? : @strategy.CapturedEffectLocalResultExport? = None,
) -> (
  @strategy.CapturedEffectLocalResultExport,
  @execution.CompletedRelationExportReceipt,
  String,
) raise {
  let limits = original_keyed_content_workspace().export_limits
  let exported = exact_export.unwrap_or_else(() => {
    @strategy.start_captured_effect_local_result_export(
      inputs,
      index,
      {
        max_fields: 2,
        max_mapping_work: 10000,
        max_order_work: 10000,
        max_workspace_entries: 20,
      },
      10,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      limits.max_batch_bytes,
    ).unwrap()
  })
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  for _ in 0..<10000 {
    if @execution.advance_completed_result_relation_export(preparation, 256).unwrap().0 {
      break
    }
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  let text = StringBuilder()
  while @execution.next_completed_output_export(stream).unwrap() is Some(frame) {
    text.write_string(frame)
  }
  let (receipt, tail) = @execution.finish_completed_relation_export(stream).unwrap()
  text.write_string(tail)
  assert_eq(text.to_string(), "[{\"id\":3},{\"id\":5}]")
  (exported, receipt, text.to_string())
}

///|
// These genuine typed semantic ports issue no Store ACK or physical grant.
// Complete inventory construction below uses the original admitted Run owner.
fn dependency_boundary_complete_inventory(
  original : DependencyBoundaryOriginal,
  inputs : @strategy.CapturedEffectInputs,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  evidence : @publication.RunEvidenceValue,
  source_policy : String,
  authority : String,
  allowed : @publication_host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : (@publication.RunEvidenceValue, @publication.PublicationContract),
  execution : LocalValuesExecution,
  captured_run : @strategy.CapturedEffectRunDAG,
  consumer_static : Array[(String, @checked.CheckedLocalDependencyBody)],
  minimum_data_bytes : Int64,
  duplicate_root? : Bool = false,
) -> Unit raise {
  let plan = original.plan
  let max_bytes = 1000000
  let max_nodes = 100000
  let depth = 64
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"sha256:" +
    "a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a" +
    "\",\"effective_data_policy_cid\":\"" +
    source_policy +
    "\",\"available_until\":\"2027-01-01T00:00:00.000Z\",\"delete_by\":\"2027-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2027-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:" +
    "dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095" +
    "\",\"metadata_delete_by\":\"2027-01-04T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:" +
    "c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356" +
    "\"}",
    max_bytes,
    max_nodes,
    depth,
  ).unwrap()
  let source_retention = @publication.issue_result_retention_for_data_policy(
    retention, source_policy, max_bytes, max_nodes, depth,
  ).unwrap()
  let acquired = @publication_host.issue_client_effect_acquired_evidence(
    plan.prepared,
    source,
    identity,
    plan.captures[0].requirement,
    logical,
    evidence,
    authority,
    source_policy,
    source_retention,
    max_bytes,
    max_nodes,
    depth,
    publication_retention=Some(retention),
  ).unwrap()
  let admission = @publication_host.client_effect_allowed_run_admission(allowed)
  assert_eq(@strategy.captured_effect_local_result_count(inputs), 2)
  let mut producer_index = -1
  let mut consumer_index = -1
  for index in 0..<2 {
    let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
    match @strategy.captured_effect_local_result_stage(result) {
      0 => producer_index = index
      1 => consumer_index = index
      _ => fail("DependencyBoundary.ForeignStage")
    }
  }
  assert_true(producer_index >= 0 && consumer_index >= 0)
  let (producer_export, producer_receipt, producer_rows) = dependency_boundary_export(
    inputs, producer_index,
  )
  let producer_definition = @publication_host.issue_client_effect_local_result_definition(
    plan.prepared,
    0,
    "rows",
    max_bytes,
    max_nodes,
    depth,
  ).unwrap()
  let producer_issue = @publication_host.issue_acquired_client_effect_local_result_artifact(
    plan.prepared,
    inputs,
    producer_export,
    acquired,
    producer_definition,
    producer_receipt,
    admission,
    definition,
    issued.1,
    issued.0,
    max_bytes,
    max_nodes,
    depth,
  )
  let producer = match producer_issue {
    Ok(value) => value
    Err(Context(ForeignRetention)) =>
      fail("DependencyBoundary.Artifact.Context.Retention")
    Err(Context(ForeignRun)) => fail("DependencyBoundary.Artifact.Context.Run")
    Err(Context(ForeignInvocation)) =>
      fail("DependencyBoundary.Artifact.Context.Invocation")
    Err(Context(ForeignObservation)) =>
      fail("DependencyBoundary.Artifact.Context.Observation")
    Err(Context(MissingScope)) =>
      fail("DependencyBoundary.Artifact.Context.Scope")
    Err(ForeignOwner) => fail("DependencyBoundary.Artifact.Owner")
    Err(ForeignDefinition) => fail("DependencyBoundary.Artifact.Definition")
    Err(ForeignInvocation) => fail("DependencyBoundary.Artifact.Invocation")
    Err(ForeignRun) => fail("DependencyBoundary.Artifact.Run")
    Err(ForeignExport) => fail("DependencyBoundary.Artifact.Export")
    Err(Evidence(_)) => fail("DependencyBoundary.Artifact.Evidence")
    Err(Artifact(_)) => fail("DependencyBoundary.Artifact.Artifact")
    Err(Scope(_)) => fail("DependencyBoundary.Artifact.Scope")
    Err(MissingInput) => fail("DependencyBoundary.Artifact.Input")
  }
  let producer_invocation = @publication_host.client_effect_acquired_invocation(
    acquired,
  )
  let manifest = @publication_host.issue_client_effect_local_manifest(
    plan.prepared,
    producer_invocation,
    [producer],
    max_bytes,
    max_nodes,
    depth,
  ).unwrap()
  let kinds : Array[String] = []
  let identities : Array[String?] = []
  let wires : Array[String] = []
  fn append(kind : String, cid : String?, wire : String) {
    kinds.push(kind)
    let identity = if cid is None &&
      ["request_values", "relation_value", "relation_schema"].contains(kind) {
      Some("sha256:" + @sha.hex(@utf8.encode(wire)))
    } else {
      cid
    }
    identities.push(identity)
    wires.push(wire)
  }
  append(
    "local_manifest",
    None,
    @publication_host.client_effect_local_manifest_json(manifest),
  )
  for
    (kind, name, cid) in [
      (
        "retention_contract", "local-result-retention", "sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a",
      ),
      (
        "metadata_retention_policy", "local-result-metadata", "sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095",
      ),
      (
        "clock_contract", "local-clock", "sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356",
      ),
    ] {
    append(
      kind,
      Some(cid),
      "{\"name\":\"" +
      name +
      "\",\"version\":\"actql-installed-local-policy/0.1\"}",
    )
  }

  for
    (kind, wire) in @publication_host.client_effect_acquired_dependency_bodies(
      acquired,
    ) {
    append(kind, None, wire)
  }
  for
    (kind, wire) in @publication_host.client_effect_acquired_relation_dependency_bodies(
      acquired,
    ).unwrap() {
    append(kind, None, wire)
  }
  let program = @checked.effect_program_static_checked_computation(
    @publication_host.prepared_client_effect_computation_candidate(
      plan.prepared,
    ),
  )
  let count = @checked.unit_result_import_count(program, 1).unwrap()
  let observations : Array[
    @publication_host.ClientEffectResultImportObservation,
  ] = []
  for port in 0..<count {
    let captured = @strategy.capture_effect_result_import(
      inputs, 1, port, 100000,
    ).unwrap()
    let observed = @publication_host.issue_client_effect_result_import_observation(
      plan.prepared,
      inputs,
      captured,
      manifest,
      producer,
      max_bytes,
      max_nodes,
      depth,
    ).unwrap()
    if count == 2 {
      let cid = @publication_host.client_effect_result_import_observation_cid(
        observed,
      )
      let wire = @publication_host.client_effect_result_import_observation_json(
        observed,
      )
      let capacity = @publication_host.client_effect_result_import_observation_retained_capacity(
        observed,
      ).unwrap()
      // Observation and capture records, their retained references and
      // consumer coordinate, plus the two owned Strings and their text.
      let expected = 4L * 16L +
        10L * 8L +
        8L +
        2L * (cid.length().to_int64() + wire.length().to_int64())
      assert_eq(
        @execution.execution_capacity_retained_bytes(capacity),
        expected,
      )
      assert_eq(
        @execution.execution_capacity_execution_bytes(capacity),
        expected,
      )
    }
    append(
      "result_import_observation",
      Some(
        @publication_host.client_effect_result_import_observation_cid(observed),
      ),
      @publication_host.client_effect_result_import_observation_json(observed),
    )
    observations.push(observed)
  }
  let imported = @publication_host.issue_client_effect_imported_evidence(
    plan.prepared,
    inputs,
    1,
    observations,
    max_bytes,
    max_nodes,
    depth,
  ).unwrap()
  if count == 2 {
    let scope = @publication_host.client_effect_imported_scope_json(imported)
    let relations = @publication_host.client_effect_imported_relation_bodies(
      imported,
    )
    let invocation = @publication_host.client_effect_imported_invocation(
      imported,
    )
    // Independently measure the completed wire contracts to set the exact
    // traversal bounds. Pricing still walks the original retained trees.
    let scope_contract = @publication.admit_publication_contract(
      "acquisition_scope", scope, max_bytes, max_nodes, depth,
    ).unwrap()
    let (_, scope_nodes, scope_depth) = @publication.publication_contract_wire_usage(
      scope_contract,
    ).unwrap()
    let mut nodes = scope_nodes
    let mut retained_depth = scope_depth
    let mut text = scope.length().to_int64() +
      @publication_host.client_effect_local_invocation_json(invocation)
      .length()
      .to_int64()
    for wire in relations {
      let contract = @publication.admit_publication_contract(
        "acquisition_relation", wire, max_bytes, max_nodes, depth,
      ).unwrap()
      let (_, relation_nodes, relation_depth) = @publication.publication_contract_wire_usage(
        contract,
      ).unwrap()
      nodes = Int::max(nodes, relation_nodes)
      retained_depth = Int::max(retained_depth, relation_depth)
      text += wire.length().to_int64()
    }
    let retained = @publication_host.client_effect_imported_evidence_retained_bytes(
      imported, nodes, retained_depth,
    ).unwrap()
    assert_true(retained > 2L * text)
    assert_true(
      @publication_host.client_effect_imported_evidence_retained_bytes(
        imported,
        nodes - 1,
        retained_depth,
      )
      is None,
    )
    assert_eq(
      @publication_host.client_effect_imported_scope_json(imported),
      scope,
    )
    assert_eq(
      @publication_host.client_effect_imported_relation_bodies(imported),
      relations,
    )
  }
  let managed = execution
    .prepare_effect_result_export(
      captured_run,
      inputs,
      consumer_index,
      {
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 64,
        max_text_bytes: 1000000,
      },
      100000,
      1000000,
      original_keyed_content_workspace().export_limits,
    )
    .unwrap()
  let (consumer_export, consumer_receipt, consumer_rows) = dependency_boundary_export(
    inputs,
    consumer_index,
    exact_export=Some(managed.captured_export().unwrap()),
  )
  let consumer_definition = @publication_host.issue_client_effect_local_result_definition(
    plan.prepared,
    1,
    "rows",
    max_bytes,
    max_nodes,
    depth,
  ).unwrap()
  let consumer = @publication_host.issue_imported_client_effect_local_result_artifact(
    plan.prepared,
    inputs,
    consumer_export,
    imported,
    consumer_definition,
    consumer_receipt,
    retention,
    admission,
    definition,
    issued.1,
    issued.0,
    max_bytes,
    max_nodes,
    depth,
  ).unwrap()
  let consumer_invocation = @publication_host.client_effect_imported_invocation(
    imported,
  )
  let consumer_manifest = @publication_host.issue_client_effect_local_manifest(
    plan.prepared,
    consumer_invocation,
    [consumer],
    max_bytes,
    max_nodes,
    depth,
  ).unwrap()
  assert_true(
    @publication_host.client_effect_local_manifest_matches(
      consumer_manifest,
      plan.prepared,
      consumer_invocation,
      [consumer],
    ),
  )
  append(
    "acquisition_scope",
    None,
    @publication_host.client_effect_imported_scope_json(imported),
  )
  for wire in @publication_host.client_effect_imported_relation_bodies(imported) {
    append("acquisition_relation", None, wire)
  }
  // Use the actual exported rows/receipt and issued Artifact witnesses. Static
  // bodies use the same funded original selector, without the legacy Native
  // capture convenience envelope's independent 4k/16MiB aggregate defaults.
  let producer_static = prepare_installed_effect_dependency_bodies(
    original.run,
    plan.prepared,
    plan.request,
    plan,
    inputs,
    0,
    max_bytes,
    max_nodes,
    depth,
  ).unwrap()
  for members in [producer_static, consumer_static] {
    for (kind, body) in members {
      append(
        kind,
        Some(@checked.checked_local_dependency_body_cid(body)),
        @checked.checked_local_dependency_body_json(body),
      )
    }
  }
  for
    (artifact, local_definition, invocation, receipt, rows) in [
      (
        producer, producer_definition, producer_invocation, producer_receipt, producer_rows,
      ),
      (
        consumer, consumer_definition, consumer_invocation, consumer_receipt, consumer_rows,
      ),
    ] {
    let relation = @execution.completed_relation_export_identity(receipt)
    let schema = @execution.completed_relation_export_schema_identity(receipt)
    append(
      "relation_value",
      Some(@execution.logical_relation_cid(relation)),
      "{\"sort\":\"relation\",\"value\":" + rows + "}",
    )
    append(
      "relation_schema",
      Some(@execution.relation_schema_cid(schema)),
      @execution.relation_schema_wire(schema),
    )
    append(
      "local_result_definition",
      None,
      @publication_host.client_effect_local_result_definition_json(
        local_definition,
      ),
    )
    append(
      "local_computation",
      None,
      @publication_host.client_effect_local_invocation_json(invocation),
    )
    append(
      "result_artifact",
      None,
      @publication_host.client_effect_local_result_artifact_json(artifact),
    )
    append(
      "derivation_evidence",
      None,
      @publication_host.client_effect_local_result_derivation_json(artifact),
    )
    append(
      "ordering_evidence",
      None,
      @publication_host.client_effect_local_result_ordering_json(artifact),
    )
    append(
      "result_retention_policy",
      None,
      @publication.publication_contract_json(retention),
    )
  }
  let selected_artifacts = [producer, consumer]
  if duplicate_root {
    selected_artifacts.push(consumer)
  }
  reserve_installed_effect_dependency_group(
    original.run,
    plan.prepared,
    plan.request,
    plan,
    wires.length(),
    selected_artifacts.length(),
  ).unwrap()
  let inventory_result = prepare_installed_effect_dependency_inventory(
    original.run,
    plan.prepared,
    plan.request,
    plan,
    kinds,
    identities,
    wires,
    selected_artifacts,
    max_bytes,
    max_nodes,
    depth,
    original_artifacts=[producer, consumer],
  )
  let inventory = match inventory_result {
    Ok(value) => value
    Err(Ledger(PlanningLimit)) =>
      fail(
        "DependencyBoundary.Inventory.PlanningLimit.used=" +
        @resources.ledger_usage(original.parent.ledger).planning_work.to_string(),
      )
    Err(Ledger(RetentionLimit)) =>
      fail("DependencyBoundary.Inventory.RetentionLimit")
    Err(Ledger(ExecutionLimit)) =>
      fail("DependencyBoundary.Inventory.ExecutionLimit")
    Err(Ledger(ForeignOwner)) =>
      fail("DependencyBoundary.Inventory.ForeignOwner")
    Err(Ledger(ClosedReservation)) =>
      fail("DependencyBoundary.Inventory.ClosedReservation")
    Err(Ledger(InvalidCharge)) =>
      fail("DependencyBoundary.Inventory.InvalidCharge")
    Err(Ledger(_)) => fail("DependencyBoundary.Inventory.OtherLedger")
    Err(Unsupported) => fail("DependencyBoundary.Inventory.Unsupported")
    Err(ForeignOriginal) => fail("DependencyBoundary.Inventory.ForeignOriginal")
    Err(InsufficientCapacity) => fail("DependencyBoundary.Inventory.Capacity")
    Err(_) => fail("DependencyBoundary.Inventory.Other")
  }
  assert_true(
    physical_equal(
      original.run.effect_operation_controls.unwrap().dependency_inputs.unwrap(),
      inputs,
    ),
  )
  assert_true(@strategy.captured_effect_inputs_retained(inputs))
  guard @json.parse(inventory) is Array(entries) else {
    fail("DependencyBoundary.Inventory.Array")
  }
  let unique : Map[String, Bool] = Map([])
  let mut metadata_bytes = 2L + Int::max(0, entries.length() - 1).to_int64()
  let mut import_observations = 0
  let mut import_interfaces = 0
  for entry in entries {
    guard entry is Object(fields) &&
      fields["kind"] is String(kind) &&
      fields["cid"] is String(cid) else {
      fail("DependencyBoundary.Inventory.Entry")
    }
    // Exact canonical envelope syntax, independent of the body tree. Cross-
    // check this sum against full fresh re-admission on the narrow case.
    metadata_bytes += @utf8.encode(
        "{\"body\":,\"cid\":" +
        Json::string(cid).stringify() +
        ",\"kind\":" +
        Json::string(kind).stringify() +
        "}",
      )
      .length()
      .to_int64()
    let key = kind + "\u0000" + cid
    assert_false(unique.contains(key))
    unique[key] = true
    if kind == "result_import_observation" {
      import_observations += 1
    }
    if kind == "result_import_interface" {
      import_interfaces += 1
    }
  }
  assert_eq(import_observations, count)
  assert_eq(import_interfaces, count)
  if count == 2050 {
    assert_true(unique.length() > 4096)
  }
  println(
    "DependencyBoundary.Complete unique_data=" + unique.length().to_string(),
  )
  println(
    "DependencyBoundary.Complete imports=" +
    count.to_string() +
    "; inventory_bytes=" +
    inventory.length().to_string(),
  )
  let body_bytes = @utf8.encode(inventory).length().to_int64() - metadata_bytes
  if minimum_data_bytes == 0L {
    let cold_bytes = dependency_boundary_cold_roundtrip(original, inventory, [
      @publication_host.client_effect_local_result_artifact_cid(producer),
      @publication_host.client_effect_local_result_artifact_cid(consumer),
    ])
    assert_eq(cold_bytes, body_bytes)
  }
  assert_true(body_bytes > minimum_data_bytes)
  println(
    "DependencyBoundary.Complete canonical_data_bytes=" + body_bytes.to_string(),
  )
  @execution.cancel_completed_relation_export_receipt(producer_receipt)
  @execution.cancel_completed_relation_export_receipt(consumer_receipt)
  managed.close()
}

///|
test "genuine two-import complete producer consumer Artifact Manifest inventory" {
  dependency_boundary_execute_static(2, complete=true)
}

///|
test "same original Result selected twice keeps complete inventory and retained inputs" {
  dependency_boundary_execute_static(2, complete=true, duplicate_root=true)
}

///|
test "genuine 2050-import complete inventory exceeds old4096 DATA under one original Run" {
  dependency_boundary_execute_static(2050, complete=true)
}

///|
test "genuine 2050-import fresh complete inventory exceeds old16MiB DATA under one original Run" {
  dependency_boundary_execute_static(2050, complete=true, program_id_width=8192)
}

///|
// Re-admit persisted immutable DATA with no Source/Model execution, static
// body cache or Catalog fallback. This semantic component does not issue a
// physical Read grant or claim a separate-process Store/Saved acceptance.
fn dependency_boundary_cold_issue(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  roots : Array[@publication.CapturedEffectDependencyBody],
  kinds : Array[String],
  identities : Array[String?],
  wires : Array[String],
) -> Result[
  (
    @publication.CapturedEffectDependencyInventory,
    @encode.EncodingConstructionGeometry,
  ),
  ClientInstalledManagedRunIssue,
] {
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, original) &&
    physical_equal(original, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) else {
    return Err(ForeignOriginal)
  }
  let refused : Ref[@resources.LedgerIssue?] = Ref(None)
  let grow = capacity => {
    retain_installed_effect_dependency_capacity(
      owner, preparation, admission, plan, ledger, control, capacity,
    )
  }
  let segment = fn(
    task : ((Int) -> Bool) -> Result[
      ClientEffectDependencyGroupStep,
      ClientInstalledManagedRunIssue,
    ],
  ) -> Result[ClientEffectDependencyGroupStep, ClientInstalledManagedRunIssue] {
    let result = with_installed_effect_dependency_work(
      control,
      admission,
      plan,
      ledger,
      () => {
        check_installed_effect_operation_original(
          owner,
          ledger,
          preparation,
          Some(control),
        )
      },
      control.reservation,
      () => !owner.effect_operation_closing,
      spend => {
        task(units => {
          match spend(units) {
            Ok(_) => true
            Err(issue) => {
              refused.val = Some(issue)
              false
            }
          }
        }).map_err(issue => {
          @resources.NodeManagedRunOperationIssue::Original(issue)
        })
      },
    )
    result.map_err(issue => {
      match refused.val {
        Some(original) => ClientInstalledManagedRunIssue::Ledger(original)
        None => installed_effect_operation_reservation_issue(issue)
      }
    })
  }
  prepare_funded_effect_dependency_inventory(
    kinds,
    identities,
    wires,
    roots,
    None,
    1000000,
    100000,
    64,
    grow,
    segment,
  )
}

///|
fn dependency_boundary_cold_roundtrip(
  original : DependencyBoundaryOriginal,
  wire : String,
  root_cids : Array[String],
) -> Int64 raise {
  let owner = original.run
  let plan = original.plan
  guard owner.preparation is Some(preparation) &&
    preparation is PlannedEffectManaged(admission, selected) &&
    physical_equal(selected, plan) &&
    owner.ledger is Some(ledger) &&
    owner.effect_operation_controls is Some(control) &&
    control.dependency_inventory_geometry is Some(geometry) &&
    control.dependency_inventory is Some(inventory) else {
    fail("DependencyBoundary.Cold.Original")
  }
  let count = @publication.captured_effect_dependency_inventory_count(inventory)
  // The actual original final-encoder extent funds the additional raw tree,
  // owned canonical body wires and typed index before decoding any entry.
  let fixed = installed_effect_dependency_fixed_capacity(
    count,
    root_cids.length(),
    64,
  ).unwrap()
  let body = installed_effect_dependency_body_capacity(geometry).unwrap()
  let capacity = standard_create_sum_capacities(
    [fixed, body],
    sequential_workspace=true,
  ).unwrap()
  retain_installed_effect_dependency_capacity(
    owner, preparation, admission, plan, ledger, control, capacity,
  ).unwrap()
  guard @json.parse(wire) is Array(entries) else {
    fail("DependencyBoundary.Cold.Array")
  }
  let kinds : Array[String] = []
  let ids : Array[String?] = []
  let wires : Array[String] = []
  let roots : Array[@publication.CapturedEffectDependencyBody] = []
  let mut body_bytes = 0L
  for entry in entries {
    guard entry is Object(fields) &&
      fields["kind"] is String(kind) &&
      fields["cid"] is String(cid) &&
      fields.get("body") is Some(value) else {
      fail("DependencyBoundary.Cold.Entry")
    }
    let canonical = @identity.stringify_value(
      @identity.from_json(value, 100000, 64, 1000000),
      1000000,
      100000,
      64,
    )
    body_bytes += @utf8.encode(canonical).length().to_int64()
    kinds.push(kind)
    ids.push(Some(cid))
    wires.push(canonical)
    if kind == "result_artifact" && root_cids.contains(cid) {
      roots.push(
        @publication.admit_captured_effect_dependency_body(
          kind,
          Some(cid),
          canonical,
          1000000,
          100000,
          64,
        ).unwrap(),
      )
    }
  }
  assert_eq(roots.length(), root_cids.length())
  let (cold, _) = match
    dependency_boundary_cold_issue(owner, plan, roots, kinds, ids, wires) {
    Ok(value) => value
    Err(Ledger(PlanningLimit)) =>
      fail(
        "DependencyBoundary.Cold.PlanningLimit.used=" +
        @resources.ledger_usage(ledger).planning_work.to_string() +
        ";limit=" +
        @resources.ledger_limits(ledger).planning_work.to_string(),
      )
    Err(Ledger(RetentionLimit)) =>
      fail("DependencyBoundary.Cold.RetentionLimit")
    Err(Ledger(ExecutionLimit)) =>
      fail("DependencyBoundary.Cold.ExecutionLimit")
    Err(Ledger(ForeignOwner)) => fail("DependencyBoundary.Cold.ForeignOwner")
    Err(Unsupported) => fail("DependencyBoundary.Cold.Unsupported")
    Err(_) => fail("DependencyBoundary.Cold.Other")
  }
  assert_eq(
    @publication.captured_effect_dependency_inventory_count(cold),
    count,
  )
  assert_eq(@publication.captured_effect_dependency_inventory_json(cold), wire)
  println(
    "DependencyBoundary.Cold unique_data=" +
    count.to_string() +
    "; no_cache_or_catalog=true",
  )
  body_bytes
}

///|
test "wide genuine Program keeps ordinary finite10M compiler resource refusal before Source" {
  let original = dependency_boundary_original(2)
  let document = dependency_boundary_document(
    original.document,
    2050,
    program_id_width=8192,
  )
  let failure : Ref[ClientRequestTerminalIssue?] = Ref(None)
  let (parent, _) = dependency_boundary_check(
    document,
    original.environment,
    4000000,
    failure=Some(failure),
  )
  assert_true(
    failure.val
    is Some(
      Preparation(
        ProgramCheck(
          EffectInput(
            @checked.EffectComputationIssue::Computation(
              @checked.LocalConstructionFailure::Units(
                @checked.UnitBuildFailure::Encoding(@encode.OutputLimit)
              )
            )
          )
        )
      )
    ),
  )
  assert_true(parent.compiled_effect is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  retire_installed_managed_run(original.run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(
    @resources.ledger_usage(original.parent.ledger).live_reservations,
    0,
  )
}
