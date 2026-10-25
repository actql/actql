///|
fn binding_check_environment() -> @checked.CheckEnvironment {
  // Reuse the independently pinned, installed Table environment fixture.
  // These source-free checks do not admit a Run or invoke a provider.
  let wire = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:5e08bd4afedbd52e332bff556d21ae024806b40acfdff7d683c63fbfd9c12576\",\"commands\":[],\"connector_id\":\"table\",\"connector_version\":\"fixture\",\"contracts\":[],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[]}],\"connector_manifest\":{\"connectors\":[{\"connector\":\"table\",\"connector_id\":\"table\",\"connector_version\":\"fixture\"}],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[{\"connector_manifest_cid\":\"sha256:a1a3727735c1e6af17286d33e4eccf591d11821edb1fbed9bb963284027b9874\",\"conversions\":[],\"mapping_contract_cid\":\"sha256:112eeda664d4f10b1a5c827b49ff301c42366fc831b381919036d2cf81591f1b\",\"mapping_ref\":\"mapping:table.catalog.v1\",\"minimum_approval\":\"required\",\"permission_rules\":[{\"effect_kind\":\"store\",\"permissions\":[\"scope:store\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}],\"primary_identity\":\"Id\",\"required_fields\":[],\"required_permissions\":[],\"resource_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"row_mapping\":{\"Name\":{\"field\":\"id\",\"null_behavior\":\"reject\"}},\"schema\":\"actql.mapping_contract/0.1\",\"target_ref\":\"connector://table/catalog\",\"target_schema\":{\"additional_properties\":false,\"fields\":{\"Id\":{\"nullable\":false,\"type\":\"number\"},\"Name\":{\"nullable\":true,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"},\"target_schema_identity\":\"sha256:c000fb12383456a0e123e74501d164b96bb886251dbb44f301661070321be8e0\",\"version\":\"reference-v1\",\"writable_fields\":[\"Name\"]}],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  @host.admit_client_check_environment(
    wire,
    "sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn binding_check_report(text : String, format : String) -> String {
  client_program_check_source(
    text,
    format,
    binding_check_environment(),
    "{\"environmentCid\":\"sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc\",\"aliases\":[]}",
    None,
    None,
    "ctx:binding",
    "rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    None,
    None,
    "corr:binding",
    "bound_input",
    None,
  )
}

///|
test "Source request preparation refuses partial forms without misclassifying budgets or foreign owners" {
  let cases : Array[(@query.BindingPreparationIssue, String?, String?)] = [
    (SourceRequestForm(PartialCorrelation), None, Some("invalid")),
    (SourceRequestForm(WorkLimit), None, Some("undetermined")),
    (SourceRequestForm(InvalidLimits), Some("check_context_invalid"), None),
    (SourceRequestForm(ForeignRequests), None, Some("undetermined")),
  ]
  for (issue, failure, verdict) in cases {
    let findings : Array[CheckFinding] = []
    assert_eq(
      check_binding_preparation_findings(findings, issue, BoundInput),
      failure,
    )
    match verdict {
      None => assert_eq(findings.length(), 0)
      Some(expected) => assert_eq(check_verdict(findings), expected)
    }
    assert_true(!findings.iter().any(finding => finding is Unresolved(_)))
  }
}

///|
test "public check retains the common unused WITH arithmetic input violation" {
  for format in ["sql", "aql-text"] {
    let report = binding_check_report(
      "WITH unused AS (SELECT 1 + 'text' AS invalid) SELECT 1 AS id", format,
    )
    // Only the public outcome is emitted for the focused wire/SDK consumer.
    println("ACTQL_BINDING_CHECK_REPORT " + report)
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    // Preserve the original domain requirement, not a guessed scalar type.
    assert_true(
      report.contains("\"code\":\"expression_domain_mismatch\""),
      msg=report,
    )
    assert_true(
      report.contains("\"domain\":\"key_comparable_operands\""),
      msg=report,
    )
    assert_true(!report.contains("\"expected_type\""), msg=report)
    assert_true(!report.contains("\"location\""), msg=report)
    assert_true(!report.contains("\"pointer\""), msg=report)
  }
}

