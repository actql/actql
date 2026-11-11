///|
test "collection original Request follows Node256 snapshot then finalization" {
  let digits : Array[String] = []
  for n in 0..<10 {
    digits.push("SELECT " + n.to_string() + " AS n")
  }
  let sql = "WITH d AS (" +
    digits.join(" UNION ALL ") +
    ") SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < 9999"
  let environment = collection_capacity_selected_environment(
    client_local_materialized_row_ceiling(client_local_resource_policy()).unwrap(),
  )
  let cid = @checked.checking_environment_cid(environment)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" + cid + "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, input) = native_driver_parent(sql)
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
  let prepared = compile_program_check_preparation(check, limits).unwrap()
  continue_request_program_preparation(parent, input).unwrap() |> ignore
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
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
    "same9999-request-finalization",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
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
    Ok(value) => value
    Err(failure) => {
      let family = match local_values_execution_failure_issue(failure) {
        Driver(
          @local_driver.ManagedValues(
            @execution.Admission(@execution.CaptureLimit)
          )
        ) => "ManagedValues/Admission/CaptureLimit"
        Driver(@local_driver.Configuration(@connector.InputUnavailable)) =>
          "Configuration/InputUnavailable"
        _ => "different checked failure"
      }
      let cleaned = retry_local_values_execution_failure_cleanup(failure)
      fail("request-finalization " + family + " cleanup=" + cleaned.to_string())
    }
  }
  let rows = output.rows().unwrap()
  assert_eq(rows.length(), 9999)
  for row in rows {
    assert_eq(row, "{\"n\":0}")
  }
  assert_true(output.close())
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
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
  for _ in 0..<100000 {
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
