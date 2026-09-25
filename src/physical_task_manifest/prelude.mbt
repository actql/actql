///|
priv suberror ApplicationSyntaxFailure {
  Syntax(@syntax.SyntaxError)
}

///|
/// The checked Program and exact task graph are independent of the physical
/// DuckDB query, generated fragments, and selected execution environment.
pub struct ApplicationGraphPrelude {
  checked : @program_check.CheckedProgram
  identity : @context.ProgramSourceIdentity
  acquisition : @acquisition.QueryAcquisition
  owners : Array[@lower.BoundPrepared]
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
pub fn prepare_application_graph_prelude(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
  data : DataProfile?,
) -> ApplicationGraphPrelude raise {
  if data is Some(value) && !validate_data_profile(value) {
    fail("invalid application data profile")
  }
  let input_limits : @syntax.Limits = {
    source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    tree: {
      max_nodes: 100000,
      max_depth: 100,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
    max_stages: 5,
  }
  let program = match @syntax.parse(program_json, input_limits, format=Json) {
    Ok(program) => program
    Err(issue) => raise Syntax(issue)
  }
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
  let evidence = if stages == 5 {
    [join_capacity_material(environment, @syntax.stages(program)[3].id)]
  } else {
    []
  }
  let checked = match
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
      Some(cursor(parameter_json)),
      evidence,
      { input: input_limits, compilation: source_limits(10), },
    ) {
    Checked(value) => value
    NeedsInputs(_) => fail("example requires complete checking inputs")
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
  }
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
  { checked, identity, acquisition, owners, }
}

///|
/// Control-side projection of the same checked task graph. It does not create
/// physical candidates, a DuckDB query, or execution resources.
pub fn application_task_manifest(
  program_json : String,
  environment_json : String,
  environment_cid : String,
  parameter_json : String,
  data : DataProfile?,
) -> Array[@strategy.CheckedTaskIdentity] raise {
  let prelude = prepare_application_graph_prelude(
    program_json, environment_json, environment_cid, parameter_json, data,
  )
  let graph = @strategy.prepare_checked_dag(
    prelude.checked,
    prelude.owners,
    5,
    10000,
  ).unwrap()
  Array::makei(@program_check.unit_count(prelude.checked) - 1, index => {
    let reference = @strategy.prepare_checked_task_reference(
      graph,
      index + 1,
      20,
      1000,
    ).unwrap()
    @strategy.checked_task_identity(reference)
  })
}

///|
fn source_limits(stage_count : Int) -> @program_check.CompileLimits {
  {
    work: 100000000,
    artifacts: { bytes: 10000000, nodes: 1000000, depth: 100, },
    structure: {
      stages: stage_count,
      steps: stage_count,
      results: stage_count,
      parameters: 1,
      bindings: 100,
      slots: 1000,
      references: 1000,
      requirements: 1000,
      tokens: 10000,
    },
    traversal: {
      nodes: 100000,
      depth: 100,
      text_bytes: 10000000,
      string_bytes: 100000,
      name_bytes: 1000000,
      pointer_units: 1000000,
      comparison_pairs: 1000000,
    },
    values: { nodes: 1000000, depth: 100, text_bytes: 100000, },
    policy: { bytes: 10000, nodes: 1000000, depth: 100, },
    patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
  }
}
