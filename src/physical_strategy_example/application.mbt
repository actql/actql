///|
struct Application {
  acquisition : @acquisition_host.NativeHostConfiguration
  acquisition_preparation : @duckdb_query.DuckDBQueryPreparation
  graph : @strategy.CheckedDAG
  registry : @connector.CapabilityRegistry
  input_sequence : @query.QuerySequence
  program : @context.ProgramSourceIdentity
  generated : Array[@execution.GeneratedSequence]
  data : DataProfile?
}

///|
// The Node transport and selected offer must use the same admission envelope.
fn core_application_compute_transfer_capacity(app : Application) -> Int64 {
  app.data.map(profile_compute_transfer_capacity).unwrap_or(100000L)
}

///|
fn contract(text : String) -> @identity.CanonicalValue raise {
  @identity.from_json(@json.parse(text), 100000, 100, 1000000)
}

///|
// Preparation occurs before DB authorization or any execution resources.
// These limits and selected external claims belong to this bounded example only.
fn core_prepare_application(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  database_schema : String,
  table : String,
) -> Application raise {
  prepare_application_internal(
    program_json,
    environment_json,
    environment_cid,
    parameter_json,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    database_schema,
    table,
    None,
  )
}

///|
fn core_prepare_application_with_data(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  database_schema : String,
  table : String,
  data : DataProfile,
) -> Application raise {
  prepare_application_internal(
    program_json,
    environment_json,
    environment_cid,
    parameter_json,
    registry_json,
    values_json,
    fragment_json,
    query_json,
    evidence_json,
    two_receipt_json,
    database_schema,
    table,
    Some(data),
  )
}

