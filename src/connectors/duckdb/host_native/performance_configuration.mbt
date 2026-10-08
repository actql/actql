///|
/// Optional descriptive references never confer execution authority.
pub(all) enum NativePerformanceMode {
  DiagnosticReference
  SelectReference
} derive(Eq, Debug)

///|
/// Trusted application/runtime settings, independent of the profile payload.
/// Artifact and environment attestations remain the configuring application's
/// responsibility; the Host binds these frozen values to its actual inputs.
pub(all) struct NativePerformanceRuntime {
  runtime_revision : String
  artifact_digest : String
  environment_digest : String
  control_digest : String
  instrumentation_revision : String
  measurement_scope_revision : String
  capture_mode : String
  process_state : String
  authorized_scope : String
  realization : String
  concurrency : Int
}

///|
pub struct NativePerformanceInput {
  dispatch : @duckdb_standard_host.StrategyHostDispatch
  source : @query.CapturedInputSource
  identity : @query.CapturedSourceRelationIdentity
}

///|
/// Identify already captured rows through the existing bounded identity API,
/// then bind that token to the actual Source capture of this dispatch.
pub fn prepare_native_performance_input(
  dispatch : @duckdb_standard_host.StrategyHostDispatch,
  source : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
) -> Result[NativePerformanceInput, NativeStandardPolicyIssue] {
  if !@strategy.captured_task_source_matches(
      @duckdb_standard_host.dispatch_run(dispatch),
      0,
      source,
    ) ||
    !@query.captured_source_relation_identity_matches_source(identity, source) {
    return Err(InvalidConfiguration)
  }
  Ok({ dispatch, source, identity, })
}

///|
/// One immutable trusted local template. Loading is lazy, bounded and once
/// per handle; this cache contains neither a pending request nor a commit.
pub struct NativeLocalPerformanceProfile {
  root_path : String
  name : String
  template_digest : String
  original_revision : String
  creation_ms : Double?
  mut template : String?
  mut header : @strategy.OperationalProfileTemplateHeader?
  mut attempted : Bool
  mut failure : NativeStandardPolicyIssue?
  mut read_microseconds : Double
}

///|
pub fn prepare_native_local_performance_profile(
  trusted_root_path : String,
  name : String,
  template_digest : String,
  original_revision : String,
  creation_ms? : Double,
) -> Result[NativeLocalPerformanceProfile, NativeStandardPolicyIssue] {
  if trusted_root_path.is_empty() ||
    name.is_empty() ||
    template_digest.length() != 64 ||
    original_revision.is_empty() ||
    @utf8.encode(original_revision).length() > 128 ||
    (creation_ms is Some(cost) && (cost < 0.0 || cost - cost != 0.0)) {
    return Err(InvalidConfiguration)
  }
  Ok({
    root_path: trusted_root_path,
    name,
    template_digest,
    original_revision,
    creation_ms,
    template: None,
    header: None,
    attempted: false,
    failure: None,
    read_microseconds: 0.0,
  })
}

///|
fn load_native_performance_profile(
  profile : NativeLocalPerformanceProfile,
) -> Result[Unit, NativeStandardPolicyIssue] {
  if profile.attempted {
    return match profile.failure {
      Some(issue) => Err(issue)
      None => Ok(())
    }
  }
  profile.attempted = true
  let started = @bench.monotonic_clock_start()
  let loaded = @files.read_bounded_text_file(
    profile.root_path,
    profile.name,
    61440L,
  )
  profile.read_microseconds = @bench.monotonic_clock_end(started)
  let text = match loaded {
    Ok(value) => value
    Err(@files.Missing) => return Ok(())
    Err(_) => {
      profile.failure = Some(InvalidConfiguration)
      return Err(InvalidConfiguration)
    }
  }
  if @sha.hex(@utf8.encode(text)) != profile.template_digest {
    profile.failure = Some(InvalidConfiguration)
    return Err(InvalidConfiguration)
  }
  let started = @bench.monotonic_clock_start()
  let header = @strategy.operational_profile_template_header(text)
  profile.read_microseconds += @bench.monotonic_clock_end(started)
  match header {
    Err(issue) => {
      profile.failure = Some(Wire(issue))
      Err(Wire(issue))
    }
    Ok(header) => {
      if header.profile_revision != profile.original_revision {
        profile.failure = Some(InvalidConfiguration)
        return Err(InvalidConfiguration)
      }
      profile.template = Some(text)
      profile.header = Some(header)
      Ok(())
    }
  }
}

