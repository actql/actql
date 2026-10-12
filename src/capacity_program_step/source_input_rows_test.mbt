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
    @utf8.encode(@identity.stringify_value(sealed_body, 100000, 10000, 100)),
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
  let program = @stage.parse(
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
  let stage = @stage.stages(program)[0]
  let body = @decode.open_object(@stage.stage_body(stage)).unwrap()
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
    Some(cursor("\"files\"")),
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
test "checked listing input ceiling reaches only its real nonexpanding target" {
  let requests = source_rows_requests_fixture(Some(3L))
  let contract = @environment.source_request_at(requests, 0).unwrap()
  let profile = @environment.source_request_file_listing(contract).unwrap()
  let root = source_rows_pipeline_fixture(requests)
  let limit = @environment.resolve_file_listing_rows(
    profile,
    None,
    @capacity_program_step.source_input_rows_subject(root, 0).unwrap(),
  ).unwrap()
  // One input visit, five name units and three owner correspondences.
  let bound = @capacity_program_step.check_source_input_rows(
    root, 0, requests, contract, limit, 9,
  ).unwrap()
  assert_eq(@capacity_program_step.source_input_rows_work(bound), 9)
  assert_true(
    physical_equal(
      @capacity_program_step.source_input_rows_requests(bound),
      requests,
    ),
  )
  assert_true(
    physical_equal(
      @capacity_program_step.source_input_rows_request(bound),
      contract,
    ),
  )
  assert_true(
    physical_equal(@capacity_program_step.source_input_rows_limit(bound), limit),
  )
  assert_true(
    @capacity_program_step.check_source_input_rows(
      root, 0, requests, contract, limit, 8,
    )
    is Err(@capacity_program_step.SourceInputRowsIssue::WorkLimit),
  )
  let downstream = consume(root, @pipeline.Step(1), "[{\"drop\":[]}]")
  for
    (p, target, work) in [
      (root, @pipeline.Input(0), 1),
      (root, @pipeline.Step(0), 2),
      (root, @pipeline.Step(1), 3),
      (downstream, @pipeline.Input(0), 4),
      (downstream, @pipeline.Step(0), 5),
    ] {
    let rows = @capacity_program_step.check_source_target_rows(
      p, target, bound, work,
    ).unwrap()
    assert_eq(@capacity_program_step.target_rows_value(rows), 3L)
    assert_eq(@capacity_program_step.target_rows_work(rows), work)
    assert_true(@capacity_program_step.target_rows_bound(rows) is None)
    assert_true(
      physical_equal(
        @capacity_program_step.target_rows_source(rows).unwrap(),
        bound,
      ),
    )
    let (short, used) = @capacity_program_step.check_source_target_rows_usage(
      p,
      target,
      bound,
      work - 1,
    )
    assert_true(short is Err(@capacity_program_step.TargetRowsIssue::WorkLimit))
    assert_eq(used, work - 1)
  }
  let foreign = source_rows_pipeline_fixture(requests)
  assert_true(
    @capacity_program_step.check_source_target_rows(
      foreign,
      @pipeline.Input(0),
      bound,
      100,
    )
    is Err(@capacity_program_step.MissingProducer),
  )
}

///|
test "listing root rejects detached admission and unrelated limit subjects" {
  let requests = source_rows_requests_fixture(Some(3L))
  let contract = @environment.source_request_at(requests, 0).unwrap()
  let profile = @environment.source_request_file_listing(contract).unwrap()
  let root = source_rows_pipeline_fixture(requests)
  let subject = @capacity_program_step.source_input_rows_subject(root, 0).unwrap()
  let limit = @environment.resolve_file_listing_rows(profile, None, subject).unwrap()
  let detached = source_rows_requests_fixture(Some(3L))
  let detached_contract = @environment.source_request_at(detached, 0).unwrap()
  let detached_profile = @environment.source_request_file_listing(
    detached_contract,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_source_input_rows(
      root, 0, detached, contract, limit, 100,
    )
    is Err(@capacity_program_step.ForeignRequest),
  )
  let foreign_limit = @environment.resolve_file_listing_rows(
    detached_profile,
    None,
    subject,
  ).unwrap()
  assert_true(
    @capacity_program_step.check_source_input_rows(
      root, 0, requests, contract, foreign_limit, 100,
    )
    is Err(@capacity_program_step.ForeignProfile),
  )
  assert_true(
    @capacity_program_step.check_source_input_rows(
      root, 0, detached, detached_contract, foreign_limit, 100,
    )
    is Err(@capacity_program_step.ForeignCarrier),
  )
  let unrelated = @environment.resolve_file_listing_rows(
    profile,
    None,
    "file-listing:other",
  ).unwrap()
  assert_true(
    @capacity_program_step.check_source_input_rows(
      root, 0, requests, contract, unrelated, 100,
    )
    is Err(@capacity_program_step.SubjectMismatch),
  )
  for input in [-1, 1] {
    assert_true(
      @capacity_program_step.check_source_input_rows(
        root, input, requests, contract, limit, 100,
      )
      is Err(@capacity_program_step.SourceInputRowsIssue::InvalidInput),
    )
  }
  assert_true(
    @capacity_program_step.check_source_input_rows(
      root, 0, requests, contract, limit, -1,
    )
    is Err(@capacity_program_step.SourceInputRowsIssue::InvalidLimits),
  )
}
