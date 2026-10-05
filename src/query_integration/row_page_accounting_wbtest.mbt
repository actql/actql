///|
fn row_page_observation(
  native_type? : String = "int",
  site_generation? : Int = 1,
) -> @salesforce_catalog.CatalogObservation {
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
  let description = "{\"name\":\"r\",\"queryable\":true,\"fields\":[{\"name\":\"id\",\"type\":\"" +
    native_type +
    "\",\"nillable\":false,\"filterable\":false}]}"
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
  @salesforce_catalog.prepare_catalog_observation(
    sync,
    { ..salesforce_row_binding(), site_generation, },
    "sha256:" + "c".repeat(64),
    [Some("sha256:" + "d".repeat(64))],
    [
      Some(
        @salesforce_catalog.catalog_response_sha256(@utf8.encode(description)),
      ),
    ],
    4096,
  ).unwrap()
}

///|
fn row_page_requirement() -> @planning.QueryRequirement raise {
  let declaration = salesforce_row_declaration()
  let (schemas, capabilities) = @salesforce_host.salesforce_source_evidence_members(
    declaration,
  )
  let (wire, original_cid) = declaration_environment(
    [declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    [],
    host_policy="{\"capacity\":{\"max_aggregate_array_items\":10000,\"max_artifact_bytes\":10000,\"max_artifact_rows\":10000,\"max_effect_items\":10000,\"max_graph_input_edges\":10000,\"max_graph_input_nodes\":10000,\"max_graph_output_rows\":10000,\"max_graph_paths\":10000,\"max_infer_items\":10000,\"max_model_input_tokens_per_item\":10000,\"max_model_request_bytes_per_item\":10000,\"max_model_total_duration_ms\":10000,\"max_nested_value_bytes\":10000,\"max_nested_value_depth\":10000,\"max_relation_output_rows\":10000,\"max_temporal_matches_per_key\":10000,\"max_temporal_output_rows\":10000,\"version\":\"actql-capacity-host-policy/0.1\"}}",
  )
  let body = wire
    .replace(old=",\"evidence_bundle_cid\":\"" + original_cid + "\"", new="")
    .replace(
      old="\"connector_capabilities\":[]",
      new="\"connector_capabilities\":[" + capabilities.join(",") + "]",
    )
    .replace(
      old="\"schema_snapshots\":[]",
      new="\"schema_snapshots\":[" + schemas.join(",") + "]",
    )
  let cid = text_cid(body)
  let complete = body.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let checked = query_checked_program_fixture(
    catalog=Some(query_catalog_from_wire(complete, expected=cid)),
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
fn row_page_acquisition() -> (
  @salesforce_host.InstalledSalesforceDeclaration,
  @row_host.RowAcquisition,
) raise {
  let binding = salesforce_row_binding()
  let site = @salesforce_host.installed_salesforce_site(
    binding.namespace_id,
    binding.principal,
    binding.environment,
    binding.connection_revision,
    binding.org_id,
    binding.site_key,
    binding.site_generation,
    binding.resource_origin,
  ).unwrap()
  let declaration = @salesforce_host.restore_installed_salesforce_declaration(
    site,
    row_page_observation(),
    "crm/main",
    salesforce_row_declaration().catalog_cid,
    { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
  ).unwrap()
  let requirement = row_page_requirement()
  let (query, evidence) = query_evidence_test_bodies()
  let acquisition = @salesforce_host.prepare_installed_salesforce_declared_row_acquisition(
    declaration,
    requirement,
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
  ).unwrap()
  assert_true(
    physical_equal(
      @row_host.row_acquisition_requirement(acquisition),
      requirement,
    ),
  )
  (declaration, acquisition)
}

///|
fn row_page_run(
  nonce : String,
  transfer_bytes? : Int64 = 1024L,
  max_page_bytes? : Int = 128,
) -> (@row_host.RowRun, @resources.Ledger, @salesforce_catalog.ReadProjection) raise {
  let (declaration, acquisition) = row_page_acquisition()
  let plan = @salesforce_host.recheck_installed_salesforce_row_projection(
    declaration,
    acquisition,
    row_page_observation(),
    100,
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 2,
    holdings: 2,
    transfer_bytes,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition),
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) +
    max_page_bytes.to_int64(),
  }).unwrap()
  let run = @row_host.start_accounted_row_acquisition(
    acquisition,
    nonce,
    _ => true,
    ledger,
    transfer_bytes,
    max_page_bytes.to_int64(),
  ).unwrap()
  @row_host.begin_row_run(run, max_page_bytes, 10, 10).unwrap()
  (run, ledger, plan)
}

///|
fn row_page_body(id : Int) -> Bytes {
  @utf8.encode(
    "{\"totalSize\":1,\"done\":true,\"records\":[{\"id\":" +
    id.to_string() +
    "}]}",
  )
}

///|
fn row_page_values(
  body : Bytes,
  plan : @salesforce_catalog.ReadProjection,
) -> Array[Array[@admitted.CheckedValue]] {
  let page = @salesforce_catalog.project_query_page(body, plan, "v62.0", {
    max_bytes: 128,
    max_nodes: 100,
    max_depth: 10,
    max_rows: 10,
    max_locator_units: 100,
  }).unwrap()
  let rows = []
  for row in 0..<@salesforce_catalog.query_page_row_count(page) {
    rows.push([@salesforce_catalog.query_page_cell(page, row, 0).unwrap()])
  }
  rows
}

///|
fn row_page_assert_closed(
  run : @row_host.RowRun,
  ledger : @resources.Ledger,
) -> Unit raise {
  assert_true(@row_host.finish_row_run(run) is Err(_))
  assert_true(@row_host.capture_row_run(run) is Err(_))
  @row_host.close_accounted_row_run(run).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "typed provider pages charge actual bodies once before decode and retain through neutral capture" {
  let first = row_page_body(2)
  let second = row_page_body(3)
  let (run, ledger, plan) = row_page_run(
    "row-page-success",
    transfer_bytes=(first.length() + second.length()).to_int64(),
  )
  let mut expected = 0L
  for body in [first, second] {
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    expected += body.length().to_int64()
    // The complete provider envelope is charged before provider decoding.
    assert_eq(@resources.ledger_usage(ledger).transferred_bytes, expected)
    let values = row_page_values(body, plan)
    assert_eq(
      @row_host.accept_charged_row_run_values(run, charge, ["id"], values).unwrap(),
      1,
    )
    assert_eq(@resources.ledger_usage(ledger).transferred_bytes, expected)
  }
  @row_host.finish_row_run(run).unwrap()
  let capture = @row_host.capture_row_run(run).unwrap()
  assert_true(@row_host.row_capture_source(capture) is Ok(_))
  let captured = @resources.ledger_usage(ledger)
  assert_eq(captured.transferred_bytes, expected)
  assert_true(captured.held_bytes > 0L)
  assert_eq(captured.reserved_transfer_bytes, 0L)
  assert_eq(captured.reserved_retention_bytes, 0L)
  assert_eq(captured.reserved_execution_bytes, 0L)
  assert_true(@row_host.capture_row_run(run) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), captured)
  assert_true(@row_host.row_capture_source(capture) is Ok(_))
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(@row_host.row_capture_source(capture) is Err(_))
}

///|
test "accounted typed admission without a body charge fails closed" {
  let (run, ledger, plan) = row_page_run("row-page-missing")
  assert_true(
    @row_host.accept_row_run_values(
      run,
      ["id"],
      row_page_values(row_page_body(2), plan),
    )
    is Err(Physical(InvalidCharge)),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  row_page_assert_closed(run, ledger)
}

///|
test "a duplicate body charge aborts without charging the page twice" {
  let (run, ledger, _) = row_page_run("row-page-double-charge")
  let body = row_page_body(2)
  @row_host.charge_row_run_page(run, body).unwrap() |> ignore
  assert_true(
    @row_host.charge_row_run_page(run, body) is Err(Physical(InvalidCharge)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  row_page_assert_closed(run, ledger)
}

///|
test "a foreign page charge cannot authorize another run" {
  let (owner, owner_ledger, plan) = row_page_run("row-page-owner")
  let (foreign, foreign_ledger, _) = row_page_run("row-page-foreign")
  let body = row_page_body(2)
  let charge = @row_host.charge_row_run_page(owner, body).unwrap()
  let values = row_page_values(body, plan)
  assert_true(
    @row_host.accept_charged_row_run_values(foreign, charge, ["id"], values)
    is Err(Physical(ForeignOwner)),
  )
  assert_eq(@resources.ledger_usage(foreign_ledger).transferred_bytes, 0L)
  row_page_assert_closed(foreign, foreign_ledger)
  // A rejected foreign consumer cannot consume the genuine owner's ticket.
  assert_eq(
    @row_host.accept_charged_row_run_values(owner, charge, ["id"], values).unwrap(),
    1,
  )
  assert_eq(
    @resources.ledger_usage(owner_ledger).transferred_bytes,
    body.length().to_int64(),
  )
  @row_host.close_accounted_row_run(owner).unwrap()
}

///|
test "a consumed page charge cannot be replayed" {
  let (run, ledger, plan) = row_page_run("row-page-replay")
  let body = row_page_body(2)
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  let values = row_page_values(body, plan)
  @row_host.accept_charged_row_run_values(run, charge, ["id"], values).unwrap()
  |> ignore
  assert_true(
    @row_host.accept_charged_row_run_values(run, charge, ["id"], values)
    is Err(Physical(InvalidCharge)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  row_page_assert_closed(run, ledger)
}

///|
test "a charged page cannot be omitted from a completed read" {
  let (run, ledger, _) = row_page_run("row-page-omitted")
  @row_host.charge_row_run_page(run, row_page_body(2)).unwrap() |> ignore
  assert_true(@row_host.finish_row_run(run) is Err(Physical(InvalidCharge)))
  row_page_assert_closed(run, ledger)
}

///|
test "page scratch and transfer limits fail before provider decoding" {
  let body = row_page_body(2)
  let (oversized, oversized_ledger, _) = row_page_run(
    "row-page-scratch",
    max_page_bytes=16,
  )
  assert_true(
    @row_host.charge_row_run_page(oversized, body) is Err(Source(InvalidPage)),
  )
  assert_eq(
    @resources.ledger_usage(oversized_ledger).transferred_bytes,
    body.length().to_int64(),
  )
  row_page_assert_closed(oversized, oversized_ledger)
  let second = row_page_body(3)
  let (bounded, bounded_ledger, plan) = row_page_run(
    "row-page-transfer",
    transfer_bytes=(body.length() + second.length() - 1).to_int64(),
  )
  let first_charge = @row_host.charge_row_run_page(bounded, body).unwrap()
  @row_host.accept_charged_row_run_values(
    bounded,
    first_charge,
    ["id"],
    row_page_values(body, plan),
  ).unwrap()
  |> ignore
  assert_true(
    @row_host.charge_row_run_page(bounded, second)
    is Err(Physical(TransferLimit)),
  )
  assert_eq(
    @resources.ledger_usage(bounded_ledger).transferred_bytes,
    body.length().to_int64(),
  )
  row_page_assert_closed(bounded, bounded_ledger)
}

///|
test "charged JSON projections account different raw envelopes once for identical rows" {
  let first = @utf8.encode("{\"nodes\":[{\"id\":2}]}")
  let second = @utf8.encode(
    "{\"nodes\":[{\"id\":2}],\"pageInfo\":{\"hasNextPage\":false}}",
  )
  let projected = @utf8.encode("[{\"id\":2}]")
  assert_true(first.length() != second.length())
  let (run, ledger, _) = row_page_run(
    "row-page-json-envelopes",
    transfer_bytes=(first.length() + second.length()).to_int64(),
  )
  let mut expected = 0L
  for body in [first, second] {
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    expected += body.length().to_int64()
    assert_eq(@resources.ledger_usage(ledger).transferred_bytes, expected)
    assert_eq(
      @row_host.accept_charged_row_run_page(run, charge, projected).unwrap(),
      1,
    )
    assert_eq(@resources.ledger_usage(ledger).transferred_bytes, expected)
  }
  @row_host.finish_row_run(run).unwrap()
  let capture = @row_host.capture_row_run(run).unwrap()
  assert_true(@row_host.row_capture_source(capture) is Ok(_))
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, expected)
  assert_true(@resources.ledger_usage(ledger).held_bytes > 0L)
  @row_host.close_accounted_row_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.transferred_bytes, expected)
  assert_eq(closed.held_bytes, 0L)
  assert_eq(closed.reserved_transfer_bytes, 0L)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
  assert_true(@row_host.row_capture_source(capture) is Err(_))
}

///|
test "charged JSON admission rejects replay with a missing or replacement pending ticket" {
  let body = row_page_body(2)
  let projected = @utf8.encode("[{\"id\":2}]")
  for replacement in [false, true] {
    let (run, ledger, _) = row_page_run(
      "row-page-json-replay-" + replacement.to_string(),
    )
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    @row_host.accept_charged_row_run_page(run, charge, projected).unwrap()
    |> ignore
    let mut expected = body.length().to_int64()
    if replacement {
      @row_host.charge_row_run_page(run, body).unwrap() |> ignore
      expected += body.length().to_int64()
    }
    assert_true(
      @row_host.accept_charged_row_run_page(run, charge, projected)
      is Err(Physical(InvalidCharge)),
    )
    row_page_assert_closed(run, ledger)
    assert_eq(@resources.ledger_usage(ledger).transferred_bytes, expected)
  }
}

///|
test "charged JSON admission refuses cross-run tickets without consuming their owner" {
  let body = row_page_body(2)
  let projected = @utf8.encode("[{\"id\":2}]")
  for pending in [false, true] {
    let (owner, owner_ledger, _) = row_page_run(
      "row-page-json-owner-" + pending.to_string(),
    )
    let (foreign, foreign_ledger, _) = row_page_run(
      "row-page-json-foreign-" + pending.to_string(),
    )
    let charge = @row_host.charge_row_run_page(owner, body).unwrap()
    let mut foreign_bytes = 0L
    if pending {
      @row_host.charge_row_run_page(foreign, body).unwrap() |> ignore
      foreign_bytes = body.length().to_int64()
    }
    assert_true(
      @row_host.accept_charged_row_run_page(foreign, charge, projected)
      is Err(Physical(ForeignOwner)),
    )
    row_page_assert_closed(foreign, foreign_ledger)
    assert_eq(
      @resources.ledger_usage(foreign_ledger).transferred_bytes,
      foreign_bytes,
    )
    assert_eq(
      @row_host.accept_charged_row_run_page(owner, charge, projected).unwrap(),
      1,
    )
    @row_host.finish_row_run(owner).unwrap()
    @row_host.capture_row_run(owner).unwrap() |> ignore
    @row_host.close_accounted_row_run(owner).unwrap()
    assert_eq(
      @resources.ledger_usage(owner_ledger).transferred_bytes,
      body.length().to_int64(),
    )
  }
}

///|
test "refused projected JSON aborts its raw charge without refunding transfer" {
  let body = row_page_body(2)
  for projected in [@utf8.encode("[{\"id\":"), @utf8.encode(" ".repeat(129))] {
    let (run, ledger, _) = row_page_run(
      "row-page-json-refused-" + projected.length().to_string(),
    )
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    assert_true(
      @row_host.accept_charged_row_run_page(run, charge, projected)
      is Err(Source(InvalidPage)),
    )
    assert_true(
      @row_host.accept_charged_row_run_page(
        run,
        charge,
        @utf8.encode("[{\"id\":2}]"),
      )
      is Err(InvalidState),
    )
    row_page_assert_closed(run, ledger)
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      body.length().to_int64(),
    )
  }
}

///|
test "a parser-refused raw body retains its charge and cannot finish without admission" {
  let body = @utf8.encode("{\"nodes\":[")
  let (run, ledger, _) = row_page_run("row-page-json-raw-refused")
  @row_host.charge_row_run_page(run, body).unwrap() |> ignore
  assert_true(
    @source.parse_json_bytes(body, {
      max_input_bytes: 128,
      max_nodes: 100,
      max_depth: 10,
    })
    is Err(_),
  )
  assert_true(@row_host.finish_row_run(run) is Err(Physical(InvalidCharge)))
  row_page_assert_closed(run, ledger)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
}

///|
test "ordinary JSON pages share the charging path without a duplicate charge" {
  let (run, ledger, _) = row_page_run("row-page-json")
  let body = @utf8.encode("[{\"id\":2}]")
  assert_eq(@row_host.accept_row_run_page(run, body).unwrap(), 1)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  @row_host.finish_row_run(run).unwrap()
  @row_host.capture_row_run(run).unwrap() |> ignore
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}

///|
test "JSON admission cannot bypass an outstanding typed page charge" {
  let (run, ledger, _) = row_page_run("row-page-mixed")
  let body = row_page_body(2)
  @row_host.charge_row_run_page(run, body).unwrap() |> ignore
  assert_true(
    @row_host.accept_row_run_page(run, @utf8.encode("[{\"id\":2}]"))
    is Err(Physical(InvalidCharge)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  row_page_assert_closed(run, ledger)
}

///|
test "a refused typed page has no capture and cannot refund its received bytes" {
  let (run, ledger, plan) = row_page_run("row-page-invalid")
  let body = row_page_body(2)
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  assert_true(
    @row_host.accept_charged_row_run_values(
      run,
      charge,
      ["foreign"],
      row_page_values(body, plan),
    )
    is Err(Source(InvalidPage)),
  )
  row_page_assert_closed(run, ledger)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
}

///|
test "unaccounted typed providers keep compatibility and can use bounded charged handoff" {
  let (declaration, acquisition) = row_page_acquisition()
  let plan = @salesforce_host.recheck_installed_salesforce_row_projection(
    declaration,
    acquisition,
    row_page_observation(),
    100,
  ).unwrap()
  let body = row_page_body(2)
  for charged in [false, true] {
    let run = @row_host.start_row_acquisition(
      acquisition,
      "row-page-ordinary-" + charged.to_string(),
      _ => true,
    ).unwrap()
    @row_host.begin_row_run(run, 128, 10, 10).unwrap()
    let values = row_page_values(body, plan)
    if charged {
      let charge = @row_host.charge_row_run_page(run, body).unwrap()
      assert_eq(
        @row_host.accept_charged_row_run_values(run, charge, ["id"], values).unwrap(),
        1,
      )
    } else {
      assert_eq(
        @row_host.accept_row_run_values(run, ["id"], values).unwrap(),
        1,
      )
    }
    @row_host.finish_row_run(run).unwrap()
    @row_host.capture_row_run(run).unwrap() |> ignore
    @row_host.close_row_run(run)
  }
  let run = @row_host.start_row_acquisition(
    acquisition,
    "row-page-ordinary-bound",
    _ => true,
  ).unwrap()
  @row_host.begin_row_run(run, 16, 10, 10).unwrap()
  assert_true(
    @row_host.charge_row_run_page(run, body) is Err(Source(InvalidPage)),
  )
  assert_true(@row_host.capture_row_run(run) is Err(_))
  @row_host.close_row_run(run)
}

///|
test "declared Salesforce preparation preserves capacity while dispatch rechecks fresh binding and types" {
  let (declaration, acquisition) = row_page_acquisition()
  let retained = @row_host.row_acquisition_retained_capacity(acquisition)
  let execution = @row_host.row_acquisition_execution_capacity(acquisition)
  assert_true(retained > 0L)
  assert_true(execution > 0L)
  let plan = @salesforce_host.recheck_installed_salesforce_row_projection(
    declaration,
    acquisition,
    row_page_observation(),
    100,
  ).unwrap()
  assert_eq(@salesforce_catalog.read_projection_soql(plan), "SELECT id FROM r")
  assert_true(
    @salesforce_host.recheck_installed_salesforce_row_projection(
      declaration,
      acquisition,
      row_page_observation(site_generation=2),
      100,
    )
    is Err(ForeignBinding),
  )
  assert_true(
    @salesforce_host.recheck_installed_salesforce_row_projection(
      declaration,
      acquisition,
      row_page_observation(native_type="string"),
      100,
    )
    is Err(Preparation(InvalidInputSchema)),
  )
  assert_eq(@row_host.row_acquisition_retained_capacity(acquisition), retained)
  assert_eq(
    @row_host.row_acquisition_execution_capacity(acquisition),
    execution,
  )
}

///|
test "closing a failed typed run isolates sibling reservations and allows a fresh retry" {
  let (declaration, acquisition) = row_page_acquisition()
  let plan = @salesforce_host.recheck_installed_salesforce_row_projection(
    declaration,
    acquisition,
    row_page_observation(),
    100,
  ).unwrap()
  let retained = @row_host.row_acquisition_retained_capacity(acquisition)
  let execution = @row_host.row_acquisition_execution_capacity(acquisition) +
    128L
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 4096L,
    retained_bytes: retained * 2L,
    execution_bytes: execution * 2L,
  }).unwrap()
  let first = @row_host.start_accounted_row_acquisition(
    acquisition,
    "row-page-close-first",
    _ => true,
    ledger,
    1024L,
    128L,
  ).unwrap()
  let sibling = @row_host.start_accounted_row_acquisition(
    acquisition,
    "row-page-close-sibling",
    _ => true,
    ledger,
    1024L,
    128L,
  ).unwrap()
  for run in [first, sibling] {
    @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  }
  let body = row_page_body(2)
  let values = row_page_values(body, plan)
  let first_charge = @row_host.charge_row_run_page(first, body).unwrap()
  let sibling_charge = @row_host.charge_row_run_page(sibling, body).unwrap()
  assert_true(
    @row_host.accept_charged_row_run_values(
      first,
      first_charge,
      ["wrong"],
      values,
    )
    is Err(Source(InvalidPage)),
  )
  @row_host.close_accounted_row_run(first).unwrap()
  @row_host.close_accounted_row_run(first).unwrap()
  let isolated = @resources.ledger_usage(ledger)
  assert_eq(isolated.transferred_bytes, body.length().to_int64() * 2L)
  assert_eq(isolated.reserved_transfer_bytes, 1024L - body.length().to_int64())
  assert_eq(isolated.reserved_retention_bytes, retained)
  assert_eq(isolated.reserved_execution_bytes, execution)
  assert_eq(
    @row_host.accept_charged_row_run_values(
      sibling,
      sibling_charge,
      ["id"],
      values,
    ).unwrap(),
    1,
  )
  @row_host.finish_row_run(sibling).unwrap()
  @row_host.capture_row_run(sibling).unwrap() |> ignore
  @row_host.close_accounted_row_run(sibling).unwrap()
  let retry = @row_host.start_accounted_row_acquisition(
    acquisition,
    "row-page-close-retry",
    _ => true,
    ledger,
    1024L,
    128L,
  ).unwrap()
  @row_host.begin_row_run(retry, 128, 10, 10).unwrap()
  let retry_charge = @row_host.charge_row_run_page(retry, body).unwrap()
  assert_eq(
    @row_host.accept_charged_row_run_values(retry, retry_charge, ["id"], values).unwrap(),
    1,
  )
  @row_host.finish_row_run(retry).unwrap()
  @row_host.capture_row_run(retry).unwrap() |> ignore
  @row_host.close_accounted_row_run(retry).unwrap()
  let complete = @resources.ledger_usage(ledger)
  assert_eq(complete.transferred_bytes, body.length().to_int64() * 3L)
  assert_eq(complete.held_bytes, 0L)
  assert_eq(complete.reserved_transfer_bytes, 0L)
  assert_eq(complete.reserved_retention_bytes, 0L)
  assert_eq(complete.reserved_execution_bytes, 0L)
}