///|
/// Default absence keeps the ordinary offline path completely unchanged.
/// The caller explicitly permits offline fallback for insufficient references
/// by configuring this local mode, not as a response to transport failure.
pub struct NativePerformanceConfiguration {
  mode : NativePerformanceMode
  runtime : NativePerformanceRuntime
  profile : NativeLocalPerformanceProfile?
  clock : @clock.NativeTrustedClock
  run_identity : String
  authority : String
  policy_revision : String
  allow_uncontrolled_load : Bool
  timeout_ms : Int64
}

///|
pub fn prepare_native_performance_configuration(
  mode : NativePerformanceMode,
  runtime : NativePerformanceRuntime,
  clock : @clock.NativeTrustedClock,
  run_identity : String,
  authority : String,
  policy_revision : String,
  profile? : NativeLocalPerformanceProfile,
  allow_uncontrolled_load? : Bool = false,
  timeout_ms? : Int64 = 60000L,
) -> Result[NativePerformanceConfiguration, NativeStandardPolicyIssue] {
  for
    value in [
      run_identity,
      authority,
      policy_revision,
      runtime.runtime_revision,
      runtime.artifact_digest,
      runtime.environment_digest,
      runtime.control_digest,
      runtime.instrumentation_revision,
      runtime.measurement_scope_revision,
      runtime.capture_mode,
      runtime.process_state,
      runtime.authorized_scope,
      runtime.realization,
    ] {
    if value.is_empty() || @utf8.encode(value).length() > 128 {
      return Err(InvalidConfiguration)
    }
  }
  if timeout_ms < 1L ||
    timeout_ms > 60000L ||
    runtime.concurrency < 1 ||
    !["off", "metadata-only", "evidence-enabled"].contains(runtime.capture_mode) ||
    !["fresh", "resident"].contains(runtime.realization) {
    return Err(InvalidConfiguration)
  }
  Ok({
    mode,
    runtime,
    profile,
    clock,
    run_identity,
    authority,
    policy_revision,
    allow_uncontrolled_load,
    timeout_ms,
  })
}

///|
/// Bounded in-memory explanation. No arbitrary sink callback runs in admission
/// or release. Serialization/storage is optional work owned by the caller.
pub(all) struct NativePerformanceDecision {
  task : Int
  positions : Array[Int]
  evaluated_ms : Int64
  max_age_ms : Int64?
  mode : NativePerformanceMode
  objective : String
  request : @strategy.PolicyRequest
  profile_revision : String?
  reason : String
  selected_position : Int?
  offline_position : Int?
  conditions : @strategy.OperationalEstimateConditions?
  references : Array[@strategy.OperationalTimeReference]
  profile_creation_ms : Double?
  profile_read_microseconds : Double
  consultation_microseconds : Double
  reused_profile : Bool
  oldest_ms : Int64?
  newest_ms : Int64?
  /// External load is not controlled or established as applicable by opt-in.
  load_applicability : String
  stable_improvement : String
  net_benefit : String
}

///|
priv struct NativePerformanceSession {
  configuration : NativePerformanceConfiguration
  mut input : NativePerformanceInput?
  mut trajectory : @strategy.OperationalAssignmentTrajectory?
  // Retain only the latest bounded immutable projection for caller diagnostics.
  // This is not a pending request, a grant or a history of candidate bodies.
  mut candidates : @strategy.PolicyCandidateSet?
  decisions : Array[NativePerformanceDecision]
  mut omitted : Int
  mut unavailable_reason : String?
}

///|
/// The last consultation's immutable projection, after common admission.
/// Its positions cannot authorize another request or dispatch.
pub fn native_performance_candidate_snapshot(
  run : NativeStandardStrategyRun,
) -> @strategy.PolicyCandidateSet? {
  run.performance.bind(session => session.candidates)
}

