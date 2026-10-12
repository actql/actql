///|
// The existing environment contract orders evidence sections by whole-member
// canonical CID, as does rowSourceCheckEnvironment. This constructs inputs;
// it supplies no expectation for a Source observation or Model result.
fn original_keyed_environment_members(
  bodies : Array[String],
) -> Json raise {
  let ordered = bodies.map(body => {
    let wire = @identity.stringify_value(
      @identity.from_json(@json.parse(body), 100000, 100, 1000000),
      1000000,
      100000,
      100,
    )
    (@sha.hex(@utf8.encode(wire)), wire)
  })
  ordered.sort_by((left, right) => left.0.compare(right.0))
  @json.parse("[" + ordered.map(value => value.1).join(",") + "]")
}

///|
// Inputs mirror the existing finite file-listing/content declaration fixtures.
// Declaration generation builds test inputs, never expected output/custody.
fn original_keyed_declaration_environment() -> (
  @row_source_host.RowDeclaration,
  String,
) raise {
  let listing = "{\"media_type\":{\"nullable\":true,\"type\":\"string\"},\"modified_at\":{\"nullable\":true,\"type\":\"timestamp\"},\"name\":{\"nullable\":false,\"type\":\"string\"},\"path\":{\"nullable\":true,\"type\":\"string\"},\"resource\":{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"},\"size_bytes\":{\"nullable\":true,\"type\":\"number\"},\"version\":{\"nullable\":false,\"type\":\"string\"}}"
  let content = "{\"content\":{\"media_type\":\"application/pdf\",\"nullable\":false,\"type\":\"content_ref\"},\"resource\":{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"},\"version\":{\"nullable\":false,\"type\":\"string\"}}"
  let listed : @row_source_host.RowRelationViewSpec = {
    resource: "files",
    resource_kind: "file",
    schema_wire: listing,
    schema_cid: "sha256:" + @sha.hex(@utf8.encode(listing)),
    request_schema_wire: Some(
      "{\"additional_properties\":false,\"fields\":{\"glob\":{\"nullable\":true,\"type\":\"string\"},\"paths\":{\"items\":{\"nullable\":false,\"type\":\"string\"},\"max_items\":8,\"nullable\":true,\"type\":\"array\"}},\"nullable\":false,\"type\":\"object\"}",
    ),
    facts_wire: None,
    acquisition_wire: None,
  }
  let fetched : @row_source_host.RowRelationViewSpec = {
    resource: "contents",
    resource_kind: "file",
    schema_wire: content,
    schema_cid: "sha256:" + @sha.hex(@utf8.encode(content)),
    request_schema_wire: Some(
      "{\"additional_properties\":false,\"fields\":{\"resource\":{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"},\"version\":{\"nullable\":false,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"}",
    ),
    facts_wire: None,
    acquisition_wire: Some(
      "{\"authority\":\"read_content\",\"correlation\":{\"cardinality\":\"one\",\"identity\":[\"resource\",\"version\"],\"request_fields\":[\"resource\",\"version\"],\"response_fields\":[\"resource\",\"version\"]},\"kind\":\"fetch\"}",
    ),
  }
  let limits : @row_source_host.RowDeclarationLimits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
    max_views: 2,
    max_fields: 20,
  }
  let initial = @row_source_host.generate_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    [listed, fetched],
    limits,
  ).unwrap()
  let listing_schema = initial.views.filter(view => view.resource == "files")[0].carrier_schema_cid
  let content_schema = initial.views.filter(view => view.resource == "contents")[0].carrier_schema_cid
  let listed = {
    ..listed,
    facts_wire: Some(
      "{\"file_listing\":{\"admitted_scope_contract_cid\":\"sha256:" +
      "a".repeat(64) +
      "\",\"allow_unfiltered_listing\":true,\"kind\":\"file_listing\",\"listing_schema_contract_cid\":\"" +
      listing_schema +
      "\",\"max_examined_items\":9,\"max_listing_bytes\":32768,\"max_listing_duration_ms\":10000,\"max_listing_items\":3,\"max_listing_pages\":4,\"max_request_attempts\":4,\"maximum_path_length\":64,\"selectable\":[\"paths\",\"glob\"],\"version\":\"actql-file-list/0.1\",\"version_capability\":{\"contract_cid\":\"sha256:" +
      "b".repeat(64) +
      "\",\"required_nonnull\":true}}}",
    ),
  }
  let fetched = {
    ..fetched,
    facts_wire: Some(
      "{\"file_content\":{\"admitted_scope_contract_cid\":\"sha256:" +
      "a".repeat(64) +
      "\",\"content_schema_contract_cid\":\"" +
      content_schema +
      "\",\"kind\":\"file_content\",\"representation\":\"exact_stored_bytes\",\"version\":\"actql-file-content/0.1\",\"version_capability\":{\"contract_cid\":\"sha256:" +
      "b".repeat(64) +
      "\",\"required_nonnull\":true}},\"lookup_capacity\":{\"completeness\":\"complete_per_requested_key\",\"max_pages_per_request\":2,\"max_response_bytes_per_page\":4096,\"max_rows_per_key\":1,\"version\":\"actql-lookup-capacity/0.1\"}}",
    ),
  }
  let declaration = @row_source_host.generate_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    [listed, fetched],
    limits,
  ).unwrap()
  let parsed = @json.parse(source_query_original_environment)
  guard parsed is Object(base) else { abort("fixture environment object") }
  base.remove("evidence_bundle_cid")
  let (schemas, capabilities) = @row_source_host.row_declaration_evidence_members(
    declaration,
  )
  base["connector_catalogs"] = @json.parse("[" + declaration.catalog + "]")
  base["contract_registry"] = original_keyed_environment_members(
    declaration.contracts,
  )
  base["source_views"] = original_keyed_environment_members(
    declaration.view_bodies,
  )
  base["schema_snapshots"] = original_keyed_environment_members(schemas)
  base["connector_capabilities"] = original_keyed_environment_members(
    capabilities,
  )
  base["connector_manifest"] = @json.parse(
    "{\"connectors\":[" +
    declaration.manifest_entry +
    "],\"version\":\"actql-connectors/0.1\"}",
  )
  base["mapping_contracts"] = @json.parse("[]")
  guard base["host_policy_profile"] is Object(policy) else {
    abort("fixture Host policy")
  }
  policy["lookup_execution"] = @json.parse(
    "{\"max_network_attempts_per_request\":3,\"max_request_bytes_per_attempt\":4096,\"max_total_decoded_response_bytes\":32768,\"max_total_duration_ms\":30000,\"max_total_request_bytes\":32768,\"max_total_response_bytes\":32768,\"version\":\"actql-lookup-execution-policy/0.1\"}",
  )
  let wire = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  let cid = "sha256:" + @sha.hex(@utf8.encode(wire))
  base["evidence_bundle_cid"] = @json.parse("\"" + cid + "\"")
  (
    declaration,
    @identity.stringify_value(
      @identity.from_json(parsed, 100000, 100, 1000000),
      1000000,
      100000,
      100,
    ),
  )
}

