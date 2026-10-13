///|
// The environment and snapshot identities below were assembled independently
// with Python SHA-256 over the declared canonical JSON bodies, not product output.
fn scored_snapshot_environment() -> @check.CheckEnvironment {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:dcbf92df12cceb2d1e646b1130d8421a2cebcaff177250025db16746194c9bd7","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[{"output_carrier":"relation","schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"s":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"score_contracts":{"s":{"domain":"Relevance","normalization":"Identity","range":[0,1]}},"source_ref":"source:local/main/right","version":"actql-local-input-schema/0.1"},{"output_carrier":"relation","schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"s":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"score_contracts":{"s":{"domain":"Relevance","normalization":"Identity","range":[0,1]}},"source_ref":"source:local/main/left","version":"actql-local-input-schema/0.1"}],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:dcbf92df12cceb2d1e646b1130d8421a2cebcaff177250025db16746194c9bd7",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  ).unwrap()
  @check.checking_environment(
    wire,
    { text_time: false, veca: true, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile=Some(@numeric.builtin_profile()),
  )
}

///|
fn scored_snapshot_context() -> Context {
  let declaration = from_unpivot_public_cursor(
    "{\"carrier\":\"relation\",\"primary_key\":[\"id\"],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"s\":{\"nullable\":false,\"type\":\"number\"}}}",
  )
  let catalog = @check.source_catalog_contracts(
    @check.prepare_source_catalog(scored_snapshot_environment(), {
      max_work: 1000000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
  )
  {
    ..pair_context(),
    program_id: "fixture.scored_catalog",
    source_catalog: Some(catalog),
    inputs: [
      {
        relation: [{ value: "l", quoted: false, }],
        name: "left",
        source: Captured(declaration),
        visible_fields: ["id", "s"],
        graph_bindings: [],
      },
      {
        relation: [{ value: "r", quoted: false, }],
        name: "right",
        source: Captured(declaration),
        visible_fields: ["id", "s"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn scored_snapshot_checked(program : @program.Program) -> Unit raise {
  match
    @check.check_parsed(
      program,
      scored_snapshot_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) =>
      fail("schema snapshots must retain input schema admission")
  }
}

///|
fn check_scored_snapshot_text(max~ : Bool) -> Unit raise {
  let control_text =
    #|{"id":"fixture.scored_catalog","results":{"answer":{"from":{"result":"rows","stage":"main"}}},"stages":[{"id":"main","inputs":{"left":{"carrier":"relation","primary_key":["id"],"schema":{"id":{"nullable":false,"type":"number"},"s":{"nullable":false,"type":"number"}}},"right":{"carrier":"relation","primary_key":["id"],"schema":{"id":{"nullable":false,"type":"number"},"s":{"nullable":false,"type":"number"}}}},"results":{"rows":{"fields":["id","score","rank"],"from":"out"}},"steps":[{"as":"fused","from":"left","merge_rankings":{"by":[],"candidate":"id","k":3,"score":"s","score_contract":{"domain":"Relevance","normalization":"Identity","range":[0,1]},"score_policy":{"weighted_sum":{"left":0.5,"right":0.5}},"with":"right"}},{"from":"fused","sort":[{"dir":"asc","field":"rank","nulls":"first"}]},{"as":"out","select":["id","score","rank"]}]}],"version":"actql/0.1"}
  let control = @program.parse(
    if max {
      control_text.replace(
        old="{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}",
        new="\"max\"",
      )
    } else {
      control_text
    },
    construction_limits().program,
    format=Json,
  ).unwrap()
  scored_snapshot_checked(control)
  let source = "FROM l |> merge_rankings(with: r, by: [], candidate: id, score: s, k: 3, score_policy: {weighted_sum: {left: 0.5, right: 0.5}}, score_contract: {domain: 'Relevance', range: [0, 1], normalization: 'Identity'}) |> SELECT id, score, rank |> ORDER BY rank"
  let source = if max {
    source.replace(old="{weighted_sum: {left: 0.5, right: 0.5}}", new="'max'")
  } else {
    source
  }
  for
    text in [
      source,
      "WITH fused AS (" +
      source +
      ") SELECT id, score, rank FROM fused ORDER BY rank",
    ] {
    let actual = match
      @frontend.lower(text, Text, Some(scored_snapshot_context())) {
      Ok(value) => value.program.unwrap()
      Err(
        QueryLowering(
          BindingPreparation(
            SourceProgram(Program(Pipeline(index, issue)))
            | LocalProgram(Pipeline(index, issue))
          )
        )
      ) =>
        fail(
          "scored text pipeline " +
          index.to_string() +
          ": " +
          @debug.to_string(issue.kind),
        )
      Err(
        QueryLowering(
          BindingPreparation(
            SourceRegistration(
              LocalInputs(
                Environment(_, Snapshots(Resolution(UnknownInput(stage, name))))
              )
            )
          )
        )
      ) => fail("snapshot refers to absent prefix input " + stage + "/" + name)
      Err(
        QueryLowering(
          BindingPreparation(
            SourceRegistration(LocalInputs(UnknownStage(_, stage)))
          )
        )
      ) => fail("snapshot refers to absent prefix stage " + stage)
      Err(QueryLowering(BindingPreparation(SourceRegistration(_)))) =>
        fail("scored text: source registration")
      Err(QuerySyntax(_)) => fail("scored text: parser")
      Err(QueryLowering(UnsupportedGraph)) =>
        fail(
          "scored text: ordinary compile bypassed the existing Carrier owner",
        )
      Err(QueryLowering(UnknownColumn)) => fail("scored text: unknown column")
      Err(QueryLowering(UnknownRelation)) =>
        fail("scored text: unknown relation")
      Err(_) => fail("scored text: other typed lowering refusal")
    }
    scored_snapshot_checked(actual)
    assert_eq(
      @json.parse(with_carrier_argument(actual, "merge_rankings")),
      @json.parse(with_carrier_argument(control, "merge_rankings")),
    )
    assert_eq(semantic(actual).split("\"merge_rankings\":").length(), 2)
    let body = @json.parse(semantic(actual))
    guard body is Object(root) && root.get("stages") is Some(Array(stages)) else {
      fail("ordinary stage array")
    }
    assert_eq(stages.length(), 1)
    guard stages[0] is Object(stage) &&
      stage.get("inputs") is Some(Object(inputs)) else {
      fail("declared local inputs")
    }
    assert_eq(inputs.length(), 2)
    guard @json.parse(semantic(control)) is Object(control_root) &&
      control_root.get("stages") is Some(Array(control_stages)) &&
      control_stages[0] is Object(control_stage) &&
      control_stage.get("inputs") is Some(_) else {
      fail("independent input oracle")
    }
    assert_eq(stage.get("inputs"), control_stage.get("inputs"))
    assert_true(inputs.get("left") is Some(_))
    assert_true(inputs.get("right") is Some(_))
  }
}

///|
test "weighted score snapshots reach flat and WITH text through the ordinary checker" {
  check_scored_snapshot_text(max=false)
}

///|
test "max score snapshots reach flat and WITH text through the ordinary checker" {
  check_scored_snapshot_text(max=true)
}
