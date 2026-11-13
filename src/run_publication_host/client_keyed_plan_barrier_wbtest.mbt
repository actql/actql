///|
// Fresh authored compiler input; no Source IO, rows, physical authority or
// expected output is supplied by declaration generation.
fn client_keyed_plan_test_inputs(
  plural? : Bool = false,
  declared? : Bool = false,
  imported_left? : Bool = false,
  joined_producer? : Bool = false,
) -> (
  ClientInferOccurrence,
  ClientKeyedAcquisition,
  @publication.PublicationContract,
) raise {
  let schema = "{\"id\":{\"nullable\":false,\"type\":\"string\"},\"mime\":{\"nullable\":false,\"type\":\"string\"},\"text\":{\"nullable\":false,\"type\":\"string\"},\"version\":{\"nullable\":false,\"type\":\"string\"}}"
  let declaration = @row_host.generate_relation_row_declaration(
    "lookup-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "contents",
        resource_kind: "file",
        schema_wire: schema,
        schema_cid: "sha256:" + @sha.text_hex(schema).unwrap(),
        request_schema_wire: Some(
          "{\"additional_properties\":false,\"fields\":{\"id\":{\"nullable\":false,\"type\":\"string\"},\"tenant\":{\"nullable\":true,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"}",
        ),
        facts_wire: Some(
          "{\"lookup_capacity\":{\"completeness\":\"complete_per_requested_key\",\"max_pages_per_request\":2,\"max_response_bytes_per_page\":4096,\"max_rows_per_key\":1,\"version\":\"actql-lookup-capacity/0.1\"}}",
        ),
        acquisition_wire: Some(
          "{\"authority\":\"read_content\",\"correlation\":{\"cardinality\":\"one\",\"identity\":[\"id\"],\"request_fields\":[\"id\"],\"response_fields\":[\"id\"]},\"kind\":\"fetch\"}",
        ),
      },
      {
        resource: "files",
        resource_kind: "file",
        schema_wire: schema,
        schema_cid: "sha256:" + @sha.text_hex(schema).unwrap(),
        request_schema_wire: None,
        facts_wire: None,
        acquisition_wire: None,
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 2,
      max_fields: 10,
    },
    classifications=Some([@environment.Internal, @environment.Internal]),
  ).unwrap()
  let view = declaration.views.filter(view => view.resource == "contents")[0]
  let (request, response) = @row_host.row_declaration_keyed_read_schema_identities(
    declaration,
    view.source_ref,
  ).unwrap()
  let profile = if declared {
    let bound = @row_host.bind_declared_file_read_profile(
      declaration,
      view.source_ref,
      declaration,
      "files",
      {
        identity: "id",
        name: "id",
        version: "version",
        media_type: "mime",
        content_utf8: "text",
        path: None,
        items_path: ["items"],
        key_path: ["id"],
      },
    ).unwrap()
    @row_host.row_declaration_file_read_profile(bound, view.source_ref).unwrap()
  } else {
    @publication.seal_publication_contract(
      "native_file_content_read",
      "{\"physical_source_view_contract_cid\":\"" +
      (if plural {
        declaration.views.filter(view => view.resource == "files")[0].view_cid
      } else {
        "sha256:" + "b".repeat(64)
      }) +
      "\",\"projection\":{\"content_utf8_field\":\"text\",\"identity_field\":\"id\",\"items_path\":[\"items\"],\"key_path\":[\"id\"],\"media_type_field\":\"mime\",\"name_field\":\"id\",\"path_field\":null,\"version_field\":\"version\"},\"request_schema_cid\":\"" +
      request +
      "\",\"response_schema_cid\":\"" +
      response +
      "\",\"source_view_contract_cid\":\"" +
      view.view_cid +
      "\",\"version\":\"actql-native-file-content-read/0.1\"}",
      16384,
      1024,
      20,
    ).unwrap()
  }
  let (base, _) = client_infer_prefix_test_environment()
  guard @json.parse(base) is Object(fields) else { fail("Model environment") }
  fields.remove("evidence_bundle_cid")
  fields["connector_catalogs"] = @json.parse("[" + declaration.catalog + "]")
  fields["connector_manifest"] = @json.parse(
    "{\"connectors\":[" +
    declaration.manifest_entry +
    "],\"version\":\"actql-connectors/0.1\"}",
  )
  let members = (bodies : Array[String]) => {
    let entries = bodies.map(body => {
      let value = @canonical.from_json(@json.parse(body), 100000, 100, 1000000)
      (@canonical.cid_value(value, 1000000, 100000, 100), value)
    })
    entries.sort_by((a, b) => a.0.compare(b.0))
    @json.parse(
      "[" +
      entries
      .map(entry => @canonical.stringify_value(entry.1, 1000000, 100000, 100))
      .join(",") +
      "]",
    )
  }
  fields["contract_registry"] = members(declaration.contracts)
  fields["source_views"] = members(declaration.view_bodies)
  let (schemas, capabilities) = @row_host.row_declaration_evidence_members(
    declaration,
  )
  fields["schema_snapshots"] = members(schemas)
  fields["connector_capabilities"] = members(capabilities)
  guard fields["connector_capabilities"] is Array(caps) else {
    fail("capabilities")
  }
  for item in caps {
    guard item is Object(cap) && cap["capability_contract_cids"] is Array(ids) else {
      fail("capability")
    }
    ids.push(Json::string(@publication.publication_contract_identity(profile)))
    ids.sort_by((a, b) => a.stringify().compare(b.stringify()))
  }
  guard fields["host_policy_profile"] is Object(policy) else {
    fail("Host policy")
  }
  policy["lookup_execution"] = @json.parse(
    "{\"max_network_attempts_per_request\":3,\"max_request_bytes_per_attempt\":4096,\"max_total_decoded_response_bytes\":32768,\"max_total_duration_ms\":30000,\"max_total_request_bytes\":32768,\"max_total_response_bytes\":32768,\"version\":\"actql-lookup-execution-policy/0.1\"}",
  )
  let unsigned = @canonical.from_json(
    Json::object(fields),
    100000,
    100,
    1000000,
  )
  let cid = @canonical.cid_value(unsigned, 1000000, 100000, 100)
  let wire = @canonical.stringify_value(
    @canonical.object_with_string_field(unsigned, "evidence_bundle_cid", cid).unwrap(),
    1000000,
    100000,
    100,
  )
  let environment = admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"keyed-first-plan","stages":[{"id":"capture","inputs":{"files":{"connector":"lookup-fixture","resource":"files"}},"steps":[{"from":"files","filter":"id <> ''"},{"select":["id","text","mime","version"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","text","mime","version"]}}},{"id":"main","inputs":{"remote":{"connector":"lookup-fixture","resource":"contents","request":{"tenant":"original"}},"left_rows":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"from":"left_rows","filter":"id <> ''","as":"left"},{"from":"left","join":{"with":"remote","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id","text":"right.text"}},"as":"joined"},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let document = if joined_producer {
    guard @json.parse(document) is Object(fields) &&
      fields["stages"] is Array(stages) &&
      stages[0] is Object(producer) &&
      producer["inputs"] is Object(inputs) else {
      fail("joined original producer fixture")
    }
    inputs["right_files"] = @json.parse(
      "{\"connector\":\"lookup-fixture\",\"resource\":\"files\"}",
    )
    producer["from"] = Json::string("files")
    producer["steps"] = @json.parse(
      (
        #|[{"join":{"with":"right_files","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id","text":"right.text","mime":"right.mime","version":"right.version"}},"as":"captured"}]
      ),
    )
    Json::object(fields).stringify()
  } else {
    document
  }
  let document = if imported_left {
    document.replace(
      old="{\"from\":\"left_rows\",\"filter\":\"id <> ''\",\"as\":\"left\"},{\"from\":\"left\",\"join\":",
      new="{\"from\":\"left_rows\",\"join\":",
    )
  } else {
    document
  }
  let document = if plural {
    guard @json.parse(document) is Object(fields) &&
      fields["stages"] is Array(stages) else {
      fail("original keyed authored stages")
    }
    stages.push(
      @json.parse(
        (
          #|{"id":"confirm","inputs":{"reviewed":{"result":{"stage":"main","result":"rows"}}},"from":"reviewed","steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"literal":"confirm original"}}},"as":"confirmed"}],"results":{"rows":{"from":"confirmed","fields":["id","outcome","value"]}}}
        ),
      ),
    )
    fields["results"] = @json.parse(
      (
        #|{"answer":{"from":{"stage":"confirm","result":"rows"}}}
      ),
    )
    Json::object(fields).stringify()
  } else {
    document
  }
  let prepared = match
    prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Check(issue)) => raise @checked.diagnostic_cause(issue)
    Err(Syntax(_)) => fail("original keyed syntax")
    Err(Graph(_)) => fail("original keyed task graph")
    Err(Lowering(_)) => fail("original keyed lowering")
    Err(Binding(_)) => fail("original keyed binding")
    Err(ValuesProfileUnsupported) => fail("original keyed Values profile")
    Err(NeedsInputs(_)) => fail("original keyed missing input")
    Err(_) => fail("original keyed compiler preparation")
  }
  let occurrence = if plural {
    let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
    assert_eq(occurrences.length(), 2)
    occurrences[0]
  } else {
    prepared_client_composed_infer_occurrence(prepared).unwrap()
  }
  let (stage, input, step) = client_composed_keyed_source_coordinates(prepared)
    .unwrap()
    .unwrap()
  let keyed = prepare_client_keyed_acquisition(
    prepared,
    stage,
    input,
    1000000,
    join_step=Some(step),
  ).unwrap()
  (occurrence, keyed, profile)
}

///|
test "actual checked left lookup and joined Fragments retain genuine ports and runtime policy without fake completed input" {
  let (occurrence, keyed, profile) = client_keyed_plan_test_inputs()
  let input = prepare_client_keyed_plan_fragment_inputs(
    occurrence,
    keyed,
    client_standard_values_sequence_limits(),
    100000,
  ).unwrap()
  let (left_geometry, joined_geometry) = measure_client_keyed_plan_fragments(
    input, 1000000, 100000, 100,
  ).unwrap()
  let (left, joined) = issue_client_keyed_plan_fragments(
    input, 1000000, 100000, 100,
  ).unwrap()
  for (fragment, geometry) in [(left, left_geometry), (joined, joined_geometry)] {
    let actual = content_construction_geometry(fragment.wire)
    assert_true(
      actual.0 <= geometry.fragment.0 &&
      actual.1 <= geometry.fragment.1 &&
      actual.2 <= geometry.fragment.2,
    )
  }
  let left_node = parse_plan_identity_value(left.wire, 1000000, 100000, 100).unwrap()
  assert_eq(
    @canonical.object_field_count(
      @canonical.object_field(left_node, "input_contracts").unwrap(),
    ),
    Some(1),
  )
  let original = prepare_client_keyed_plan_barrier_input(
    input, profile, 1000000, 1000000, 100000, 100,
  ).unwrap()
  let (barrier, original_body) = issue_client_keyed_plan_barrier(
    original, left, 1000000, 100000, 100,
  ).unwrap()
  let node = parse_plan_identity_value(barrier.wire, 1000000, 100000, 100).unwrap()
  let body = @canonical.object_field(node, "barrier").unwrap()
  assert_eq(
    client_keyed_plan_test_text(node, "profile_id"),
    Some("actql-lookup/0.1"),
  )
  let wire = @canonical.stringify_value(body, 1000000, 100000, 100)
  let admitted = @publication.admit_publication_contract(
    "lookup_barrier", wire, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(@encode.document_text(original_body), wire)
  let retained = issue_client_keyed_plan_component(
    original, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(@encode.document_text(retained.barrier_body), wire)
  assert_eq(
    @publication.publication_contract_identity(admitted),
    barrier.logical_cid,
  )
  assert_true(@canonical.object_field(body, "bounds") is None)
  assert_true(@canonical.object_field(body, "proof") is None)
  assert_eq(
    client_keyed_plan_test_text(body, "effective_request_classification"),
    Some("unknown"),
  )
  assert_eq(
    client_keyed_plan_test_text(body, "effective_response_data_policy_cid"),
    Some(@checked.source_execution_subject(keyed.check).response_policy_cid),
  )
  assert_true(original.response_policy_cid != original.response_data_policy_cid)
  let mapping = @canonical.object_field(body, "request_mapping").unwrap()
  assert_eq(
    client_keyed_plan_test_text(
      @canonical.object_field(mapping, "id").unwrap(),
      "field",
    ),
    Some("id"),
  )
  assert_eq(
    client_keyed_plan_test_text(
      @canonical.object_field(mapping, "tenant").unwrap(),
      "literal",
    ),
    Some("original"),
  )
  let joined_node = parse_plan_identity_value(joined.wire, 1000000, 100000, 100).unwrap()
  let ports = @canonical.object_field(joined_node, "input_contracts").unwrap()
  assert_eq(
    client_keyed_plan_test_text(ports, "input_0"),
    Some(left.output_contract_cid),
  )
  assert_eq(
    client_keyed_plan_test_text(ports, "input_1"),
    Some(barrier.output_contract_cid),
  )
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let construction = measure_installed_client_composed_infer_graph_construction(
    occurrence,
    execution,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
    keyed_native_read=Some((keyed, profile)),
  ).unwrap()
  let graph = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
    construction=Some(construction),
    keyed_native_read=Some((keyed, profile)),
  ).unwrap()
  assert_eq(graph.graph_nodes.length(), 4)
  assert_eq(graph.graph_edges.length(), 4)
  assert_true(
    client_infer_required_profiles(graph).contains(
      ("actql-lookup/0.1", @environment.compiler_lookup_barrier_contract_cid()),
    ),
  )
  assert_eq(graph.input.logical_cid, joined.logical_cid)
  assert_eq(graph.input_fragment_cid, joined.logical_cid)
  assert_true(
    physical_equal(
      client_infer_plan_native_keyed_read_profile(graph).unwrap(),
      profile,
    ),
  )
  let actual = content_construction_geometry(graph.graph.wire)
  assert_true(
    actual.0 <= construction.graph.0 &&
    actual.1 <= construction.graph.1 &&
    actual.2 <= construction.graph.2,
  )
}

///|
test "keyed first Plan refuses foreign original occurrence profile and codec exhaustion" {
  let (occurrence, keyed, profile) = client_keyed_plan_test_inputs()
  let (foreign, _, _) = client_keyed_plan_test_inputs()
  assert_true(
    prepare_client_keyed_plan_fragment_inputs(
      foreign,
      keyed,
      client_standard_values_sequence_limits(),
      100000,
    )
    is Err(_),
  )
  let input = prepare_client_keyed_plan_fragment_inputs(
    occurrence,
    keyed,
    client_standard_values_sequence_limits(),
    100000,
  ).unwrap()
  assert_true(
    prepare_client_keyed_plan_barrier_input(
      input, profile, 0, 1000000, 100000, 100,
    )
    is Err(_),
  )
  let wrong = @publication.seal_publication_contract(
    "lookup_barrier", "{}", 1000, 100, 20,
  )
  assert_true(wrong is Err(_))
  let original = prepare_client_keyed_plan_barrier_input(
    input, profile, 1000000, 1000000, 100000, 100,
  ).unwrap()
  let (left, _) = issue_client_keyed_plan_fragments(input, 1000000, 100000, 100).unwrap()
  assert_true(
    issue_client_keyed_plan_barrier(original, left, 1, 100000, 100)
    is Err(Encoding),
  )
  assert_true(physical_equal(original.policies.original, keyed.check))
}

///|
fn client_keyed_plan_test_text(
  value : @canonical.CanonicalValue,
  key : String,
) -> String? {
  match @canonical.object_field(value, key) {
    Some(@canonical.String(text)) => Some(text)
    _ => None
  }
}

///|
// The original imported Result is already the left input. No dummy filter or
// replacement Source is introduced to manufacture a preceding Step.
test "keyed Model construction retains original imported Result as its direct left input" {
  let (occurrence, keyed, profile) = client_keyed_plan_test_inputs(
    imported_left=true,
  )
  assert_true(
    @acquisition.keyed_join_left(keyed.binding.join) is @pipeline.Input(_),
  )
  assert_true(
    client_keyed_plan_metadata_storage(occurrence) is Some(_),
    msg="original imported Result left metadata must remain measurable",
  )
  match
    prepare_client_keyed_plan_fragment_inputs(
      occurrence,
      keyed,
      client_standard_values_sequence_limits(),
      100000,
    ) {
    Ok(input) => {
      assert_eq(@lower.sequence_count(input.left.sequence), 0)
      let (left, joined) = issue_client_keyed_plan_fragments(
        input, 1000000, 100000, 100,
      ).unwrap()
      assert_eq(left.output_port, input.left.output)
      assert_eq(input.left_sources.length(), 1)
      let barrier = prepare_client_keyed_plan_barrier_input(
        input, profile, 1000000, 1000000, 100000, 100,
      ).unwrap()
      assert_true(physical_equal(barrier.fragments, input))
      assert_eq(joined.output_port, input.joined.output)
    }
    Err(_) => fail("original imported Result left fragment is unsupported")
  }
}

///|
test "keyed Model whole graph preserves one imported Result from two original Source ports" {
  let (occurrence, keyed, profile) = client_keyed_plan_test_inputs(
    imported_left=true,
    joined_producer=true,
  )
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let graph = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
    keyed_native_read=Some((keyed, profile)),
  ).unwrap()
  match
    issue_client_task_plan_graph(
      occurrence.owner,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
      false,
      [],
      infer=Some(graph),
    ) {
    Ok(_) => ()
    Err(InvalidLimits) => fail("joined graph:invalid_limits")
    Err(UnsupportedGraph) => fail("joined graph:unsupported_graph")
    Err(Fragment(_)) => fail("joined graph:fragment")
    Err(Root(_)) => fail("joined graph:root")
    Err(InvalidEdge) => fail("joined graph:invalid_edge")
    Err(ContractMismatch) => fail("joined graph:contract_mismatch")
    Err(Encoding) => fail("joined graph:encoding")
  }
}

///|
test "joined keyed Result graph refuses foreign owner and invalid original Model coordinates" {
  let (occurrence, keyed, profile) = client_keyed_plan_test_inputs(
    imported_left=true,
    joined_producer=true,
  )
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let component = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
    keyed_native_read=Some((keyed, profile)),
  ).unwrap()
  assert_true(
    @strategy.graph_keyed_model_plan_inputs_complete(
      occurrence.owner.graph,
      component.task,
      component.source_ordinal,
    ),
  )
  for
    (task, step) in [
      (-1, component.source_ordinal),
      (100000, component.source_ordinal),
      (component.task, -1),
    ] {
    assert_false(
      @strategy.graph_keyed_model_plan_inputs_complete(
        occurrence.owner.graph,
        task,
        step,
      ),
    )
  }
  let (foreign, _, _) = client_keyed_plan_test_inputs(
    imported_left=true,
    joined_producer=true,
  )
  assert_true(
    issue_client_task_plan_graph(
      foreign.owner,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
      false,
      [],
      infer=Some(component),
    )
    is Err(UnsupportedGraph),
  )
}
