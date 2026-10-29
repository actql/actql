///|
// Static caller inputs only: these declarations never issue Source authority.
fn readme_deal_review_environment() -> @check.CheckEnvironment raise {
  let wire = match
    @environment.read(
      @utf8.encode(
        (
          #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:189e570b7553c768f55852ec2f1a36e1386c4c4118ca62efc8578d028e40c648","commands":[],"connector_id":"salesforce","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]},{"catalog_cid":"sha256:a0c3b72a8e54182fb9f852d4c01f9516455c074ca6569e66cd90f33696b19a30","commands":[],"connector_id":"drive","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"salesforce","connector_id":"salesforce","connector_version":"fixture"},{"connector":"drive","connector_id":"drive","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:3497da6024e88702936ae75a95f05fb197c22bd6a0d5f9dcddf7d5f80fab0844","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:9a6a8e56c272ccc2e238e67707085a0ba0eedadee6cbe701670c830ab704459a","conversions":[],"mapping_contract_cid":"sha256:b952a5acf065b108c8fa9ec939c5298bf13c73da0cfe827b4b41445c5bbc47c7","mapping_ref":"mapping:salesforce.deal-review.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["StageName","NextStep"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"NextStep":{"field":"NextStep","null_behavior":"reject"},"StageName":{"field":"StageName","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://salesforce/Opportunity","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"NextStep":{"nullable":true,"type":"string"},"StageName":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1aa681b79a32d9073f1330c36478daabc6a7221c7e504bb397ab15fabc2b9523","version":"fixture","writable_fields":["StageName","NextStep"]}],"model_task_contracts":[{"authored_model_selector":"fixture-deal-review-model","connector_id":"models/fixture","contract_cid":"sha256:c8cb0faf2961b98b3fb9ef9291fe8d6a33ce50d8f3531db81f1c059fe3a32ee9","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"NextStep":{"nullable":true,"type":"string"},"StageName":{"nullable":false,"type":"string"},"notes":{"nullable":false,"type":"content_ref"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:38a67b5f1a41c1e63eacf1f38f426dde5725cd03cb8085900febaa857c9a5936","max_items":2,"output_contract":{"additional_properties":false,"fields":{"changed":{"nullable":false,"type":"boolean"},"next_step":{"nullable":false,"type":"string"},"stage":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:0d05df32d7be6d60f252d58ec6990fc1522ea2f9b7097fe6f5bd4f0746177dd6","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:deal-review.v1","task_kind":"structured_generate","tool_policy":"none","version":"fixture"}],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
      ),
      "sha256:3497da6024e88702936ae75a95f05fb197c22bd6a0d5f9dcddf7d5f80fab0844",
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
    ) {
    Ok(wire) => wire
    Err(issue) => fail("independent environment: " + @debug.to_string(issue))
  }
  let tasks = match
    @environment.check_model_tasks(wire, {
      bodies: {
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
        max_members: 100,
      },
      contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
      max_work: 100000,
    }) {
    Ok(tasks) => tasks
    Err(issue) => fail("independent ModelTask: " + @debug.to_string(issue.kind))
  }
  @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=Some(tasks),
  )
}

///|
fn readme_deal_review_text() -> String {
  (
    #|SELECT o.id AS id, o.StageName, o.NextStep,
    #|       c.content AS notes
    #|FROM salesforce.opportunities AS o
    #|JOIN drive.files AS f ON f.name = o.name
    #|JOIN drive.contents AS c USING (resource, version)
    #||> ASSERT UNIQUE BY (id)
    #||> INFER `model-task:deal-review.v1`
    #|     INPUT (StageName, NextStep, notes) AS review
    #||> WHERE review.outcome = 'ok' AND review.value.changed
    #||> RESULT updates
    #||> EFFECT UPDATE salesforce.Opportunity
    #|     ID id SET (
    #|       StageName = review.value.stage,
    #|       NextStep = review.value.next_step
    #|     );
  )
}

