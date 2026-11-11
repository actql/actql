///|
test "collection original Request publishes 9999 with its same live output" {
  collection_request_publication_case(9999, false)
}

///|
test "collection original Request snapshot refuses occupied retention" {
  collection_request_publication_case(9999, true)
}

///|
test "collection original Request publishes 9999 with explicit finite work" {
  collection_request_publication_case(
    9999,
    false,
    source_free_max_work=Some(30000000),
  )
}

///|
test "collection original Request default work refusal retains bounded cleanup" {
  collection_request_publication_case(100000, false, expect_work_refusal=true)
}

///|
test "collection original Request 100000 uses selected finite initial parent through Result and close" {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  collection_request_publication_case(
    100000,
    false,
    source_free_max_work=Some(30000000),
    initial_limits=Some(limits),
  )
}

///|
test "small original Request actual demand is unchanged by larger finite memory ceilings" {
  let baseline : Array[@resources.LedgerUsage] = []
  for
    memory in [
      None,
      Some(1073741824L),
      Some(2147483648L),
      Some(268435456L),
      Some(67108864L),
    ] {
    let samples : Array[@resources.LedgerUsage] = []
    let limits = client_local_preparation_initial_limits(
      client_local_resource_policy(),
      retained_bytes=memory,
      execution_bytes=memory,
    ).unwrap()
    collection_request_publication_case(
      1,
      false,
      source_free_max_work=Some(30000000),
      initial_limits=Some(limits),
      simple=true,
      observed=Some(samples),
    )
    assert_eq(samples.length(), 8)
    if baseline.is_empty() {
      for sample in samples {
        baseline.push(sample)
      }
    } else {
      assert_eq(samples, baseline)
    }
    for phase, sample in samples {
      println(
        "small-request-demand cap=" +
        limits.retained_bytes.to_string() +
        " phase=" +
        phase.to_string() +
        " R=" +
        sample.reserved_retention_bytes.to_string() +
        " E=" +
        sample.reserved_execution_bytes.to_string() +
        " held=" +
        sample.held_bytes.to_string() +
        " peakR=" +
        sample.peak_retention_bytes.to_string(),
      )
    }
  }
}

