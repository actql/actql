///|
/// Trusted local application settings, not a new public transport or CLI.
/// This caller example delegates every decision to the public Native Host API.
struct NormalHostExample {
  configuration : @host.NativePerformanceConfiguration
  input : @host.NativePerformanceInput
  clock : @clock.NativeTrustedClock
}

///|
fn normal_setting(object : @decode.ObjectView, key : String) -> String {
  @decode.text(@decode.required(object, key).unwrap()).unwrap()
}

///|
fn normal_host_example(
  root : String,
  dispatch : @standard_host.StrategyHostDispatch,
  source : @query.CapturedInputSource,
  rows : Int,
  columns : Int,
  value_nodes : Int,
  text_bytes : Int,
  wire_bytes : Int,
  work : Int,
  batch_bytes : Int,
) -> NormalHostExample? {
  guard @env.get_env_var("ACTQL_NATIVE_HOST_PROFILE_SETTINGS") is Some(name) else {
    return None
  }
  let settings = @files.read_bounded_text_file(root, name, 8192L).unwrap()
  let node = @source.parse_json_bytes(@utf8.encode(settings), {
    max_input_bytes: 8192,
    max_nodes: 128,
    max_depth: 2,
  }).unwrap()
  let decoded = @decode.admit(node, {
    max_nodes: 128,
    max_depth: 2,
    max_string_bytes: 1024,
    max_total_string_bytes: 8192,
  }).unwrap()
  let object = @decode.closed_object(decoded, [
    "mode", "runtime_revision", "artifact_digest", "environment_digest", "control_digest",
    "instrumentation_revision", "measurement_scope_revision", "capture_mode", "process_state",
    "authorized_scope", "realization", "concurrency", "allow_uncontrolled_load",
    "profile_file", "profile_digest", "profile_revision", "profile_creation_ms",
    "sqlite_library",
  ]).unwrap()
  let mode = match normal_setting(object, "mode") {
    "diagnostic-reference" => @host.DiagnosticReference
    "select-reference" => @host.SelectReference
    _ => abort("invalid normal Host profile mode")
  }
  let library = @sqlite.load_library(normal_setting(object, "sqlite_library")).unwrap()
  let clock = @clock.open(
    library,
    root + "/normal-clock.sqlite",
    "normal-host-local-profile/0.1",
    "host",
  ).unwrap()
  let file = normal_setting(object, "profile_file")
  let cost = @decode.required(object, "profile_creation_ms").unwrap()
  let creation_ms = if @decode.is_null(cost) {
    None
  } else {
    Some(@decode.finite_number(cost).unwrap())
  }
  let profile = if file == "-" {
    None
  } else {
    Some(
      @host.prepare_native_local_performance_profile(
        root,
        file,
        normal_setting(object, "profile_digest"),
        normal_setting(object, "profile_revision"),
        creation_ms?,
      ).unwrap(),
    )
  }
  let configuration = @host.prepare_native_performance_configuration(
    mode,
    {
      runtime_revision: normal_setting(object, "runtime_revision"),
      artifact_digest: normal_setting(object, "artifact_digest"),
      environment_digest: normal_setting(object, "environment_digest"),
      control_digest: normal_setting(object, "control_digest"),
      instrumentation_revision: normal_setting(
        object, "instrumentation_revision",
      ),
      measurement_scope_revision: normal_setting(
        object, "measurement_scope_revision",
      ),
      capture_mode: normal_setting(object, "capture_mode"),
      process_state: normal_setting(object, "process_state"),
      authorized_scope: normal_setting(object, "authorized_scope"),
      realization: normal_setting(object, "realization"),
      concurrency: @decode.int32(
        @decode.required(object, "concurrency").unwrap(),
      ).unwrap(),
    },
    clock,
    "normal-host-" + @env.now().to_string(),
    "configured-local-native-application",
    "native-profile-reference/0.1",
    profile?,
    allow_uncontrolled_load=@decode.boolean(
      @decode.required(object, "allow_uncontrolled_load").unwrap(),
    ).unwrap(),
  ).unwrap()
  let started = @bench.monotonic_clock_start()
  let wire : @execution.RowWireLimits = {
    max_columns: columns,
    max_order_work: work,
    max_bytes: wire_bytes,
    max_nodes: value_nodes,
    max_depth: 64,
  }
  let identity = @query.identify_captured_source_relation(
    source,
    rows,
    {
      max_nodes: value_nodes,
      max_text_bytes: text_bytes,
      max_depth: 64,
      max_work: work,
    },
    wire,
    wire,
    { max_fields: columns, max_bytes: 65536, max_nodes: 4096, max_depth: 16, },
    batch_bytes,
  ).unwrap()
  let input = @host.prepare_native_performance_input(dispatch, source, identity).unwrap()
  println(
    "normal-host-input-binding-us:" +
    @bench.monotonic_clock_end(started).to_string(),
  )
  Some({ configuration, input, clock, })
}

///|
fn emit_normal_host_decisions(run : @host.NativeStandardStrategyRun) -> Unit {
  for decision in @host.native_performance_decisions(run) {
    // Optional serialization failure is deliberately exercised; execution and
    // release never depend on this diagnostic result.
    operational_require(
      @host.native_performance_decision_json(decision, max_bytes=1) is Err(_),
    )
    match @host.native_performance_decision_json(decision) {
      Ok(body) => println("normal-host-decision:" + body)
      Err(_) => println("normal-host-diagnostic:unavailable")
    }
  }
}