///|
fn prepare_application_internal(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  database_schema : String,
  table : String,
  data : DataProfile?,
) -> Application raise {
  let prelude = @manifest.prepare_application_graph_prelude(
    program_json, environment_json, environment_cid, parameter_json, data,
  )
  let checked = prelude.checked
  let identity = prelude.identity
  let acquisition = prelude.acquisition
  let owners = prelude.owners
  // These installed contracts do not depend on the stage or its parameters.
  // Admit them once; each stage still prepares and checks its own fragment.
  let registry_limits : @execution.RegistryLimits = {
    max_body_bytes: 100000,
    max_body_nodes: 10000,
    max_body_depth: 100,
  }
  let registered = @execution.admit_relation_registry(
    contract(registry_json),
    contract(values_json),
    registry_limits,
  ).unwrap()
  let fragment = @execution.admit_fragment_contract(
    registered,
    contract(fragment_json),
    registry_limits,
  ).unwrap()
  let generated = owners.mapi((index, owner) => {
    generate(owner, registered, fragment, true, data~, acquisition=index == 0)
  })
  let graph = @strategy.prepare_checked_dag(checked, owners, 5, 10000).unwrap()
  let task_generated = Array::makei(@strategy.graph_task_count(graph) - 1, index => {
    let task = index + 1
    let owner = @strategy.graph_task_owner(graph, task).unwrap()
    let mut source = None
    for stage in 1..<owners.length() {
      if physical_equal(owner, owners[stage]) {
        source = Some(generated[stage])
      }
    }
    let sequence = source.unwrap()
    match @strategy.graph_task_selected_step(graph, task) {
      Some(step) =>
        @execution.select_generated_sequence_step(sequence, step).unwrap()
      None =>
        match @strategy.graph_task_prefix_end(graph, task) {
          Some(last) =>
            @execution.select_generated_sequence_prefix(sequence, last).unwrap()
          None => sequence
        }
    }
  })
  let sequence = @query.prepare_query_sequence(acquisition, generated[0], 10000).unwrap()
  let material : @planning.QueryMaterialLimits = {
    max_work: 1000000,
    // Requirement admission counts both source and projected output fields.
    max_fields: data.map(value => value.columns * 2).unwrap_or(100),
    max_parameters: 100,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, material).unwrap(),
    identity,
    {
      max_rows: data.map(value => value.source_rows).unwrap_or(100),
      max_value_bytes: data.map(value => value.value_bytes).unwrap_or(1000),
    },
    material,
  ).unwrap()
  let preparation = @duckdb_query.prepare_duckdb_query(
    requirement,
    database_schema,
    table,
    data.map(value => value.columns).unwrap_or(10),
    native_query_limits(),
  ).unwrap()
  let registry = @connector.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, effect: false, },
      { name: "duckdb", acquisition: true, fixed_compute: true, effect: false, },
    ],
    2,
    100,
  ).unwrap()
  let candidate = @duckdb_query.duckdb_native_candidate(
    @connector.capability_registration_at(registry, 1).unwrap(),
    preparation,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], milliseconds: None, }],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      Some([0]),
      100,
    ).unwrap()
    is Proposed(choice) else {
    fail("no acquisition candidate")
  }
  let evidence = @planning.admit_query_evidence_contracts(
    contract(query_json),
    contract(evidence_json),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  let receipts = @planning.admit_query_two_receipt_contract(
    evidence,
    contract(two_receipt_json),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  {
    acquisition_preparation: preparation,
    acquisition: @acquisition_host.configure_native_host(
      receipts,
      requirement,
      choice,
      candidate,
      acquisition_limits(data~),
    ),
    graph,
    registry,
    input_sequence: sequence,
    program: identity,
    generated: task_generated,
    data,
  }
}

///|
fn core_application_acquisition(
  app : Application,
) -> @acquisition_host.NativeHostConfiguration {
  app.acquisition
}

///|
fn core_application_graph(app : Application) -> @strategy.CheckedDAG {
  app.graph
}

///|
/// Returns the checked acquisition sequence fixed by this application. Native
/// Site composition uses this value to admit an exact transferred input
/// without reparsing or reconstructing the Program.
pub fn application_input_sequence(app : Application) -> @query.QuerySequence {
  app.input_sequence
}

///|
/// Returns the exact checked Program identity used by the application graph.
/// It is retained separately from physical input and Connector selection.
pub fn application_program_identity(
  app : Application,
) -> @context.ProgramSourceIdentity {
  app.program
}

///|
fn core_application_compute_count(app : Application) -> Int {
  app.generated.length()
}

///|
fn core_application_task_reference(
  app : Application,
  task : Int,
) -> @strategy.CheckedTaskReference raise {
  match @strategy.prepare_checked_task_reference(app.graph, task, 20, 1000) {
    Ok(reference) => reference
    Err(_) => fail("invalid checked task reference")
  }
}

///|
fn core_application_task_identity(
  reference : @strategy.CheckedTaskReference,
) -> @strategy.CheckedTaskIdentity {
  @strategy.checked_task_identity(reference)
}

///|
fn core_application_task_output_matches(
  reference : @strategy.CheckedTaskReference,
  output : @execution.CompletedOutput,
) -> Bool {
  @strategy.checked_task_output_matches(reference, output)
}

///|
/// Content-only revalidation for the installed fresh-reader example. This
/// projection neither runs the Local evaluator nor recreates task completion.
fn core_application_task_content_read(
  app : Application,
  task : Int,
  descriptor : @execution.RetainedCompletionDescriptor,
) -> @execution.RetainedContentRead raise {
  guard task > 0 && app.generated.get(task - 1) is Some(generated) else {
    fail("invalid content task")
  }
  match
    @execution.prepare_retained_content_read(
      @execution.generated_completion_preparation(generated),
      descriptor,
      app.data.map(value => value.task_rows).unwrap_or(100),
      {
        max_nodes: app.data.map(value => value.value_nodes).unwrap_or(100000),
        max_text_bytes: app.data
        .map(value => value.text_bytes)
        .unwrap_or(100000),
        max_depth: 64,
        max_work: app.data.map(value => value.work).unwrap_or(1000000),
      },
      {
        max_bytes: app.data.map(value => value.wire_bytes).unwrap_or(100000),
        max_nodes: app.data.map(value => value.value_nodes).unwrap_or(10000),
        max_depth: 64,
        max_columns: app.data.map(value => value.columns).unwrap_or(10),
        max_order_work: app.data.map(value => value.work).unwrap_or(10000),
      },
      app.data.map(value => value.batch_bytes).unwrap_or(100000),
    ) {
    Ok(value) => value
    Err(_) => fail("content admission failed")
  }
}

///|
fn core_application_task_completion_preparation(
  app : Application,
  task : Int,
) -> @execution.CompletionPreparation raise {
  guard task > 0 && app.generated.get(task - 1) is Some(generated) else {
    fail("invalid completion task")
  }
  @execution.generated_completion_preparation(generated)
}

///|
/// Bind a checked port only. This does not start or resume the consumer task.
fn core_application_bind_readmitted_output(
  app : Application,
  producer : Int,
  consumer : Int,
  input : Int,
  output : @execution.CompletedOutput,
) -> @execution.ProducerRead raise {
  let mut connected = false
  for index in 0..<@strategy.graph_data_count(app.graph) {
    let edge = @strategy.graph_data_at(app.graph, index).unwrap()
    if edge.producer == producer &&
      edge.consumer == consumer &&
      edge.input == input {
      connected = true
    }
  }
  guard connected &&
    @strategy.graph_task_owner(app.graph, producer) is Some(owner) &&
    @strategy.graph_task_owner(app.graph, consumer) is Some(receiver) else {
    fail("foreign readmitted input port")
  }
  let bound = match
    @execution.bind_completed_input(receiver, input, owner, output) {
    Ok(bound) => bound
    Err(_) => fail("readmitted binding rejected")
  }
  // Projection matching is metadata work, not a row-count allowance. Use the
  // same configured-profile ceiling as the normal Compute preparation path.
  let entries = if app.data is Some(_) { 100000 } else { 1000 }
  match @execution.prepare_producer_read(receiver, bound, entries, 10000) {
    Ok(read) => read
    Err(_) => fail("readmitted producer unavailable")
  }
}

///|
// Bounded diagnostic hashing, not a transferable completion or publication grant.
fn core_application_output_cid(
  run : @strategy.CapturedDAG,
  task : Int,
) -> String? {
  output_cid_with_limits(run, task, {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  })
}

///|
fn core_application_profile_output_cid(
  app : Application,
  run : @strategy.CapturedDAG,
  task : Int,
) -> String? {
  if !physical_equal(app.graph, @strategy.captured_dag_graph(run)) {
    return None
  }
  output_cid_with_limits(run, task, {
    max_columns: app.data.map(value => value.columns).unwrap_or(10),
    max_order_work: app.data.map(value => value.work).unwrap_or(10000),
    max_bytes: app.data.map(value => value.wire_bytes).unwrap_or(100000),
    max_nodes: app.data.map(value => value.value_nodes).unwrap_or(10000),
    max_depth: 100,
  })
}

///|
fn output_cid_with_limits(
  run : @strategy.CapturedDAG,
  task : Int,
  limits : @execution.RowWireLimits,
) -> String? {
  guard @strategy.captured_task_target(run, task) is Some(target) &&
    @strategy.captured_task_output(run, task, target) is Some(output) else {
    return None
  }
  match @execution.identify_completed_rows(output, limits) {
    Ok(identity) => Some(@execution.row_wire_cid(identity))
    Err(_) => None
  }
}

///|
fn core_application_ledger() -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 500000L,
    retained_bytes: 200000000L,
    execution_bytes: 268435456L,
  }).unwrap()
}

