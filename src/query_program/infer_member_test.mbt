///|
// Fixture task/schema identities are retained from the independent infer owner
// fixture. The environment sha256:fb83357ad53e8aff3da606f999a60d491ae313d4056e2fe4083db68f4345f00c was calculated with Node/Python SHA-256 over
// the explicit canonical fixture body, never observed from product output.
fn infer_member_environment() -> @check.CheckEnvironment {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:fb83357ad53e8aff3da606f999a60d491ae313d4056e2fe4083db68f4345f00c","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:fb83357ad53e8aff3da606f999a60d491ae313d4056e2fe4083db68f4345f00c",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let tasks = @environment.check_model_tasks(wire, {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 10,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 100000,
  }).unwrap()
  @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=Some(tasks),
  )
}

///|
fn infer_member_context(environment : @check.CheckEnvironment) -> Context {
  @frontend.bind_query_context(
    [],
    @check.checking_environment_cid(environment),
    program_id="fixture.query_pair",
    model_tasks=@check.checking_environment_model_tasks(environment),
  ).unwrap()
}

///|
fn infer_member_source(tail : String) -> String {
  "SELECT DISTINCT 'a' AS id |> EXTEND 'urgent' AS text " +
  "|> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (text = text) " +
  "KEEP (id) AS assessment |> " +
  tail
}

///|
test "INFER members use declared outcome object names after KEEP projection" {
  let environment = infer_member_environment()
  for
    tail in [
      "SELECT assessment.value.risk AS risk", "SELECT assessment.VALUE.RISK AS risk",
      "SELECT `assessment`.`VaLuE`.`RiSk` AS risk",
    ] {
    let actual = compile(
      @query.parse_query(infer_member_source(tail), syntax_limits()).unwrap(),
      infer_member_context(environment),
      construction_limits(),
    ).unwrap()
    // Exact expression expectation authored from the fixed common ModelTask
    // output contract, independently of the lowercase compiler control.
    assert_true(
      semantic(actual).contains(
        "\"property\":{\"name\":\"risk\",\"value\":{\"property\":{\"name\":\"value\",\"value\":{\"field\":\"assessment\"}}}}",
      ),
      msg=tail,
    )
    match @check.check_parsed(actual, environment, None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) =>
        fail("closed INFER source must check without missing inputs")
    }
  }
}

///|
test "Frontend Context retains the exact selected ModelTask owner" {
  let environment = infer_member_environment()
  let context = infer_member_context(environment)
  assert_true(
    physical_equal(
      context.model_tasks.unwrap(),
      @check.checking_environment_model_tasks(environment).unwrap(),
    ),
  )
}

///|
test "INFER member binding follows a projected receiver and preserves literal values" {
  let environment = infer_member_environment()
  for
    tail in [
      "SELECT assessment AS kept |> SELECT kept.VALUE.RISK AS risk", "WHERE assessment.OUTCOME = 'VALUE' |> SELECT assessment.VALUE.RISK AS risk",
    ] {
    let actual = compile(
      @query.parse_query(infer_member_source(tail), syntax_limits()).unwrap(),
      infer_member_context(environment),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_false(body.contains("\"name\":\"RISK\""))
    assert_false(body.contains("\"name\":\"VALUE\""))
    if tail.has_prefix("WHERE") {
      assert_true(body.contains("\"literal\":\"VALUE\""))
    }
    match @check.check_parsed(actual, environment, None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) => fail("closed INFER source must check")
    }
  }
}

///|
test "INFER member type probing does not invent a key or a ModelTask" {
  let environment = infer_member_environment()
  for
    text in [
      infer_member_source("SELECT assessment.VALUE.RISK AS risk").replace(
        old="SELECT DISTINCT",
        new="SELECT",
      ),
      infer_member_source("SELECT assessment.VALUE.RISK AS risk").replace(
        old="model-task:risk-score.v1",
        new="model-task:absent.v1",
      ),
      infer_member_source("SELECT assessment.VALUE.absent AS risk"),
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      infer_member_context(environment),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, environment, None, check_limits())
      is Rejected(_),
    )
  }
}

///|
test "Frontend refuses ModelTask facts from a different published environment" {
  let environment = infer_member_environment()
  assert_true(
    @frontend.bind_query_context(
      [],
      @check.checking_environment_cid(check_environment()),
      model_tasks=@check.checking_environment_model_tasks(environment),
    )
    is Err(EnvironmentMismatch),
  )
}

///|
test "independent machine INFER control retains nullable member contracts" {
  // This Program is authored directly from common infer/key/expression
  // contracts. It is not a compiler dump or an INFER-specific evaluator.
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.infer_member_control","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"unit":{"type":"number","nullable":false}},"rows":[{"unit":0}]},"as":"seed"},{"derive":{"id":{"literal":"a"}}},{"select":["id"]},{"distinct":["id"]},{"derive":{"text":{"literal":"urgent"}}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"outcomes"},{"derive":{"assessment":{"object":{"input_key":{"object":{"id":{"field":"id"}}},"outcome":{"field":"outcome"},"value":{"field":"value"}}}}},{"select":["assessment"]},{"derive":{"risk":{"property":{"name":"risk","value":{"property":{"name":"value","value":{"field":"assessment"}}}}},"reason":{"property":{"name":"reason","value":{"property":{"name":"value","value":{"field":"assessment"}}}}}}},{"select":["risk","reason"],"as":"final"}],"results":{"rows":{"from":"final","fields":["risk","reason"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      control,
      infer_member_environment(),
      None,
      check_limits(),
    ) {
    Checked(checked) => {
      let pipeline = @check.unit_pipeline(checked, 0).unwrap()
      let output = @pipeline.output_carrier(pipeline).unwrap()
      let rows = @carrier.complete_schema(
        @carrier.relation_rows(output).unwrap(),
      ).unwrap()
      let risk = @schema.lookup_reference(rows, "risk").unwrap()
      let reason = @schema.lookup_reference(rows, "reason").unwrap()
      assert_true(risk.contract.nullable)
      assert_true(reason.contract.nullable)
      assert_true(risk.contract.shape is @contract.Text(_))
      // Schema field indices are canonical reference order, not authored
      // projection order (relation_schema::field_at). Result fields below
      // retain the declared risk/reason order independently.
      assert_eq(@schema.field_count(rows), 2)
      assert_true(
        semantic(control).contains("\"fields\":[\"risk\",\"reason\"]"),
      )
    }
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
          fail("machine control pipeline: " + @debug.to_string(issue.kind))
        Source(SourceView(Context(Stages(Capacity(stage, visit, issue))))) =>
          fail(
            "machine control capacity " +
            stage.to_string() +
            "/" +
            visit.to_string() +
            " " +
            @debug.to_string(issue),
          )
        Source(issue) => raise issue
        other => raise other
      }
    NeedsInputs(_) => fail("closed JSON control must check")
  }
}
