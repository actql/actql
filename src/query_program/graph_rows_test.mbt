///|
fn graph_rows_prefix() -> String {
  "DATA n = SELECT 2 AS node_key, 'B' AS name UNION ALL SELECT 1 AS node_key, 'A' AS name; DATA e = SELECT 11 AS edge_key, 1 AS src_key, 2 AS dst_key UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 2 AS dst_key; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (name)) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R NO PROPERTIES)); "
}

///|
fn graph_rows_environment() -> @check.CheckEnvironment {
  @check.checking_environment(
    @environment.read(
      @utf8.encode(
        (
          #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:f7a722e2504c266873a228d46add79847b08daa2ff3a457baa140d08accbd3c6","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
      ),
      "sha256:f7a722e2504c266873a228d46add79847b08daa2ff3a457baa140d08accbd3c6",
      { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
    ).unwrap(),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    graph=true,
    numeric_profile=Some(@numeric.builtin_profile()),
  )
}

///|
fn graph_rows_rejected(diagnostic : @check.CheckDiagnostic) -> Unit raise {
  match @check.diagnostic_cause(diagnostic) {
    Source(SourceView(Program(Program(Pipeline(stage, issue))))) =>
      fail("Pipeline \{stage}: " + @debug.to_string(issue.kind))
    Source(SourceView(Program(Program(Order(stage, _))))) =>
      fail("Result Order \{stage}")
    Source(SourceView(Program(Program(Results(stage, _))))) =>
      fail("Results \{stage}")
    Source(Checks(OperationProfiles(issue))) => fail(@debug.to_string(issue))
    Source(Checks(ExpressionProfiles(issue))) => fail(@debug.to_string(issue))
    Source(Checks(Validation(issue))) => fail(@debug.to_string(issue))
    Source(Checks(Assembly(issue))) => fail(@debug.to_string(issue))
    Source(Checks(TextBounds(_))) => fail("Source Checks TextBounds")
    Source(Checks(Patterns(_))) => fail("Source Checks Patterns")
    Source(Checks(BudgetExceeded)) => fail("Source Checks BudgetExceeded")
    Closure(Requirements(Publications(RowTarget(stage, result, _)))) =>
      fail("Publication row target \{stage}:\{result}")
    Closure(Requirements(Operations(IncompleteResolution(index)))) =>
      fail("Operation incomplete \{index}")
    Closure(UnresolvedOperation(site)) => {
      let kind = match site.requirement {
        @pipeline.RelationRequirement(pending) => @debug.to_string(pending.kind)
        @pipeline.SequenceRowsRequirement(pending) =>
          @debug.to_string(pending.kind)
        @pipeline.SelectorRequirement(_) => "Selector"
        @pipeline.ConstructionRequirement(_) => "Construction"
        @pipeline.ValuesRequirement(_) => "Values"
        @pipeline.AppendRequirement(_) => "Append"
        @pipeline.SequenceRequirement(_) => "Sequence"
        _ => "other"
      }
      fail("Unresolved operation \{site.step}:\{site.index} " + kind)
    }
    cause => raise cause
  }
}

///|
fn graph_rows_check_limits() -> @check.CheckLimits {
  let base = check_limits()
  {
    ..base,
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, steps: 64, },
    },
  }
}

///|
test "Graph row source has an independently authored complete Program" {
  let actual = compile_data_set(
    "DATA n = SELECT 1 AS node_key, 7 AS p; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))); FROM g |> node_rows() |> SELECT p, node_key",
  )
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1},"aql_query_expr_1":{"literal":7}}},{"select":[{"node_key":"aql_query_expr_0"},{"p":"aql_query_expr_1"}],"as":"aql_data_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["node_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","node_rows":true,"as":"aql_sga_3"},{"from":"aql_sga_3","select":["p","node_key"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["p","node_key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Graph row source lowers the existing node bridge and relational suffix" {
  let program = compile_data_set(
    graph_rows_prefix() +
    "FROM g |> node_rows() |> SELECT node_key, name |> WHERE node_key > 0 |> ORDER BY node_key",
  )
  let body = semantic(program)
  assert_true(body.contains("\"node_rows\":true"))
  assert_true(body.contains("\"fields\":[\"node_key\",\"name\"]"))
  match
    @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("Graph rows add no acquisition")
  }
}

///|
test "Graph row DATA alias lowers the existing edge bridge once" {
  let program = compile_data_set(
    graph_rows_prefix() +
    "DATA `rows` = FROM `g` |> edge_rows() |> SELECT edge_key, labels; FROM `rows` |> ORDER BY edge_key",
  )
  let body = semantic(program)
  assert_eq(body.split("\"edge_rows\":true").length(), 2)
  assert_true(body.contains("\"fields\":[\"edge_key\",\"labels\"]"))
  match
    @check.check_parsed_with_evidence(
      program,
      graph_rows_environment(),
      None,
      [],
      graph_rows_check_limits(),
    ) {
    Checked(_) => ()
    Rejected(diagnostic) => graph_rows_rejected(diagnostic)
    NeedsInputs(_) => fail("Graph row DATA adds no acquisition")
  }
}

///|
test "Graph row source rejects invented selection arguments and Carrier changes" {
  for
    suffix in [
      "FROM g |> node_rows(definition: 'N', label: 'Node') |> SELECT id", "FROM g |> edge_rows(extra: true) |> SELECT id",
      "FROM g |> node_rows() |> edge_rows() |> SELECT id", "FROM n |> node_rows() |> SELECT id",
      "FROM g |> node_rows() |> SELECT missing",
    ] {
    let script = @query.parse_query_script(
      graph_rows_prefix() + suffix,
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(_),
      msg=suffix,
    )
  }
}
