// Actual Native Source/Compute custody for an original Effect Run.
// Approval, physical Effect writes, durable restart and Cloud remain separate.

///|
let resident_native_effect_document : String =
  #|{"id":"source-compute","results":{"answer":{"from":{"result":"r","stage":"compute"}}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"results":{"r":{"fields":["id"],"from":"captured"}},"steps":[{"as":"filtered","filter":"id > 0"},{"as":"captured","select":["id"]}]},{"effects":{"save":{"update":{"from":{"result":"r"},"id":"id","mapping":"mapping:crm.account.v1","set":{"Name":{"field":"id"}},"target":"connector://crm/account"}}},"id":"compute","inputs":{"x":{"result":{"result":"r","stage":"acquire"}}},"results":{"r":{"fields":["id"],"from":"out"}},"steps":[{"filter":"id > 2"},{"as":"out","select":["id"]}]}],"version":"actql/0.1"}

///|
fn resident_native_effect_prepared() -> @host.PreparedClientEffectComputation {
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    resident_effect_source_bundle_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @host.prepare_client_effect_computation(
    resident_native_effect_document,
    Json,
    environment,
    None,
    [],
    {
      program: @host.client_standard_program_preparation_limits(),
      max_members: 1,
      max_header_work: 1000,
      mapping: {
        max_bytes: 20000,
        max_nodes: 2000,
        max_depth: 100,
        max_members: 100,
      },
      max_mapping_work: 1000,
      effects: {
        max_members: 1,
        max_work: 1000,
        max_admission_nodes: 100,
        max_admission_depth: 10,
        max_admission_text_bytes: 1000,
      },
    },
  ).unwrap()
}

///|
fn resident_native_effect_bound_run() -> @host.PreparedClientEffectRun {
  let prepared = resident_native_effect_prepared()
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_effect_run_definition(
    allowed, "resident-effect", "original-effect-run", "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  // The Native execution input now comes from the received original Effect
  // materials and dispatch admission, rather than the sender's local handle.
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    resident_effect_source_bundle_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let effect_limits : @host.ClientEffectComputationLimits = {
    program: @host.client_standard_program_preparation_limits(),
    max_members: 1,
    max_header_work: 1000,
    mapping: {
      max_bytes: 20000,
      max_nodes: 2000,
      max_depth: 100,
      max_members: 100,
    },
    max_mapping_work: 1000,
    effects: {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  }
  let caller = @host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-caller",
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  let selection : @host.ClientValuesSiteSelection = {
    site_key: "retained-native",
    site_generation: 1,
    runtime_bundle_cid: "sha256:" + "d".repeat(64),
    connector_registration: "local",
    connector_revision: "local/1",
    strategy_revision: "strategy/1",
    obligations_cid: "sha256:" + "2".repeat(64),
    budget_cid: "sha256:" + "3".repeat(64),
    evidence_issuer_capability_cid: "sha256:" + "4".repeat(64),
    grant_cid: "sha256:" + "5".repeat(64),
  }
  let request = @host.prepare_client_effect_source_dispatch(
    allowed, definition, caller, 1, "original-effect-producer", selection,
  ).unwrap()
  let wire = @host.issue_client_effect_run_materials(
    allowed,
    definition,
    environment,
    resident_effect_source_environment,
    resident_native_effect_document,
    None,
    effect_limits,
  ).unwrap()
  @resident.admit_resident_effect_source_dispatch(
    {
      expressions: { text_time: false, veca: false, },
      operations: {
        rela: true,
        sga: false,
        tea: false,
        calendar: false,
        text_rank: false,
      },
      manifests,
      limits: {
        preparation: @host.client_standard_program_preparation_limits(),
        sequence: @host.client_standard_values_sequence_limits(),
        max_sequence_steps: 1000,
        max_sequence_work: 1000,
        max_evidence_bytes: 1000000,
        max_evidence_nodes: 100000,
        max_evidence_depth: 100,
      },
      source: Some(
        (
          "connector://crm/main/r#v", "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3",
        ),
      ),
    },
    effect_limits,
    {
      coordinator_authority: "sha256:" + "c".repeat(64),
      site_key: selection.site_key,
      runtime_bundle_cid: selection.runtime_bundle_cid,
      connector_registration: selection.connector_registration,
      connector_revision: selection.connector_revision,
      strategy_revision: selection.strategy_revision,
      grant_cid: selection.grant_cid,
      evidence_issuer_capability_cid: selection.evidence_issuer_capability_cid,
      budget_cids: [selection.budget_cid],
    },
    1,
    request,
    wire,
    @host.prepare_client_effect_source_input_binding(compilation).unwrap(),
    "2026-10-09T01:00:00.000Z",
    resident_compute_installed_contracts(),
    resident_effect_source_values,
    resident_effect_source_fragment,
  ).unwrap()
}

///|
test "resident Effect computation retains the exact physical input until its pin returns" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "effect-source-compute-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let events : Array[String] = []
  let owner = resident_native_effect_open(
    resident_native_effect_bound_run(),
    resident_compute_configuration(library, path),
    name,
    observe=event => {
      events.push(resident_compute_event_name(event))
      true
    },
  )
  assert_eq(events, ["acquisition-entered", "producer-captured"])
  assert_eq(owner.usage().attempts, 1)
  assert_true(owner.execute_task(0) is Err(Unavailable))
  // A second Source open would fail after this owned pathname is reclaimed.
  resident_compute_reclaim(root, name)
  resident_compute_execute(owner) |> ignore
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_eq(events, [
    "acquisition-entered", "producer-captured", "consumer-entered-1", "consumer-completed-1",
  ])
  let effect_run = owner.effect_run().unwrap()
  let inputs = @strategy.pin_captured_effect_sources(effect_run, 4).unwrap()
  let input = @strategy.captured_effect_input_at(inputs, 0).unwrap()
  assert_eq(@strategy.captured_effect_input_task(input), 1)
  assert_eq(@strategy.captured_effect_input_stage(input), 1)
  // This export checks Compute bytes, not public publication or Effect apply.
  let output = owner.prepare_result_export(resident_compute_limits()).unwrap()
  let body = StringBuilder()
  while output.next().unwrap() is Some(chunk) {
    body.write_string(chunk)
  }
  body.write_string(output.finish().unwrap())
  assert_eq(body.to_string(), "[{\"id\":3}]")
  assert_eq(
    output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  output.cancel()
  assert_false(owner.close())
  let held = owner.usage().held_bytes
  assert_true(held > 0L)
  assert_false(owner.close())
  assert_eq(owner.usage().held_bytes, held)
  assert_eq(owner.usage().attempts, 2)
  // Stopping revokes access/apply availability, while the outstanding pin
  // still prevents physical cleanup and reservation return.
  assert_true(@strategy.captured_effect_input_at(inputs, 0) is None)
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.release_captured_effect_inputs(inputs))
  assert_true(owner.close())
  let count = events.length()
  assert_true(owner.close())
  assert_eq(events.length(), count)
  assert_eq(events[count - 1], "cleanup-completed")
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().reserved_transfer_bytes, 0L)
  assert_eq(owner.usage().reserved_execution_bytes, 0L)
  assert_eq(owner.usage().attempts, 2)
}

