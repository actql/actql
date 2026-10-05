///|
/// Native registered-case product path. The wrapper supplies the checked
/// application files and compares this result with its independent oracle.
fn required(matches : @argparse.Matches, name : String) -> String {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => abort("missing or repeated option --" + name)
  }
}

///|
fn optional_quantity_json(value : Int64?) -> String {
  match value {
    Some(value) => "\"" + value.to_string() + "\""
    None => "null"
  }
}

///|
fn int_option(matches : @argparse.Matches, name : String) -> Int {
  let parsed : Int = @string.from_str(required(matches, name)) catch {
    _ => abort("invalid integer option --" + name)
  }
  if parsed < 1 {
    abort("nonpositive option --" + name)
  }
  parsed
}

///|
fn int64_option(matches : @argparse.Matches, name : String) -> Int64 {
  let parsed : Int64 = @string.from_str(required(matches, name)) catch {
    _ => abort("invalid integer option --" + name)
  }
  if parsed < 1L {
    abort("nonpositive option --" + name)
  }
  parsed
}

///|
fn task_rates_option(
  matches : @argparse.Matches,
  name : String,
  task_count : Int,
) -> Array[Int64] {
  let raw = required(matches, name)
  if raw == "-" {
    return []
  }
  let parts = raw.split(",").to_array()
  if parts.length() != task_count {
    abort("incorrect task estimate count --" + name)
  }
  let rates : Array[Int64] = []
  for part in parts {
    let rate : Int64 = @string.from_str(part) catch {
      _ => abort("invalid task estimate --" + name)
    }
    if rate < 1L || rate > 2147483647L {
      abort("out-of-range task estimate --" + name)
    }
    rates.push(rate)
  }
  rates
}

///|
fn resident_estimates_option(
  matches : @argparse.Matches,
  task_count : Int,
) -> @example.NativeResidentEstimateProfile? {
  let names = [
    "resident-task-ms", "resident-prepare-ms", "resident-cleanup-ms", "resident-import-ms",
  ]
  let missing = names.filter(name => required(matches, name) == "-")
  if missing.length() == names.length() {
    return None
  }
  if !missing.is_empty() {
    abort("incomplete resident estimates")
  }
  let imports = required(matches, "resident-import-ms").split(",").to_array()
  if imports.length() != task_count + 1 {
    abort("incorrect resident import estimate count")
  }
  let import_milliseconds : Array[Int64?] = imports.map(part => {
    if part == "?" {
      None
    } else {
      let ms : Int64 = @string.from_str(part) catch {
        _ => abort("invalid resident import estimate")
      }
      if ms < 1L || ms > 2147483647L {
        abort("out-of-range resident import estimate")
      }
      Some(ms)
    }
  })
  Some({
    preparation_milliseconds: int64_option(matches, "resident-prepare-ms"),
    cleanup_milliseconds: int64_option(matches, "resident-cleanup-ms"),
    task_milliseconds: task_rates_option(
      matches, "resident-task-ms", task_count,
    ),
    import_milliseconds,
  })
}

///|
fn rejection_name(issue : @resources.LedgerIssue?) -> String {
  match issue {
    None => "feasible"
    Some(@resources.PlanningLimit) => "planning"
    Some(@resources.AttemptLimit) => "attempt"
    Some(@resources.TokenLimit) => "token"
    Some(@resources.CostLimit) => "cost"
    Some(@resources.DurationLimit) => "duration"
    Some(@resources.HoldingLimit) => "holding"
    Some(@resources.TransferLimit) => "transfer"
    Some(@resources.RetentionLimit) => "retention"
    Some(@resources.ExecutionLimit) => "execution"
    Some(@resources.InvalidLimits) => "invalid-limits"
    Some(@resources.ForeignOwner) => "foreign-owner"
    Some(@resources.ClosedReservation) => "closed-reservation"
    Some(@resources.ClosedHolding) => "closed-holding"
    Some(@resources.InvalidCharge) => "invalid-charge"
  }
}

