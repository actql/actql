///|
fn salesforce_broad_plan(
  resource? : String = "r",
  native_type? : String = "int",
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
    "\",\"nillable\":false}]}"
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
  let binding : @salesforce_catalog.CatalogObservationBinding = {
    tenant: "tenant-a",
    principal: "principal-a",
    environment: "test",
    connection_revision: "connection-a",
    site_key: "site-a",
    site_generation: 1,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: "https://example.invalid",
    run_invocation_cid: "sha256:" + "a".repeat(64),
    dispatch_request_cid: "sha256:" + "b".repeat(64),
    sync_occurrence: "sync-a",
  }
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
    100,
  ).unwrap()
}

///|
fn salesforce_broad_requirement() -> @planning.QueryRequirement raise {
  let checked = query_checked_program_fixture()
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
  let preparation = @salesforce_query.prepare_salesforce_broad_query(
    requirement, plan, "crm/main",
  ).unwrap()
  assert_true(
    physical_equal(
      @salesforce_query.salesforce_broad_requirement(preparation),
      requirement,
    ),
  )
  assert_true(
    @salesforce_query.prepare_salesforce_broad_query(
      requirement, plan, "foreign/instance",
    )
    is Err(ForeignSource),
  )
  assert_true(
    @salesforce_query.prepare_salesforce_broad_query(
      requirement,
      salesforce_broad_plan(resource="other"),
      "crm/main",
    )
    is Err(ForeignSource),
  )
  assert_true(
    @salesforce_query.prepare_salesforce_broad_query(
      requirement,
      salesforce_broad_plan(native_type="string"),
      "crm/main",
    )
    is Err(InvalidInputSchema),
  )
  let registry = @connector.prepare_capability_registry(
    [{ name: "salesforce", acquisition: true, fixed_compute: false, }],
    1,
    20,
  ).unwrap()
  let candidate = @salesforce_query.salesforce_broad_candidate(
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
test "Salesforce broad pages use checked input admission and Local residual" {
  let preparation = @salesforce_query.prepare_salesforce_broad_query(
    salesforce_broad_requirement(),
    salesforce_broad_plan(),
    "crm/main",
  ).unwrap()
  let query = @salesforce_query.begin_salesforce_broad_query(
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
  let path = @salesforce_query.salesforce_broad_next_path(query).unwrap()
  assert_eq(path, "/services/data/v62.0/query?q=SELECT%20id%20FROM%20r")
  @salesforce_query.accept_salesforce_broad_page(
    query,
    path,
    @utf8.encode(
      (
        #|{"totalSize":3,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC","records":[{"id":3},{"id":1}]}
      ),
    ),
  ).unwrap()
  |> ignore
  let next = @salesforce_query.salesforce_broad_next_path(query).unwrap()
  assert_eq(next, "/services/data/v62.0/query/01gABC")
  @salesforce_query.accept_salesforce_broad_page(
    query,
    next,
    @utf8.encode(
      (
        #|{"totalSize":3,"done":true,"records":[{"id":2}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(@salesforce_query.salesforce_broad_complete(query))
  let input = @salesforce_query.finish_salesforce_broad_query(query).unwrap()
  assert_eq(@execution.captured_row_count(input), 3)
  assert_true(
    @salesforce_query.finish_salesforce_broad_query(query) is Err(Closed),
  )
  let (completed, _) = @salesforce_query.execute_salesforce_broad_residual(
    preparation,
    input,
    compute_test_limits(),
    query_guard_physical(),
  ).unwrap()
  let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(
    @salesforce_query.execute_salesforce_broad_residual(
      @salesforce_query.prepare_salesforce_broad_query(
        salesforce_broad_requirement(),
        salesforce_broad_plan(),
        "crm/main",
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
  let preparation = @salesforce_query.prepare_salesforce_broad_query(
    salesforce_broad_requirement(),
    salesforce_broad_plan(),
    "crm/main",
  ).unwrap()
  let limits : @salesforce_catalog.QueryPageLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_rows: 3,
    max_locator_units: 128,
  }
  let limited = @salesforce_query.begin_salesforce_broad_query(
    preparation,
    "v62.0",
    limits,
    2,
    3L,
    1,
    run_limits().input_values,
  ).unwrap()
  let initial = @salesforce_query.salesforce_broad_next_path(limited).unwrap()
  assert_true(
    @salesforce_query.accept_salesforce_broad_page(
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
  assert_true(@salesforce_query.salesforce_broad_next_path(limited) is None)
  assert_true(
    @salesforce_query.finish_salesforce_broad_query(limited) is Err(Closed),
  )
  let cancelled = @salesforce_query.begin_salesforce_broad_query(
    preparation,
    "v62.0",
    limits,
    2,
    3L,
    3,
    run_limits().input_values,
  ).unwrap()
  let first = @salesforce_query.salesforce_broad_next_path(cancelled).unwrap()
  @salesforce_query.accept_salesforce_broad_page(
    cancelled,
    first,
    @utf8.encode(
      (
        #|{"totalSize":2,"done":false,"nextRecordsUrl":"/services/data/v62.0/query/01gABC","records":[{"id":3}]}
      ),
    ),
  ).unwrap()
  |> ignore
  assert_true(@salesforce_query.cancel_salesforce_broad_query(cancelled))
  assert_true(@salesforce_query.salesforce_broad_next_path(cancelled) is None)
  assert_true(
    @salesforce_query.finish_salesforce_broad_query(cancelled) is Err(Closed),
  )
}