///|
pub fn native_performance_decisions(
  run : NativeStandardStrategyRun,
) -> Array[NativePerformanceDecision] {
  match run.performance {
    None => []
    Some(session) =>
      session.decisions.map(item => {
        ..item,
        references: item.references.copy(),
        positions: item.positions.copy(),
      })
  }
}

///|
pub fn native_performance_omitted_decisions(
  run : NativeStandardStrategyRun,
) -> Int {
  match run.performance {
    Some(session) => session.omitted
    None => 0
  }
}

///|
/// Obtain the current Host-owned conditions without reading any profile. The
/// optional captured identity is checked every time; no Source is re-acquired.
pub fn native_performance_conditions(
  run : NativeStandardStrategyRun,
) -> Result[@strategy.OperationalEstimateConditions?, NativeStandardPolicyIssue] {
  guard run.performance is Some(session) && session.input is Some(input) else {
    return Ok(None)
  }
  let dag = @duckdb_standard_host.dispatch_run(run.dispatch)
  if !physical_equal(input.dispatch, run.dispatch) ||
    !@strategy.captured_task_source_matches(dag, 0, input.source) ||
    !@query.captured_source_relation_identity_matches_source(
      input.identity,
      input.source,
    ) {
    return Err(InvalidConfiguration)
  }
  if @strategy.graph_captured_prefix(@strategy.captured_dag_graph(dag)) != 1 {
    // This input token covers one capture only, not all data in a multi-Source
    // Program. Keep execution feasible, but never manufacture a full profile.
    session.unavailable_reason = Some("multiple-captured-inputs-unprofiled")
    return Ok(None)
  }
  guard @strategy.captured_execution_root_statistics(dag) is Some(stats) else {
    return Err(InvalidConfiguration)
  }
  if stats.rows != @query.captured_source_relation_row_count(input.identity) {
    return Err(InvalidConfiguration)
  }
  let runtime = session.configuration.runtime
  // Current source/Program and actual Native limits, not claims from a profile.
  let limits = run.import_limits
  let retained_body = match run.retained_profile {
    None => "no-retained-file"
    Some(profile) =>
      profile.max_file_bytes.to_string() +
      ":" +
      profile.max_batch_bytes.to_string() +
      ":" +
      profile.max_chunk_rows.to_string() +
      ":" +
      profile.wire.max_columns.to_string() +
      ":" +
      profile.wire.max_order_work.to_string() +
      ":" +
      profile.wire.max_nodes.to_string() +
      ":" +
      profile.wire.max_depth.to_string() +
      ":" +
      profile.wire.max_bytes.to_string()
  }
  let limits_body = limits.max_rows.to_string() +
    ":" +
    limits.max_cells.to_string() +
    ":" +
    limits.max_parameters.to_string() +
    ":" +
    limits.max_sql_bytes.to_string() +
    ":" +
    limits.max_batch_rows.to_string() +
    ":" +
    run.transfer_bytes.to_string() +
    ":" +
    run.database_memory_bytes.to_string() +
    ":" +
    retained_body
  Ok(
    Some({
      host: "native",
      realization: runtime.realization,
      capture_mode: runtime.capture_mode,
      runtime_revision: runtime.runtime_revision,
      binary_digest: runtime.artifact_digest,
      input_digest: @query.captured_source_relation_logical_cid(input.identity),
      program_digest: @strategy.graph_program_definition_cid(
        @strategy.captured_dag_graph(dag),
      ),
      input_rows: stats.rows,
      schema_layout: @query.captured_source_relation_schema_cid(input.identity),
      limits_digest: @sha.hex(@utf8.encode(limits_body)),
      instrumentation_revision: runtime.instrumentation_revision,
      measurement_scope_revision: runtime.measurement_scope_revision,
      environment_digest: runtime.environment_digest,
      control_digest: runtime.control_digest,
      concurrency: runtime.concurrency,
      process_state: runtime.process_state,
      os_cache: "uncontrolled",
      authorized_scope: runtime.authorized_scope,
    }),
  )
}

///|
/// Unknown when this normal Host has no measured-input or candidate path.
/// Absence of a request does not manufacture one for diagnostics.
pub fn native_performance_unavailable_reason(
  run : NativeStandardStrategyRun,
) -> String? {
  run.performance.bind(session => session.unavailable_reason)
}