///|
test "public check retains a closed scalar type reason from binding preparation" {
  for format in ["sql", "aql-text"] {
    let report = binding_check_report(
      "WITH unused AS (SELECT 1 / 'text' AS invalid) SELECT 1 AS id", format,
    )
    // Only the public outcome is emitted for the focused wire/SDK consumer.
    println("ACTQL_BINDING_CHECK_REPORT " + report)
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(
      report.contains("\"code\":\"expression_type_mismatch\""),
      msg=report,
    )
    assert_true(report.contains("\"expected_type\":\"number\""), msg=report)
    assert_true(!report.contains("\"location\""), msg=report)
  }
}

///|
test "public check projects Graph range aliases as query invalid" {
  for format in ["sql", "aql-text"] {
    let report = binding_check_report(
      "WITH n AS (SELECT 1 AS id), g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES))) FROM GRAPH g AS r |> MATCH WALK (a:Node) |> SELECT a.id",
      format,
    )
    // Only the public outcome is emitted for the focused wire/SDK consumer.
    println("ACTQL_BINDING_CHECK_REPORT " + report)
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(report.contains("\"code\":\"query_invalid\""), msg=report)
    assert_true(!report.contains("\"location\""), msg=report)
  }
}

///|
test "binding preparation preserves budgets configuration and internal uncertainty" {
  let source = private_binding_source("hidden/one", "secret-one")
  let budget = binding_local_failure(source, 0)
  guard budget is BudgetExceeded else {
    fail("the original topology budget must fail")
  }
  let declaration_budget = match
    @sourceview_input.collect(source, { max_work: 0, max_order_keys: 16, }) {
    Err(issue) => issue
    Ok(_) => fail("the original declaration collection budget must fail")
  }
  guard @context.local_program_diagnostic_issue(budget)
    is Program(source_budget) else {
    fail("the diagnostic wrapper must retain its original program cause")
  }
  let limits : Array[@query.BindingPreparationIssue] = [
    Demand(WorkLimit),
    LocalProgram(budget),
    SourceProgram(source_budget),
    SourceDeclarations(declaration_budget),
    SourceRegistration(
      @context.source_declaration_diagnostic_issue(declaration_budget),
    ),
  ]
  for issue in limits {
    let findings : Array[CheckFinding] = []
    assert_true(
      check_binding_preparation_findings(findings, issue, BoundInput) is None,
    )
    assert_eq(check_verdict(findings), "undetermined")
    assert_true(findings[:] is [Limit("analysis_budget_exhausted")])
  }
  let invalid = binding_local_failure(source, -1)
  guard invalid is InvalidLimits else {
    fail("the original topology settings must fail")
  }
  guard @context.local_program_diagnostic_issue(invalid)
    is Program(source_invalid) else {
    fail("the diagnostic wrapper must retain its original settings cause")
  }
  for issue in [@query.LocalProgram(invalid), SourceProgram(source_invalid)] {
    let findings : Array[CheckFinding] = []
    assert_eq(
      check_binding_preparation_findings(findings, issue, BoundInput),
      Some("check_context_invalid"),
    )
    assert_eq(findings.length(), 0)
  }
  for
    issue in [
      @query.Demand(ForeignStage),
      Demand(InvalidRange),
      Demand(MissingImport),
    ] {
    let findings : Array[CheckFinding] = []
    assert_eq(
      check_binding_preparation_findings(findings, issue, BoundInput),
      Some("check_internal"),
    )
    assert_eq(findings.length(), 0)
  }
  let findings : Array[CheckFinding] = []
  assert_true(
    check_binding_preparation_findings(
      findings,
      Declarations(ForeignSteps),
      BoundInput,
    )
    is None,
  )
  assert_eq(check_verdict(findings), "undetermined")
  assert_true(findings[:] is [Limit("check_unclassified")])
}

