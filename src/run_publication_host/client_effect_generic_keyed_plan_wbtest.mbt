///|
// Real checked file-content Source declaration with content_ref Carrier DATA.
// No Native read profile or provider/Store success is manufactured here.
fn generic_file_effect_fixture(
  whole? : Bool = false,
  lookup_bytes? : Int = 32768,
  installed_rows? : Bool = false,
) -> (
  PreparedClientEffectComputation,
  ClientKeyedAcquisition,
  @row_host.RowDeclaration,
) raise {
  let files = "{\"path\":{\"nullable\":false,\"type\":\"string\"},\"resource\":{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"},\"version\":{\"nullable\":false,\"type\":\"string\"}}"
  let contents = "{\"content\":{\"nullable\":false,\"type\":\"content_ref\"},\"media_type\":{\"nullable\":false,\"type\":\"string\"},\"path\":{\"nullable\":false,\"type\":\"string\"},\"resource\":{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"},\"version\":{\"nullable\":false,\"type\":\"string\"}}"
  let specs : Array[@row_host.RowRelationViewSpec] = [
    {
      resource: "files",
      resource_kind: "file",
      schema_wire: files,
      schema_cid: "sha256:" + @sha.text_hex(files).unwrap(),
      request_schema_wire: None,
      facts_wire: None,
      acquisition_wire: None,
    },
    {
      resource: "contents",
      resource_kind: "file",
      schema_wire: contents,
      schema_cid: "sha256:" + @sha.text_hex(contents).unwrap(),
      request_schema_wire: Some(
        "{\"additional_properties\":false,\"fields\":{\"resource\":{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"},\"version\":{\"nullable\":false,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"}",
      ),
      facts_wire: None,
      acquisition_wire: Some(
        "{\"authority\":\"read_content\",\"correlation\":{\"cardinality\":\"one\",\"identity\":[\"resource\",\"version\"],\"request_fields\":[\"resource\",\"version\"],\"response_fields\":[\"resource\",\"version\"]},\"kind\":\"fetch\"}",
      ),
    },
  ]
  let limits : @row_host.RowDeclarationLimits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
    max_views: 2,
    max_fields: 10,
  }
  let initial = @row_host.generate_relation_row_declaration(
    "local-files",
    "local",
    "local/0.1",
    specs,
    limits,
    classifications=Some([@environment.Internal, @environment.Internal]),
  ).unwrap()
  let facts : Json = {
    "file_content": {
      "version": "actql-file-content/0.1",
      "kind": "file_content",
      "admitted_scope_contract_cid": "sha256:" + "a".repeat(64),
      "content_schema_contract_cid": initial.views[1].carrier_schema_cid,
      "version_capability": {
        "contract_cid": "sha256:" + "b".repeat(64),
        "required_nonnull": true,
      },
      "representation": "exact_stored_bytes",
    },
    "lookup_capacity": {
      "version": "actql-lookup-capacity/0.1",
      "completeness": "complete_per_requested_key",
      "max_rows_per_key": 1,
      "max_pages_per_request": 2,
      "max_response_bytes_per_page": 4096,
    },
  }
  let declaration = @row_host.generate_relation_row_declaration(
    "local-files",
    "local",
    "local/0.1",
    [specs[0], { ..specs[1], facts_wire: Some(facts.stringify()), }],
    limits,
    classifications=Some([@environment.Internal, @environment.Internal]),
  ).unwrap()
  let declaration = if installed_rows {
    @row_host.bind_installed_row_read_profile(
      declaration,
      declaration.views[1].source_ref,
    ).unwrap()
  } else {
    declaration
  }
  let document =
    #|{"version":"actql/0.1","id":"generic-file-effect","stages":[{"id":"capture","inputs":{"files":{"connector":"local-files","resource":"files"},"remote":{"connector":"local-files","resource":"contents"}},"steps":[{"from":"files","filter":"path <> ''"},{"select":["resource","version","path"],"as":"left"},{"from":"left","join":{"with":"remote","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"path":"left.path","content":"right.content"}},"as":"joined"},{"derive":{"value":{"literal":1}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"capture","result":"out"}}}}
  let document = if whole {
    document.replace(
      old="\"steps\":[{\"from\":\"files\",\"filter\":\"path <> ''\"},{\"select\":[\"resource\",\"version\",\"path\"],\"as\":\"left\"},{\"from\":\"left\",\"join\":",
      new="\"steps\":[{\"from\":\"files\",\"join\":",
    )
  } else {
    document
  }
  let base = whole_row_environment(declaration)
  let emitted = @encode.writer(1000000, 100000, 100)
  @environment.emit(@checked.checking_environment_wire(base), emitted)
  guard @json.parse(@encode.finish(emitted)) is Object(fields) &&
    fields["host_policy_profile"] is Object(policy) else {
    fail("generic Host policy")
  }
  fields.remove("evidence_bundle_cid") |> ignore
  let (_, effect, _) = client_composed_effect_base_fixture()
  let effect_writer = @encode.writer(1000000, 100000, 100)
  @environment.emit(@checked.checking_environment_wire(effect), effect_writer)
  guard @json.parse(@encode.finish(effect_writer)) is Object(effect_fields) &&
    fields["connector_catalogs"] is Array(catalogs) &&
    effect_fields["connector_catalogs"] is Array(effect_catalogs) &&
    fields["connector_manifest"] is Object(manifest) &&
    manifest["connectors"] is Array(connectors) else {
    fail("generic Effect mapping")
  }
  fields["mapping_contracts"] = effect_fields["mapping_contracts"]
  for catalog in effect_catalogs {
    catalogs.push(catalog)
  }
  connectors.push(
    @json.parse(
      "{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\"}",
    ),
  )
  policy["lookup_execution"] = @json.parse(
    "{\"max_network_attempts_per_request\":3,\"max_request_bytes_per_attempt\":4096,\"max_total_decoded_response_bytes\":" +
    lookup_bytes.to_string() +
    ",\"max_total_duration_ms\":30000,\"max_total_request_bytes\":" +
    lookup_bytes.to_string() +
    ",\"max_total_response_bytes\":" +
    lookup_bytes.to_string() +
    ",\"version\":\"actql-lookup-execution-policy/0.1\"}",
  )
  let unsigned = @canonical.from_json(
    Json::object(fields),
    100000,
    100,
    1000000,
  )
  let cid = @canonical.cid_value(unsigned, 1000000, 100000, 100)
  let environment = admit_client_check_environment(
    @canonical.stringify_value(
      @canonical.object_with_string_field(unsigned, "evidence_bundle_cid", cid).unwrap(),
      1000000,
      100000,
      100,
    ),
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let owner = match
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(Candidate(@checked.Computation(issue))) => raise issue
    Err(Graph(issue)) => fail("generic graph " + @debug.to_string(issue))
    Err(Candidate(_)) => fail("generic candidate")
    Err(Syntax(_)) => fail("generic syntax")
    Err(Static(issue)) =>
      match issue {
        @stage_results.InvalidLimits => fail("generic static limits")
        @stage_results.MemberLimit => fail("generic static member limit")
        @stage_results.ForeignEnvironment => fail("generic static environment")
        @stage_results.WorkLimit => fail("generic static work")
        @stage_results.Results(_) => fail("generic static results")
        @stage_results.MappingShapes(_) => fail("generic static mapping shape")
        @stage_results.MappingRules(_) => fail("generic static mapping rules")
        @stage_results.MappingLiterals(_) =>
          fail("generic static mapping literals")
        @stage_results.CommandTargets(_) =>
          fail("generic static command target")
        @stage_results.CommandInputs(_) => fail("generic static command input")
        @stage_results.IncompleteInventory => fail("generic static inventory")
      }
    Err(Stage(_)) => fail("generic stage")
    Err(_) => fail("generic preparation")
  }
  let keyed = select_client_effect_single_keyed_acquisition(owner)
    .unwrap()
    .unwrap()
  (owner, keyed, declaration)
}

