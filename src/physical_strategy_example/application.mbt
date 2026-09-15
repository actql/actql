///|
struct Application {
  acquisition : @dbhost.NativeHostConfiguration
  graph : @strategy.CheckedDAG
  registry : @planning.CapabilityRegistry
  generated : Array[@execution.GeneratedSequence]
}

///|
fn contract(text : String) -> @identity.CanonicalValue raise {
  @identity.from_json(@json.parse(text), 100000, 100, 1000000)
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 100000,
      max_depth: 100,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
  ).unwrap()
}

///|
// Preparation occurs before DB authorization or any execution resources.
// These limits and empty external claims belong to this bounded example only.
#export_name("prepareApplication")
pub fn prepare_application(
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
  let program = @syntax.parse(
    program_json,
    {
      source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      tree: {
        max_nodes: 100000,
        max_depth: 100,
        max_string_bytes: 1000000,
        max_total_string_bytes: 1000000,
      },
      max_stages: 5,
    },
    format=Json,
  ).unwrap()
  let stages = @syntax.stage_count(program)
  if stages != 4 && stages != 5 {
    fail(
      "example requires the four-stage filter profile or five-stage join/count profile",
    )
  }
  let environment = @environment.read(
    @utf8.encode(environment_json),
    environment_cid,
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_members: 1000,
    },
  ).unwrap()
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let join_sources = if stages == 5 {
    Some(join_capacity_material(environment))
  } else {
    None
  }
  let visits = if stages == 5 { [1, 2, 2, 5, 6] } else { [1, 2, 2, 3] }
  let checked = @program_check.check(
    program,
    environment,
    Some(cursor(parameter_json)),
    Array::makei(visits.length(), stage => {
      Array::makei(visits[stage], visit => {
        if ((stage == 3 && visit == 0) || (stage == 4 && visit == 1)) &&
          join_sources is Some(join_sources) {
          {
            sources: join_sources,
            consumers: [@capacity.Join(step=0, output=0)],
          }
        } else {
          { sources, consumers: [], }
        }
      })
    }),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    source_limits(10),
    max_work=100000000,
    max_bytes=10000000,
    max_nodes=1000000,
    max_depth=100,
  )
  if @program_check.unit_count(checked) != stages {
    fail("example requires one unit per stage")
  }
  let identity = @program_check.source_identity(checked)
  let requests = @context.program_identity_stage_requests(identity, 0).unwrap()
  let acquisition = @acquisition.derive_query_acquisition(requests, 0, 1000000).unwrap()
  let owners = Array::makei(stages, index => {
    let pipeline = if index == 0 {
      @acquisition.query_acquisition_pipeline(acquisition)
    } else {
      @program_check.unit_pipeline(checked, index).unwrap()
    }
    let preparation = @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    }).unwrap()
    let parameters = @parameters.bound_values(
      @context.stage_identity_parameter_values(
        @context.program_identity_stage_at(identity, index).unwrap(),
      ),
    )
    @lower.bind_parameters(
      preparation,
      Some(parameters),
      max_parameters=100,
      max_name_bytes=10000,
    ).unwrap()
  })
  let generated = owners.map(owner => {
    generate(owner, registry_json, values_json, fragment_json, true)
  })
  let graph = @strategy.prepare_checked_dag(checked, owners, 5, 10000).unwrap()
  let sequence = @query.prepare_query_sequence(acquisition, generated[0], 10000).unwrap()
  let material : @planning.QueryMaterialLimits = {
    max_work: 1000000,
    max_fields: 100,
    max_parameters: 100,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, material).unwrap(),
    identity,
    { max_rows: 100, max_value_bytes: 1000, },
    material,
  ).unwrap()
  let preparation = @planning.prepare_duckdb_query(
    requirement,
    database_schema,
    table,
    10,
    native_query_limits(),
  ).unwrap()
  let registry = @planning.prepare_capability_registry(
    [
      { name: "local", acquisition: false, fixed_compute: true, },
      { name: "duckdb", acquisition: true, fixed_compute: true, },
    ],
    2,
    100,
  ).unwrap()
  let candidate = @planning.duckdb_native_candidate(
    @planning.capability_registration_at(registry, 1).unwrap(),
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
    acquisition: @dbhost.configure_native_host(
      receipts,
      requirement,
      choice,
      candidate,
      acquisition_limits(),
    ),
    graph,
    registry,
    generated: generated[1:].to_owned(),
  }
}

///|
#export_name("applicationAcquisition")
pub fn application_acquisition(
  app : Application,
) -> @dbhost.NativeHostConfiguration {
  app.acquisition
}

///|
#export_name("applicationGraph")
pub fn application_graph(app : Application) -> @strategy.CheckedDAG {
  app.graph
}

///|
// Bounded diagnostic hashing, not a transferable completion or publication grant.
#export_name("applicationOutputCid")
pub fn application_output_cid(
  run : @strategy.CapturedDAG,
  task : Int,
) -> String? {
  guard @strategy.captured_task_target(run, task) is Some(target) &&
    @strategy.captured_task_output(run, task, target) is Some(output) else {
    return None
  }
  match
    @execution.identify_completed_rows(output, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }) {
    Ok(identity) => Some(@execution.row_wire_cid(identity))
    Err(_) => None
  }
}

///|
#export_name("applicationLedger")
pub fn application_ledger() -> @resources.Ledger {
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
#export_name("applicationDispatch")
pub fn application_dispatch(
  app : Application,
  run : @strategy.CapturedDAG,
  native_fixed_ms : Int64,
  resident : Bool,
) -> @dbhost.StrategyHostDispatch raise {
  if !physical_equal(@strategy.captured_dag_graph(run), app.graph) {
    fail("foreign graph")
  }
  let dispatch = @dbhost.configure_strategy_dispatch(
    run,
    app.registry,
    @planning.capability_registration_at(app.registry, 0).unwrap(),
    @planning.capability_registration_at(app.registry, 1).unwrap(),
    app.generated,
    dispatch_limits(),
  ).unwrap()
  let count = app.generated.length()
  let profiles : Array[@dbhost.DispatchEstimateProfile] = Array::makei(count, _ => {
    local_rates: [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some(1L),
        per_row_ms: Some(2L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_rates: [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(native_fixed_ms),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_capacity: {
      transfer_bytes: 100000L,
      retained_bytes: 4000000L,
      execution_bytes: 268435456L,
    },
    output_rows_per_mille: Some(1000),
  })
  @dbhost.configure_dispatch_estimates(dispatch, profiles, {
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
  }).unwrap()
  if resident {
    let profile = @strategy.prepare_resident_profile(
      run,
      134217728L,
      Some(1L),
      Some(1L),
      Array::make(count + 1, @strategy.ResidentImportEstimate::{
        milliseconds: Some(1L),
        transfer_bytes: 100000L,
        scratch_bytes: 2000000L,
        table_bytes: 4000000L,
      }),
    ).unwrap()
    @dbhost.configure_resident_dispatch(
      dispatch,
      profile,
      Array::make(count, [
        {
          work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
          fixed_ms: Some(1L),
          per_row_ms: Some(0L),
          per_wire_byte_ms: Some(0L),
          per_pair_ms: Some(0L),
        },
      ]),
    ).unwrap()
  }
  dispatch
}