///|
fn collection_request_publication_case(
  count : Int,
  occupied : Bool,
  source_free_max_work? : Int? = None,
  expect_work_refusal? : Bool = false,
  initial_limits? : @resources.LedgerLimits? = None,
  simple? : Bool = false,
  observed? : Array[@resources.LedgerUsage]? = None,
  actual_request_profile? : Bool = false,
  giant_elements? : Int? = None,
) -> Unit raise {
  let digits : Array[String] = []
  for n in 0..<10 {
    digits.push("SELECT " + n.to_string() + " AS n")
  }
  let giant_row = giant_elements.map(elements => {
    "{\"cells\":[" + Array::make(elements, "0").join(",") + "]}"
  })
  let sql = if giant_elements is Some(elements) {
    "SELECT [" + Array::make(elements, "0").join(",") + "] AS cells"
  } else if simple {
    "SELECT 0 AS n"
  } else {
    "WITH d AS (" +
    digits.join(" UNION ALL ") +
    ") SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < " +
    count.to_string()
  }
  let selected_rows = if actual_request_profile {
    let initial = initial_limits.unwrap()
    client_local_materialized_row_ceiling(
      client_local_resource_policy(),
      retained_bytes=Some(initial.retained_bytes),
      execution_bytes=Some(initial.execution_bytes),
    ).unwrap()
  } else {
    client_local_materialized_row_ceiling(client_local_resource_policy()).unwrap()
  }
  let environment = collection_capacity_selected_environment(selected_rows)
  let cid = @checked.checking_environment_cid(environment)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" + cid + "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, input) = native_driver_parent(sql, initial_limits~, observed~)
  let original_ledger = parent.ledger
  if initial_limits is Some(selected) {
    assert_eq(@resources.ledger_limits(original_ledger), selected)
  }
  let prepared = if actual_request_profile {
    prepare_request_default_source_computation_check(
      parent,
      input,
      request_document_test_source(sql, "sql"),
      native_json_reader,
      environment,
      publication,
      [],
      None,
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap()
    finish_request_checked_computation(parent, input, environment, publication).unwrap()
    |> ignore
    parent.compiled_program.unwrap()
  } else {
    parse_request_query_syntax(parent, input, sql, @frontend.Sql).unwrap()
    |> ignore
    lower_request_published_query(
      parent,
      input,
      publication,
      environment,
      None,
      public_primary=true,
    ).unwrap()
    |> ignore
    let limits = @publication_host.client_standard_program_preparation_limits()
    let check = prepare_request_program_check_preparation(
      parent,
      input,
      environment,
      None,
      [],
      limits.checking,
    ).unwrap()
    prepare_program_check_input(check).unwrap()
    prepare_program_check_prelude(check).unwrap() |> ignore
    prepare_program_check_registry(check).unwrap() |> ignore
    prepare_program_check_contents(check).unwrap() |> ignore
    prepare_program_check_references(check).unwrap() |> ignore
    prepare_program_check_policies(check).unwrap() |> ignore
    prepare_program_check_values(check).unwrap() |> ignore
    prepare_program_check_views(check).unwrap() |> ignore
    prepare_program_check_carriers(check).unwrap() |> ignore
    prepare_program_check_requests(check).unwrap() |> ignore
    reconcile_program_check_requests(check).unwrap()
    assert_true(
      finish_program_check_preparation(check).unwrap() is @checked.Checked(_),
    )
    compile_program_check_preparation(check, limits).unwrap()
  }
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
  if !actual_request_profile {
    continue_request_program_preparation(parent, input).unwrap() |> ignore
  }
  let selected_codec = if actual_request_profile {
    request_program_compilation_limits(parent, input).unwrap()
  } else {
    @publication_host.client_standard_pure_compilation_limits()
  }
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=selected_codec,
    runtime_compilation_limits=if actual_request_profile {
      Some(selected_codec)
    } else {
      None
    },
    retained_output=false,
    provider_factory=_ => [],
    source_free_max_work~,
  ).unwrap()
  // A second module entrance cannot replace the first selected policy or
  // construct another Plan on the same original Request.
  assert_true(
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=false,
      provider_factory=_ => [],
      source_free_max_work=Some(40000000),
    )
    is Err(Preparation(WrongPhase)),
  )
  let plan = parent.program_source_free.unwrap()
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
  assert_eq(
    plan.capacity_plan.values.max_work,
    source_free_max_work.unwrap_or(20000000),
  )
  assert_eq(
    plan.capacity_plan.execution.rows.output_values.max_work,
    plan.capacity_plan.values.max_work,
  )
  assert_eq(
    plan.capacity_plan.execution.max_work,
    plan.capacity_plan.values.max_work,
  )
  assert_eq(
    parent.program_source_free_max_work,
    Some(plan.capacity_plan.values.max_work),
  )
  if !simple {
    let actual_requirements = @execution.generated_sequence_requirements(
      plan.sequences[43],
      10000,
    ).unwrap()
    let actual_fragment = @lower.sequence_requirements_fragment_for_step(
      actual_requirements, 43,
    ).unwrap()
    assert_eq(
      actual_fragment.logical.max_work,
      plan.capacity_plan.values.max_work.to_int64(),
    )
  }
  println(
    "request-finalization-policy " +
    @debug.to_string(
      (
        @publication_host.prepared_client_values_max_rows(prepared),
        plan.capacity_plan.execution.rows.max_rows,
        plan.capacity_plan.execution.rows.output_values,
      ),
    ),
  )
  let holder = borrow_request_program_preparation(parent).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-request-finalization-" + count.to_string(),
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(physical_equal(run.ledger.unwrap(), original_ledger))
  if initial_limits is Some(selected) {
    assert_eq(@resources.ledger_limits(run.ledger.unwrap()), selected)
  }
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
  // Consume the SAME compilation retained by this Request's existing Plan.
  // This does not compile another Program or substitute a serialized body.
  let compiled = match plan.compilation.unwrap() {
    Values(original) =>
      @publication_host.issue_client_values_compiled_run(
        prepared,
        original,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    Tasks(original) =>
      @publication_host.issue_client_task_compiled_run(
        prepared,
        original,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    _ => fail("original source-free Values or Tasks compilation required")
  }
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled,
    "collection-publication",
    "same-original-" + count.to_string(),
    "2026-10-29T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  issue_program_publication_invocation(
    run, prepared, compiled, definition, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    65536, 8192, 64,
  ).unwrap()
  |> ignore
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      false,
    )
    .unwrap()
    .unwrap()
  let ledger = parent.ledger
  let result = collection_node_callback_order(
    setup,
    32,
    100000,
    () => true,
    require_live=None,
    first=0,
    component_compute_quantum=256,
    component_after_compute=Some((operations, task) => {
      collection_node_snapshot(operations, task, ledger)
    }),
  )
  let output = match result {
    Ok(value) => {
      assert_false(expect_work_refusal)
      value
    }
    Err(failure) => {
      if expect_work_refusal {
        assert_true(source_free_max_work is None)
        assert_true(
          local_values_execution_failure_issue(failure)
          is Driver(
            @local_driver.Configuration(
              @connector.Execution(
                @execution.Rows(
                  43,
                  @execution.LogicalRows(@execution.WorkLimit)
                )
              )
            )
          ),
        )
        let mut cleanup_polls = 0
        let mut cleaned = false
        for _ in 0..<100000 {
          cleanup_polls += 1
          if retry_local_values_execution_failure_cleanup(failure) {
            cleaned = true
            break
          }
        }
        println(
          "default-work-refusal cleanupPolls=" +
          cleanup_polls.to_string() +
          " complete=" +
          cleaned.to_string(),
        )
        assert_true(cleaned)
        @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
        retire_installed_managed_run(run).unwrap()
        assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
        return
      }
      let family = match local_values_execution_failure_issue(failure) {
        Driver(
          @local_driver.ManagedValues(
            @execution.Admission(@execution.CaptureLimit)
          )
        ) => "ManagedValues/Admission/CaptureLimit"
        Driver(@local_driver.Configuration(@connector.InputUnavailable)) =>
          "Configuration/InputUnavailable"
        Driver(@local_driver.Execution(@strategy.Physical(original))) =>
          "Execution/Physical/" + @debug.to_string(original)
        Driver(
          @local_driver.Configuration(
            @connector.Execution(@execution.Capture(step, original))
          )
        ) =>
          "Configuration/Execution/Capture/" +
          @debug.to_string((step, original))
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.LogicalRows(original))
            )
          )
        ) =>
          "Configuration/Execution/LogicalRows/" +
          @debug.to_string((step, original))
        Driver(
          @local_driver.Configuration(
            @connector.Execution(@execution.Rows(step, @execution.RowLimit))
          )
        ) => "Configuration/Execution/RowLimit/" + step.to_string()
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(
                step,
                @execution.Evaluation(row, binding, original)
              )
            )
          )
        ) =>
          "Configuration/Execution/Evaluation/" +
          @debug.to_string((step, row, binding, original.kind))
        Driver(
          @local_driver.Configuration(
            @connector.Execution(@execution.Rows(step, @execution.InvalidRows))
          )
        ) => "Configuration/Execution/InvalidRows/" + step.to_string()
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.InvalidRowLimits)
            )
          )
        ) => "Configuration/Execution/InvalidRowLimits/" + step.to_string()
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.OwnerMismatch)
            )
          )
        ) => "Configuration/Execution/OwnerMismatch/" + step.to_string()
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.InputMismatch)
            )
          )
        ) => "Configuration/Execution/InputMismatch/" + step.to_string()
        Driver(@local_driver.Configuration(_)) => "Configuration/other"
        Driver(@local_driver.Execution(_)) => "Execution/other"
        Driver(@local_driver.ManagedValues(_)) => "ManagedValues/other"
        Driver(@local_driver.ManagedCopy(original)) =>
          "ManagedCopy/" + @debug.to_string(original)
        Driver(@local_driver.ManagedRetention(original)) =>
          "ManagedRetention/" + @debug.to_string(original)
        _ => "different checked failure"
      }
      let cleaned = retry_local_values_execution_failure_cleanup(failure)
      println(
        "request-finalization-budget " +
        @debug.to_string(@resources.ledger_usage(parent.ledger)),
      )
      fail("request-finalization " + family + " cleanup=" + cleaned.to_string())
    }
  }
  // The ordinary caller reserves publication BEFORE closing its still-needed
  // completed output. The earlier isolated component closed that output first.
  let before = @resources.ledger_usage(parent.ledger)
  if observed is Some(samples) {
    samples.push(before)
  }
  let caps = @resources.ledger_admission_limits(parent.ledger)
  println(
    "publication-live held=" +
    before.held_bytes.to_string() +
    " reservedR=" +
    before.reserved_retention_bytes.to_string() +
    " reservedE=" +
    before.reserved_execution_bytes.to_string() +
    " limitR=" +
    caps.retained_bytes.to_string() +
    " limitE=" +
    caps.execution_bytes.to_string(),
  )
  let publication = match reserve_program_publication(run, prepared) {
    Ok(value) => value
    Err(issue) => {
      let family = match issue {
        Capacity(Resource(original)) =>
          "Capacity/Resource/" + @debug.to_string(original)
        Capacity(original) => "Capacity/" + @debug.to_string(original)
        WrongPhase => "WrongPhase"
        ForeignOriginal => "ForeignOriginal"
        Policy => "Policy"
        _ => "different checked publication failure"
      }
      let closed = output.close()
      @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
      let retired = retire_installed_managed_run(run) is Ok(_)
      fail(
        "same-live-publication " +
        family +
        " close=" +
        closed.to_string() +
        " retired=" +
        retired.to_string(),
      )
    }
  }
  assert_true(physical_equal(run.publication.unwrap(), publication))
  if !simple {
    assert_false(publication.snapshot_prequoted)
  }
  let rows = output.rows().unwrap()
  assert_eq(rows.length(), count)
  for row in rows {
    assert_eq(row, giant_row.unwrap_or("{\"n\":0}"))
  }
  // Use the same retained Plan's actual export limits and the original
  // physical output bridge. No replacement Result/schema/row owner is issued.
  let limits = installed_managed_publication_limits(run, prepared, 10000000).unwrap()
  let (bridge, export_output) = output
    .prepare_publication_bridge(
      plan.capacity_plan.imports.row,
      plan.capacity_plan.metadata.bridge_entries,
      plan.capacity_plan.metadata.name_bytes,
      limits,
    )
    .unwrap()
  let transformation = @publication_host.start_captured_managed_result_publication_export(
    publication.run.unwrap(),
    0,
    output.completed,
    bridge,
    export_output,
    limits,
  ).unwrap()
  let mut transformed = false
  for _ in 0..<100000 {
    let (done, work) = transformation.advance(64).unwrap()
    assert_true(work <= 64)
    if done {
      transformed = true
      break
    }
  }
  assert_true(transformed)
  let stream = transformation.finish().unwrap()
  let exported = StringBuilder()
  let mut eof = false
  let mut export_polls = limits.payload_wire.max_bytes.to_int64() + 2L
  while export_polls > 0L {
    export_polls -= 1L
    match stream.next().unwrap() {
      Some(chunk) => exported.write_string(chunk)
      None => {
        eof = true
        break
      }
    }
  }
  assert_true(eof)
  exported.write_string(stream.finish().unwrap())
  let expected = "[" +
    Array::make(count, giant_row.unwrap_or("{\"n\":0}")).join(",") +
    "]"
  assert_eq(exported.to_string(), expected)
  stream
  .issue_result_evidence(
    "sha256:" + "1".repeat(64),
    ["sha256:" + "2".repeat(64)],
    @publication.publication_contract_identity(definition),
    "sha256:" + "4".repeat(64),
    "sha256:" + "5".repeat(64),
    65536,
    8192,
    64,
  )
  .unwrap()
  // Explicit component retention contract. It is no Account/Host/Store
  // admission; all actual output/occurrence evidence above is retained.
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"sha256:" +
    "8".repeat(64) +
    "\",\"effective_data_policy_cid\":\"sha256:" +
    "4".repeat(64) +
    "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:" +
    "9".repeat(64) +
    "\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:" +
    "a".repeat(64) +
    "\"}",
    65536,
    8192,
    64,
  ).unwrap()
  stream
  .issue_artifact(
    run.publication_invocation.unwrap(),
    retention,
    65536,
    8192,
    64,
  )
  .unwrap()
  |> ignore
  if occupied {
    let usage = @resources.ledger_usage(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      caps.retained_bytes - usage.held_bytes - usage.reserved_retention_bytes,
      0L,
    ).unwrap()
    assert_true(
      begin_program_snapshot(publication, stream)
      is Err(Capacity(Resource(RetentionLimit))),
    )
    assert_true(publication.snapshot is None)
    assert_eq(publication.completed_snapshots.length(), 0)
    assert_false(publication.snapshot_starting)
    assert_eq(publication.next_snapshot_index, 1)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    // Failed constructor admission consumed the occurrence; releasing a
    // different reservation cannot authorize a retry or issue a snapshot.
    assert_true(begin_program_snapshot(publication, stream) is Err(WrongPhase))
  } else {
    let snapshot = begin_program_snapshot(publication, stream).unwrap()
    let mut done = false
    for _ in 0..<100000 {
      let (complete, work) = advance_program_snapshot(snapshot, 64).unwrap()
      assert_true(work <= 64)
      if complete {
        done = true
        break
      }
    }
    assert_true(done)
    let captured = finish_program_snapshot(snapshot).unwrap()
    // Successful nominal completion rechecks the original artifact hash and
    // row/field binding; its private rows are deliberately not projected here.
    assert_true(physical_equal(publication.completed_snapshots[0], captured))
    assert_true(finish_program_snapshot(snapshot) is Err(ForeignOriginal))
    cancel_program_snapshot(snapshot)
    assert_eq(publication.completed_snapshots.length(), 1)
  }
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
  stream.cancel()
  @execution.close_managed_publication_bridge(bridge)
  assert_true(output.close())
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
}