///|
fn native_strategy_issue_name(
  issue : @host.NativeStrategyComputeRunIssue,
) -> String {
  match issue {
    @host.Closed => "closed"
    @host.Start(start) =>
      match start {
        @host.Physical(@host.InvalidLimits) => "start-physical-limits"
        @host.Physical(@host.ImportCount) => "start-import-count"
        @host.Physical(@host.ImportRows) => "start-import-rows"
        @host.Physical(@host.ImportColumns) => "start-import-columns"
        @host.Physical(@host.ImportCells) => "start-import-cells"
        @host.Physical(_) => "start-physical"
        @host.Strategy(run) =>
          match run {
            @strategy.UnsupportedGraph => "start-strategy-graph"
            @strategy.PreviewWorkLimit => "start-strategy-preview-work"
            @strategy.ForeignCapture => "start-strategy-capture"
            @strategy.NotReady => "start-strategy-not-ready"
            @strategy.Stopped => "start-strategy-stopped"
            @strategy.ForeignCandidate => "start-strategy-candidate"
            @strategy.MissingOutput => "start-strategy-output"
            @strategy.Capture(_) => "start-strategy-source"
            @strategy.Binding(_) => "start-strategy-binding"
            @strategy.Read(_) => "start-strategy-read"
            @strategy.Compute(_) => "start-strategy-compute"
            @strategy.Implementation(_) => "start-strategy-implementation"
            @strategy.Physical(issue) =>
              "start-strategy-physical-" + rejection_name(Some(issue))
            @strategy.ActivationNotAuthorized =>
              "start-strategy-activation-not-authorized"
          }
        @host.Settlement(_) => "start-settlement"
        @host.MissingOutput => "start-missing-output"
      }
    @host.Execution(failure) =>
      match failure.primary {
        @host.Physical(physical) =>
          match physical {
            @host.RuntimeState => "physical-runtime-state"
            @host.InvalidLimits => "physical-limits"
            @host.ImportCount => "physical-import-count"
            @host.ImportRows => "physical-import-rows"
            @host.ImportColumns => "physical-import-columns"
            @host.ImportCells => "physical-import-cells"
            @host.ParameterCount => "physical-parameters"
            @host.Runtime(_) => "physical-duckdb"
            @host.Parameter(_) => "physical-parameter-binding"
            @host.Query(_) => "physical-query"
            @host.Fields(_) => "physical-fields"
            @host.Columns(_) => "physical-columns"
            @host.Compute(_) => "physical-compute"
            @host.RetainedFile(_) => "physical-retained-file"
            @host.RowFrames(_) => "physical-row-frames"
            @host.RetainedImport(_) => "physical-retained-import"
            @host.ResidentImport(_) => "physical-resident-import"
          }
        @host.Strategy(_) => "strategy"
        @host.Settlement(_) => "settlement"
        @host.MissingOutput => "missing-output"
      }
  }
}