///|
test "resident Effect Source cancellation before Compute keeps its cleanup owner" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "effect-source-cancel-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let record_cleanup = Ref(false)
  let events : Array[String] = []
  let owner = resident_native_effect_open(
    resident_native_effect_bound_run(),
    resident_compute_configuration(library, path),
    name,
    observe=event => {
      events.push(resident_compute_event_name(event))
      !(event is CleanupCompleted) || record_cleanup.val
    },
  )
  assert_false(owner.close())
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_true(owner.effect_run() is None)
  assert_eq(owner.usage().attempts, 1)
  record_cleanup.val = true
  assert_true(owner.close())
  let count = events.length()
  assert_true(owner.close())
  assert_eq(events.length(), count)
  assert_false(events.contains("consumer-entered-1"))
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().reserved_execution_bytes, 0L)
  resident_compute_reclaim(root, name)
}

///|
test "resident Effect failed Compute does not reacquire Source or abandon its holding" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "effect-source-failure-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let owner = resident_native_effect_open(
    resident_native_effect_bound_run(),
    resident_compute_configuration(library, path, import_rows=1),
    name,
  )
  assert_true(owner.execute_task(1) is Err(Compute(_)))
  let failed = owner.usage()
  assert_true(failed.held_bytes > 0L)
  assert_true(owner.execute_task(1) is Err(Unavailable))
  assert_eq(owner.usage().attempts, failed.attempts)
  assert_true(owner.close())
  assert_true(owner.close())
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().reserved_execution_bytes, 0L)
  resident_compute_reclaim(root, name)
}

///|
test "resident Effect Source rejects configured identity before acquisition IO" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "effect-source-absent-" + @env.now().to_string() + ".duckdb"
  let root = @filesystem.open_root(root_path).unwrap()
  let config = resident_compute_configuration(library, root_path + "/" + name)
  let events : Array[String] = []
  let (issue, cleanup) = @resident.open_resident_effect_source_compute(
    resident_native_effect_bound_run(),
    {
      ..config,
      source: { ..config.source, source_ref: "connector://crm/other/r#v", },
    },
    name,
    observe=event => {
      events.push(resident_compute_event_name(event))
      true
    },
  ).unwrap_err()
  assert_true(issue is Source(ForeignInput))
  assert_eq(events, [])
  assert_eq(root.inspect_generation(name).unwrap(), None)
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(cleanup),
  )
}

///|
fn resident_native_effect_open(
  bound : @host.PreparedClientEffectRun,
  config : @resident.ResidentSourceComputeConfiguration,
  occurrence : String,
  observe? : (@resident.ResidentSourceComputeEvent) -> Bool,
) -> @resident.ResidentSourceCompute raise {
  match
    @resident.open_resident_effect_source_compute(
      bound,
      config,
      occurrence,
      observe?,
    ) {
    Ok(owner) => owner
    Err((issue, cleanup)) => {
      let label = match issue {
        UnsupportedGraph => "checked graph"
        Unavailable => "unavailable"
        Source(Query(_)) => "checked Source requirement"
        Source(Acquisition(_)) => "acquisition preparation"
        Source(Binding(_)) => "Source binding"
        Source(_) => "Source identity"
        Acquisition(_) => "physical acquisition open"
        Execution(_) => "physical acquisition execution"
        Capture => "physical capture"
        RetainedInput(_) => "retained input"
        EffectRun(_) => "Effect Run binding"
        ForeignEffectMaterials => "foreign Effect review materials"
        EffectInput(_) => "Effect retained input"
        Run(Run(UnsupportedGraph)) => "captured Effect graph"
        Run(_) => "captured Effect Run"
        Dispatch(_) => "standard strategy dispatch"
        Compute(_) => "Native Compute open"
        Export(_) => "output export"
        Capacity(_) => "reservation"
        ObservationUnrecorded(_) => "observation"
      }
      assert_true(
        @output.retry_native_remote_standard_input_failure_cleanup(cleanup),
      )
      fail("resident Effect computation failed to open: " + label)
    }
  }
}