///|
fn original_keyed_run_fixture() -> (
  @row_source_host.RowDeclaration,
  @publication_host.PreparedClientProgram,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication_host.ClientInferPlanGraph,
  @publication_host.ClientKeyedAcquisition,
  @planning.QueryRequirement,
) raise {
  let (declaration, environment) = original_keyed_declaration_environment()
  let document =
    #|{"version":"actql/0.1","id":"original-keyed-content","stages":[{"id":"capture","inputs":{"contents":{"connector":"content-fixture","resource":"contents"},"files":{"connector":"content-fixture","resource":"files","request":{"paths":["invoice.pdf"],"glob":null}}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"selected"},{"join":{"left":"selected","with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"captured"},{"from":"captured","assert_rows":{"unique_by":["name"]}},{"serialize":{"format":"jsonl","fields":["name","content"],"order_by":[{"name":"asc"}],"name":"captured.jsonl","bounds":{"max_rows":3,"max_bytes":4096}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["name","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"capture","result":"rows"}}}}
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(
    source=true,
    environment_override=Some(environment),
    document_override=Some(document),
    serialization_coordinate=Some((0, 4)),
    serialization_bounds=(3, 4096),
  )
  let keyed = @publication_host.select_client_single_keyed_acquisition(prepared)
    .unwrap()
    .unwrap()
  let (_, direct, _) = @publication_host.client_keyed_direct_acquisition_coordinates(
    keyed,
  ).unwrap()
  let requirement = prepare_local_query_requirement(
    prepared,
    0,
    direct,
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  (declaration, prepared, compiled, definition, plan, keyed, requirement)
}

///|
test "original keyed Direct binding follows the checked resource occurrence before any Row IO" {
  let (declaration, prepared, compiled, definition, plan, keyed, requirement) = original_keyed_run_fixture()
  // The alphabetically first input is contents (keyed), not the Direct files.
  assert_eq(
    @publication_host.client_keyed_direct_acquisition_coordinates(keyed),
    Some((0, 1, 0)),
  )
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let view = @row_source_host.row_declaration_view(
    declaration,
    facts.source_ref,
  ).unwrap()
  let source = @row_source_host.prepare_declared_row_source(
    requirement, "content-fixture", view,
  ).unwrap()
  let acquisition = @row_source_host.prepare_declared_row_acquisition(
    source, "fixture-original-keyed", original_row_query_contract_fixture, original_row_evidence_contract_fixture,
  ).unwrap()
  let (scope, ledger) = original_row_scope(
    compiled,
    definition,
    plan,
    retained_bytes=@row_source_host.row_acquisition_retained_capacity(
        acquisition,
      ) +
      3L,
    execution_bytes=@row_source_host.row_acquisition_execution_capacity(
        acquisition,
      ) +
      2L,
  )
  let verifies = Ref(0)
  let run = start_client_original_keyed_direct_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    acquisition,
    "original-keyed-direct",
    _ => {
      verifies.val += 1
      true
    },
    0L,
    0L,
  ).unwrap()
  assert_eq(verifies.val, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(
    start_client_original_keyed_direct_row_acquisition(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      keyed,
      acquisition,
      "no-reacquisition",
      _ => true,
      0L,
      0L,
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
}

///|
test "original keyed Direct binding rejects a foreign checked selection and issued read without changing usage" {
  let (_, prepared, compiled, definition, plan, keyed, requirement) = original_keyed_run_fixture()
  let (_, foreign, _, _, _, foreign_keyed, foreign_requirement) = original_keyed_run_fixture()
  let (scope, ledger) = original_row_scope(compiled, definition, plan)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @publication_host.borrow_client_original_keyed_direct_ledger(
      scope, compiled, definition, plan, prepared, foreign_keyed, requirement,
    )
    is Err(@publication_host.ForeignRun),
  )
  assert_true(
    @publication_host.borrow_client_original_keyed_direct_ledger(
      scope, compiled, definition, plan, foreign, keyed, foreign_requirement,
    )
    is Err(@publication_host.ForeignRun),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let issued = @resources.ledger_usage(ledger)
  assert_true(
    @publication_host.borrow_client_original_keyed_direct_ledger(
      scope, compiled, definition, plan, prepared, keyed, requirement,
    )
    is Err(@publication_host.Resource(@resources.ChangedOriginalState)),
  )
  assert_eq(@resources.ledger_usage(ledger), issued)
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
}
