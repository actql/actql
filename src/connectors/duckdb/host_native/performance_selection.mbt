///|
fn performance_clock(
  configuration : NativePerformanceConfiguration,
) -> Result[Int64, NativeStandardPolicyIssue] {
  configuration.clock.observe().map_err(issue => Clock(issue))
}

///|
fn performance_validate_current(
  run : NativeStandardStrategyRun,
  configuration : NativePerformanceConfiguration,
  request : @strategy.PolicyRequest,
) -> Result[Unit, NativeStandardPolicyIssue] {
  let now = match performance_clock(configuration) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @duckdb_standard_host.validate_dispatch_policy_request(
    run.dispatch,
    request,
    now,
  ).map_err(issue => Dispatch(issue))
}

///|
/// Synchronous local reference consultation before ordinary dispatch. Unknown
/// references use the configured offline policy only after rechecking the same
/// current Owner request. Invalid evidence/request never invokes fallback.
fn prepare_native_performance_selection(
  run : NativeStandardStrategyRun,
) -> Result[Unit, NativeStandardPolicyIssue] {
  guard run.performance is Some(session) else { return Ok(()) }
  if !@duckdb_standard_host.dispatch_has_estimates(run.dispatch) {
    session.unavailable_reason = Some("candidate-estimates-unavailable")
    return Ok(())
  }
  let captured = @duckdb_standard_host.dispatch_run(run.dispatch)
  guard @strategy.next_captured_task(captured) is Some(task) else {
    return Ok(())
  }
  let started = @bench.monotonic_clock_start()
  let configuration = session.configuration
  // A stopped/already committed Owner has no consultation. Check that
  // boundary before requiring its optional profile clock to remain open.
  match @duckdb_standard_host.prepare_dispatch_policy_choice(run.dispatch) {
    Err(issue) => return Err(Dispatch(issue))
    Ok(false) => return Ok(())
    Ok(true) => ()
  }
  let now = match performance_clock(configuration) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if now < 0L || now > 9223372036854715807L {
    return Err(InvalidConfiguration)
  }
  let request = match
    @duckdb_standard_host.prepare_dispatch_policy_request(
      run.dispatch,
      configuration.run_identity + ":" + task.to_string(),
      configuration.run_identity,
      configuration.authority,
      now + configuration.timeout_ms,
      now,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  guard @duckdb_standard_host.dispatch_policy_candidates(run.dispatch)
    is Some(candidates) else {
    return Err(InvalidConfiguration)
  }
  let offline = match
    @duckdb_standard_host.dispatch_offline_policy_position(run.dispatch) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  let conditions = match native_performance_conditions(run) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reused = configuration.profile is Some(profile) && profile.attempted
  let mut reason = "profile-not-configured"
  let mut proposed : Int? = None
  let mut references : Array[@strategy.OperationalTimeReference] = []
  if configuration.profile is Some(profile) {
    match load_native_performance_profile(profile) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    reason = "profile-unavailable"
    if profile.header is Some(header) && profile.template is Some(template) {
      let observed = match performance_clock(configuration) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if conditions is None {
        reason = "input-identity-unavailable"
      } else if conditions.unwrap() != header.conditions {
        reason = "conditions-mismatch"
      } else if run.observe_phase is None ||
        configuration.runtime.capture_mode == "off" {
        reason = "physical-phase-observer-off"
      } else if observed < header.newest_ms ||
        observed - header.oldest_ms > header.max_age_ms {
        reason = "freshness-insufficient"
      } else if !configuration.allow_uncontrolled_load {
        reason = "uncontrolled-load-not-permitted"
      } else if session.trajectory is Some(trajectory) {
        // Never reuse a previous request or a previous position. The current
        // feasible residual assignments must contain the chosen realizations.
        proposed = match
          @strategy.operational_residual_position(candidates, trajectory, task) {
          Ok(value) => value
          Err(issue) => return Err(Wire(issue))
        }
        reason = if proposed is Some(_) {
          "current-residual-assignment"
        } else {
          "residual-attribution-insufficient"
        }
      } else if header.candidate_snapshot_cid != candidates.cid || task != 1 {
        reason = "candidate-attribution-insufficient"
      } else {
        let body = match
          @strategy.bind_operational_profile_template(template, request) {
          Ok(value) => value
          Err(issue) => return Err(Wire(issue))
        }
        let sidecar = match
          admit_native_operational_estimate(
            run.dispatch,
            request,
            body,
            "configured-local-profile",
            profile.original_revision,
            configuration.clock,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        references = sidecar.references.copy()
        let ranking = match
          rank_native_operational_estimate(
            run.dispatch,
            sidecar,
            task,
            configuration.policy_revision,
            configuration.clock,
            quantity="run-caller-elapsed",
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        proposed = ranking.selected_position
        reason = ranking.reason
      }
    }
  }
  // Diagnostic references never alter the ordinary offline selection.
  let mut selected = if configuration.mode == SelectReference {
    proposed
  } else {
    None
  }
  match performance_validate_current(run, configuration, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let evaluated_ms = match performance_clock(configuration) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @duckdb_standard_host.validate_dispatch_policy_request(
      run.dispatch,
      request,
      evaluated_ms,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Dispatch(issue))
  }
  if selected is Some(_) &&
    configuration.profile is Some(profile) &&
    profile.header is Some(header) &&
    (
      evaluated_ms < header.newest_ms ||
      evaluated_ms - header.oldest_ms > header.max_age_ms
    ) {
    selected = None
    reason = "freshness-insufficient"
    references = references.map(reference => {
      ..reference,
      median_ms: None,
      minimum_ms: None,
      maximum_ms: None,
      unknown_reason: Some("freshness-insufficient"),
    })
  }
  let positions = match @strategy.operational_candidate_positions(candidates) {
    Ok(value) => value
    Err(issue) => return Err(Wire(issue))
  }
  if positions.is_empty() {
    selected = None
    reason = "comparison-limit"
  }
  if selected is Some(position) {
    let trajectory = match
      @strategy.operational_candidate_trajectory(candidates, position) {
      Ok(value) => value
      Err(issue) => return Err(Wire(issue))
    }
    let body = match
      @strategy.placement_policy_response_json({
        request,
        position,
        policy_id: "native-local-reference",
        policy_revision: configuration.policy_revision,
        explanation: "Explicit descriptive Run reference; load applicability and benefit unknown",
      }) {
      Ok(value) => value
      Err(issue) => return Err(Wire(issue))
    }
    match
      commit_native_local_policy_response(
        run.dispatch,
        request,
        body,
        "native-local-reference",
        configuration.clock,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => session.trajectory = Some(trajectory)
    }
  } else {
    match
      @duckdb_standard_host.commit_dispatch_offline_policy_choice(run.dispatch) {
      Err(issue) => return Err(Dispatch(issue))
      Ok(_) => session.trajectory = None
    }
  }
  let decision : NativePerformanceDecision = {
    task,
    positions,
    evaluated_ms,
    max_age_ms: configuration.profile.bind(profile => {
      profile.header.map(header => header.max_age_ms)
    }),
    mode: configuration.mode,
    objective: "descriptive-run-caller-elapsed",
    request,
    reason,
    selected_position: selected,
    offline_position: offline,
    conditions,
    references,
    profile_revision: configuration.profile.bind(profile => {
      profile.header.map(header => header.profile_revision)
    }),
    profile_creation_ms: configuration.profile.bind(profile => {
      profile.creation_ms
    }),
    profile_read_microseconds: if reused {
      0.0
    } else {
      configuration.profile
      .map(profile => profile.read_microseconds)
      .unwrap_or(0.0)
    },
    consultation_microseconds: @bench.monotonic_clock_end(started),
    reused_profile: reused,
    oldest_ms: configuration.profile.bind(profile => {
      profile.header.map(header => header.oldest_ms)
    }),
    newest_ms: configuration.profile.bind(profile => {
      profile.header.map(header => header.newest_ms)
    }),
    load_applicability: "unknown-uncontrolled",
    stable_improvement: "unknown",
    net_benefit: "unknown",
  }
  if session.decisions.length() < 64 {
    session.decisions.push(decision)
  } else if session.omitted < 2147483647 {
    session.omitted += 1
  }
  Ok(())
}

///|
/// Optional explicit pre-dispatch consultation, also called by ordinary task
/// execution. Repeated calls after commit do not mint another request.
pub fn prepare_native_standard_strategy_performance_choice(
  run : NativeStandardStrategyRun,
) -> Result[Unit, NativeStandardStrategyRunIssue] {
  if !run.accepting {
    return Err(Closed)
  }
  match prepare_native_performance_selection(run) {
    Ok(_) => Ok(())
    Err(issue) => {
      run.accepting = false
      run.stop_dispatch()
      Err(Performance(issue))
    }
  }
}
