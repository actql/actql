///|
// Fixed test Program, real public checks and execution. No private completion,
// fabricated records, source permission or arbitrary Plan constructor.
struct IssuedBroadFixture {
  configuration : @acquisition_host.BroadHostConfiguration
  issuer : @duckdb_query.DuckDBQueryIssuer
  attempt : @duckdb_query.DuckDBBroadAttempt
  requirement : @planning.QueryRequirement
  scan : @duckdb.BroadScan
  owner : @lower.BoundPrepared
  consumer : @execution.GeneratedSequence
  mut observation : @duckdb_query.DuckDBBroadObservation?
}

///|
fn issued_fixture_checked(
  environment_json : String,
  environment_cid : String,
  source_override? : String? = None,
  join? : Bool = false,
) -> @program_check.CheckedProgram raise {
  let source =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}}],"results":{"out":{"from":{"stage":"a","result":"r"}}}}
  let input_limits : @syntax.Limits = {
    source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    tree: {
      max_nodes: 100000,
      max_depth: 100,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
    max_stages: 10,
  }
  let program = @syntax.parse(
    source_override.unwrap_or(source),
    input_limits,
    format=Json,
  ).unwrap()
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
  let evidence = if join {
    guard @syntax.stage_count(program) == 5 else {
      fail("join fixture requires five authored Stages")
    }
    [join_fixture_capacity(environment, @syntax.stages(program)[3].id)]
  } else {
    []
  }
  match
    @program_check.check_parsed_with_evidence(
      program,
      @program_check.checking_environment(
        environment,
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
      ),
      Some(cursor("{\"minimum\":1}")),
      evidence,
      { input: input_limits, compilation: fixture_query_limits(20), },
    ) {
    Checked(value) => value
    NeedsInputs(_) => fail("fixture requires complete checking inputs")
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
  }
}

///|
fn issued_fixture_consumer(
  owner : @lower.BoundPrepared,
  steps? : String = "[{\"select\":[\"id\"]}]",
  target? : @pipeline.Target = Step(1),
) -> @lower.BoundPrepared {
  let pipeline = @pipeline.check_with_evidence(
    cursor(steps),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(owner)),
            target,
          ).unwrap(),
        ),
      ),
    ],
    None,
    Some(cursor("\"prior\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn issued_fixture_preparation(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  output_rows : Int,
  checked_override? : @program_check.CheckedProgram? = None,
) -> (@duckdb_query.DuckDBQueryPreparation, @lower.BoundPrepared) raise {
  let checked = match checked_override {
    Some(checked) => checked
    None => issued_fixture_checked(environment_json, environment_cid)
  }
  let identity = @program_check.source_identity(checked)
  let requests = @context.program_identity_stage_requests(identity, 0).unwrap()
  let acquisition = @acquisition.derive_query_acquisition(requests, 0, 1000000).unwrap()
  let pipeline = @acquisition.query_acquisition_pipeline(acquisition)
  let prepared = @lower.prepare(pipeline, {
    max_nodes: 100,
    max_references: 100,
    max_work: 100000,
    max_identifier_bytes: 10000,
  }).unwrap()
  let params = @acquisition.request_parameter_values(
    @acquisition.pipeline_requests_parameters(requests),
  )
  let owner = @lower.bind_parameters(
    prepared,
    Some(params),
    max_parameters=100,
    max_name_bytes=10000,
  ).unwrap()
  let generated = fixture_generated(
    owner, registry_json, values_json, fragment_json, true,
  )
  let sequence = @query.prepare_query_sequence(acquisition, generated, 10000).unwrap()
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
    { max_rows: output_rows, max_value_bytes: 100, },
    material,
  ).unwrap()
  let preparation = @duckdb_query.prepare_duckdb_query(
    requirement,
    "main",
    "records",
    10,
    {
      max_entries: 100,
      max_sql_bytes: 10000,
      expressions: {
        max_nodes: 1000,
        max_work: 10000,
        max_depth: 100,
        max_literal_nodes: 1000,
        max_literal_text_bytes: 10000,
      },
    },
  ).unwrap()
  (preparation, owner)
}

