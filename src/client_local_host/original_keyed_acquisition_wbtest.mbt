///|
// The existing environment contract orders evidence sections by whole-member
// canonical CID, as does rowSourceCheckEnvironment. This constructs inputs;
// it supplies no expectation for a Source observation or Model result.
fn original_keyed_environment_members(bodies : Array[String]) -> Json raise {
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
fn original_keyed_declaration_environment(
  relation_versions? : Bool = false,
) -> (@row_source_host.RowDeclaration, String) raise {
  let listing = "{\"media_type\":{\"nullable\":true,\"type\":\"string\"},\"modified_at\":{\"nullable\":true,\"type\":\"timestamp\"},\"name\":{\"nullable\":false,\"type\":\"string\"},\"path\":{\"nullable\":true,\"type\":\"string\"},\"resource\":{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"},\"size_bytes\":{\"nullable\":true,\"type\":\"number\"},\"version\":{\"nullable\":false,\"type\":\"string\"}}"
  let content = "{\"content\":{\"media_type\":\"application/pdf\",\"nullable\":false,\"type\":\"content_ref\"},\"resource\":{\"nullable\":false,\"resource_kind\":\"file\",\"type\":\"resource_ref\"},\"version\":{\"nullable\":false,\"type\":\"string\"}}"
  let listed : @row_source_host.RowRelationViewSpec = {
    resource: "files",
    resource_kind: "file",
    schema_wire: listing,
    schema_cid: "sha256:" + @sha.hex(@utf8.encode(listing)),
    request_schema_wire: if relation_versions {
      None
    } else {
      Some(
        "{\"additional_properties\":false,\"fields\":{\"glob\":{\"nullable\":true,\"type\":\"string\"},\"paths\":{\"items\":{\"nullable\":false,\"type\":\"string\"},\"max_items\":8,\"nullable\":true,\"type\":\"array\"}},\"nullable\":false,\"type\":\"object\"}",
      )
    },
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
    // An ordinary Relation can contain a Resource's version history. It is
    // not a contradictory FILES listing and must not acquire listing facts.
    facts_wire: if relation_versions {
      None
    } else {
      Some(
        "{\"file_listing\":{\"admitted_scope_contract_cid\":\"sha256:" +
        "a".repeat(64) +
        "\",\"allow_unfiltered_listing\":true,\"kind\":\"file_listing\",\"listing_schema_contract_cid\":\"" +
        listing_schema +
        "\",\"max_examined_items\":9,\"max_listing_bytes\":32768,\"max_listing_duration_ms\":10000,\"max_listing_items\":3,\"max_listing_pages\":4,\"max_request_attempts\":4,\"maximum_path_length\":64,\"selectable\":[\"paths\",\"glob\"],\"version\":\"actql-file-list/0.1\",\"version_capability\":{\"contract_cid\":\"sha256:" +
        "b".repeat(64) +
        "\",\"required_nonnull\":true}}}",
      )
    },
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
fn original_keyed_run_fixture(
  selector_free? : Bool = false,
  relation_versions? : Bool = false,
  unknown_left_rows? : Bool = false,
  serialization_max_bytes? : Int = 4096,
  typed_content_input? : Bool = false,
) -> (
  @row_source_host.RowDeclaration,
  @publication_host.PreparedClientProgram,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication_host.ClientInferPlanGraph,
  @publication_host.ClientKeyedAcquisition,
  @planning.QueryRequirement,
) raise {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let (declaration, environment) = original_keyed_declaration_environment(
    relation_versions~,
  )
  let document =
    #|{"version":"actql/0.1","id":"original-keyed-content","stages":[{"id":"capture","inputs":{"contents":{"connector":"content-fixture","resource":"contents"},"files":{"connector":"content-fixture","resource":"files","request":{"paths":["invoice.pdf"],"glob":null}}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"selected"},{"join":{"left":"selected","with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"captured"},{"from":"captured","assert_rows":{"unique_by":["name"]}},{"serialize":{"format":"jsonl","fields":["name","content"],"order_by":[{"name":"asc"}],"name":"captured.jsonl","bounds":{"max_rows":3,"max_bytes":4096}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["name","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"capture","result":"rows"}}}}
  let document = if selector_free || relation_versions {
    // An empty terminal listing is valid for the explicitly admitted unfiltered
    // selection, not for a missing mandatory exact path.
    let parsed = @json.parse(document)
    guard parsed is Object(root) &&
      root.get("stages") is Some(Array(stages)) &&
      stages[0] is Object(stage) &&
      stage.get("inputs") is Some(Object(inputs)) &&
      inputs.get("files") is Some(Object(files)) &&
      files.get("request") is Some(Object(request)) else {
      abort("fixture Direct request")
    }
    if relation_versions {
      // The left connector Resource is an ordinary row relation, not FILES.
      // Do not fabricate a listing observation to admit multiple versions.
      files.remove("request")
      guard stage.get("steps") is Some(Array(steps)) &&
        steps.length() >= 3 &&
        steps[2] is Object(join_step) &&
        join_step.get("join") is Some(Object(join)) else {
        abort("fixture version-history steps")
      }
      // The optional take provides an actual static bound. Its companion
      // keeps the same ordinary Source and checked target without that bound;
      // a preserving filter neither counts rows nor invents FILES evidence.
      // Preserve the existing scan/filter/select acquisition. The later
      // bounded Local prefix, not an invented Source query, owns these guards.
      join["left"] = @json.parse("\"bounded\"")
      let augmented = [
        steps[0],
        steps[1],
        @json.parse(
          "{\"from\":\"selected\",\"assert_rows\":{\"unique_by\":[\"name\"]},\"as\":\"unique_names\"}",
        ),
        @json.parse(
          "{\"from\":\"unique_names\",\"sort\":[{\"field\":\"name\",\"dir\":\"asc\",\"nulls\":\"last\"}],\"as\":\"ordered_names\"}",
        ),
        @json.parse(
          if unknown_left_rows {
            "{\"from\":\"ordered_names\",\"filter\":{\"literal\":true},\"as\":\"bounded\"}"
          } else {
            "{\"from\":\"ordered_names\",\"take\":3,\"as\":\"bounded\"}"
          },
        ),
      ]
      for index in 2..<steps.length() {
        augmented.push(steps[index])
      }
      stage["steps"] = Json::array(augmented)
    } else {
      request["paths"] = @json.parse("null")
    }
    @identity.stringify_value(
      @identity.from_json(parsed, 100000, 100, 1000000),
      1000000,
      100000,
      100,
    )
  } else {
    document
  }
  let document = if serialization_max_bytes == 4096 {
    document
  } else {
    document.replace(
      old="\"max_bytes\":4096",
      new="\"max_bytes\":" + serialization_max_bytes.to_string(),
    )
  }
  let document = if typed_content_input {
    document.replace(
      old="\"input\":{\"text\":{\"field\":\"name\"}}",
      new="\"input\":{\"document\":{\"field\":\"content\"}}",
    )
  } else {
    document
  }
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture(
    source=true,
    environment_override=Some(environment),
    document_override=Some(document),
    serialization_coordinate=Some((0, if relation_versions { 7 } else { 4 })),
    serialization_bounds=(3, serialization_max_bytes),
    model_task_override=if typed_content_input {
      Some(original_typed_content_task())
    } else {
      None
    },
    model_execution_override=if typed_content_input {
      Some(original_typed_content_execution())
    } else {
      None
    },
  )
  let keyed = @publication_host.select_client_single_keyed_acquisition(prepared)
    .unwrap()
    .unwrap()
  if unknown_left_rows {
    let (rows, keys, _, _) = @publication_host.client_keyed_lookup_capacity(
      keyed, 4096, 100000,
    ).unwrap()
    assert_true(rows is None && keys is None)
  }
  let (_, direct, _) = @publication_host.client_keyed_direct_acquisition_coordinates(
    keyed,
  ).unwrap()
  let requirement = prepare_local_query_requirement(
    prepared,
    0,
    direct,
    source_contracts,
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
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
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
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
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
    @publication_host.client_original_keyed_capture_available(
      scope, compiled, definition, plan, prepared, keyed,
    ),
  )
  assert_false(
    @publication_host.client_original_keyed_capture_available(
      scope, compiled, definition, plan, foreign, foreign_keyed,
    ),
  )
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
  // Existing dependencies survive immutable descriptor/read issuance; only
  // NEW capture preparation must reject this phase.
  assert_true(
    @publication_host.client_original_keyed_capture_available(
      scope, compiled, definition, plan, prepared, keyed,
    ),
  )
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
  assert_false(
    @publication_host.client_original_keyed_capture_available(
      scope, compiled, definition, plan, prepared, keyed,
    ),
  )
}

///|
test "original keyed empty listing keeps Direct custody through assembly cleanup without reacquisition" {
  let (declaration, prepared, compiled, definition, plan, keyed, requirement) = original_keyed_run_fixture(
    selector_free=true,
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
    source, "fixture-original-keyed-empty", original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
  ).unwrap()
  // The empty assembly owns only its fixed 4096-byte control envelope.
  // The max-work ceiling allocates no absent key/copy traversal. The original
  // Direct capture independently retains its three bytes and two execution bytes.
  // These canonical-layout budgets are not a normal Node physical profile.
  let (scope, ledger) = original_row_scope(
    compiled,
    definition,
    plan,
    retained_bytes=@row_source_host.row_acquisition_retained_capacity(
        acquisition,
      ) +
      4096L +
      3L,
    execution_bytes=@row_source_host.row_acquisition_execution_capacity(
        acquisition,
      ) +
      4096L +
      6656L +
      2L,
    transfer_bytes=4096L,
  )
  let cleanup_requested = Ref(false)
  let run = start_client_original_keyed_direct_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    acquisition,
    "original-empty-direct",
    _ => {
      if cleanup_requested.val {
        @publication_host.finish_client_model_read_scope(
          scope, compiled, definition, plan, false,
        )
        |> ignore
      }
      true
    },
    4096L,
    4096L,
  ).unwrap()
  // The listing profile requires an installed Ref issuer even for zero rows.
  // This one refuses all issuance; an empty page must never call it.
  let reference_calls = Ref(0)
  let reference_issuer = @admitted.bind_reference_issuer(
    (_, _) => {
      reference_calls.val += 1
      false
    },
    _ => false,
  )
  @row_source_host.begin_row_run(
    run,
    4096,
    3,
    3,
    reference_issuer=Some(reference_issuer),
  ).unwrap()
  @row_source_host.begin_row_run_listing_request(run, None, 0L).unwrap()
  // Independently authored terminal protocol envelope, not an empty query
  // response inferred from absent pages or a successful selected prefix.
  let body = @utf8.encode(
    "{\"items\":[],\"request_token\":null,\"next_token\":null}",
  )
  @row_source_host.begin_row_run_listing_page(run, body, 0L).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    match @row_source_host.advance_row_run_listing_page(run, 1, 0L).unwrap() {
      @row_source_host.ListingPageContinue(_) => ()
      @row_source_host.ListingPageComplete(rows~, ..) => {
        assert_eq(rows, 0)
        complete = true
        break
      }
    }
  }
  assert_true(complete)
  @row_source_host.finish_row_run(run).unwrap()
  @row_source_host.begin_row_capture(run).unwrap()
  complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(run, 1).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(run).unwrap()
  assert_eq(reference_calls.val, 0)
  let captured_usage = @resources.ledger_usage(ledger)
  assert_eq(captured_usage.attempts, 1)
  assert_eq(captured_usage.holdings, 1)
  let lookup = start_client_original_keyed_lookup(
    scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096, 64, 64,
  ).unwrap()
  let assembled_usage = @resources.ledger_usage(ledger)
  assert_eq(assembled_usage.attempts, captured_usage.attempts)
  assert_eq(
    assembled_usage.reserved_attempts,
    captured_usage.reserved_attempts + 1,
  )
  // Same constructor retains original left receipt/identity and optional
  // Source-cache references plus one consumed-work word: 3*8 + 8 under
  // the pinned central tariff. The cache payload is funded only on use.
  // Preserve this capture's independently supplied retained3/execution2.
  let original_identity_fields = 3L * 8L + 8L
  assert_eq(
    assembled_usage.reserved_retention_bytes,
    4096L + original_identity_fields + 3L,
  )
  assert_eq(
    assembled_usage.reserved_execution_bytes,
    4096L + original_identity_fields + 2L,
  )
  assert_eq(assembled_usage.holdings, 1)
  // Zero progress is neither cleanup acknowledgment nor permission to return
  // the buffer's reservation. It must not close the original Direct child.
  assert_false(
    @publication_host.cleanup_client_keyed_lookup_input(lookup, 0).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger), assembled_usage)
  assert_true(@row_source_host.row_capture_source(capture) is Ok(_))
  assert_true(
    @publication_host.cleanup_client_keyed_lookup_input(lookup, 8).unwrap(),
  )
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.attempts, captured_usage.attempts)
  assert_eq(retired.reserved_attempts, captured_usage.reserved_attempts)
  assert_eq(retired.holdings, 1)
  assert_eq(retired.reserved_retention_bytes, 3L)
  assert_eq(retired.reserved_execution_bytes, 2L)
  assert_true(@row_source_host.row_capture_source(capture) is Ok(_))
  assert_true(
    start_client_original_keyed_lookup(
      scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096, 64,
      64,
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), retired)
  // A liveness callback can begin original cleanup synchronously and still
  // return true. The AFTER-callback fence must revoke use without certifying
  // physical close or returning the Direct holding. Cleanup remains callable.
  cleanup_requested.val = true
  assert_true(@row_source_host.row_capture_source(capture) is Err(_))
  assert_false(
    @publication_host.client_original_keyed_capture_available(
      scope, compiled, definition, plan, prepared, keyed,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger).holdings, 1)
  @row_source_host.close_accounted_row_run(run).unwrap()
  assert_true(@row_source_host.row_capture_source(capture) is Err(_))
  // The original physical child's ACK returns its live holding slot. Issued
  // token identity and consumed work/transfer are independent of that slot.
  assert_eq(@resources.ledger_usage(ledger).holdings, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