///|
/// Measure the same one-task product boundary used by the full Run helper.
/// These monotonic intervals are calibration inputs, never acceptance
/// timings. The clock observation grants no execution authority.
fn execute_timed_native_strategy_run(
  run : @host.NativeStandardStrategyRun,
  dispatch : @standard_host.StrategyHostDispatch,
  captured : @strategy.CapturedDAG,
  ledger : @resources.Ledger,
  stop_after_task : Int?,
) -> Result[Unit, @host.NativeStandardStrategyRunIssue] {
  let mut next_task = 1
  while true {
    if @strategy.next_captured_task(captured) is None {
      return Ok(())
    }
    emit_owner_observation("before-task", next_task, run, ledger)
    let before = @bench.monotonic_clock_start()
    // Pause at the existing policy boundary; commit its ordinary offline
    // choice, never a benchmark-authored ranking or physical task.
    match @standard_host.prepare_dispatch_policy_choice(dispatch) {
      Err(issue) => return Err(@host.Dispatch(issue))
      Ok(true) => {
        let observer_start = @bench.monotonic_clock_start()
        let planning_before = @resources.ledger_usage(ledger).planning_work
        // The existing bounded consultation owns the immutable projection.
        // Its planning charge is part of this instrumented experiment.
        match
          @standard_host.prepare_dispatch_policy_request(
            dispatch,
            "benchmark-task-" + next_task.to_string(),
            @strategy.graph_program_definition_cid(
              @strategy.captured_dag_graph(captured),
            ),
            "native-benchmark-offline",
            1L,
            0L,
          ) {
          Err(issue) => return Err(@host.Dispatch(issue))
          Ok(_) => ()
        }
        let candidates = @standard_host.dispatch_policy_candidates(dispatch).unwrap()
        println(
          "compute-candidates:" +
          next_task.to_string() +
          ":" +
          candidates.canonical_json,
        )
        match @standard_host.commit_dispatch_offline_policy_choice(dispatch) {
          Err(issue) => return Err(@host.Dispatch(issue))
          Ok(_) => ()
        }
        // Preserve the owner's rejected assessments as well as feasible
        // policy candidates. Unknown estimates and capacity refusals stay
        // distinguishable from an executed physical provider.
        println(
          "compute-explanation:" +
          next_task.to_string() +
          ":" +
          @strategy.explain_captured_strategy(captured, 65536, 10000).unwrap(),
        )
        let revision = @strategy.strategy_history_at(
          captured,
          @strategy.strategy_history_count(captured) - 1,
        ).unwrap()
        let assessment = @strategy.strategy_assessment(revision)
        let selection_source = match
          @strategy.strategy_selection_source(revision) {
          @strategy.OfflineLatency => "OfflineLatency"
          @strategy.BoundedLatency => "BoundedLatency"
          @strategy.HostProposal => "HostProposal"
          @strategy.ExternalPolicy(_) => "ExternalPolicy"
        }
        let registration = @strategy.strategy_registration(revision, next_task).unwrap()
        println(
          "planner-observer-work:" +
          next_task.to_string() +
          ":" +
          (@resources.ledger_usage(ledger).planning_work - planning_before).to_string(),
        )
        println(
          "planner-observer-us:" +
          next_task.to_string() +
          ":" +
          @bench.monotonic_clock_end(observer_start).to_int64().to_string(),
        )
        println(
          "compute-choice:{\"task\":" +
          next_task.to_string() +
          ",\"position\":" +
          assessment.position.to_string() +
          ",\"source\":\"" +
          selection_source +
          "\"" +
          ",\"revision\":" +
          @strategy.strategy_revision_number(revision).to_string() +
          ",\"registration\":\"" +
          @connector.capability_registration_selection_key(registration) +
          "\",\"name\":\"" +
          @connector.capability_description(registration).name +
          "\",\"resident\":" +
          (@strategy.strategy_resident_profile(revision, next_task) is Some(_)).to_string() +
          "}",
        )
      }
      Ok(false) => ()
    }
    match @host.execute_next_native_standard_strategy_task(run) {
      Ok(Some(completion)) => {
        let elapsed = @bench.monotonic_clock_end(before).to_int64()
        if elapsed < 0L {
          abort("invalid monotonic interval")
        }
        guard completion.usage is Some(usage) else {
          abort("completed task lacks product measurement")
        }
        guard completion.holding is Some(holding) else {
          abort("completed task lacks sealed holding")
        }
        println(
          "task-elapsed-us:" +
          completion.task.to_string() +
          ":" +
          elapsed.to_string(),
        )
        println(
          "task-usage:" +
          completion.task.to_string() +
          ":" +
          usage.measurement_work.to_string() +
          ":" +
          usage.measurement_bytes.to_string() +
          ":" +
          usage.measurement_nodes.to_string() +
          ":" +
          usage.comparison_work.to_string() +
          ":" +
          usage.comparison_bytes.to_string() +
          ":" +
          usage.comparison_nodes.to_string(),
        )
        println(
          "task-measurement-scope:" +
          completion.task.to_string() +
          ":" +
          (match usage.measurement_scope {
            @host.InputOutputValues => "input-output-values"
            @host.ProviderWork => "provider-work"
          }),
        )
        println(
          "task-holding:" +
          completion.task.to_string() +
          ":" +
          holding.rows.to_string() +
          ":" +
          holding.rows_cid +
          ":" +
          holding.bytes.to_string(),
        )
        // Observed after the timed interval: resident imports so far and the
        // shared database's objects visible to the next task.
        let resident = @host.native_standard_strategy_run_resident_observation(
          run,
        )
        if resident.environments > 0 {
          println(
            "task-resident:" +
            completion.task.to_string() +
            ":imports=" +
            resident.imports.to_string() +
            ":imported-rows=" +
            resident.imported_rows.to_string() +
            ":borrowed=" +
            resident.borrowed_inputs.to_string() +
            ":temporary-views=" +
            resident.temporary_views.to_string() +
            ":tables=" +
            resident.tables.to_string(),
          )
        }
        emit_owner_observation("after-task", completion.task, run, ledger)
        next_task += 1
        if stop_after_task == Some(completion.task) {
          return Ok(())
        }
      }
      Ok(None) => return Ok(())
      Err(issue) => return Err(issue)
    }
  } nobreak {
    Err(@host.InvalidSelection)
  }
}

///|
/// Read only the existing owner and ledger. This observation does not create
/// reservations or replace their identity/cleanup checks. Its SQL observation
/// cost stays inside the enclosing execution interval and is recorded separately.
fn emit_owner_observation(
  boundary : String,
  task : Int,
  run : @host.NativeStandardStrategyRun,
  ledger : @resources.Ledger,
) -> Unit {
  let start = @bench.monotonic_clock_start()
  let resident = @host.native_standard_strategy_run_resident_observation(run)
  let usage = @resources.ledger_usage(ledger)
  println(
    "owner-observation:{\"boundary\":\"" +
    boundary +
    "\",\"task\":" +
    task.to_string() +
    ",\"planningWork\":" +
    usage.planning_work.to_string() +
    ",\"attempts\":" +
    usage.attempts.to_string() +
    ",\"holdings\":" +
    usage.holdings.to_string() +
    ",\"heldBytes\":" +
    usage.held_bytes.to_string() +
    ",\"reservedExecutionBytes\":" +
    usage.reserved_execution_bytes.to_string() +
    ",\"reservedRetentionBytes\":" +
    usage.reserved_retention_bytes.to_string() +
    ",\"reservedTransferBytes\":" +
    usage.reserved_transfer_bytes.to_string() +
    ",\"uncertainTransferBytes\":" +
    usage.uncertain_transfer_bytes.to_string() +
    ",\"environments\":" +
    resident.environments.to_string() +
    ",\"imports\":" +
    resident.imports.to_string() +
    ",\"borrowedInputs\":" +
    resident.borrowed_inputs.to_string() +
    ",\"importedRows\":" +
    resident.imported_rows.to_string() +
    ",\"unconfirmedEnvironments\":" +
    resident.unconfirmed_environments.to_string() +
    ",\"importScratchBytes\":" +
    resident.import_scratch_bytes.to_string() +
    ",\"taskDemandBytes\":" +
    resident.task_demand_bytes.to_string() +
    ",\"temporaryViews\":" +
    resident.temporary_views.to_string() +
    ",\"tables\":" +
    resident.tables.to_string() +
    "}",
  )
  println(
    "observer-elapsed-us:" +
    @bench.monotonic_clock_end(start).to_int64().to_string(),
  )
}