///|
// Diagnostic component backing only. The real driver owns source revocation,
// export/import receipts, completed output and reference reclamation. Encoded
// chunks stand in for physical Store I/O; this is not Node file/close evidence.
fn collection_node_snapshot(
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  task : Int,
  ledger : @resources.Ledger,
) -> Result[Unit, @local_driver.LocalDispatchIssue] {
  let released = Ref(false)
  let present = Ref(true)
  let snapshot = match
    (operations.prepare_relation_snapshot)(() => released.val) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(())
    Err(issue) =>
      return collection_node_snapshot_failure(task, 1, issue, ledger)
  }
  let parts : Array[String] = []
  let mut bytes = 0
  let mut saved = false
  // Consume the selected finite byte stream, including its tail/EOF calls.
  // The former 100000-poll fixture stopped a valid 100000-row stream early;
  // this changes no product wire/work/resource limit or outer guard duration.
  let mut save_polls = snapshot.frames.maxBytes.to_int64() + 2L
  while save_polls > 0L {
    save_polls -= 1L
    match (snapshot.next)() {
      Ok(Some(part)) => {
        bytes += @utf8.encode(part).length()
        parts.push(part)
      }
      Ok(None) => {
        saved = true
        break
      }
      Err(issue) =>
        return collection_node_snapshot_failure(task, 2, issue, ledger)
    }
  }
  if !saved {
    return collection_node_snapshot_failure(
      task,
      3,
      @local_driver.Configuration(@connector.InvalidLimits),
      ledger,
    )
  }
  let content = match (snapshot.content)() {
    Ok(value) => value
    Err(issue) =>
      return collection_node_snapshot_failure(task, 4, issue, ledger)
  }
  if content.bytes != bytes ||
    content.cid != "sha256:" + @sha.hex(@utf8.encode(parts.join(""))) {
    return collection_node_snapshot_failure(
      task,
      5,
      @local_driver.Configuration(@connector.InputUnavailable),
      ledger,
    )
  }
  let source_rows = (operations.output_rows)()
  match (snapshot.release_source)(content.cid, () => present.val) {
    Ok(_) => ()
    Err(issue) =>
      return collection_node_snapshot_failure(task, 6, issue, ledger)
  }
  if (snapshot.source_available)() ||
    (source_rows > 0 && (operations.output_row)(0) is Ok(_)) {
    return collection_node_snapshot_failure(
      task,
      7,
      @local_driver.Configuration(@connector.InputUnavailable),
      ledger,
    )
  }
  match (snapshot.begin_reload)() {
    Ok(_) => ()
    Err(issue) =>
      return collection_node_snapshot_failure(task, 8, issue, ledger)
  }
  let limits = snapshot.frames
  let frames = match
    @publication.prepare_durable_result_row_frames(
      limits.maxBytes,
      limits.maxRows,
      limits.maxRowBytes,
      limits.maxDepth,
      limits.maxFrameBytes,
    ) {
    Ok(value) => value
    Err(issue) => {
      println(
        "node-component framer-prepare task=" +
        task.to_string() +
        " issue=" +
        @debug.to_string(issue),
      )
      return Err(@local_driver.Configuration(@connector.InvalidLimits))
    }
  }
  for part in parts {
    let rows = match
      @publication.feed_durable_result_row_frames(frames, @utf8.encode(part)) {
      Ok(value) => value
      Err(issue) => {
        @publication.cancel_durable_result_row_frames(frames)
        println(
          "node-component framer-feed task=" +
          task.to_string() +
          " issue=" +
          @debug.to_string(issue),
        )
        return Err(@local_driver.Configuration(@connector.InvalidLimits))
      }
    }
    for row in rows {
      match (snapshot.append_reload)(row) {
        Ok(_) => ()
        Err(issue) => {
          @publication.cancel_durable_result_row_frames(frames)
          return collection_node_snapshot_failure(task, 9, issue, ledger)
        }
      }
    }
  }
  let usage = match @publication.finish_durable_result_row_frames(frames) {
    Ok(value) => value
    Err(issue) => {
      @publication.cancel_durable_result_row_frames(frames)
      println(
        "node-component framer-finish task=" +
        task.to_string() +
        " issue=" +
        @debug.to_string(issue),
      )
      return Err(@local_driver.Configuration(@connector.InvalidLimits))
    }
  }
  @publication.cancel_durable_result_row_frames(frames)
  if usage.bytes != bytes {
    return collection_node_snapshot_failure(
      task,
      10,
      @local_driver.Configuration(@connector.InputUnavailable),
      ledger,
    )
  }
  match (snapshot.finish_reload)() {
    Ok(_) => ()
    Err(issue) =>
      return collection_node_snapshot_failure(task, 11, issue, ledger)
  }
  present.val = false
  parts.clear()
  released.val = true
  let mut cleaned = false
  for _ in 0..<100000 {
    if (snapshot.cleanup_references)(32) {
      cleaned = true
      break
    }
  }
  if !cleaned {
    return collection_node_snapshot_failure(
      task,
      12,
      @local_driver.Configuration(@connector.InvalidLimits),
      ledger,
    )
  }
  match (snapshot.finish)() {
    Ok(_) => Ok(())
    Err(issue) => collection_node_snapshot_failure(task, 13, issue, ledger)
  }
}