///|
#export_name("issuedBroadCreate")
pub fn issued_broad_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  output_rows : Int,
  verify : (@duckdb_query.DuckDBBroadAttempt) -> Bool,
) -> IssuedBroadFixture {
  try {
    let (preparation, owner) = issued_fixture_preparation(
      environment_json, environment_cid, registry_json, values_json, fragment_json,
      output_rows,
    )
    let requirement = @duckdb_query.duckdb_query_requirement(preparation)
    let registry = @connector.prepare_capability_registry(
      [{ name: "duckdb", acquisition: true, fixed_compute: true, }],
      1,
      6,
    ).unwrap()
    let candidate = @duckdb_query.duckdb_broad_candidate(
      @connector.capability_registration_at(registry, 0).unwrap(),
      preparation,
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ).unwrap()
    guard @planning.choose_acquisition_candidate(
        registry,
        requirement,
        [@planning.prepared_acquisition_candidate(candidate)],
        None,
        100,
      ).unwrap()
      is Proposed(choice) else {
      abort("fixture choice")
    }
    let evidence = @planning.admit_query_evidence_contracts(
      fixture_contract(query_json),
      fixture_contract(evidence_json),
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ).unwrap()
    let issuer = @duckdb_query.prepare_duckdb_query_issuer(
      evidence, requirement, "real-node-fixture", 100, verify,
    ).unwrap()
    let attempt = @duckdb_query.prepare_issued_duckdb_broad_attempt(
      issuer, choice, candidate,
    ).unwrap()
    let consumer_owner = issued_fixture_consumer(owner)
    let consumer = fixture_generated(
      consumer_owner, registry_json, values_json, fragment_json, false,
    )
    {
      configuration: @acquisition_host.configure_broad_host(
        evidence,
        requirement,
        choice,
        candidate,
        {
          physical: {
            max_rows: 100,
            max_cells: 1000,
            max_nodes: 1000,
            max_text_bytes: 10000,
          },
          metadata_work: 10000,
          retention: {
            max_nodes: 10000,
            max_text_bytes: 10000,
            max_depth: 100,
            max_work: 100000,
          },
          completion: issued_broad_completion_limits(1000000),
          transport: {
            max_bytes: 100000,
            max_nodes: 10000,
            max_columns: 10,
            max_rows: 100,
            max_text_bytes: 100000,
          },
        },
      ),
      issuer,
      attempt,
      requirement,
      scan: @duckdb_query.duckdb_query_broad_scan(preparation),
      owner,
      consumer,
      observation: None,
    }
  } catch {
    _ => abort("fixed checked query setup")
  }
}

///|
#export_name("issuedBroadAttempt")
pub fn issued_broad_attempt(
  value : IssuedBroadFixture,
) -> @duckdb_query.DuckDBBroadAttempt {
  value.attempt
}

///|
#export_name("issuedBroadSql")
pub fn issued_broad_sql(value : IssuedBroadFixture, metadata : Bool) -> String {
  if metadata {
    @duckdb.broad_scan_metadata_sql(value.scan)
  } else {
    @duckdb.broad_scan_sql(value.scan)
  }
}

///|
#export_name("issuedBroadParameter")
pub fn issued_broad_parameter(
  value : IssuedBroadFixture,
  index : Int,
) -> String {
  try {
    let writer = @encode.writer(1000, 100, 10)
    @duckdb.emit_physical_parameter(
      @duckdb.broad_scan_metadata_parameter(value.scan, index).unwrap(),
      writer,
    )
    @encode.finish(writer)
  } catch {
    _ => abort("fixed metadata parameter")
  }
}

///|
#export_name("issuedBroadMetadata")
pub fn issued_broad_metadata(
  value : IssuedBroadFixture,
  rows : Int,
  names : String,
  data : String,
) -> Bool {
  @duckdb_query.admit_duckdb_broad_metadata(
    value.attempt,
    rows,
    fields(names),
    columns(data),
  )
  is Ok(_)
}

