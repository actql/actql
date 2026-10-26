///|
#borrow(path)
extern "C" fn diagnostic_cleanup_access(path : Bytes, allow : Bool) -> Bool = "actql_probe_cleanup_access"

///|
extern "C" fn diagnostic_expiry_wait() -> Unit = "actql_probe_expiry_wait"

///|
/// Native registered-case product path. The wrapper supplies the checked
/// application files and compares this result with its independent oracle.

///|
// This fixture authenticates the local producer through pins supplied by its
// trusted caller configuration, outside the payload. It never grants dispatch.
fn operational_require(value : Bool) -> Unit {
  if !value {
    abort("OperationalEstimateAcceptance")
  }
}

///|
fn inspect_operational_estimate(
  dispatch : @standard_host.StrategyHostDispatch,
  request : @strategy.PolicyRequest,
  task : Int,
  root : String,
  profile_revision : String,
  pins : Array[String],
  clock : @clock.NativeTrustedClock,
) -> String {
  let started = @bench.monotonic_clock_start()
  operational_require(pins.length() == 6)
  let template = @files.read_bounded_text_file(
    root,
    "task-" + task.to_string() + ".json",
    61440L,
  ).unwrap()
  operational_require(
    "sha256:" + @sha.hex(@utf8.encode(template)) == pins[task - 1],
  )
  let request_json = @strategy.placement_policy_request_json(request).unwrap()
  let body = "{\"binding\":" +
    request_json +
    "," +
    template.strip_prefix("{").unwrap().to_owned()
  let admitted = @host.admit_native_operational_estimate(
    dispatch, request, body, "configured-local-profile-producer", profile_revision,
    clock,
  ).unwrap()
  operational_require(
    admitted.references.any(reference => {
      reference.quantity == "task-processing" && reference.median_ms is Some(_)
    }),
  )
  println("operational-estimate:" + task.to_string() + ":" + body)
  // Every binding mutation reaches the real held Native request boundary.
  for
    changed in [
      { ..request, request_id: "other-request", },
      { ..request, run_identity: "other-run", },
      { ..request, authority: "other-authority", },
      { ..request, generation: request.generation + 1, },
      { ..request, revision: request.revision + 1, },
      { ..request, deadline_ms: request.deadline_ms - 1L, },
      { ..request, candidate_set_cid: "other-snapshot", },
    ] {
    operational_require(
      @host.admit_native_operational_estimate(
        dispatch, changed, body, "configured-local-profile-producer", profile_revision,
        clock,
      )
      is Err(_),
    )
  }
  operational_require(
    @host.admit_native_operational_estimate(
      dispatch, request, body, "", profile_revision, clock,
    )
    is Err(_),
  )
  operational_require(
    @host.admit_native_operational_estimate(
      dispatch, request, body, "configured-local-profile-producer", "different-profile",
      clock,
    )
    is Err(_),
  )
  let wrong_position = body.replace(
    old="\"position\":" + admitted.references[0].position.to_string(),
    new="\"position\":2147483647",
  )
  operational_require(wrong_position != body)
  operational_require(
    @host.admit_native_operational_estimate(
      dispatch, request, wrong_position, "configured-local-profile-producer", profile_revision,
      clock,
    )
    is Err(_),
  )
  let unknown_template = @files.read_bounded_text_file(
    root,
    "task-" + task.to_string() + "-unknown.json",
    61440L,
  ).unwrap()
  operational_require(
    "sha256:" + @sha.hex(@utf8.encode(unknown_template)) == pins[task + 2],
  )
  let unknown_body = "{\"binding\":" +
    request_json +
    "," +
    unknown_template.strip_prefix("{").unwrap().to_owned()
  let unknown = @host.admit_native_operational_estimate(
    dispatch, request, unknown_body, "configured-local-profile-producer", profile_revision,
    clock,
  ).unwrap()
  operational_require(!unknown.references.is_empty())
  operational_require(
    unknown.references.all(reference => {
      reference.median_ms is None && reference.unknown_reason is Some(_)
    }),
  )
  println("operational-unknown:" + task.to_string() + ":" + unknown_body)
  println("operational-refusals:" + task.to_string() + ":10")
  println(
    "operational-admission-us:" +
    task.to_string() +
    ":" +
    @bench.monotonic_clock_end(started).to_string(),
  )
  body
}