///|
fn collection_node_snapshot_failure(
  task : Int,
  phase : Int,
  issue : @local_driver.LocalDispatchIssue,
  ledger : @resources.Ledger,
) -> Result[Unit, @local_driver.LocalDispatchIssue] {
  let family = match issue {
    Configuration(@connector.InputUnavailable) =>
      "Configuration/InputUnavailable"
    Configuration(@connector.InvalidLimits) => "Configuration/InvalidLimits"
    ManagedValues(@execution.Admission(@execution.CaptureLimit)) =>
      "ManagedValues/Admission/CaptureLimit"
    _ => "different checked failure"
  }
  println(
    "node-component snapshot task=" +
    task.to_string() +
    " phase=" +
    phase.to_string() +
    " issue=" +
    family +
    " usage=" +
    @debug.to_string(@resources.ledger_usage(ledger)),
  )
  Err(issue)
}

///|
// Existing component driver body moved byte-exactly into this whitebox fixture.
// It calls the same original owners; no product callback or public API is added.
fn collection_node_callback_order(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  require_live~ : (() -> Bool)?,
  first~ : Int,
  retained_effect? : @strategy.CapturedEffectRunDAG? = None,
  component_compute_quantum? : Int = 0,
  component_after_compute? : ((
    @local_driver.LocalManagedDispatchOperations[Int],
    Int,
  ) -> Result[Unit, @local_driver.LocalDispatchIssue])? = None,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  if finalization_quantum <= 0 || max_finalization_rounds <= 0 {
    return Err(failed_local_values_execution(InvalidLimits))
  }
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  let count = @strategy.graph_task_count(graph)
  // Do not size the retained task table from an unsupported graph. Stopping
  // this original run is still its caller-owned cleanup, not another attempt.
  if count <= first {
    let cleanup = () => close_local_values_tasks(run, [])
    return Err({ issue: UnsupportedGraph, cleanup, cleaned: cleanup(), })
  }
  let tasks : Array[LocalValuesTaskExecution?] = Array::make(count, None)
  let available = Ref(true)
  let current = () => available.val && require_current()
  // Legacy callers retain their original callback at each poll. A trusted
  // caller may separate cheap original-lifetime polling from its currentness
  // guard, which still runs at dispatch and callback-return boundaries below.
  // Neither callback establishes Account authorization in this adapter.
  let live = () => {
    if !available.val {
      return false
    }
    match require_live {
      Some(check) => check()
      None => require_current()
    }
  }
  let reject = fn(
    issue : LocalValuesExecutionIssue,
  ) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
    available.val = false
    let cleanup = () => close_local_values_tasks(run, tasks)
    Err(LocalValuesExecutionFailure::{ issue, cleanup, cleaned: cleanup(), })
  }
  if !current() {
    return reject(Fenced)
  }
  if require_live is Some(poll) && !poll() {
    return reject(Fenced)
  }
  let continuation = retained_effect is Some(original) &&
    physical_equal(@strategy.captured_effect_run_dag(original), run) &&
    @strategy.graph_program_has_effects(graph)
  if @strategy.graph_captured_prefix(graph) != first ||
    (
      !continuation &&
      (
        (first == 0 && !@strategy.graph_source_free_inputs_complete(graph)) ||
        @strategy.graph_program_has_effects(graph) ||
        @strategy.next_captured_task(run) != Some(first)
      )
    ) {
    return reject(UnsupportedGraph)
  }
  guard @builtin.configured_local_module(
      @builtin.configured_host_modules(setup),
    )
    is Some(installed) else {
    return reject(MissingLocalModule)
  }
  for _ in first..<count {
    if !current() {
      return reject(Fenced)
    }
    // The single-capture factory retains adaptive proposals, not a selected
    // strategy. Let the existing Host select/refresh them on this same Run.
    if first == 1 {
      match
        @host_driver.refresh_compute_host(
          @builtin.configured_host_runtime(setup),
        ) {
        Ok(_) => ()
        Err(issue) => return reject(Estimate(issue))
      }
      if !current() {
        return reject(Fenced)
      }
    }
    // The retained Model can have completed intermediate tasks already. None
    // only ends dispatch here; the original Result output is still required.
    if continuation && @strategy.next_captured_task(run) is None {
      break
    }
    guard @strategy.next_captured_task(run) is Some(index) &&
      index >= first &&
      index < count &&
      tasks[index] is None &&
      @strategy.graph_task_owner(graph, index) is Some(_) else {
      return reject(UnsupportedGraph)
    }
    // Carrier snapshots remain with their existing physical Store owner.
    // This entry does not turn a missing Carrier custody into row storage.
    if @local_driver.local_dispatch_next_carrier_path(installed) {
      return reject(UnsupportedGraph)
    }
    let producers = @strategy.captured_next_managed_producers(run)
    let inputs : Array[@local_driver.LocalManagedAvailableOutput[Int]] = []
    for producer in producers {
      if continuation && producer == -1 {
        inputs.push(@local_driver.local_managed_supplied_relation_input())
        continue
      }
      if continuation &&
        producer >= 0 &&
        producer < count &&
        tasks[producer] is None &&
        @strategy.captured_task_completed(run, producer) {
        // The common DAG binds the receiver to this exact original output.
        // This does not fabricate a ManagedCompletedOutput or its provider.
        inputs.push(@local_driver.local_managed_captured_relation_input())
        continue
      }
      if first == 1 && producer == 0 {
        inputs.push(@local_driver.local_managed_captured_relation_input())
        continue
      }
      guard producer >= first &&
        producer < count &&
        tasks[producer] is Some(task) &&
        task.completed is Some(output) else {
        return reject(MissingOutput)
      }
      inputs.push(@local_driver.local_managed_relation_output(output))
    }
    let obligations = match
      @strategy.captured_next_managed_obligations(
        run,
        @host_driver.compute_host_max_entries(
          @builtin.configured_host_runtime(setup),
        ),
      ) {
      Ok(value) => value
      Err(_) => return reject(Driver(Configuration(InvalidLimits)))
    }
    let prepared = match
      @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed, inputs, obligations, 0L,
      ) {
      Ok(Some(value)) => value
      Ok(None) => return reject(UnsupportedGraph)
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
    if continuation {
      match
        @strategy.select_captured_managed_registration(
          run,
          index,
          @local_driver.local_dispatch_registration(installed),
        ) {
        Ok(_) => ()
        Err(issue) => return reject(Driver(Execution(issue)))
      }
    }
    let operations = match
      @local_driver.start_local_managed_dispatch_node(prepared) {
      Ok(value) => value
      Err(issue) => return reject(Driver(issue))
    }
    // Retain actual operations before the next current callback can fail.
    let task : LocalValuesTaskExecution = {
      operations,
      settled: false,
      completed: None,
    }
    tasks[index] = Some(task)
    if !current() {
      return reject(Fenced)
    }
    if !operations.retained_inputs.is_empty() {
      return reject(UnsupportedGraph)
    }
    for transfer in operations.inputs {
      if !current() {
        return reject(Fenced)
      }
      let input = @execution.managed_producer_read_input_index(transfer.input)
      guard input >= 0 &&
        input < producers.length() &&
        tasks[producers[input]] is Some(producer) &&
        producer.completed is Some(output) &&
        @execution.managed_producer_read_matches_reference(
          transfer.input,
          @execution.managed_completed_reference(output),
        ) else {
        return reject(MissingOutput)
      }
      for row in 0..<@execution.managed_completed_output_row_count(output) {
        if !live() {
          return reject(Fenced)
        }
        let wire = match (producer.operations.output_row)(row) {
          Ok(value) => value
          Err(issue) => return reject(Driver(issue))
        }
        match (transfer.append)(wire) {
          Ok(_) => ()
          Err(issue) => return reject(Driver(issue))
        }
      }
      if !current() {
        return reject(Fenced)
      }
      match (transfer.finish)() {
        Ok(_) => ()
        Err(issue) => return reject(Driver(issue))
      }
      if !current() {
        return reject(Fenced)
      }
    }
    if !current() {
      return reject(Fenced)
    }
    if component_compute_quantum == 0 {
      match (operations.execute)() {
        Ok(_) => ()
        Err(issue) => return reject(Driver(issue))
      }
    } else {
      let mut executed = false
      for _ in 0..<max_finalization_rounds {
        if !live() {
          return reject(Fenced)
        }
        let progress = match (operations.advance)(component_compute_quantum) {
          Ok(value) => value
          Err(issue) => {
            println("node-component advance task=" + index.to_string())
            return reject(Driver(issue))
          }
        }
        if progress.complete {
          executed = true
          break
        }
        if progress.work <= 0L {
          break
        }
      }
      if !executed {
        return reject(FinalizationLimit)
      }
    }
    if component_after_compute is Some(snapshot) {
      match snapshot(operations, index) {
        Ok(_) => ()
        Err(issue) => return reject(Driver(issue))
      }
    }
    if !current() {
      return reject(Fenced)
    }
    match
      (operations.prepare_finalization)(index, operations.storage_bytes, live) {
      Ok(_) => ()
      Err(issue) => {
        println("node-component prepare-finalization task=" + index.to_string())
        return reject(Driver(issue))
      }
    }
    if !current() {
      return reject(Fenced)
    }
    let mut complete = false
    for _ in 0..<max_finalization_rounds {
      if !live() {
        return reject(Fenced)
      }
      let progress = match
        (operations.advance_finalization)(finalization_quantum) {
        Ok(value) => value
        Err(issue) => {
          println(
            "node-component advance-finalization task=" + index.to_string(),
          )
          return reject(Driver(issue))
        }
      }
      if progress.complete {
        complete = true
        break
      }
      if progress.work <= 0L {
        break
      }
    }
    if !current() {
      return reject(Fenced)
    }
    if !complete {
      return reject(FinalizationLimit)
    }
    match (operations.settle)() {
      Ok(_) => task.settled = true
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
    task.completed = match
      (operations.complete)(index, operations.storage_bytes, live) {
      Ok(value) => Some(value)
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
  }
  if @strategy.next_captured_task(run) is Some(_) {
    return reject(UnsupportedGraph)
  }
  let result = match retained_effect {
    None => @strategy.graph_result_task(graph, 0).unwrap_or(count - 1)
    Some(original) =>
      // A Model introduces its own retained Result root. The Effect's primary
      // output is selected from its checked source ports, not that Model root.
      @strategy.captured_effect_run_source_at(original, 0)
      .map(@strategy.checked_effect_source_task)
      .unwrap_or(-1)
  }
  guard result >= 0 &&
    result < count &&
    tasks[result] is Some(primary) &&
    primary.completed is Some(completed) else {
    return reject(MissingOutput)
  }
  let lookup = fn(task : Int) {
    guard tasks.get(task) is Some(Some(original)) &&
      original.completed is Some(output) else {
      return None
    }
    Some((original.operations, output))
  }
  let cleanup = () => close_local_values_tasks(run, tasks)
  Ok({
    run,
    operations: primary.operations,
    completed,
    available,
    tasks: Some((lookup, cleanup)),
  })
}

///|
test "collection actual default Request codec reloads 100000 from the same receipt and finite parent" {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  collection_request_publication_case(
    100000,
    false,
    source_free_max_work=Some(30000000),
    initial_limits=Some(limits),
    actual_request_profile=true,
  )
}

///|
test "actual default Request giant scalar array executes before SDK row-retention refusal" {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  collection_request_publication_case(
    1,
    false,
    source_free_max_work=Some(30000000),
    initial_limits=Some(limits),
    simple=true,
    actual_request_profile=true,
    giant_elements=Some(20000),
  )
}