///|
fn readme_deal_review_inputs(proven_keys? : Bool = true) -> Array[Input] {
  let declarations = [
    (
      "salesforce.opportunities",
      (
        #|{"carrier":"relation","primary_key":["id"],"schema":{"NextStep":{"nullable":true,"type":"string"},"StageName":{"nullable":false,"type":"string"},"id":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"}}}
      ),
    ),
    (
      "drive.files",
      (
        #|{"carrier":"relation","primary_key":["id"],"schema":{"id":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}}}
      ),
    ),
    (
      "drive.contents",
      (
        #|{"carrier":"relation","primary_key":["resource","version"],"schema":{"content":{"nullable":false,"type":"content_ref"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}}}
      ),
    ),
  ]
  declarations.map(entry => {
    let source = if proven_keys {
      entry.1
    } else {
      entry.1
      .replace(old="\"primary_key\":[\"id\"],", new="")
      .replace(old="\"primary_key\":[\"account_id\"],", new="")
    }
    let declaration = @wire.admit(
      @source.parse_json(source, construction_limits().source.source).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    {
      relation: @query.parse_relation_path(entry.0, syntax_limits().lexical).unwrap(),
      name: entry.0.replace(old=".", new="_"),
      source: Captured(declaration),
      visible_fields: match entry.0 {
        "salesforce.opportunities" => ["NextStep", "StageName", "id", "name"]
        "drive.files" => ["id", "name", "resource", "version"]
        _ => ["content", "resource", "version"]
      },
      graph_bindings: [],
    }
  })
}

///|
fn readme_deal_review_context(
  environment : @check.CheckEnvironment,
  proven_keys? : Bool = true,
) -> Context {
  {
    ..infer_member_context(environment),
    program_id: "fixture.readme_deal_review",
    captured_stage: None,
    inputs: readme_deal_review_inputs(proven_keys~),
  }
}

///|
fn readme_deal_review_publication(
  environment : @check.CheckEnvironment,
) -> UpdateTargetPublication raise {
  let mappings = match
    @environment.check_mapping_contract_shapes(
      @check.checking_environment_wire(environment),
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
      100000,
    ) {
    Ok(mappings) => mappings
    Err(issue) => fail("independent Mapping: " + @debug.to_string(issue))
  }
  bind_update_target_publication(
    mappings,
    [
      {
        name: [
          { value: "salesforce", quoted: false, },
          { value: "Opportunity", quoted: false, },
        ],
        target_ref: "connector://salesforce/Opportunity",
        installation_binding_cid: "sha256:" + "d".repeat(64),
        installation_owner_cid: "sha256:" + "e".repeat(64),
      },
    ],
    100000,
  ).unwrap()
}

///|
fn readme_deal_review_checked_effect(
  program : @program.Program,
  environment : @check.CheckEnvironment,
) -> @check.EffectProgramStaticCandidate raise {
  let candidate = @check.prepare_effect_computation_candidate(
    program,
    environment,
    None,
    [],
    check_limits(),
    1,
    1000,
  )
  let candidate = match candidate {
    Ok(value) => value
    Err(Computation(Source(SourceView(Program(Program(Pipeline(_, issue))))))) =>
      fail("pipeline: " + @debug.to_string(issue.kind))
    Err(Computation(Source(SourceView(Context(Stages(Capacity(_, _, issue))))))) =>
      fail("capacity: " + @debug.to_string(issue))
    Err(Computation(Source(SourceView(_)))) => fail("other SourceView context")
    Err(Computation(Source(issue))) => raise issue
    Err(Computation(issue)) => raise issue
    Err(_) => fail("candidate preparation")
  }
  let mappings = @environment.check_mapping_contract_shapes(
    @check.checking_environment_wire(environment),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
    100000,
  ).unwrap()
  match
    @check.close_effect_computation_static(candidate, mappings, {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    }) {
    Ok(checked) => checked
    Err(MappingRules(issue)) =>
      fail(
        "hero mapping rules: " +
        @debug.to_string(@stage_results.effect_mapping_rule_issue_kind(issue)),
      )
    Err(MappingShapes(issue)) =>
      fail(
        "hero mapping shape: " +
        @debug.to_string(@stage_results.effect_mapping_shape_issue_kind(issue)),
      )
    Err(Results(issue)) =>
      fail(
        "hero result binding: " +
        @debug.to_string(@stage_results.effect_result_binding_issue_kind(issue)),
      )
    Err(WorkLimit) => fail("hero static work limit")
    Err(_) => fail("hero other static closure refusal")
  }
}

///|
test "current README deal review retains exact defaults and checked UPDATE types" {
  let environment = readme_deal_review_environment()
  let context = readme_deal_review_context(environment)
  let publication = readme_deal_review_publication(environment)
  let source = readme_deal_review_text()
  let explicit = source.replace(
    old="INPUT (StageName, NextStep, notes)",
    new="ITEM KEY (id) INPUT (StageName = StageName, NextStep = NextStep, notes = notes) KEEP (id, StageName, NextStep, notes)",
  )
  let prepare = fn(text) {
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
      update_targets=Some(publication),
    ).unwrap()
  }
  let actual = prepare(source)
  let expanded = prepare(explicit)
  assert_eq(semantic(actual), semantic(expanded))
  let actual_checked = readme_deal_review_checked_effect(actual, environment)
  let expanded_checked = readme_deal_review_checked_effect(
    expanded, environment,
  )
  assert_shorthand_checked_identity(
    @check.effect_program_static_checked_computation(actual_checked),
    @check.effect_program_static_checked_computation(expanded_checked),
  )
  assert_eq(
    @check.effect_program_static_definition_cid(actual_checked),
    @check.effect_program_static_definition_cid(expanded_checked),
  )
  assert_eq(@program.exports(actual).map(value => value.0), ["updates"])
}

///|
test "current README file names cannot manufacture a deal key" {
  let environment = readme_deal_review_environment()
  let source = readme_deal_review_text().replace(
    old="|> ASSERT UNIQUE BY (id)\n",
    new="",
  )
  let result = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    readme_deal_review_context(environment),
    construction_limits(),
    update_targets=Some(readme_deal_review_publication(environment)),
  )
  assert_eq(
    infer_defaults_prefix_refusal(result),
    @pipeline.Infer(@evidence.CandidateKeyRequired),
  )
}