///|
fn close_observed_run(
  run : @host.NativeStandardStrategyRun,
  ledger : @resources.Ledger,
  task : Int,
) -> Unit {
  emit_owner_observation("before-close", task, run, ledger)
  if !@host.close_native_standard_strategy_run(run).unwrap() {
    abort("native strategy cleanup unconfirmed")
  }
  emit_owner_observation("after-close", task, run, ledger)
  let first_close = @resources.ledger_usage(ledger)
  if !@host.close_native_standard_strategy_run(run).unwrap() ||
    @resources.ledger_usage(ledger) != first_close {
    abort("duplicate native strategy cleanup changed ledger")
  }
  if !(@host.execute_next_native_standard_strategy_task(run)
    is Err(@host.Closed)) ||
    @resources.ledger_usage(ledger) != first_close {
    abort("closed native strategy Run resumed physical work")
  }
  emit_owner_observation("duplicate-close", task, run, ledger)
}

///|
/// Monotonic enclosing boundaries, not additive timers for parallel subwork.
fn phase_boundary(name : String, start : @bench.Timestamp) -> Unit {
  println("phase:" + name)
  println(
    "phase-time-us:" +
    name +
    ":" +
    @bench.monotonic_clock_end(start).to_int64().to_string(),
  )
}

///|
fn emit_native_phase_observations(
  events : Array[(@host.NativeStandardStrategyPhaseEvent, Int64, Int64)],
) -> Unit {
  for (event, elapsed, overhead) in events {
    let (phase, boundary, success) = match event {
      @host.Begin(phase) => (phase, "begin", "null")
      @host.End(phase, success) => (phase, "end", success.to_string())
    }
    let (name, task, producer) = match phase {
      @host.ResidentEnvironment(task) => ("environment", task, "null")
      @host.ResidentInputImport(task, producer) =>
        ("import", task, producer.to_string())
      @host.ResidentTask(task) => ("compute", task, "null")
    }
    println(
      "physical-phase-event:{\"phase\":\"" +
      name +
      "\",\"task\":" +
      task.to_string() +
      ",\"producer\":" +
      producer +
      ",\"boundary\":\"" +
      boundary +
      "\",\"success\":" +
      success +
      ",\"elapsedMicroseconds\":" +
      elapsed.to_string() +
      ",\"observerMicroseconds\":" +
      overhead.to_string() +
      "}",
    )
  }
}