///|
priv struct EmpiricalProbe {
  mode : String
  position : Int?
  root : String
  profile_revision : String
  template_pin : String
  offline_fallback : Bool
  clock : @clock.NativeTrustedClock
  whole_run : Bool
  validation_probes : Bool
  mut trajectory : Array[Json]?
}

///|
fn commit_empirical_probe(
  probe : EmpiricalProbe,
  dispatch : @standard_host.StrategyHostDispatch,
  request : @strategy.PolicyRequest,
  task : Int,
  ledger : @resources.Ledger,
) -> String? {
  if (!probe.whole_run && task != 1) ||
    probe.mode == "offline" ||
    (probe.whole_run && task > 1 && probe.trajectory is None) {
    @standard_host.commit_dispatch_offline_policy_choice(dispatch).unwrap()
    println("empirical-fallback:" + task.to_string() + ":preconfigured-offline")
    return None
  }
  let started = @bench.monotonic_clock_start()
  let policy_revision = if probe.whole_run {
    "local-run-caller-elapsed-median/0.1"
  } else {
    "local-task-processing-median/0.1"
  }
  let mut position = probe.position
  let mut reason = "experiment-forced-position"
  let mut profile_revision = "unmeasured"
  if probe.whole_run && task > 1 && probe.trajectory is Some(trajectory) {
    position = whole_run_residual_position(dispatch, trajectory, task)
    operational_require(position is Some(_))
    reason = "current-snapshot-residual-assignment"
  } else if probe.mode == "empirical" {
    let template = @files.read_bounded_text_file(
      probe.root,
      "task-1.json",
      61440L,
    ).unwrap()
    operational_require(
      "sha256:" + @sha.hex(@utf8.encode(template)) == probe.template_pin,
    )
    let body = "{\"binding\":" +
      @strategy.placement_policy_request_json(request).unwrap() +
      "," +
      template.strip_prefix("{").unwrap().to_owned()
    let before = @resources.ledger_usage(ledger)
    let sidecar = @host.admit_native_operational_estimate(
      dispatch,
      request,
      body,
      "configured-local-profile-producer",
      probe.profile_revision,
      probe.clock,
    ).unwrap()
    let ranking = @host.rank_native_operational_estimate(
      dispatch,
      sidecar,
      task,
      policy_revision,
      probe.clock,
      quantity=if probe.whole_run {
        "run-caller-elapsed"
      } else {
        "task-processing"
      },
    ).unwrap()
    position = ranking.selected_position
    reason = ranking.reason
    profile_revision = ranking.profile_revision
    println("empirical-sidecar:" + body)
    println(
      "empirical-ranking:{\"task\":1,\"reason\":\"" +
      reason +
      "\",\"profile_revision\":\"" +
      profile_revision +
      "\",\"policy_revision\":\"" +
      policy_revision +
      "\",\"objective\":\"" +
      (if probe.whole_run {
        "run-caller-elapsed-median"
      } else {
        "task-processing-median"
      }) +
      "\",\"positions\":" +
      ranking.positions.to_json().stringify() +
      ",\"selected_position\":" +
      ranking.selected_position.to_json().stringify() +
      "}",
    )
    operational_require(@resources.ledger_usage(ledger) == before)
  }
  guard position is Some(chosen) else {
    operational_require(probe.offline_fallback)
    // The fallback was selected in trusted configuration before execution;
    // neither malformed requests nor transport failures arrive here.
    @standard_host.commit_dispatch_offline_policy_choice(dispatch).unwrap()
    println("empirical-fallback:1:" + reason)
    println(
      "empirical-consult-us:" + @bench.monotonic_clock_end(started).to_string(),
    )
    return None
  }
  let response : @strategy.PolicyResponse = {
    request,
    position: chosen,
    policy_id: "local-empirical-policy",
    policy_revision,
    explanation: reason +
    "; objective=" +
    (if probe.whole_run {
      "run-caller-elapsed"
    } else {
      "first-task-processing"
    }) +
    "; profile=" +
    profile_revision,
  }
  let wire = @strategy.placement_policy_response_json(response).unwrap()
  if !probe.whole_run || probe.validation_probes {
    // Invalid binding is rejected by the real closed decoder before any commit.
    let changed = @strategy.placement_policy_response_json({
      ..response,
      request: { ..request, request_id: "different-request", },
    }).unwrap()
    operational_require(
      @host.commit_native_local_policy_response(
        dispatch,
        request,
        changed,
        "local-empirical-policy",
        probe.clock,
      )
      is Err(_),
    )
    println("empirical-modified-request-refused:" + task.to_string())
  }
  if probe.whole_run && task == 1 {
    probe.trajectory = Some(whole_run_selected_trajectory(dispatch, chosen))
  }
  println(
    "empirical-current-request:" +
    @strategy.placement_policy_request_json(request).unwrap(),
  )
  @host.commit_native_local_policy_response(
    dispatch,
    request,
    wire,
    "local-empirical-policy",
    probe.clock,
  ).unwrap()
  println("empirical-response:" + wire)
  println(
    "empirical-consult-us:" + @bench.monotonic_clock_end(started).to_string(),
  )
  // Do not replay a refusal into the dispatch Owner: stale commit makes that
  // driver terminal. Read-only Owner validation establishes revoked admission.
  operational_require(
    @standard_host.validate_dispatch_policy_request(
      dispatch,
      request,
      probe.clock.observe().unwrap(),
    )
    is Err(_),
  )
  println("empirical-old-request-refused:" + task.to_string())
  Some(wire)
}