///|
fn core_application_bounded_ledger(
  limits : @resources.LedgerLimits,
) -> @resources.Ledger raise {
  match @resources.create_ledger(limits) {
    Ok(ledger) => ledger
    Err(_) => fail("invalid application ledger limits")
  }
}

///|
fn core_application_ledger_limits(
  ledger : @resources.Ledger,
) -> @resources.LedgerLimits {
  @resources.ledger_limits(ledger)
}

///|
fn core_application_ledger_usage(
  ledger : @resources.Ledger,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(ledger)
}

///|
fn core_application_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  @dbhost.dispatch_installation(
    create_application_strategy_dispatch(
      app,
      run,
      native_fixed_ms,
      resident,
      None,
    ),
  )
}

///|
pub fn application_strategy_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  resident : Bool,
) -> @dbhost.StrategyHostDispatch raise {
  create_application_strategy_dispatch(
    app,
    run,
    native_fixed_ms,
    resident,
    None,
  )
}

///|
/// Native physical duration estimates; these do not replace reservation,
/// transfer, activation or logical-work bounds.
pub(all) struct NativeResidentEstimateProfile {
  preparation_milliseconds : Int64
  cleanup_milliseconds : Int64
  task_milliseconds : Array[Int64]
  /// Producer-indexed estimates. None remains unknown; an unmeasured import
  /// must not silently inherit another producer's timing.
  import_milliseconds : Array[Int64?]
}