///|
#export_name("issuedBroadBegin")
pub fn issued_broad_begin(value : IssuedBroadFixture, names : String) -> Bool {
  @duckdb_query.begin_duckdb_broad_receipt(
    value.attempt,
    fields(names),
    { max_rows: 100, max_cells: 1000, max_nodes: 1000, max_text_bytes: 10000, },
    10000,
    {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
  )
  is Ok(_)
}

///|
#export_name("issuedBroadAccept")
pub fn issued_broad_accept(
  value : IssuedBroadFixture,
  rows : Int,
  data : String,
) -> Bool {
  @duckdb_query.accept_duckdb_broad_chunk(value.attempt, rows, columns(data))
  is Ok(_)
}

///|
#export_name("issuedBroadFinish")
pub fn issued_broad_finish(value : IssuedBroadFixture) -> Bool {
  @duckdb_query.finish_duckdb_broad_receipt(value.attempt) is Ok(_)
}

///|
fn issued_execution_limits(rows : Int) -> @execution.SequenceExecutionLimits {
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  {
    rows: {
      max_rows: rows,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
}

///|
#export_name("issuedBroadComplete")
pub fn issued_broad_complete(
  value : IssuedBroadFixture,
  artifact_bytes : Int,
) -> Bool {
  guard @duckdb_query.complete_duckdb_broad_capture(
      value.issuer,
      value.attempt,
      issued_broad_completion_limits(artifact_bytes),
    )
    is Ok(observation) else {
    return false
  }
  value.observation = Some(observation)
  true
}

///|
fn issued_broad_completion_limits(
  artifact_bytes : Int,
) -> @duckdb_query.DuckDBBroadCompletionLimits {
  {
    execution: issued_execution_limits(100),
    guards: {
      max_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    },
    retention: {
      received_wire_bytes: 100000,
      retained_wire_bytes: 100000,
      measurement: {
        max_columns: 10,
        max_order_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    },
    records: {
      max_work: 1000000,
      max_fields: 100,
      max_parameters: 100,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
    },
    capture: { max_bytes: artifact_bytes, max_nodes: 100000, max_depth: 100, },
  }
}

///|
#export_name("issuedBroadConfiguration")
pub fn issued_broad_configuration(
  value : IssuedBroadFixture,
) -> @acquisition_host.BroadHostConfiguration {
  value.configuration
}

///|
#export_name("issuedBroadConsumer")
pub fn issued_broad_consumer(
  value : IssuedBroadFixture,
) -> @lower.BoundPrepared {
  @execution.generated_sequence_owner(value.consumer)
}

///|
#export_name("issuedBroadConsumeInput")
pub fn issued_broad_consume_input(
  value : IssuedBroadFixture,
  bound : @execution.BoundProducerInput,
  rows : Int,
) -> String {
  guard @execution.execute_generated_sequence(
      value.consumer,
      [],
      issued_execution_limits(rows),
      produced=[bound],
    )
    is Ok(completed) else {
    return "null"
  }
  let output = @execution.completed_output(completed, Step(0)).unwrap()
  guard @execution.identify_completed_rows(output, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    })
    is Ok(identity) else {
    return "null"
  }
  @execution.row_wire_cid(identity)
}

///|
#export_name("issuedBroadObservation")
pub fn issued_broad_observation(
  value : IssuedBroadFixture,
) -> @duckdb_query.DuckDBBroadObservation {
  value.observation.unwrap()
}

///|
#export_name("issuedBroadDocument")
pub fn issued_broad_document(value : IssuedBroadFixture) -> String {
  match value.observation {
    Some(observation) =>
      @encode.document_text(
        @duckdb_query.duckdb_broad_observation_document(observation),
      )
    None => "null"
  }
}

///|
#export_name("issuedBroadBind")
pub fn issued_broad_bind(
  value : IssuedBroadFixture,
  observation : @duckdb_query.DuckDBBroadObservation,
  rows : Int,
) -> String {
  guard @duckdb_query.bind_captured_duckdb_broad_input(
      value.issuer,
      value.attempt,
      observation,
      @execution.generated_sequence_owner(value.consumer),
      0,
      value.owner,
    )
    is Ok(bound) else {
    return "null"
  }
  guard @execution.execute_generated_sequence(
      value.consumer,
      [],
      issued_execution_limits(rows),
      produced=[bound],
    )
    is Ok(completed) else {
    return "null"
  }
  let output = @execution.completed_output(completed, Step(0)).unwrap()
  guard @execution.identify_completed_rows(output, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    })
    is Ok(identity) else {
    return "null"
  }
  @execution.row_wire_cid(identity)
}

///|
#export_name("issuedBroadAbort")
pub fn issued_broad_abort(value : IssuedBroadFixture) -> Unit {
  @duckdb_query.abort_duckdb_broad_attempt(value.attempt)
}

///|
#export_name("issuedBroadClose")
pub fn issued_broad_close(value : IssuedBroadFixture) -> Unit {
  @duckdb_query.close_duckdb_query_issuer(value.issuer)
}

///|
#export_name("issuedBroadRequirement")
pub fn issued_broad_requirement(value : IssuedBroadFixture) -> String {
  @encode.document_text(@planning.query_requirement_document(value.requirement))
}

///|
#export_name("issuedBroadIds")
pub fn issued_broad_ids(value : IssuedBroadFixture) -> String {
  let (issuer, attempt) = @duckdb_query.duckdb_broad_attempt_identity(
    value.attempt,
  ).unwrap()
  try {
    let writer = @encode.writer(1000, 10, 2)
    @encode.begin_array(writer)
    @encode.string_value(writer, issuer)
    @encode.string_value(writer, attempt)
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    _ => abort("fixture IDs")
  }
}