///|
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
    Some(@resources.IdentityOverflow) => "identity-overflow"
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
    Some(@resources.ResourceParked) => "resource-parked"
    Some(@resources.ChildFundingUnavailable) => "child-funding-unavailable"
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
        @host.Physical(@host.RuntimeState) => "start-physical-state"
        @host.Physical(@host.RetainedFile(_)) => "start-retained-file"
        @host.Physical(@host.RetainedImport(_)) => "start-retained-import"
        @host.Physical(@host.ResidentImport(_)) => "start-resident-import"
        @host.Physical(@host.Runtime(_)) => "start-physical-runtime"
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
  operational : (String, String, Array[String], @clock.NativeTrustedClock)?,
  empirical : EmpiricalProbe?,
) -> Result[Unit, @host.NativeStandardStrategyRunIssue] {
  let mut next_task = 1
  let mut retired_response : String? = None
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
        let normal = @env.get_env_var("ACTQL_NATIVE_HOST_PROFILE_SETTINGS")
          is Some(_) &&
          empirical is None
        let now = match operational {
          Some((_, _, _, clock)) => clock.observe().unwrap()
          None =>
            match empirical {
              Some(probe) => probe.clock.observe().unwrap()
              None => 0L
            }
        }
        let request = if normal && empirical is None {
          None
        } else {
          Some(
            match
              @standard_host.prepare_dispatch_policy_request(
                dispatch,
                "benchmark-task-" + next_task.to_string(),
                @strategy.graph_program_definition_cid(
                  @strategy.captured_dag_graph(captured),
                ),
                "native-benchmark-offline",
                if empirical is Some(probe) && probe.mode == "expiry" {
                  now + 1L
                } else if operational is None && empirical is None {
                  1L
                } else {
                  now + 60000L
                },
                now,
              ) {
              Err(issue) => return Err(@host.Dispatch(issue))
              Ok(value) => value
            },
          )
        }
        // The normal Host mints and commits its own request. The immutable
        // projection becomes visible only after that consultation; do not read
        // the common pending projection before a request has been minted.
        let candidates = if normal {
          match @host.prepare_native_standard_strategy_performance_choice(run) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
          @host.native_performance_candidate_snapshot(run).unwrap()
        } else {
          @standard_host.dispatch_policy_candidates(dispatch).unwrap()
        }
        println(
          "compute-candidates:" +
          next_task.to_string() +
          ":" +
          candidates.canonical_json,
        )
        if empirical is Some(probe) && probe.mode == "expiry" {
          let mut observed = probe.clock.observe().unwrap()
          for _ in 0..<16 {
            if observed > request.unwrap().deadline_ms {
              break
            }
            // Observe the original request after a real bounded wait, rather
            // than assuming fast durable reads advance the wall clock.
            diagnostic_expiry_wait()
            observed = probe.clock.observe().unwrap()
          }
          operational_require(observed > request.unwrap().deadline_ms)
          let before_refusal = @resources.ledger_usage(ledger)
          let response : @strategy.PolicyResponse = {
            request: request.unwrap(),
            position: 0,
            policy_id: "local-empirical-policy",
            policy_revision: "expiry-diagnostic",
            explanation: "expired actual pending request",
          }
          let body = @strategy.placement_policy_response_json(response).unwrap()
          operational_require(
            @host.commit_native_local_policy_response(
              dispatch,
              request.unwrap(),
              body,
              "local-empirical-policy",
              probe.clock,
            )
            is Err(_),
          )
          operational_require(@resources.ledger_usage(ledger) == before_refusal)
          println(
            "empirical-expired-request:{\"deadline_ms\":\"" +
            request.unwrap().deadline_ms.to_string() +
            "\",\"observed_ms\":\"" +
            observed.to_string() +
            "\"}",
          )
          return Ok(())
        }
        match (empirical, retired_response) {
          (Some(probe), Some(body)) if !probe.whole_run ||
            probe.validation_probes => {
            operational_require(
              @host.commit_native_local_policy_response(
                dispatch,
                request.unwrap(),
                body,
                "local-empirical-policy",
                probe.clock,
              )
              is Err(_),
            )
            println("empirical-old-state-refused:" + next_task.to_string())
          }
          _ => ()
        }
        let admitted_body = match operational {
          Some((root, profile_revision, pins, clock)) => {
            let before_estimate = @resources.ledger_usage(ledger)
            let body = inspect_operational_estimate(
              dispatch,
              request.unwrap(),
              next_task,
              root,
              profile_revision,
              pins,
              clock,
            )
            operational_require(
              @resources.ledger_usage(ledger) == before_estimate,
            )
            Some(body)
          }
          None => None
        }
        match empirical {
          Some(probe) => {
            let body = commit_empirical_probe(
              probe,
              dispatch,
              request.unwrap(),
              next_task,
              ledger,
            )
            if next_task == 1 {
              retired_response = body
            }
          }
          None =>
            if !normal {
              match
                @standard_host.commit_dispatch_offline_policy_choice(dispatch) {
                Err(issue) => return Err(@host.Dispatch(issue))
                Ok(_) => ()
              }
            }
        }
        match (operational, admitted_body) {
          (Some((_, profile_revision, _, clock)), Some(body)) => {
            operational_require(
              @host.admit_native_operational_estimate(
                dispatch,
                request.unwrap(),
                body,
                "configured-local-profile-producer",
                profile_revision,
                clock,
              )
              is Err(_),
            )
            println("operational-after-commit-refused:" + next_task.to_string())
          }
          _ => ()
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
        let selected_policy = match
          @strategy.strategy_selection_source(revision) {
          @strategy.ExternalPolicy(policy) => {
            let w = @encode.writer(4096, 32, 2) catch {
              _ => abort("policy observation limit")
            }
            @encode.begin_object(w) catch {
              _ => abort("policy observation")
            }
            for
              (key, value) in [
                ("policy_id", policy.policy_id),
                ("revision", policy.revision),
                ("request_id", policy.request_id),
                ("explanation", policy.explanation),
              ] {
              @encode.key(w, key) catch {
                _ => abort("policy observation")
              }
              @encode.string_value(w, value) catch {
                _ => abort("policy observation")
              }
            }
            @encode.end_object(w) catch {
              _ => abort("policy observation")
            }
            @encode.finish(w) catch {
              _ => abort("policy observation")
            }
          }
          _ => "null"
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
          ",\"policy\":" +
          selected_policy +
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
  observe_before? : Bool = true,
) -> Unit {
  if observe_before {
    emit_owner_observation("before-close", task, run, ledger)
  }
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
      @host.SelectedTaskExecution(task) => ("task", task, "null")
      @host.ResidentEnvironment(task) => ("environment", task, "null")
      @host.ResidentInputImport(task, producer) =>
        ("import", task, producer.to_string())
      @host.ResidentTask(task) => ("compute", task, "null")
      @host.TaskRelease(task) => ("task-release", task, "null")
      @host.ResidentDatabaseClose(index) =>
        ("environment-close", 0, index.to_string())
      @host.ResidentEnvironmentRelease(index) =>
        ("environment-release", 0, index.to_string())
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
    @argparse.OptionArg("operational-estimate-root", default_values=["-"]),
    @argparse.OptionArg("operational-profile-revision", default_values=["-"]),
    @argparse.OptionArg("operational-template-pins", default_values=["-"]),
    @argparse.OptionArg("sqlite-library", default_values=["-"]),
    @argparse.OptionArg("empirical-mode", default_values=["-"]),
    @argparse.OptionArg("diagnostic-cleanup-failure", default_values=["false"]),
    @argparse.OptionArg("empirical-validation-probes", default_values=["false"]),
    @argparse.OptionArg("empirical-objective", default_values=[
      "task-processing",
    ]),
    @argparse.OptionArg("empirical-position", default_values=["-"]),
    @argparse.OptionArg("empirical-profile-root", default_values=["-"]),
    @argparse.OptionArg("empirical-profile-revision", default_values=["-"]),
    @argparse.OptionArg("empirical-template-pin", default_values=["-"]),
    @argparse.OptionArg("empirical-fallback", default_values=["reject"]),
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
    @argparse.OptionArg("source-read-only", default_values=["true"]),
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
  operational_require(
    ["task-processing", "run-caller-elapsed"].contains(
      required(matches, "empirical-objective"),
    ),
  )
  operational_require(
    ["true", "false"].contains(required(matches, "diagnostic-cleanup-failure")),
  )
  operational_require(
    ["true", "false"].contains(required(matches, "empirical-validation-probes")),
  )
  let empirical_mode = required(matches, "empirical-mode")
  operational_require(
    ["-", "forced", "empirical", "offline", "expiry"].contains(empirical_mode),
  )
  operational_require(
    ["reject", "offline"].contains(required(matches, "empirical-fallback")),
  )
  // A candidate position is zero-based, unlike positive fixture counts.
  // Admit this input before opening Source or allocating Native resources.
  let empirical_position = if empirical_mode == "forced" {
    let position : Int = @string.from_str(
      required(matches, "empirical-position"),
    ) catch {
      _ => abort("invalid candidate position")
    }
    if position < 0 {
      abort("negative candidate position")
    }
    Some(position)
  } else {
    None
  }
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
  // Acquisition reads an immutable source. The explicit read-write control
  // reproduces the previous preparation mode in the bounded paired experiment.
  let source_read_only = match required(matches, "source-read-only") {
    "true" => true
    "false" => false
    _ => abort("invalid source read-only mode")
  }
  println(
    if source_read_only {
      "source-open-mode:read-only"
    } else {
      "source-open-mode:read-write"
    },
  )
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
        read_only: source_read_only,
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
  let normal = normal_host_example(
    root, dispatch, source, source_rows, columns, value_nodes, text_bytes, wire_bytes,
    work, batch_bytes,
  )
  let performance = normal.map(example => example.configuration)
  let performance_input = normal.map(example => example.input)
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
    performance?,
    performance_input?,
  ).unwrap()
  if normal is Some(_) {
    match @host.native_performance_conditions(run).unwrap() {
      Some(conditions) =>
        println(
          "normal-host-conditions:" +
          @strategy.operational_estimate_conditions_json(conditions).unwrap(),
        )
      None => println("normal-host-conditions:null")
    }
  }
  phase_boundary("strategy-execute", execution_start)
  let estimate_root = required(matches, "operational-estimate-root")
  operational_require(normal is None || estimate_root == "-")
  let operational = if estimate_root == "-" {
    None
  } else {
    let sqlite = @sqlite.load_library(required(matches, "sqlite-library")).unwrap()
    let clock = @clock.open(
      sqlite,
      estimate_root + "/estimate-clock.sqlite",
      "operational-estimate/0.1",
      "host",
    ).unwrap()
    Some(
      (
        estimate_root,
        required(matches, "operational-profile-revision"),
        required(matches, "operational-template-pins")
        .split(",")
        .map(v => v.to_owned())
        .to_array(),
        clock,
      ),
    )
  }
  let empirical = if empirical_mode == "-" {
    None
  } else {
    operational_require(
      operational is None &&
      ["forced", "empirical", "offline", "expiry"].contains(empirical_mode),
    )
    let sqlite = @sqlite.load_library(required(matches, "sqlite-library")).unwrap()
    let clock = @clock.open(
      sqlite,
      root + "/empirical-clock.sqlite",
      "empirical-policy/0.1",
      "host",
    ).unwrap()
    Some({
      mode: empirical_mode,
      position: empirical_position,
      root: required(matches, "empirical-profile-root"),
      profile_revision: required(matches, "empirical-profile-revision"),
      template_pin: required(matches, "empirical-template-pin"),
      offline_fallback: required(matches, "empirical-fallback") == "offline",
      clock,
      whole_run: required(matches, "empirical-objective") ==
      "run-caller-elapsed",
      validation_probes: required(matches, "empirical-validation-probes") ==
      "true",
      trajectory: None,
    })
  }
  let execution = execute_timed_native_strategy_run(
    run, dispatch, captured, ledger, stop_after_task, operational, empirical,
  )
  emit_normal_host_decisions(run)
  match normal {
    Some(example) => operational_require(example.clock.close())
    None => ()
  }
  match empirical {
    Some(probe) => operational_require(probe.clock.close())
    None => ()
  }
  match operational {
    Some((_, _, _, clock)) => operational_require(clock.close())
    None => ()
  }
  // Flush only after the physical work interval: diagnostic output is not
  // charged to environment, import or Compute durations. Clock/buffer overhead
  // remains part of the enclosing process measurement.
  emit_native_phase_observations(phase_events)
  phase_events.clear()
  if execution is Err(_) {
    close_observed_run(run, ledger, 0)
    @host.close_native_acquisition_runtime(acquisition)
    @strategy.stop_captured_dag(captured)
    emit_native_phase_observations(phase_events)
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
    Err(@host.Performance(issue)) => {
      let stage = match issue {
        @host.InvalidConfiguration => "configuration"
        @host.DisclosureDenied => "disclosure"
        @host.EnvelopeTooLarge => "envelope"
        @host.AlreadyCommitted => "committed"
        @host.InvalidResponse => "response"
        @host.HttpStatus(_) => "http-status"
        @host.Dispatch(_) => "dispatch"
        @host.Clock(_) => "clock"
        @host.Transport(_) => "transport"
        @host.Wire(_) => "wire"
      }
      abort("native performance consultation rejected: " + stage)
    }
  }
  if empirical_mode == "expiry" {
    close_observed_run(run, ledger, 0)
    @host.close_native_acquisition_runtime(acquisition)
    @strategy.stop_captured_dag(captured)
    emit_native_phase_observations(phase_events)
    println("{\"status\":\"rejected-expired-request\",\"completed_tasks\":0}")
    return
  }
  if stop_after_task is Some(task) {
    if empirical is Some(_) || normal is Some(_) {
      let held = @resources.ledger_usage(ledger)
      @standard_host.stop_strategy_dispatch(dispatch)
      // The existing Owner drains a stopped dispatch with no next task.
      // That closes admission, while cleanup still owns the held resources.
      operational_require(
        @host.execute_next_native_standard_strategy_task(run) is Ok(None),
      )
      operational_require(
        @host.execute_next_native_standard_strategy_task(run)
        is Err(@host.Closed),
      )
      operational_require(@resources.ledger_usage(ledger) == held)
      operational_require(held.held_bytes > 0L)
      println(
        (if normal is Some(_) {
          "normal-host-stop-retains-responsibility:"
        } else {
          "empirical-stop-retains-responsibility:"
        }) +
        task.to_string(),
      )
    }
    close_observed_run(run, ledger, task)
    @host.close_native_acquisition_runtime(acquisition)
    @strategy.stop_captured_dag(captured)
    phase_boundary("stopped-cleanup-end", execution_start)
    emit_native_phase_observations(phase_events)
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
  let result_reference = @example.application_task_reference(app, task) catch {
    _ => abort("checked final task reference unavailable")
  }
  operational_require(
    @example.application_task_output_matches(result_reference, output),
  )
  let schema_fields : Array[String] = []
  for column in 0..<@execution.completed_column_count(output) {
    schema_fields.push(
      @execution.completed_column_name(output, column).unwrap(),
    )
  }
  println("result-schema-fields:" + schema_fields.to_json().stringify())
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
  if required(matches, "diagnostic-cleanup-failure") == "true" {
    operational_require(retained_task_root == root + "/retained-task")
    emit_owner_observation("before-close", task, run, ledger)
    let before = @resources.ledger_usage(ledger)
    operational_require(
      diagnostic_cleanup_access(@utf8.encode(retained_task_root), false),
    )
    let pending = @host.close_native_standard_strategy_run(run)
    // Restore the caller-owned directory before inspecting the failure, even
    // when the diagnostic discovers an unexpected cleanup result.
    operational_require(
      diagnostic_cleanup_access(@utf8.encode(retained_task_root), true),
    )
    operational_require(pending is Err(_) || pending is Ok(false))
    let held = @resources.ledger_usage(ledger)
    operational_require(
      held.held_bytes > 0L && held.attempts == before.attempts,
    )
    operational_require(held.holdings == before.holdings)
    operational_require(
      @host.execute_next_native_standard_strategy_task(run) is Err(Closed),
    )
    println("whole-run-cleanup-pending:" + held.held_bytes.to_string())
    emit_owner_observation("failed-cleanup", task, run, ledger)
  }
  close_observed_run(
    run,
    ledger,
    task,
    observe_before=required(matches, "diagnostic-cleanup-failure") != "true",
  )
  if required(matches, "diagnostic-cleanup-failure") == "true" {
    println("whole-run-cleanup-retry-confirmed")
  }
  @host.close_native_acquisition_runtime(acquisition)
  @strategy.stop_captured_dag(captured)
  let usage = @resources.ledger_usage(ledger)
  // This is accounting DATA after the original physical close path above,
  // never another physical stop acknowledgement. Spent work remains spent.
  if @resources.ledger_usage_has_pending_resources(usage) {
    abort("native strategy ledger has unresolved capacity")
  }
  let cleanup_us = @bench.monotonic_clock_end(cleanup_start).to_int64()
  if cleanup_us < 0L {
    abort("invalid cleanup interval")
  }
  phase_boundary("cleanup-end", execution_start)
  emit_native_phase_observations(phase_events)
  println(
    "{\"task_count\":" +
    task.to_string() +
    ",\"rows_cid\":\"" +
    cid +
    "\",\"execution_us\":" +
    execution_us.to_string() +
    ",\"cleanup_us\":" +
    cleanup_us.to_string() +
    ",\"usage\":" +
    @resources.ledger_usage_diagnostic_json(usage) +
    ",\"acquisition_evidence\":" +
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