///|
fn main {
  let execution_start = @bench.monotonic_clock_start()
  let command = @argparse.Command("actql-native-retained-case-probe", options=[
    @argparse.OptionArg("application-root", required=true),
    @argparse.OptionArg("database", required=true),
    @argparse.OptionArg("duckdb-library", required=true),
    @argparse.OptionArg("retained-task-root", required=true),
    @argparse.OptionArg("expected-cid", required=true),
    @argparse.OptionArg("expected-tasks", required=true),
    @argparse.OptionArg("native-ms", default_values=["1000"]),
    @argparse.OptionArg("stop-after-task", default_values=["-"]),
    @argparse.OptionArg("attempt-cap", default_values=["12"]),
    @argparse.OptionArg("local-eligible", default_values=["true"]),
    @argparse.OptionArg("resident-policy", default_values=["false"]),
    @argparse.OptionArg("phase-observer", default_values=["false"]),
    @argparse.OptionArg("resident-task-ms", default_values=["-"]),
    @argparse.OptionArg("resident-prepare-ms", default_values=["-"]),
    @argparse.OptionArg("resident-cleanup-ms", default_values=["-"]),
    @argparse.OptionArg("resident-import-ms", default_values=["-"]),
    @argparse.OptionArg("local-task-ms", default_values=["-"]),
    @argparse.OptionArg("native-task-ms", default_values=["-"]),
    @argparse.OptionArg("source-rows", required=true),
    @argparse.OptionArg("task-rows", required=true),
    @argparse.OptionArg("columns", required=true),
    @argparse.OptionArg("value-bytes", required=true),
    @argparse.OptionArg("wire-bytes", required=true),
    @argparse.OptionArg("value-nodes", required=true),
    @argparse.OptionArg("text-bytes", required=true),
    @argparse.OptionArg("work", required=true),
    @argparse.OptionArg("entries", required=true),
    @argparse.OptionArg("batch-bytes", required=true),
    @argparse.OptionArg("planning-work", required=true),
    @argparse.OptionArg("transfer-cap", required=true),
    @argparse.OptionArg("retained-cap", required=true),
    @argparse.OptionArg("execution-cap", required=true),
  ])
  let matches = command.parse() catch { error => abort(error.to_string()) }
  let root = required(matches, "application-root")
  let database_path = required(matches, "database")
  let library_path = required(matches, "duckdb-library")
  let retained_task_root = required(matches, "retained-task-root")
  let expected_cid = required(matches, "expected-cid")
  let expected_tasks = int_option(matches, "expected-tasks")
  let stop_after_task = if required(matches, "stop-after-task") == "-" {
    None
  } else {
    let task = int_option(matches, "stop-after-task")
    if task >= expected_tasks {
      abort("between-task stop must precede final task")
    }
    Some(task)
  }
  let local_eligible = match required(matches, "local-eligible") {
    "true" => true
    "false" => false
    _ => abort("invalid local eligibility")
  }
  // Installs the resident DuckDB profile as an additional strategy candidate.
  // Whether and where it is used remains the portable strategy's selection.
  let resident_policy = match required(matches, "resident-policy") {
    "true" => true
    "false" => false
    _ => abort("invalid resident policy")
  }
  let phase_observer = match required(matches, "phase-observer") {
    "true" => true
    "false" => false
    _ => abort("invalid phase observer")
  }
  let phase_events : Array[
    (@host.NativeStandardStrategyPhaseEvent, Int64, Int64),
  ] = []
  let observe_phase : ((@host.NativeStandardStrategyPhaseEvent) -> Unit)? = if phase_observer {
    Some(event => {
      let before = @bench.monotonic_clock_start()
      let elapsed = @bench.monotonic_clock_end(execution_start).to_int64()
      let overhead = @bench.monotonic_clock_end(before).to_int64()
      phase_events.push((event, elapsed, overhead))
    })
  } else {
    None
  }
  let local_task_ms = task_rates_option(
    matches, "local-task-ms", expected_tasks,
  )
  let native_task_ms = task_rates_option(
    matches, "native-task-ms", expected_tasks,
  )
  let resident_estimates = resident_estimates_option(matches, expected_tasks)
  if !resident_policy && resident_estimates is Some(_) {
    abort("resident estimates require resident offers")
  }
  if (!local_eligible && !local_task_ms.is_empty()) ||
    (!native_task_ms.is_empty() && local_eligible && local_task_ms.is_empty()) {
    abort("incomplete task estimate profile")
  }
  let source_rows = int_option(matches, "source-rows")
  let task_rows = int_option(matches, "task-rows")
  let columns = int_option(matches, "columns")
  let value_bytes = int_option(matches, "value-bytes")
  let wire_bytes = int_option(matches, "wire-bytes")
  let value_nodes = int_option(matches, "value-nodes")
  let text_bytes = int_option(matches, "text-bytes")
  let work = int_option(matches, "work")
  let entries = int_option(matches, "entries")
  let batch_bytes = int_option(matches, "batch-bytes")
  let attempt_cap = int_option(matches, "attempt-cap")
  if attempt_cap > 12 {
    abort("diagnostic attempt cap exceeds registered ceiling")
  }
  let execution_cap = int64_option(matches, "execution-cap")
  let native_ms : Int64 = @string.from_str(required(matches, "native-ms")) catch {
    _ => abort("invalid native-ms")
  }
  phase_boundary("application", execution_start)
  let app = @application.load_native_remote_application_with_data(
    root,
    {
      program: "program.json",
      environment: "environment.json",
      environment_cid: "environment.cid",
      parameters: "parameters.json",
      registry: "registry.json",
      values: "values.json",
      fragment: "fragment.json",
      query: "query.json",
      evidence: "evidence.json",
      two_receipt: "two-receipt.json",
    },
    1048576L,
    "main",
    "records",
    {
      source_rows,
      task_rows,
      columns,
      value_bytes,
      wire_bytes,
      value_nodes,
      text_bytes,
      work,
      entries,
      batch_bytes,
    },
  ).unwrap()
  phase_boundary("library", execution_start)
  let library = @duckdb.load_library(library_path).unwrap()
  phase_boundary("database", execution_start)
  let database = library
    .open_database(
      {
        memory_bytes: execution_cap,
        threads: 1,
        external_access: false,
        read_only: false,
      },
      path=database_path,
    )
    .unwrap()
  phase_boundary("acquisition-start", execution_start)
  let acquisition_choice = @acquisition_host.configured_native_host_choice(
    @example.application_acquisition(app),
  )
  let acquisition_candidate = @planning.acquisition_choice_candidate(
    acquisition_choice,
  )
  let acquisition_reason = match
    @planning.acquisition_choice_reason(acquisition_choice) {
    @cost.HostPreferred(_) => "HostPreferred"
    @cost.EstimatedFastest(_, _) => "EstimatedFastest"
    @cost.Deferred => "Deferred"
    @cost.NoCandidates => "NoCandidates"
  }
  let acquisition_duration = match
    @planning.acquisition_candidate_duration(acquisition_candidate) {
    @cost.Complete(value) => "\"" + value.to_string() + "\""
    @cost.Unknown => "null"
  }
  let quantities = @planning.acquisition_candidate_quantities(
    acquisition_candidate,
  )
  let capacity = @acquisition_host.configured_native_capacity(
    @example.application_acquisition(app),
  ).unwrap()
  println(
    "acquisition-choice:{\"host\":\"native\",\"provided\":[\"native\"],\"registration\":\"" +
    @connector.capability_registration_selection_key(
      @planning.acquisition_candidate_registration(acquisition_candidate),
    ) +
    "\",\"milliseconds\":" +
    acquisition_duration +
    ",\"reason\":\"" +
    acquisition_reason +
    "\",\"transferBytes\":" +
    optional_quantity_json(quantities.transfer_bytes) +
    ",\"retainedBytes\":" +
    optional_quantity_json(quantities.retained_bytes) +
    ",\"moneyUnits\":" +
    optional_quantity_json(quantities.money_units) +
    ",\"receiverRetentionBytes\":\"" +
    capacity.retained_bytes.to_string() +
    "\",\"receiverExecutionBytes\":\"" +
    capacity.execution_bytes.to_string() +
    "\",\"capacityScope\":\"declared receiver, not physical heap\"}",
  )
  let acquisition = @host.start_native_acquisition_runtime(
    @example.application_acquisition(app),
    "native-retained-diagnostic",
    database,
  ).unwrap()
  phase_boundary("acquisition-execute", execution_start)
  let acquisition_observation = match
    @host.execute_native_acquisition_runtime(acquisition) {
    Ok(value) => value
    Err(failure) =>
      match failure.primary {
        @host.RuntimeState => abort("acquisition runtime state")
        @host.InvalidLimits => abort("acquisition limits")
        @host.ParameterCount => abort("acquisition parameter count")
        @host.MetadataShape => abort("acquisition metadata shape")
        @host.Runtime(_) => abort("acquisition DuckDB runtime")
        @host.Parameter(_) => abort("acquisition parameter")
        @host.Fields(_) => abort("acquisition physical fields")
        @host.Columns(_) => abort("acquisition transport columns")
        @host.Host(issue) =>
          match issue {
            @acquisition_host.InvalidState => abort("acquisition Host state")
            @acquisition_host.Evidence(_) => abort("acquisition Host evidence")
            @acquisition_host.Attempt(inner) =>
              match inner {
                @duckdb_acquisition.ForeignChoice =>
                  abort("acquisition foreign choice")
                @duckdb_acquisition.InvalidState =>
                  abort("acquisition attempt state")
                @duckdb_acquisition.Demand(_) => abort("acquisition demand")
                @duckdb_acquisition.Receipts(_) => abort("acquisition receipts")
                @duckdb_acquisition.Receiving(receiving) =>
                  match receiving {
                    @adapter.InvalidLimits =>
                      abort("acquisition receiving limits")
                    @adapter.InvalidState =>
                      abort("acquisition receiving state")
                    @adapter.ForeignReceipt =>
                      abort("acquisition foreign receipt")
                    @adapter.NotBaseTable => abort("acquisition not base table")
                    @adapter.InvalidMetadata => abort("acquisition metadata")
                    @adapter.Values(_) => abort("acquisition values")
                    @adapter.Guard(_, _, _, _) => abort("acquisition guard")
                    @adapter.Stream(_) => abort("acquisition stream")
                  }
              }
            @acquisition_host.Completion(_) =>
              abort("acquisition Host completion")
            @acquisition_host.Binding(_) => abort("acquisition Host binding")
          }
      }
  }
  let (guard_work, guard_bytes, guard_nodes) = @duckdb_acquisition.duckdb_native_observation_measurement_usage(
    acquisition_observation,
  )
  let comparison = @duckdb_acquisition.duckdb_native_observation_demand_usage(
    acquisition_observation,
  )
  let validation_receipt = @duckdb_acquisition.duckdb_native_observation_receipt_at(
    acquisition_observation, 0,
  ).unwrap()
  let output_receipt = @duckdb_acquisition.duckdb_native_observation_receipt_at(
    acquisition_observation, 1,
  ).unwrap()
  let source_record = @duckdb_acquisition.duckdb_native_observation_record_at(
    acquisition_observation, 0,
  ).unwrap()
  let filter_record = @duckdb_acquisition.duckdb_native_observation_record_at(
    acquisition_observation, 1,
  ).unwrap()
  let select_record = @duckdb_acquisition.duckdb_native_observation_record_at(
    acquisition_observation, 2,
  ).unwrap()
  let acquisition_evidence = "{\"receipts\":[" +
    @encode.document_text(validation_receipt.0) +
    "," +
    @encode.document_text(output_receipt.0) +
    "],\"records\":[" +
    @encode.document_text(source_record.0) +
    "," +
    @encode.document_text(filter_record.0) +
    "," +
    @encode.document_text(select_record.0) +
    "],\"observation\":" +
    @encode.document_text(
      @duckdb_acquisition.duckdb_native_observation_document(
        acquisition_observation,
      ),
    ) +
    "}"
  phase_boundary("acquisition-output", execution_start)
  let output = @host.native_acquisition_runtime_output(acquisition).unwrap()
  phase_boundary("source", execution_start)
  let source = @duckdb_acquisition.native_captured_source(
    output, source_rows, work,
  ).unwrap()
  let ledger = @example.application_bounded_ledger({
    planning_work: int_option(matches, "planning-work"),
    attempts: attempt_cap,
    holdings: 12,
    transfer_bytes: int64_option(matches, "transfer-cap"),
    retained_bytes: int64_option(matches, "retained-cap"),
    execution_bytes: execution_cap,
  }) catch {
    _ => abort("registered ledger limits rejected")
  }
  phase_boundary("capture", execution_start)
  let captured = @strategy.open_captured_dag(
    @example.application_graph(app),
    source,
    ledger,
  ).unwrap()
  // Capture owns the admitted rows; the acquisition database is no longer a
  // live input. Close its physical connection before task databases start.
  database.close()
  phase_boundary("dispatch", execution_start)
  let dispatch = @example.application_native_retained_strategy_dispatch(
    app,
    captured,
    native_ms,
    wire_bytes.to_int64(),
    1L,
    1L,
    1L,
    resident_policy,
    local_task_ms~,
    native_task_ms~,
    resident_estimates?,
    local_eligible~,
  ) catch {
    _ => abort("native strategy dispatch rejected")
  }
  phase_boundary("strategy-open", execution_start)
  let run = @host.open_native_standard_strategy_run(
    dispatch,
    {
      max_rows: task_rows,
      max_cells: (source_rows + task_rows) * columns,
      max_parameters: columns + 100,
      max_sql_bytes: 100000,
      max_batch_rows: Int::min(source_rows, 1000),
    },
    @example.application_native_retained_task_transfer_capacity(app),
    // The selected execution envelope also reserves decoder and query scratch.
    // The database receives its own half rather than claiming the whole pool.
    execution_cap / 2L,
    library=Some(library),
    database_path~,
    retained_profile={
      root_path: retained_task_root,
      run_occurrence: "native-application-" + @env.now().to_string(),
      max_file_bytes: wire_bytes.to_int64(),
      wire: {
        max_columns: columns,
        max_order_work: work,
        max_bytes: wire_bytes,
        max_nodes: value_nodes,
        max_depth: 64,
      },
      max_batch_bytes: batch_bytes,
      // The configured transport admits at most 512 rows per physical frame.
      max_chunk_rows: Int::min(task_rows, 512),
    },
    observe_phase?,
  ).unwrap()
  phase_boundary("strategy-execute", execution_start)
  let execution = execute_timed_native_strategy_run(
    run, dispatch, captured, ledger, stop_after_task,
  )
  // Flush only after the physical work interval: diagnostic output is not
  // charged to environment, import or Compute durations. Clock/buffer overhead
  // remains part of the enclosing process measurement.
  emit_native_phase_observations(phase_events)
  if execution is Err(_) {
    close_observed_run(run, ledger, 0)
    @host.close_native_acquisition_runtime(acquisition)
    @strategy.stop_captured_dag(captured)
  }
  match execution {
    Ok(_) => ()
    Err(@host.Closed) => abort("native strategy run closed")
    Err(@host.InvalidSelection) => abort("native strategy selection invalid")
    Err(@host.DuckDBUnavailable) => abort("native strategy DuckDB unavailable")
    Err(@host.Dispatch(issue)) =>
      match issue {
        @standard_host.InvalidConfiguration =>
          abort("native strategy dispatch configuration")
        @standard_host.NoStrategy => {
          println(
            "strategy-report-count:" +
            @strategy.strategy_report_count(captured).to_string(),
          )
          for report_index in 0..<@strategy.strategy_report_count(captured) {
            let assessment = @strategy.strategy_report_at(
              captured, report_index,
            ).unwrap()
            println(
              "strategy-rejection:" +
              report_index.to_string() +
              ":" +
              rejection_name(assessment.rejection) +
              ":retained=" +
              assessment.retained_bytes.to_string(),
            )
          }
          println("strategy-terminal:no-strategy")
          abort("native strategy missing")
        }
        @standard_host.ForeignSelection =>
          abort("native strategy foreign selection")
        @standard_host.PendingTask => abort("native strategy pending task")
        @standard_host.StaleTask => abort("native strategy stale task")
        @standard_host.Run(_) => abort("native strategy common Run rejected")
        @standard_host.Candidate(_) =>
          abort("native strategy candidate rejected")
        @standard_host.NativeCandidate(_) =>
          abort("native strategy native candidate rejected")
        @standard_host.Search(_) => abort("native strategy search rejected")
        @standard_host.EstimateOverflow =>
          abort("native strategy estimate overflow")
        @standard_host.JoinPreparation(_) =>
          abort("native strategy join preparation rejected")
      }
    Err(@host.Database(_)) => abort("native strategy database rejected")
    Err(@host.DuckDB(issue)) =>
      abort(
        "native strategy DuckDB task rejected: " +
        native_strategy_issue_name(issue),
      )
    Err(@host.Local(_)) => abort("native strategy Local task rejected")
  }
  if stop_after_task is Some(task) {
    close_observed_run(run, ledger, task)
    @host.close_native_acquisition_runtime(acquisition)
    @strategy.stop_captured_dag(captured)
    phase_boundary("stopped-cleanup-end", execution_start)
    println(
      "{\"status\":\"stopped-between-tasks\",\"completed_tasks\":" +
      task.to_string() +
      "}",
    )
    return
  }
  let task = @example.application_compute_count(app)
  if task != expected_tasks {
    abort("checked task count differs from fixture")
  }
  phase_boundary("output-cid", execution_start)
  let output = @host.read_native_standard_task_output(
    run,
    task,
    task_rows,
    {
      max_nodes: value_nodes,
      max_text_bytes: text_bytes,
      max_depth: 64,
      max_work: work,
    },
    {
      max_columns: columns,
      max_order_work: work,
      max_bytes: wire_bytes,
      max_nodes: value_nodes,
      max_depth: 64,
    },
    batch_bytes,
  ).unwrap()
  let cid = @execution.row_wire_cid(
    @execution.identify_completed_rows(output, {
      max_columns: columns,
      max_order_work: work,
      max_bytes: wire_bytes,
      max_nodes: value_nodes,
      max_depth: 64,
    }).unwrap(),
  )
  if cid != expected_cid {
    abort("final output identity differs from fixture oracle")
  }
  for index in 0..<@strategy.strategy_history_count(captured) {
    let revision = @strategy.strategy_history_at(captured, index).unwrap()
    for selected_task in 1..<(task + 1) {
      match @strategy.strategy_registration(revision, selected_task) {
        Some(registration) =>
          println(
            "selection:" +
            selected_task.to_string() +
            ":" +
            @connector.capability_description(registration).name,
          )
        None => ()
      }
    }
  }
  let execution_us = @bench.monotonic_clock_end(execution_start).to_int64()
  if execution_us < 0L {
    abort("invalid execution interval")
  }
  phase_boundary("execution-end", execution_start)
  let cleanup_start = @bench.monotonic_clock_start()
  close_observed_run(run, ledger, task)
  @host.close_native_acquisition_runtime(acquisition)
  @strategy.stop_captured_dag(captured)
  let usage = @resources.ledger_usage(ledger)
  if usage.uncertain_transfer_bytes != 0L ||
    usage.reserved_transfer_bytes != 0L ||
    usage.held_bytes != 0L ||
    usage.reserved_retention_bytes != 0L ||
    usage.reserved_execution_bytes != 0L {
    abort("native strategy ledger has unresolved capacity")
  }
  let cleanup_us = @bench.monotonic_clock_end(cleanup_start).to_int64()
  if cleanup_us < 0L {
    abort("invalid cleanup interval")
  }
  phase_boundary("cleanup-end", execution_start)
  println(
    "{\"task_count\":" +
    task.to_string() +
    ",\"rows_cid\":\"" +
    cid +
    "\",\"execution_us\":" +
    execution_us.to_string() +
    ",\"cleanup_us\":" +
    cleanup_us.to_string() +
    ",\"usage\":{\"planning_work\":" +
    usage.planning_work.to_string() +
    ",\"attempts\":" +
    usage.attempts.to_string() +
    ",\"holdings\":" +
    usage.holdings.to_string() +
    ",\"transferred_bytes\":" +
    usage.transferred_bytes.to_string() +
    ",\"uncertain_transfer_bytes\":" +
    usage.uncertain_transfer_bytes.to_string() +
    ",\"reserved_transfer_bytes\":" +
    usage.reserved_transfer_bytes.to_string() +
    ",\"held_bytes\":" +
    usage.held_bytes.to_string() +
    ",\"reserved_retention_bytes\":" +
    usage.reserved_retention_bytes.to_string() +
    ",\"reserved_execution_bytes\":" +
    usage.reserved_execution_bytes.to_string() +
    ",\"peak_retention_bytes\":" +
    usage.peak_retention_bytes.to_string() +
    "},\"acquisition_evidence\":" +
    acquisition_evidence +
    ",\"acquisition\":{\"guard_work\":" +
    guard_work.to_string() +
    ",\"guard_bytes\":" +
    guard_bytes.to_string() +
    ",\"guard_nodes\":" +
    guard_nodes.to_string() +
    ",\"comparison_work\":" +
    comparison.physical_work.to_string() +
    ",\"comparison_bytes\":" +
    comparison.physical_bytes.to_string() +
    ",\"comparison_nodes\":" +
    comparison.physical_nodes.to_string() +
    ",\"comparison_rows\":" +
    comparison.rows.to_string() +
    "}" +
    "}",
  )
}
