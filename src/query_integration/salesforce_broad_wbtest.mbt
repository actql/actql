///|
fn salesforce_broad_binding() -> @salesforce_catalog.CatalogObservationBinding {
  {
    tenant: "tenant-a",
    principal: "principal-a",
    environment: "test",
    connection_revision: "connection-a",
    org_id: "00D000000000001EAA",
    site_key: "site-a",
    site_generation: 1,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://example.invalid",
    run_invocation_cid: "sha256:" + "a".repeat(64),
    dispatch_request_cid: "sha256:" + "b".repeat(64),
    sync_occurrence: "sync-a",
  }
}

///|
fn salesforce_broad_plan(
  resource? : String = "r",
  native_type? : String = "int",
  filterable? : Bool = false,
  max_soql_bytes? : Int = 100,
) -> @salesforce_catalog.ReadProjection {
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode(
      "{\"sobjects\":[{\"name\":\"" + resource + "\",\"queryable\":true}]}",
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = @salesforce_catalog.begin_catalog_sync(listing)
  let description = "{\"name\":\"" +
    resource +
    "\",\"queryable\":true,\"fields\":[{\"name\":\"id\",\"type\":\"" +
    native_type +
    "\",\"nillable\":false,\"filterable\":" +
    filterable.to_string() +
    "}]}"
  @salesforce_catalog.catalog_sync_describe(
    sync,
    resource,
    @utf8.encode(description),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
  let binding = salesforce_broad_binding()
  let observation = @salesforce_catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [
      Some(
        @salesforce_catalog.catalog_response_sha256(@utf8.encode(description)),
      ),
    ],
    4096,
  ).unwrap()
  @salesforce_catalog.prepare_read_projection(
    observation,
    binding,
    resource,
    ["id"],
    max_soql_bytes,
  ).unwrap()
}

///|
/// This Site's declaration for the fixture Resource `r`, from the same
/// describe the plans observe; the checked Program reads its SourceView.
fn salesforce_broad_declaration(
  resource? : String = "r",
  connector_id? : String = "crm/main",
  site_generation? : Int = 1,
  filterable? : Bool = false,
) -> @salesforce_catalog.StaticDeclaration {
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode(
      "{\"sobjects\":[{\"name\":\"" + resource + "\",\"queryable\":true}]}",
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = @salesforce_catalog.begin_catalog_sync(listing)
  let description = "{\"name\":\"" +
    resource +
    "\",\"queryable\":true,\"fields\":[{\"name\":\"id\",\"type\":\"int\",\"nillable\":false,\"filterable\":" +
    filterable.to_string() +
    "}]}"
  @salesforce_catalog.catalog_sync_describe(
    sync,
    resource,
    @utf8.encode(description),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
  let binding = { ..salesforce_broad_binding(), site_generation, }
  let observation = @salesforce_catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [
      Some(
        @salesforce_catalog.catalog_response_sha256(@utf8.encode(description)),
      ),
    ],
    4096,
  ).unwrap()
  @salesforce_catalog.generate_static_declaration(
    observation,
    binding,
    @salesforce_catalog.salesforce_implementation("salesforce/0.1").unwrap(),
    connector_id,
    [resource],
    { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
  ).unwrap()
}

///|
fn salesforce_broad_catalog() -> @environment.SourceRequestContracts {
  let declaration = salesforce_broad_declaration()
  let (wire, cid) = declaration_environment(
    [declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    [],
    // The same fixed capacity policy as the existing Program fixture.
    host_policy="{\"capacity\":{\"max_aggregate_array_items\":10000,\"max_artifact_bytes\":10000,\"max_artifact_rows\":10000,\"max_effect_items\":10000,\"max_graph_input_edges\":10000,\"max_graph_input_nodes\":10000,\"max_graph_output_rows\":10000,\"max_graph_paths\":10000,\"max_infer_items\":10000,\"max_model_input_tokens_per_item\":10000,\"max_model_request_bytes_per_item\":10000,\"max_model_total_duration_ms\":10000,\"max_nested_value_bytes\":10000,\"max_nested_value_depth\":10000,\"max_relation_output_rows\":10000,\"max_temporal_matches_per_key\":10000,\"max_temporal_output_rows\":10000,\"version\":\"actql-capacity-host-policy/0.1\"}}",
  )
  query_catalog_from_wire(wire, expected=cid)
}

///|
fn salesforce_broad_requirement() -> @planning.QueryRequirement raise {
  let checked = query_checked_program_fixture(
    catalog=Some(salesforce_broad_catalog()),
  )
  let sequence = query_checked_sequence(checked)
  @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
}

///|
test "Salesforce broad candidate binds the exact checked source and common choice" {
  let requirement = salesforce_broad_requirement()
  let plan = salesforce_broad_plan()
  let preparation = @salesforce_host.prepare_salesforce_broad_query(
    requirement,
    plan,
    "crm/main",
    salesforce_broad_declaration(),
  ).unwrap()
  assert_true(
    physical_equal(
      @salesforce_host.salesforce_broad_requirement(preparation),
      requirement,
    ),
  )
  assert_true(
    @salesforce_host.prepare_salesforce_broad_query(
      requirement,
      plan,
      "foreign/instance",
      salesforce_broad_declaration(),
    )
    is Err(ForeignSource),
  )
  assert_true(
    @salesforce_host.prepare_salesforce_broad_query(
      requirement,
      salesforce_broad_plan(resource="other"),
      "crm/main",
      salesforce_broad_declaration(),
    )
    is Err(ForeignSource),
  )
  assert_true(
    @salesforce_host.prepare_salesforce_broad_query(
      requirement,
      salesforce_broad_plan(native_type="string"),
      "crm/main",
      salesforce_broad_declaration(),
    )
    is Err(InvalidInputSchema),
  )
  let registry = @connector.prepare_capability_registry(
    [
      {
        name: "salesforce",
        acquisition: true,
        fixed_compute: false,
        effect: false,
      },
    ],
    1,
    20,
  ).unwrap()
  let candidate = @salesforce_host.salesforce_broad_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    preparation,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("expected selected Salesforce candidate")
  }
  assert_true(
    @planning.acquisition_choice_payload(choice, candidate) is Some(_),
  )
}

///|
test "Salesforce pushes an exact checked integer comparison and retains residual" {
  let requirement = salesforce_broad_requirement()
  let preparation = @salesforce_host.prepare_salesforce_broad_query(
    requirement,
    salesforce_broad_plan(filterable=true),
    "crm/main",
    salesforce_broad_declaration(filterable=true),
  ).unwrap()
  assert_eq(
    @salesforce_catalog.read_projection_soql(
      @salesforce_host.salesforce_broad_plan(preparation),
    ),
    "SELECT id FROM r WHERE id > 1",
  )
  let query = @salesforce_host.begin_salesforce_broad_query(
    preparation,
    "v62.0",
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_rows: 3,
      max_locator_units: 128,
    },
    2,
    3L,
    3,
    run_limits().input_values,
  ).unwrap()
  let path = @salesforce_host.salesforce_broad_next_path(query)
    .unwrap()
    .unwrap()
  assert_eq(
    path, "/services/data/v62.0/query?q=SELECT%20id%20FROM%20r%20WHERE%20id%20%3E%201",
  )
  @salesforce_host.accept_salesforce_broad_page(
    query,
    path,
    @utf8.encode(
      (
        #|{"totalSize":2,"done":true,"records":[{"id":3},{"id":2}]}
      ),
    ),
  ).unwrap()
  |> ignore
  let input = @salesforce_host.finish_salesforce_broad_query(query).unwrap()
  let (completed, _) = @salesforce_host.execute_salesforce_broad_residual(
    preparation,
    input,
    compute_test_limits(),
    query_guard_physical(),
  ).unwrap()
  let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  let unfilterable = @salesforce_host.prepare_salesforce_broad_query(
    requirement,
    salesforce_broad_plan(),
    "crm/main",
    salesforce_broad_declaration(),
  ).unwrap()
  assert_eq(
    @salesforce_catalog.read_projection_soql(
      @salesforce_host.salesforce_broad_plan(unfilterable),
    ),
    "SELECT id FROM r",
  )
  let supplied_filter = @salesforce_catalog.with_exact_int_comparison(
    salesforce_broad_plan(filterable=true),
    "id",
    @salesforce_catalog.Greater,
    2,
  ).unwrap()
  assert_true(
    @salesforce_host.prepare_salesforce_broad_query(
      requirement,
      supplied_filter,
      "crm/main",
      salesforce_broad_declaration(),
    )
    is Err(UnexpectedPrefilter),
  )
  // A field whose current type has no exact declared contract is refused
  // before any query, even though its name is declared: a read plan and the
  // declaration admit the same types, so no plan of it exists. A Number
  // (`double`) without a described precision up to 15 is one.
  let listing = @salesforce_catalog.project_resource_listing(
    @utf8.encode("{\"sobjects\":[{\"name\":\"r\",\"queryable\":true}]}"),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 10,
      max_selected: 10,
      max_name_units: 100,
    },
  ).unwrap()
  let sync = @salesforce_catalog.begin_catalog_sync(listing)
  let description = "{\"name\":\"r\",\"queryable\":true,\"fields\":[{\"name\":\"id\",\"type\":\"double\",\"precision\":16,\"scale\":2,\"nillable\":false,\"filterable\":true}]}"
  @salesforce_catalog.catalog_sync_describe(
    sync,
    "r",
    @utf8.encode(description),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
      max_fields: 10,
      max_name_units: 100,
    },
  ).unwrap()
  @salesforce_catalog.finish_catalog_sync(sync).unwrap()
  let binding = salesforce_broad_binding()
  let observation = @salesforce_catalog.prepare_catalog_observation(
    sync,
    binding,
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [
      Some(
        @salesforce_catalog.catalog_response_sha256(@utf8.encode(description)),
      ),
    ],
    4096,
  ).unwrap()
  assert_true(
    @salesforce_catalog.prepare_read_projection(
      observation,
      binding,
      "r",
      ["id"],
      100,
    )
    is Err(UnsupportedReadType("id")),
  )
}