///|
test "generic Source-only keyed compiler retains real file-content inputs without a Native profile" {
  let (owner, keyed, declaration) = generic_file_effect_fixture()
  assert_true(
    @row_host.row_declaration_file_read_profile(
      declaration,
      declaration.views[1].source_ref,
    )
    is None,
  )
  let measured = measure_client_effect_generic_keyed_plan_construction(
    owner,
    keyed,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let graph = issue_client_effect_keyed_plan_graph(
    measured, 1000000, 100000, 100,
  ).unwrap()
  assert_true(client_effect_keyed_plan_graph_is_generic(graph))
  assert_true(client_effect_keyed_plan_graph_matches(graph, owner, keyed))
  guard graph.component is GenericKeyedPlan(component) else {
    fail("generic original")
  }
  assert_true(physical_equal(component.original.fragments.acquisition, keyed))
  assert_true(component.barrier.wire.contains("actql-lookup/0.1"))
  assert_true(
    @encode.document_text(component.barrier_body).contains("resource"),
  )
  assert_false(
    component.barrier.wire.contains("actql-native-file-content-read"),
  )
  assert_eq(graph.graph_nodes.length(), 3)
  let foreign = generic_file_effect_fixture().0
  assert_false(client_effect_keyed_plan_graph_matches(graph, foreign, keyed))
  assert_true(
    measure_client_effect_generic_keyed_plan_construction(
      foreign,
      keyed,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Err(UnsupportedProgram),
  )
  let native_geometry = prepared_client_effect_keyed_plan_measurement_storage(
    owner, keyed,
  ).unwrap()
  let generic_geometry = prepared_client_effect_keyed_plan_measurement_storage(
    owner,
    keyed,
    generic=true,
  ).unwrap()
  assert_eq(native_geometry.record_headers, generic_geometry.record_headers)
  assert_eq(
    native_geometry.reference_slots,
    generic_geometry.reference_slots + 1L,
  )
}

///|
test "generic Source-only compiler refuses an unrelated non-file read contract" {
  let (owner, keyed, _) = source_effect_keyed_fixture()
  assert_true(
    measure_client_effect_generic_keyed_plan_construction(
      owner,
      keyed,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Err(ForeignExecution),
  )
}