///|
fn private_binding_source(
  connector : String,
  resource : String,
) -> @stage_parameters.Source {
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"a\",\"inputs\":{\"private_alias\":{\"connector\":\"" +
    connector +
    "\",\"resource\":\"" +
    resource +
    "\"}},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
    {
      source: { max_input_bytes: 65536, max_nodes: 1024, max_depth: 64, },
      tree: {
        max_nodes: 1024,
        max_depth: 64,
        max_string_bytes: 65536,
        max_total_string_bytes: 65536,
      },
      max_stages: 4,
    },
    format=Json,
  ).unwrap()
  @stage_parameters.prepare(program, {
    max_parameters: 0,
    max_nodes: 1024,
    max_depth: 64,
    max_text_bytes: 65536,
  }).unwrap()
}

///|
fn private_binding_declaration(
  connector : String,
  resource : String,
) -> @sourceview_input.Declaration {
  let inputs = @sourceview_input.collect(
    private_binding_source(connector, resource),
    { max_work: 100000, max_order_keys: 16, },
  ).unwrap()
  @sourceview_input.at(inputs, 0).unwrap()
}

///|
fn binding_local_failure(
  source : @stage_parameters.Source,
  work : Int,
) -> @effect_results.LocalProgramIssue raise {
  match
    @effect_results.check_local_program(source, {
      max_stages: 4,
      max_steps: 16,
      max_results: 16,
      max_work: work,
      max_nodes: 1024,
      max_tokens: 1024,
      max_text_bytes: 65536,
      max_depth: 64,
    }) {
    Err(issue) => issue
    Ok(_) =>
      fail("this topology probe must reject its original budget or settings")
  }
}

///|
test "missing private Catalog metadata cannot disclose a Source or erase independent violations" {
  for
    (connector, resource) in [
      ("hidden/one", "secret-one"),
      ("hidden/two", "secret-two"),
    ] {
    let declaration = private_binding_declaration(connector, resource)
    let findings : Array[CheckFinding] = []
    assert_true(
      check_binding_preparation_findings(
        findings,
        MissingSourceCatalog(declaration),
        BoundInput,
      )
      is None,
    )
    assert_true(findings[:] is [Unresolved("source_resolution")])
    assert_eq(check_verdict(findings), "undetermined")
    findings.push(Violation("query_invalid"))
    assert_eq(check_verdict(findings), "invalid")
    assert_true(
      findings[:]
      is [Unresolved("source_resolution"), Violation("query_invalid")],
    )
  }
}

///|
test "public zero sequence window retains the common input rejection" {
  let text = "WITH records AS (SELECT 1 AS id, 0 AS occurred_ms, 1 AS kind UNION ALL SELECT 2, 10, 2), matches AS (FROM records AS e |> sequence(by: [], id: e.id, time: e.occurred_ms, pattern: [{as: first, where: e.kind = 1}, {as: second, where: e.kind = 2}], within: 0, overlap: 'disallow', contiguity: 'adjacent', max_matches_per_key: 2, max_output_rows: 2)) SELECT first_id, first_time_ms, match_end_ms, match_start_ms, second_id, second_time_ms FROM matches ORDER BY first_id, second_id"
  for format in ["sql", "aql-text"] {
    let report = binding_check_report(text, format)
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(report.contains("\"code\":\"program_invalid\""), msg=report)
    assert_true(!report.contains("\"check_unclassified\""), msg=report)
  }
}

///|
test "Source STORE target omission stays undetermined without namespace authority" {
  for format in ["sql", "aql-text"] {
    let report = binding_check_report(
      "SELECT 1 AS id |> EFFECT STORE hidden.objects", format,
    )
    assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
    assert_true(!report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(!report.contains("\"verdict\":\"verified\""), msg=report)
    assert_true(!report.contains("check_internal"), msg=report)
  }
}