///|
test "Salesforce broad pages use checked input admission and Local residual" {
  let preparation = @salesforce_host.prepare_salesforce_broad_query(
    salesforce_broad_requirement(),
    salesforce_broad_plan(),
    "crm/main",
    salesforce_broad_declaration(),
  ).unwrap()
  let query = @salesforce_host.begin_salesforce_broad_query(
    preparation,
    "v62.0",
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_rows: 3,
      max_locator_units: 128,
    },
    2,
    3L,
    3,
    run_limits().input_values,
  ).unwrap()
  let path = @salesforce_host.salesforce_broad_next_path(query)
    .unwrap()
    .unwrap()
  assert_eq(path, "/services/data/v62.0/query?q=SELECT%20id%20FROM%20r")
  @salesforce_host.accept_salesforce_broad_page(
    query,
    path,
    @utf8.encode(
      (
        #|{"totalSize":3,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC","records":[{"id":3},{"id":1}]}
      ),
    ),
  ).unwrap()
  |> ignore
  let next = @salesforce_host.salesforce_broad_next_path(query)
    .unwrap()
    .unwrap()
  assert_eq(next, "/services/data/v62.0/query/01gABC")
  @salesforce_host.accept_salesforce_broad_page(
    query,
    next,
    @utf8.encode(
      (
        #|{"totalSize":3,"done":true,"records":[{"id":2}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(@salesforce_host.salesforce_broad_complete(query))
  let input = @salesforce_host.finish_salesforce_broad_query(query).unwrap()
  assert_eq(@execution.captured_row_count(input), 3)
  assert_true(
    @salesforce_host.finish_salesforce_broad_query(query) is Err(Closed),
  )
  let (completed, _) = @salesforce_host.execute_salesforce_broad_residual(
    preparation,
    input,
    compute_test_limits(),
    query_guard_physical(),
  ).unwrap()
  let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(
    @salesforce_host.execute_salesforce_broad_residual(
      @salesforce_host.prepare_salesforce_broad_query(
        salesforce_broad_requirement(),
        salesforce_broad_plan(),
        "crm/main",
        salesforce_broad_declaration(),
      ).unwrap(),
      input,
      compute_test_limits(),
      query_guard_physical(),
    )
    is Err(_),
  )
}

///|
test "Salesforce broad capture failure and cancellation expose no partial input" {
  let preparation = @salesforce_host.prepare_salesforce_broad_query(
    salesforce_broad_requirement(),
    salesforce_broad_plan(),
    "crm/main",
    salesforce_broad_declaration(),
  ).unwrap()
  let limits : @salesforce_catalog.QueryPageLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_rows: 3,
    max_locator_units: 128,
  }
  let limited = @salesforce_host.begin_salesforce_broad_query(
    preparation,
    "v62.0",
    limits,
    2,
    3L,
    1,
    run_limits().input_values,
  ).unwrap()
  let initial = @salesforce_host.salesforce_broad_next_path(limited)
    .unwrap()
    .unwrap()
  assert_true(
    @salesforce_host.accept_salesforce_broad_page(
      limited,
      initial,
      @utf8.encode(
        (
          #|{"totalSize":2,"done":true,"records":[{"id":3},{"id":2}]}
        ),
      ),
    )
    is Err(Capture(_)),
  )
  assert_true(@salesforce_host.salesforce_broad_next_path(limited) is Ok(None))
  assert_true(
    @salesforce_host.finish_salesforce_broad_query(limited) is Err(Closed),
  )
  let cancelled = @salesforce_host.begin_salesforce_broad_query(
    preparation,
    "v62.0",
    limits,
    2,
    3L,
    3,
    run_limits().input_values,
  ).unwrap()
  let first = @salesforce_host.salesforce_broad_next_path(cancelled)
    .unwrap()
    .unwrap()
  @salesforce_host.accept_salesforce_broad_page(
    cancelled,
    first,
    @utf8.encode(
      (
        #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC","records":[{"id":3}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(@salesforce_host.cancel_salesforce_broad_query(cancelled))
  assert_true(
    @salesforce_host.salesforce_broad_next_path(cancelled) is Ok(None),
  )
  assert_true(
    @salesforce_host.finish_salesforce_broad_query(cancelled) is Err(Closed),
  )
  let page_limited = @salesforce_host.begin_salesforce_broad_query(
    preparation,
    "v62.0",
    limits,
    1,
    3L,
    3,
    run_limits().input_values,
  ).unwrap()
  let first_path = @salesforce_host.salesforce_broad_next_path(page_limited)
    .unwrap()
    .unwrap()
  @salesforce_host.accept_salesforce_broad_page(
    page_limited,
    first_path,
    @utf8.encode(
      (
        #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC","records":[{"id":3}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(
    @salesforce_host.salesforce_broad_next_path(page_limited) is Err(Query(_)),
  )
  assert_true(
    @salesforce_host.finish_salesforce_broad_query(page_limited) is Err(Closed),
  )
}

///|
priv struct SalesforceIssuedFixture {
  requirement : @planning.QueryRequirement
  issuer : @salesforce_host.SalesforceBroadIssuer
  choice : @planning.AcquisitionChoice
  candidate : @planning.PreparedAcquisition[
    @salesforce_host.SalesforceBroadPreparation,
  ]
  settled : Array[@salesforce_host.SalesforceBroadAttempt]
}

///|
fn salesforce_issued_fixture(
  requirement? : @planning.QueryRequirement? = None,
) -> SalesforceIssuedFixture raise {
  let requirement = match requirement {
    Some(value) => value
    None => salesforce_broad_requirement()
  }
  let preparation = @salesforce_host.prepare_salesforce_broad_query(
    requirement,
    salesforce_broad_plan(),
    "crm/main",
    salesforce_broad_declaration(),
  ).unwrap()
  let registry = @connector.prepare_capability_registry(
    [
      {
        name: "salesforce",
        acquisition: true,
        fixed_compute: false,
        effect: false,
      },
    ],
    1,
    20,
  ).unwrap()
  let candidate = @salesforce_host.salesforce_broad_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    preparation,
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("Salesforce candidate was not selected")
  }
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let settled : Array[@salesforce_host.SalesforceBroadAttempt] = []
  let issuer = @salesforce_host.prepare_salesforce_broad_issuer(
    contracts,
    requirement,
    "test-process",
    100,
    attempt => settled.any(value => physical_equal(value, attempt)),
  ).unwrap()
  { requirement, issuer, choice, candidate, settled, }
}

///|
fn salesforce_issued_read(
  fixture : SalesforceIssuedFixture,
) -> @salesforce_host.SalesforceBroadAttempt {
  let attempt = @salesforce_host.prepare_issued_salesforce_broad_attempt(
    fixture.issuer,
    fixture.choice,
    fixture.candidate,
  ).unwrap()
  @salesforce_host.begin_issued_salesforce_broad_read(
    attempt,
    "v62.0",
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_rows: 3,
      max_locator_units: 128,
    },
    2,
    3L,
    3,
    run_limits().input_values,
  ).unwrap()
  let path = @salesforce_host.salesforce_broad_attempt_next_path(attempt)
    .unwrap()
    .unwrap()
  @salesforce_host.accept_issued_salesforce_broad_page(
    attempt,
    path,
    @utf8.encode(
      (
        #|{"totalSize":3,"done":true,"records":[{"id":3},{"id":1},{"id":2}]}
      ),
    ),
  ).unwrap()
  |> ignore
  @salesforce_host.finish_issued_salesforce_broad_read(attempt).unwrap()
  attempt
}

///|
fn salesforce_completion_limits() -> @salesforce_host.SalesforceBroadCompletionLimits {
  {
    execution: compute_test_limits(),
    guards: query_guard_physical(),
    retention: {
      received_wire_bytes: 28,
      retained_wire_bytes: 47,
      measurement: {
        max_columns: 10,
        max_order_work: 1000,
        max_bytes: 47,
        max_nodes: 12,
        max_depth: 10,
      },
    },
    records: query_material_limits(),
    capture: query_capture_limits(),
  }
}

///|
test "Salesforce Host owns exact selected capture and downstream liveness" {
  let fixture = salesforce_issued_fixture()
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let configuration = @salesforce_host.configure_salesforce_broad_host(
    contracts,
    fixture.requirement,
    fixture.choice,
    fixture.candidate,
    salesforce_completion_limits(),
  )
  let settled : Array[@salesforce_host.SalesforceBroadAttempt] = []
  let run = @salesforce_host.start_salesforce_broad_host(
    configuration,
    "test-host",
    attempt => settled.any(value => physical_equal(value, attempt)),
  ).unwrap()
  let attempt = @salesforce_host.salesforce_broad_host_attempt(run)
  @salesforce_host.begin_issued_salesforce_broad_read(
    attempt,
    "v62.0",
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_rows: 3,
      max_locator_units: 128,
    },
    2,
    3L,
    3,
    run_limits().input_values,
  ).unwrap()
  let path = @salesforce_host.salesforce_broad_attempt_next_path(attempt)
    .unwrap()
    .unwrap()
  @salesforce_host.accept_issued_salesforce_broad_page(
    attempt,
    path,
    @utf8.encode(
      (
        #|{"totalSize":3,"done":true,"records":[{"id":3},{"id":1},{"id":2}]}
      ),
    ),
  ).unwrap()
  |> ignore
  @salesforce_host.finish_issued_salesforce_broad_read(attempt).unwrap()
  settled.push(attempt)
  let observation = @salesforce_host.complete_salesforce_broad_host(run).unwrap()
  let source = @salesforce_host.salesforce_broad_host_source(run, observation).unwrap()
  let producer = @query.query_sequence_owner(
    @planning.query_material_owner(
      @planning.query_requirement_material(fixture.requirement),
    ),
  )
  let receiver = typed_receiver(producer, "[{\"select\":[\"id\"]}]")
  let input = @salesforce_host.bind_salesforce_broad_host_input(
    run, observation, receiver, 0,
  ).unwrap()
  let generated = compute_test_sequence(receiver)
  let computed = @execution.execute_local_compute_attempt(
    @execution.prepare_local_compute_attempt(generated, [input], 3).unwrap(),
    compute_test_limits(),
  ).unwrap()
  let output = @execution.completed_output(computed, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@query.captured_source_available(source))
  @salesforce_host.close_salesforce_broad_host(run)
  assert_true(!@query.captured_source_available(source))
  assert_true(
    @salesforce_host.complete_salesforce_broad_host(run) is Err(InvalidState),
  )
}

///|
test "issued Salesforce read exposes only its active bounded page state" {
  let fixture = salesforce_issued_fixture()
  let attempt = @salesforce_host.prepare_issued_salesforce_broad_attempt(
    fixture.issuer,
    fixture.choice,
    fixture.candidate,
  ).unwrap()
  assert_false(@salesforce_host.salesforce_broad_attempt_read_complete(attempt))
  assert_true(
    @salesforce_host.salesforce_broad_attempt_read_row_count(attempt)
    is Err(InvalidState),
  )
  assert_eq(
    @salesforce_catalog.read_projection_soql(
      @salesforce_host.salesforce_broad_attempt_plan(attempt),
    ),
    "SELECT id FROM r",
  )
  @salesforce_host.begin_issued_salesforce_broad_read(
    attempt,
    "v62.0",
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_rows: 3,
      max_locator_units: 128,
    },
    1,
    1L,
    1,
    run_limits().input_values,
  ).unwrap()
  let path = @salesforce_host.salesforce_broad_attempt_next_path(attempt)
    .unwrap()
    .unwrap()
  @salesforce_host.accept_issued_salesforce_broad_page(
    attempt,
    path,
    @utf8.encode(
      (
        #|{"totalSize":1,"done":true,"records":[{"id":3}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(@salesforce_host.salesforce_broad_attempt_read_complete(attempt))
  assert_true(
    @salesforce_host.salesforce_broad_attempt_read_row_count(attempt) is Ok(1L),
  )
  @salesforce_host.finish_issued_salesforce_broad_read(attempt).unwrap()
  assert_false(@salesforce_host.salesforce_broad_attempt_read_complete(attempt))
  assert_true(
    @salesforce_host.salesforce_broad_attempt_read_row_count(attempt)
    is Err(InvalidState),
  )
  assert_true(
    @salesforce_host.complete_salesforce_broad_capture(
      fixture.issuer,
      attempt,
      salesforce_completion_limits(),
    )
    is Err(UnverifiedTransport),
  )
}

///|
test "Salesforce completion requires selected attempt and settled transport" {
  let fixture = salesforce_issued_fixture()
  let attempt = salesforce_issued_read(fixture)
  assert_true(
    @salesforce_host.issue_salesforce_broad_records(
      attempt,
      query_material_limits(),
    )
    is Err(NotRetained),
  )
  assert_true(
    @salesforce_host.complete_salesforce_broad_capture(
      fixture.issuer,
      attempt,
      salesforce_completion_limits(),
    )
    is Err(UnverifiedTransport),
  )
  let settled = salesforce_issued_read(fixture)
  fixture.settled.push(settled)
  let observation = @salesforce_host.complete_salesforce_broad_capture(
    fixture.issuer,
    settled,
    salesforce_completion_limits(),
  ).unwrap()
  let (expected, _) = query_observation_oracle(
    fixture.requirement,
    @salesforce_host.salesforce_broad_attempt_identity(settled),
    "[{\"id\":3},{\"id\":1},{\"id\":2}]",
    3,
    "[\"id\"]",
    "[{\"id\":3},{\"id\":2}]",
    2,
  )
  assert_eq(
    @encode.document_text(
      @salesforce_host.salesforce_broad_observation_document(observation),
    ),
    expected,
  )
  assert_eq(
    @salesforce_host.salesforce_broad_observation_cid(observation),
    query_material_expected(expected),
  )
  let owner = @query.query_sequence_owner(
    @planning.query_material_owner(
      @planning.query_requirement_material(fixture.requirement),
    ),
  )
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let source = @salesforce_host.salesforce_broad_captured_source(
    fixture.issuer,
    settled,
    observation,
  ).unwrap()
  assert_true(
    @query.captured_source_matches(
      source,
      @planning.query_requirement_program(fixture.requirement),
      owner,
    ),
  )
  assert_eq(@query.captured_source_row_count(source), Some(2))
  let source_input = @query.bind_captured_source(source, receiver, 0).unwrap()
  let input = @salesforce_host.bind_captured_salesforce_broad_input(
    fixture.issuer,
    settled,
    observation,
    receiver,
    0,
    owner,
  ).unwrap()
  let generated = compute_test_sequence(receiver)
  let local_attempt = @execution.prepare_local_compute_attempt(
    generated,
    [input],
    3,
  ).unwrap()
  let completed = @execution.execute_local_compute_attempt(
    local_attempt,
    compute_test_limits(),
  ).unwrap()
  let output = @execution.completed_output(completed, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
  let source_attempt = @execution.prepare_local_compute_attempt(
    generated,
    [source_input],
    3,
  ).unwrap()
  let source_completed = @execution.execute_local_compute_attempt(
    source_attempt,
    compute_test_limits(),
  ).unwrap()
  let source_output = @execution.completed_output(source_completed, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(source_output), 2)
  assert_true(@execution.completed_cell(source_output, 0, 0) is Some(Number(3)))
  assert_true(@execution.completed_cell(source_output, 1, 0) is Some(Number(2)))
  let foreign = salesforce_issued_read(fixture)
  fixture.settled.push(foreign)
  assert_true(
    @salesforce_host.bind_captured_salesforce_broad_input(
      fixture.issuer,
      foreign,
      observation,
      receiver,
      0,
      owner,
    )
    is Err(UnauthorizedAttempt),
  )
  @salesforce_host.abort_salesforce_broad_attempt(settled)
  assert_true(
    @salesforce_host.complete_salesforce_broad_capture(
      fixture.issuer,
      settled,
      salesforce_completion_limits(),
    )
    is Err(Attempt(InvalidState)),
  )
  fixture.settled.clear()
  assert_true(!@query.captured_source_available(source))
  assert_true(
    @salesforce_host.bind_captured_salesforce_broad_input(
      fixture.issuer,
      settled,
      observation,
      receiver,
      0,
      owner,
    )
    is Err(UnverifiedTransport),
  )
  assert_true(
    @query.bind_captured_source(source, receiver, 0) is Err(Unavailable),
  )
  @salesforce_host.close_salesforce_broad_issuer(fixture.issuer)
  assert_true(
    @salesforce_host.bind_captured_salesforce_broad_input(
      fixture.issuer,
      settled,
      observation,
      receiver,
      0,
      owner,
    )
    is Err(IssuerClosed),
  )
  assert_true(!@query.captured_source_available(source))
  assert_true(
    @query.bind_captured_source(source, receiver, 0) is Err(Unavailable),
  )
  assert_true(
    @salesforce_host.salesforce_broad_captured_source(
      fixture.issuer,
      settled,
      observation,
    )
    is Err(Unavailable),
  )
  assert_true(
    @salesforce_host.prepare_issued_salesforce_broad_attempt(
      fixture.issuer,
      fixture.choice,
      fixture.candidate,
    )
    is Err(IssuerClosed),
  )
}

///|
test "Salesforce captured source opens the checked DAG for downstream consumers" {
  let program = query_checked_program_fixture(
    dag=true,
    catalog=Some(salesforce_broad_catalog()),
  )
  let sequence = query_checked_sequence(program)
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(program),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let fixture = salesforce_issued_fixture(requirement=Some(requirement))
  let attempt = salesforce_issued_read(fixture)
  fixture.settled.push(attempt)
  let observation = @salesforce_host.complete_salesforce_broad_capture(
    fixture.issuer,
    attempt,
    salesforce_completion_limits(),
  ).unwrap()
  let source = @salesforce_host.salesforce_broad_captured_source(
    fixture.issuer,
    attempt,
    observation,
  ).unwrap()
  let owners = physical_graph_owners(program)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program) + 100,
    1000,
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 32000000L,
    execution_bytes: 134217728L,
  }).unwrap()
  let run = @strategy.open_captured_dag(graph, source, ledger).unwrap()
  assert_eq(@strategy.next_captured_task(run), Some(1))
  captured_graph_local(run, 1).unwrap()
  captured_graph_local(run, 2).unwrap()
  @salesforce_host.close_salesforce_broad_issuer(fixture.issuer)
  captured_graph_local(run, 3).unwrap()
  assert_true(@strategy.next_captured_task(run) is None)
  for (task, expected) in [(1, [3.0]), (2, [3.0, 2.0]), (3, [3.0])] {
    let output = @strategy.captured_task_output(run, task, Step(1)).unwrap()
    assert_eq(@execution.completed_row_count(output), expected.length())
    for i, value in expected {
      assert_true(
        @execution.completed_cell(output, i, 0) is Some(Number(actual)) &&
        actual == value,
      )
    }
  }
}

///|
test "Salesforce broad query requires this Site's declaration of the source" {
  let requirement = salesforce_broad_requirement()
  // Another generation of the same connection and schema is foreign.
  assert_true(
    @salesforce_host.prepare_salesforce_broad_query(
      requirement,
      salesforce_broad_plan(),
      "crm/main",
      salesforce_broad_declaration(site_generation=2),
    )
    is Err(Undeclared(ForeignDeclaration)),
  )
  // The same schema declared under another connection id is foreign.
  assert_true(
    @salesforce_host.prepare_salesforce_broad_query(
      requirement,
      salesforce_broad_plan(),
      "crm/main",
      salesforce_broad_declaration(connector_id="crm/other"),
    )
    is Err(ForeignSource),
  )
  // A declaration of another Resource does not cover the checked source.
  assert_true(
    @salesforce_host.prepare_salesforce_broad_query(
      requirement,
      salesforce_broad_plan(),
      "crm/main",
      salesforce_broad_declaration(resource="other"),
    )
    is Err(Undeclared(Undeclared)),
  )
}
