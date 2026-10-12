///|
// Assemble a genuine installed Catalog through its existing declaration and
// admission Owners. Expected maxima and target/work checks below are authored
// independently, not generated from this Catalog.
fn source_rows_requests_fixture(
  maximum : Int64?,
) -> @environment.SourceRequestContracts raise {
  let fields : Json = {
    "resource": {
      "type": "resource_ref",
      "resource_kind": "file",
      "nullable": false,
    },
    "name": { "type": "string", "nullable": false },
    "version": { "type": "string", "nullable": false },
    "path": { "type": "string", "nullable": true },
    "media_type": { "type": "string", "nullable": true },
    "size_bytes": { "type": "number", "nullable": true },
    "modified_at": { "type": "timestamp", "nullable": true },
  }
  let canonical = @identity.from_json(fields, 1000, 32, 100000)
  let spec : @row_host.RowRelationViewSpec = {
    resource: "files",
    resource_kind: "file",
    schema_wire: @identity.stringify_value(canonical, 100000, 1000, 32),
    schema_cid: @identity.cid_value(canonical, 100000, 1000, 32),
    request_schema_wire: Some(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"paths":{"type":"array","nullable":true,"items":{"type":"string","nullable":false}},"glob":{"type":"string","nullable":true}}}
      ),
    ),
    facts_wire: None,
    acquisition_wire: None,
  }
  let first = @row_host.generate_relation_row_declaration(
    "listing-fixture",
    "fixture",
    "fixture/0.1",
    [spec],
    source_rows_declaration_limits(),
  ).unwrap()
  let profile : Json = {
    "version": "actql-file-list/0.1",
    "kind": "file_listing",
    "selectable": ["paths", "glob"],
    "allow_unfiltered_listing": true,
    "admitted_scope_contract_cid": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "listing_schema_contract_cid": first.views[0].carrier_schema_cid,
    "version_capability": {
      "contract_cid": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "required_nonnull": true,
    },
  }
  if maximum is Some(maximum) {
    guard profile is Object(fields) else { abort("profile fixture") }
    fields["max_listing_items"] = Json::number(maximum.to_double())
  }
  let declaration = @row_host.generate_relation_row_declaration(
    "listing-fixture",
    "fixture",
    "fixture/0.1",
    [
      {
        ..spec,
        facts_wire: Some(({ "file_listing": profile } : Json).stringify()),
      },
    ],
    source_rows_declaration_limits(),
  ).unwrap()
  let sorted = (values : Array[String]) => {
    let bodies = values.map(text => {
      let body = @identity.from_json(@json.parse(text), 10000, 100, 100000)
      (@identity.cid_value(body, 100000, 10000, 100), @json.parse(text))
    })
    bodies.sort_by((a, b) => a.0.compare(b.0))
    Json::array(bodies.map(value => value.1))
  }
  let body : Json = {
    "version": "actql-check-environment/0.1",
    "connector_capabilities": [],
    "command_contracts": [],
    "connector_catalogs": [@json.parse(declaration.catalog)],
    "contract_registry": sorted(declaration.contracts),
    "host_policy_profile": {},
    "mapping_contracts": [],
    "model_task_contracts": [],
    "schema_snapshots": [],
    "source_views": sorted(declaration.view_bodies),
  }
  let canonical = @identity.from_json(body, 10000, 100, 100000)
  let cid = @identity.cid_value(canonical, 100000, 10000, 100)
  let sealed_body = @identity.object_with_string_field(
    canonical, "evidence_bundle_cid", cid,
  ).unwrap()
  let caps : @environment.Limits = {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_members: 100,
  }
  let raw = @environment.read(
    @wire_utf8.encode(
      @identity.stringify_value(sealed_body, 100000, 10000, 100),
    ),
    cid,
    caps,
  ).unwrap()
  let registry = @environment.check_contract_registry(raw, caps).unwrap()
  let catalogs = @environment.check_catalog_contents(registry, caps).unwrap()
  let references = @environment.check_catalog_references(catalogs, {
    max_work: 1000000,
    max_references: 1000,
  }).unwrap()
  let policies = @environment.check_source_data_policies(references, {
    max_work: 1000000,
    max_policies: 100,
  }).unwrap()
  let values = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 100,
    contracts: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
  }).unwrap()
  let shapes = @environment.check_source_view_shapes(values, {
    max_views: 100,
    max_work: 1000000,
  }).unwrap()
  let modes = @environment.check_source_read_modes(shapes, 1000000).unwrap()
  let carriers = @environment.check_carrier_schemas(modes, {
    max_work: 1000000,
    max_schemas: 100,
    bodies: { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  }).unwrap()
  let requests = @environment.check_source_request_contracts(carriers, {
    max_work: 1000000,
    max_roles: 1000,
  }).unwrap()
  requests
}