///|
/// Native process entry for the same retained Local/DuckDB candidate set used
/// by the installed Host. File bytes and work are physical policy inputs;
/// the common strategy still selects an eligible checked task realization.
pub fn application_native_retained_strategy_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  local_import_ms : Int64,
  local_export_ms : Int64,
  resident : Bool,
  local_task_ms? : Array[Int64] = [],
  native_task_ms? : Array[Int64] = [],
  resident_estimates? : NativeResidentEstimateProfile,
  local_eligible? : Bool = true,
) -> @dbhost.StrategyHostDispatch raise {
  create_application_strategy_dispatch(
    app,
    run,
    native_fixed_ms,
    resident,
    Some((file_bytes, Some(file_work_ms))),
    local_import_ms=Some(local_import_ms),
    local_export_ms=Some(local_export_ms),
    local_task_ms~,
    native_task_ms~,
    resident_estimates?,
    local_eligible~,
  )
}

///|
/// The selected DuckDB offer owns this per-task transfer envelope. A native
/// Host must not substitute the Run's larger cumulative ledger ceiling.
pub fn application_native_retained_task_transfer_capacity(
  app : Application,
) -> Int64 {
  app.data.map(profile_compute_transfer_capacity).unwrap_or(100000L)
}

///|
fn core_application_retained_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  @dbhost.dispatch_installation(
    create_application_strategy_dispatch(
      app,
      run,
      native_fixed_ms,
      resident,
      Some((file_bytes, Some(file_work_ms))),
    ),
  )
}

///|
fn core_application_managed_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  @dbhost.dispatch_installation(
    create_application_strategy_dispatch(
      app,
      run,
      native_fixed_ms,
      resident,
      Some((file_bytes, Some(file_work_ms))),
      managed_output=true,
    ),
  )
}

///|
fn core_application_materializing_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  local_import_ms : Int64,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  @dbhost.dispatch_installation(
    create_application_strategy_dispatch(
      app,
      run,
      native_fixed_ms,
      resident,
      Some((file_bytes, Some(file_work_ms))),
      local_import_ms=Some(local_import_ms),
    ),
  )
}

///|
fn core_application_retained_local_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  local_import_ms : Int64,
  local_export_ms : Int64,
  native_task_ms : Array[Int64],
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  @dbhost.dispatch_installation(
    create_application_strategy_dispatch(
      app,
      run,
      native_fixed_ms,
      resident,
      Some((file_bytes, Some(file_work_ms))),
      local_import_ms=Some(local_import_ms),
      local_export_ms=Some(local_export_ms),
      native_task_ms~,
    ),
  )
}

///|
fn core_application_retained_task_estimate_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  file_bytes : Int64,
  file_work_ms : Int64,
  local_import_ms : Int64,
  local_export_ms : Int64,
  local_task_ms : Array[Int64],
  native_task_ms : Array[Int64],
  local_eligible : Bool,
  resident : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue] raise {
  @dbhost.dispatch_installation(
    create_application_strategy_dispatch(
      app,
      run,
      native_fixed_ms,
      resident,
      Some((file_bytes, Some(file_work_ms))),
      local_import_ms=Some(local_import_ms),
      local_export_ms=Some(local_export_ms),
      local_task_ms~,
      native_task_ms~,
      local_eligible~,
    ),
  )
}