///|
fn source_rows_declaration_limits() -> @row_host.RowDeclarationLimits {
  {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_views: 2,
    max_fields: 16,
  }
}

///|
fn source_rows_pipeline_fixture(
  requests : @environment.SourceRequestContracts,
  steps? : String = "[{\"filter\":{\"literal\":true}},{\"select\":[\"name\"]}]",
) -> @pipeline.CheckedPipeline {
  let program = @syntax.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"listing-bound\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"files\":{\"connector\":\"listing-fixture\",\"resource\":\"files\",\"request\":{\"paths\":[],\"glob\":null}}},\"steps\":" +
    steps +
    ",\"results\":{\"r\":{\"fields\":[\"name\"]}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}",
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 1,
    },
    format=Json,
  ).unwrap()
  let stage = @syntax.stages(program)[0]
  let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
  let inputs = @decode.open_object(@decode.required(body, "inputs").unwrap()).unwrap()
  let contract = @environment.source_request_at(requests, 0).unwrap()
  let carrier = @environment.source_view_carrier(
    @environment.source_request_carriers(requests),
    @environment.source_request_member(contract),
  ).unwrap()
  @pipeline.check_with_evidence(
    @decode.required(body, "steps").unwrap(),
    [
      (
        "files",
        @pipeline.SourceViewInput(
          stage,
          "files",
          @decode.required(inputs, "files").unwrap(),
          carrier,
        ),
      ),
    ],
    None,
    Some(listing_rows_cursor("\"files\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 10000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn listing_rows_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn listing_rows_closure(
  pipeline : @pipeline.CheckedPipeline,
) -> @capacity.ApplicationClosure {
  let orders = @pipeline.resolve_contextual_closure(
    pipeline,
    max_steps=100,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  let selected = sequence_limit_policy(false)
  let entries = []
  for visit in 0..<@pipeline.contextual_closure_count(orders) {
    let owner = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(orders, visit).unwrap(),
    )
    let mixed = @wire.check_mixed_claims([], [], {
      max_entities: 0,
      max_references: 0,
      max_bytes: 0,
      max_nodes: 0,
      max_depth: 0,
    }).unwrap()
    let claims = @wire.check_mixed_program_claims(mixed, [], {
      max_witnesses: 0,
      max_references: 0,
    }).unwrap()
    let sources = @host.bind_claim_sources(claims, [], {
      max_entries: 0,
      max_bytes: 0,
      max_nodes: 0,
      max_depth: 0,
    }).unwrap()
    entries.push(
      @capacity.prepare_application_coverage(owner, sources, selected, [], {
        max_work: 10000,
        max_name_bytes: 10000,
        max_input_work: 10000,
        max_operand_work: 10000,
      }).unwrap(),
    )
  }
  let guards = @pipeline.bind_contextual_guards(
    orders,
    Array::make(entries.length(), None),
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  @capacity.check_application_closure(
    orders,
    entries,
    selected_policy=selected,
    bound_guards=guards,
    max_work=100000,
  ).unwrap()
}

///|
test "keyed candidate search retains the acquired Source root without a fake claim" {
  let requests = source_rows_requests_fixture(Some(3L))
  let pipeline = source_rows_pipeline_fixture(requests)
  let closure = listing_rows_closure(pipeline)
  let (candidates, work) = collect_target_row_candidates(
    closure,
    pipeline,
    @pipeline.Step(1),
    None,
    1000000,
    1,
    source_requests=Some(requests),
  ).unwrap()
  assert_eq(candidates.length(), 1)
  // One consumer visit, one producer visit, one input visit, the conservative
  // resolution allowance, nine owner/name checks, three walk steps and retain.
  assert_eq(work, 80016)
  let membership = candidates[0]
  assert_true(
    physical_equal(@capacity.target_membership_closure(membership), closure),
  )
  assert_eq(@capacity.target_membership_consumer_visit(membership), 0)
  assert_eq(
    @capacity.target_membership_input_coordinates(membership),
    Some((0, 0)),
  )
  assert_true(@capacity.target_membership_coordinates(membership) is None)
  let rows = @capacity.target_membership_rows(membership)
  assert_eq(@step_bounds.target_rows_value(rows), 3L)
  assert_true(@step_bounds.target_rows_bound(rows) is None)
  let original = @step_bounds.target_rows_source(rows).unwrap()
  assert_true(
    physical_equal(@step_bounds.source_input_rows_requests(original), requests),
  )
  assert_true(
    physical_equal(@step_bounds.source_input_rows_pipeline(original), pipeline),
  )
  let owned = @environment.source_request_at(requests, 0).unwrap()
  assert_true(
    physical_equal(@step_bounds.source_input_rows_request(original), owned),
  )
  let policy = @environment.file_listing_rows_policy(
    @step_bounds.source_input_rows_limit(original),
  ).unwrap()
  assert_true(
    physical_equal(policy, @capacity.application_closure_policy(closure)),
  )
  assert_true(
    collect_target_row_candidates(
      closure,
      pipeline,
      @pipeline.Step(1),
      None,
      work,
      1,
      source_requests=Some(requests),
    )
    is Ok(_),
  )
  assert_true(
    collect_target_row_candidates(
      closure,
      pipeline,
      @pipeline.Step(1),
      None,
      work - 1,
      1,
      source_requests=Some(requests),
    )
    is Err(CandidateBudget),
  )
  assert_true(
    collect_target_row_candidates(
      closure,
      pipeline,
      @pipeline.Step(1),
      None,
      1000000,
      0,
      source_requests=Some(requests),
    )
    is Err(CandidateBudget),
  )
  assert_eq(
    collect_target_row_candidates(
      closure,
      pipeline,
      @pipeline.Step(1),
      None,
      1000000,
      1,
    ).unwrap().0.length(),
    0,
  )
  let detached = source_rows_requests_fixture(Some(3L))
  assert_eq(
    collect_target_row_candidates(
      closure,
      pipeline,
      @pipeline.Step(1),
      None,
      1000000,
      1,
      source_requests=Some(detached),
    ).unwrap().0.length(),
    0,
  )
  let foreign = source_rows_pipeline_fixture(requests)
  assert_true(
    collect_target_row_candidates(
      closure,
      foreign,
      @pipeline.Step(1),
      None,
      1000000,
      1,
      source_requests=Some(requests),
    )
    is Err(CandidateMembership(@capacity.ForeignConsumer)),
  )
}

///|
test "keyed candidate search preserves repeated acquired Source occurrences" {
  let requests = source_rows_requests_fixture(Some(3L))
  let producer = source_rows_pipeline_fixture(requests)
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(producer, @pipeline.Step(1)).unwrap(),
  )
  let consumer = @pipeline.check_with_evidence(
    listing_rows_cursor("[]"),
    [("first", input), ("second", input)],
    None,
    Some(listing_rows_cursor("\"first\"")),
    {
      max_steps: 0,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let closure = listing_rows_closure(consumer)
  let (candidates, _) = collect_target_row_candidates(
    closure,
    consumer,
    @pipeline.Input(0),
    None,
    1000000,
    2,
    source_requests=Some(requests),
  ).unwrap()
  assert_eq(candidates.length(), 2)
  for index in 0..<2 {
    let membership = candidates[index]
    assert_eq(
      @capacity.target_membership_input_coordinates(membership),
      Some((index + 1, 0)),
    )
    assert_true(@capacity.target_membership_coordinates(membership) is None)
    let rows = @capacity.target_membership_rows(membership)
    assert_eq(@step_bounds.target_rows_value(rows), 3L)
    assert_true(
      physical_equal(
        @step_bounds.source_input_rows_pipeline(
          @step_bounds.target_rows_source(rows).unwrap(),
        ),
        producer,
      ),
    )
  }
}