///|
fn create_application_strategy_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  resident : Bool,
  retained : (Int64, Int64?)?,
  local_import_ms? : Int64? = None,
  local_export_ms? : Int64? = None,
  local_task_ms? : Array[Int64] = [],
  native_task_ms? : Array[Int64] = [],
  resident_estimates? : NativeResidentEstimateProfile,
  local_eligible? : Bool = true,
  managed_output? : Bool = false,
) -> @dbhost.StrategyHostDispatch raise {
  if !physical_equal(@strategy.captured_dag_graph(run), app.graph) {
    fail("foreign graph")
  }
  let data = app.data
  if resident_estimates is Some(estimates) &&
    (
      !resident ||
      estimates.preparation_milliseconds < 0L ||
      estimates.cleanup_milliseconds < 0L ||
      estimates.task_milliseconds.length() != app.generated.length() ||
      estimates.import_milliseconds.length() != app.generated.length() + 1 ||
      estimates.task_milliseconds.any(value => value < 0L) ||
      estimates.import_milliseconds.any(value => value is Some(ms) && ms < 0L)
    ) {
    fail("invalid resident estimates")
  }
  let configured_execution_bytes = @resources.ledger_limits(
      @strategy.captured_dag_ledger(run),
    ).execution_bytes
  if (
      !native_task_ms.is_empty() &&
      native_task_ms.length() != app.generated.length()
    ) ||
    native_task_ms.any(value => value < 0L) ||
    (
      !local_task_ms.is_empty() &&
      local_task_ms.length() != app.generated.length()
    ) ||
    local_task_ms.any(value => value < 0L) {
    fail("invalid task estimates")
  }
  let dispatch = @dbhost.configure_strategy_dispatch(
    run,
    app.registry,
    @connector.capability_registration_at(app.registry, 0).unwrap(),
    @connector.capability_registration_at(app.registry, 1).unwrap(),
    app.generated,
    dispatch_limits(data=app.data),
  ).unwrap()
  if retained is Some((bytes, work)) {
    @dbhost.configure_dispatch_retained_output(dispatch, bytes, work).unwrap()
  }
  if local_import_ms is Some(work) {
    let modules = @builtin.configured_host_modules(
      @dbhost.dispatch_installation(dispatch),
    )
    @local_driver.configure_local_retained_inputs(
      @builtin.configured_local_module(modules).unwrap(),
      {
        max_rows: data.map(value => value.task_rows).unwrap_or(100),
        values: dispatch_limits(data~).local_execution.rows.input_values,
        wire: {
          max_bytes: data.map(value => value.wire_bytes).unwrap_or(100000),
          max_nodes: data.map(value => value.value_nodes).unwrap_or(10000),
          max_depth: 64,
          max_columns: data.map(value => value.columns).unwrap_or(10),
          max_order_work: 10000,
        },
        row: {
          max_bytes: data.map(value => value.batch_bytes).unwrap_or(100000),
          max_nodes: 10000,
          max_depth: 64,
          max_text_bytes: data.map(value => value.batch_bytes).unwrap_or(10000),
        },
        max_batch_bytes: data.map(value => value.batch_bytes).unwrap_or(100000),
      },
      Some(work),
    ).unwrap()
  }
  let count = app.generated.length()
  if local_export_ms is Some(work) {
    let modules = @builtin.configured_host_modules(
      @dbhost.dispatch_installation(dispatch),
    )
    @local_driver.configure_local_retained_output(
      @builtin.configured_local_module(modules).unwrap(),
      {
        max_rows: data.map(value => value.task_rows).unwrap_or(100),
        values: dispatch_limits(data~).local_execution.rows.output_values,
        wire: {
          max_bytes: data.map(value => value.wire_bytes).unwrap_or(100000),
          max_nodes: data.map(value => value.value_nodes).unwrap_or(10000),
          max_depth: 64,
          max_columns: data.map(value => value.columns).unwrap_or(10),
          max_order_work: 10000,
        },
        max_batch_bytes: data.map(value => value.batch_bytes).unwrap_or(100000),
      },
      Some(work),
    ).unwrap()
  }
  let profiles : Array[@dbhost.DispatchEstimateProfile] = Array::makei(count, index => {
    let output_columns = @strategy.graph_task_owner(app.graph, index + 1)
      .map(@lower.bound_preparation)
      .map(@lower.pipeline)
      .bind(@pipeline.output_schema)
      .map(@schema.field_count)
      .unwrap_or(0)
    {
      local_rates: [
        {
          work_slots: [0, 1, 2, 3, 4],
          fixed_ms: Some(local_task_ms.get(index).unwrap_or(1L)),
          per_row_ms: Some(if local_task_ms.is_empty() { 2L } else { 0L }),
          per_wire_byte_ms: Some(0L),
          per_pair_ms: Some(0L),
        },
      ],
      native_rates: [
        {
          work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
          fixed_ms: Some(native_task_ms.get(index).unwrap_or(native_fixed_ms)),
          per_row_ms: Some(0L),
          per_wire_byte_ms: Some(0L),
          per_pair_ms: Some(0L),
        },
      ],
      native_capacity: {
        transfer_bytes: data
        .map(profile_compute_transfer_capacity)
        .unwrap_or(100000L),
        retained_bytes: data
        .map(value => {
          if managed_output {
            guard profile_managed_retention_capacity(
                value,
                output_columns,
                retained is Some((bytes, _)) && bytes > 0L,
              )
              is Some(capacity) else {
              fail("invalid managed measurement capacity")
            }
            capacity
          } else {
            let limits = dispatch_limits(data=Some(value)).native
            if retained is Some((bytes, _)) && bytes > 0L {
              // The connector adds its DB-copy minimum only to resident offers.
              // Fresh execution retains no DB copy after the task completes.
              @duckdb_compute.duckdb_stream_retention_capacity(limits).unwrap()
            } else {
              @duckdb_compute.duckdb_task_retention_capacity(limits).unwrap()
            }
          }
        })
        .unwrap_or(4000000L),
        execution_bytes: if data is Some(_) {
          configured_execution_bytes
        } else {
          268435456L
        },
      },
      output_rows_per_mille: Some(1000),
    }
  })
  @dbhost.configure_dispatch_estimates(
    dispatch,
    profiles,
    {
      max_offers: if resident {
        count * 3
      } else {
        count * 2
      },
      max_strategies: if resident {
        if count == 3 {
          27
        } else {
          81
        }
      } else if count == 3 {
        8
      } else {
        16
      },
      max_work: if resident {
        10000
      } else {
        1000
      },
      max_revisions: if resident {
        count + 1
      } else {
        count
      },
    },
    local_eligible=Array::make(count, local_eligible),
  ).unwrap()
  if resident {
    let profile = @strategy.prepare_resident_profile(
      run,
      @connector.prepare_resource_binding(
        app.registry,
        @connector.capability_registration_at(app.registry, 1).unwrap(),
      ).unwrap(),
      if data is Some(_) {
        configured_execution_bytes / 2L
      } else {
        134217728L
      },
      @strategy.prepare_shared_work(
        run,
        1,
        [
          {
            work_slots: [0],
            milliseconds: Some(
              resident_estimates
              .map(estimates => estimates.preparation_milliseconds)
              .unwrap_or(1L),
            ),
          },
        ],
        3,
      ).unwrap(),
      @strategy.prepare_shared_work(
        run,
        1,
        [
          {
            work_slots: [0],
            milliseconds: Some(
              resident_estimates
              .map(estimates => estimates.cleanup_milliseconds)
              .unwrap_or(1L),
            ),
          },
        ],
        3,
      ).unwrap(),
      Array::makei(count + 1, producer => @strategy.ResidentImportEstimate::{
        work: @strategy.prepare_shared_work(
          run,
          1,
          [
            {
              work_slots: [0],
              milliseconds: resident_estimates
              .map(estimates => estimates.import_milliseconds[producer])
              .unwrap_or(Some(1L)),
            },
          ],
          3,
        ).unwrap(),
        transfer_bytes: data
        .map(profile_compute_transfer_capacity)
        .unwrap_or(100000L),
        scratch_bytes: data
        .map(profile_resident_import_scratch)
        .unwrap_or(2000000L),
        table_bytes: data
        .map(value => {
          @duckdb_compute.duckdb_resident_table_allowance(
            dispatch_limits(data=Some(value)).native,
          ).unwrap()
        })
        .unwrap_or(4000000L),
      }),
    ).unwrap()
    @dbhost.configure_resident_dispatch(
      dispatch,
      profile,
      Array::makei(count, task => {
        [
          {
            work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
            fixed_ms: Some(
              resident_estimates
              .map(estimates => estimates.task_milliseconds[task])
              .unwrap_or(1L),
            ),
            per_row_ms: Some(0L),
            per_wire_byte_ms: Some(0L),
            per_pair_ms: Some(0L),
          },
        ]
      }),
    ).unwrap()
  }
  dispatch
}
