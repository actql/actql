///|
fn keyed_file_reference_wire(identity? : String = "d") -> String {
  "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:" +
  "b".repeat(64) +
  "\",\"boundary_cid\":\"sha256:" +
  "c".repeat(64) +
  "\",\"identity_cid\":\"sha256:" +
  identity.repeat(64) +
  "\",\"provider_identity_cid\":\"sha256:" +
  "a".repeat(64) +
  "\",\"provider_namespace\":\"file-fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}"
}

///|
fn keyed_file_declared_catalog() -> (
  @rowhost.RowDeclaration,
  @environment.SourceRequestContracts,
) raise {
  // The producer seals only these authored declarations. Expected runtime rows
  // and rejection conditions below are independent, not generated from output.
  let fields : Json = {
    "resource": {
      "type": "resource_ref",
      "resource_kind": "file",
      "nullable": false,
    },
    "version": { "type": "string", "nullable": false },
  }
  let canonical = @identity.from_json(fields, 1000, 32, 100000)
  let listing : @rowhost.RowRelationViewSpec = {
    resource: "files",
    resource_kind: "file",
    schema_wire: @identity.stringify_value(canonical, 100000, 1000, 32),
    schema_cid: @identity.cid_value(canonical, 100000, 1000, 32),
    request_schema_wire: None,
    facts_wire: None,
    acquisition_wire: None,
  }
  let content_schema = @identity.from_json(
    (
      {
        "p": { "type": "number", "nullable": true },
        "resource": {
          "type": "resource_ref",
          "resource_kind": "file",
          "nullable": false,
        },
        "version": { "type": "string", "nullable": false },
      } : Json),
    1000,
    32,
    100000,
  )
  let contents : @rowhost.RowRelationViewSpec = {
    ..listing,
    resource: "contents",
    schema_wire: @identity.stringify_value(content_schema, 100000, 1000, 32),
    schema_cid: @identity.cid_value(content_schema, 100000, 1000, 32),
    request_schema_wire: Some(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"resource":{"type":"resource_ref","resource_kind":"file","nullable":false},"version":{"type":"string","nullable":false}}}
      ),
    ),
    acquisition_wire: Some(
      (
        #|{"kind":"fetch","authority":"read_content","correlation":{"request_fields":["resource","version"],"response_fields":["resource","version"],"identity":["resource","version"],"cardinality":"one"}}
      ),
    ),
    facts_wire: Some(
      (
        #|{"lookup_capacity":{"version":"actql-lookup-capacity/0.1","completeness":"complete_per_requested_key","max_rows_per_key":1,"max_pages_per_request":2,"max_response_bytes_per_page":4096}}
      ),
    ),
  }
  let declaration = @rowhost.generate_relation_row_declaration(
    "file-fixture",
    "fixture",
    "fixture/0.1",
    [listing, contents],
    {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_views: 10,
      max_fields: 100,
    },
  ).unwrap()
  let sorted = (values : Array[String]) => {
    let entries = values.map(text => {
      let body = @identity.from_json(@json.parse(text), 10000, 100, 100000)
      (@identity.cid_value(body, 100000, 10000, 100), @json.parse(text))
    })
    entries.sort_by((a, b) => a.0.compare(b.0))
    Json::array(entries.map(entry => entry.1))
  }
  let (schemas, capabilities) = @rowhost.row_declaration_evidence_members(
    declaration,
  )
  let body : Json = {
    "version": "actql-check-environment/0.1",
    "connector_capabilities": sorted(capabilities),
    "command_contracts": [],
    "connector_catalogs": [@json.parse(declaration.catalog)],
    "contract_registry": sorted(declaration.contracts),
    "host_policy_profile": {},
    "mapping_contracts": [],
    "model_task_contracts": [],
    "schema_snapshots": sorted(schemas),
    "source_views": sorted(declaration.view_bodies),
  }
  let canonical = @identity.from_json(body, 10000, 100, 100000)
  let cid = @identity.cid_value(canonical, 100000, 10000, 100)
  let sealed_body = @identity.object_with_string_field(
    canonical, "evidence_bundle_cid", cid,
  ).unwrap()
  (
    declaration,
    fixture_catalog(
      @identity.stringify_value(sealed_body, 100000, 10000, 100),
      cid,
    ),
  )
}

///|
fn keyed_file_checked_owner(
  filtered? : Bool = false,
) -> (@lower.BoundPrepared, KeyedSourceFacts, @rowhost.RowDeclaredView) raise {
  let (declaration, catalog) = keyed_file_declared_catalog()
  let body = if filtered {
    (
      #|{"id":"a","inputs":{"files":{"connector":"file-fixture","resource":"files"},"contents":{"connector":"file-fixture","resource":"contents"}},"from":"files","steps":[{"filter":"version = 'v1'","as":"selected"},{"join":{"left":"selected","with":"contents","on":["resource","version"],"kind":"left","select":{"resource":"left.resource","version":"left.version"}},"as":"joined"}],"results":{"r":{"from":"joined","fields":["version"]}}}
    )
  } else {
    (
      #|{"id":"a","inputs":{"files":{"connector":"file-fixture","resource":"files"},"contents":{"connector":"file-fixture","resource":"contents"}},"from":"files","steps":[{"join":{"left":"files","with":"contents","on":["resource","version"],"kind":"left","select":{"p":"right.p","resource":"left.resource","version":"left.version"}},"as":"joined"}],"results":{"r":{"from":"joined","fields":["version"]}}}
    )
  }
  let inputs = fixture_inputs("{}", stage_bodies=Some(body))
  let resolved = resolve(inputs, catalog, caps()).unwrap()
  let prepared = prepare_pipeline_inputs(resolved, 1000000).unwrap()
  // Select registrations by their actual declaration names, not incidental
  // source-input collection order.
  let registrations = []
  for name in ["files", "contents"] {
    for i in 0..<pipeline_input_count(prepared, 0).unwrap() {
      let entry = pipeline_input_at(prepared, 0, i).unwrap()
      if entry.0 == name {
        registrations.push(entry)
      }
    }
  }
  let stage = registered_stage(@inputs.source(inputs), registrations)
  let operations = @stages.collect_operations(
    @inputs.source(inputs),
    [@collection.pipeline(@stages.collection(stage))],
    {
      max_work: 1000000,
      max_slots: 1000,
      max_references: 1000,
      max_pointer_units: 1000000,
      max_direct_text_bytes: 1000000,
    },
  ).unwrap()
  let attached = attach_pipeline_inputs(
    prepared,
    @stages.operations_stage_at(operations, 0).unwrap(),
    1000000,
  ).unwrap()
  let results = @stage_results.check(operations, {
    max_results: 100,
    max_work: 1000000,
    max_nodes: 100000,
    max_text_bytes: 1000000,
    max_depth: 100,
  }).unwrap()
  let uses = collect_pipeline_uses(attached, results, 1000000).unwrap()
  let context = prepare_requests(resolved, request_slots(inputs), 1000000).unwrap()
  let parameters = prepare_request_parameters(
    context,
    supplied_values(inputs, "{}"),
    1000000,
  ).unwrap()
  let requests = check_pipeline_requests(uses, parameters, request_caps()).unwrap()
  let joined = check_keyed_joins(requests, 1000000).unwrap()
  let facts = @environment.check_lookup_capacities(
    pipeline_catalog_references(prepared),
    { max_work: 1000000, max_facts: 100, },
  ).unwrap()
  let facts = keyed_facts_at(
    check_keyed_facts(joined, facts, 1000000).unwrap(),
    0,
  ).unwrap()
  let lowered = @lower.prepare(
    @collection.pipeline(@stages.collection(stage)),
    {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    lowered,
    Some(request_parameter_values(parameters)),
    max_parameters=100,
    max_name_bytes=10000,
  ).unwrap()
  (
    owner,
    facts,
    declaration.views.filter(view => view.resource == "contents")[0],
  )
}

///|
fn keyed_file_request_fixture(
  owner : @lower.BoundPrepared,
  facts : KeyedSourceFacts,
  issuer : @value.ReferenceIssuer,
  occurrences? : Int = 1,
) -> (KeyedRowRequest, @execution.CapturedRows) raise {
  let join = keyed_source_join(facts)
  guard keyed_join_left(join) is @pipeline.Input(index) else {
    fail("left port")
  }
  let schema = @lower.preparation_input_schema(
    @lower.bound_preparation(owner),
    index,
  ).unwrap()
  let retention : @execution.ValueLimits = {
    max_nodes: 100,
    max_depth: 10,
    max_work: 10000,
    max_text_bytes: 10000,
  }
  let input = @execution.prepare_admitted_input(
    owner, index, occurrences, retention,
  ).unwrap()
  let cells = []
  for i in 0..<@row.field_count(schema) {
    let field = @row.field_at(schema, i).unwrap()
    cells.push(
      match @row.field_reference_name(field) {
        "resource" =>
          Some(
            @value.issue_reference(
              issuer,
              field.contract,
              keyed_file_reference_wire(),
              {
                max_bytes: 4096,
                max_nodes: 256,
                max_depth: 16,
                max_text_units: 4096,
              },
            ).unwrap(),
          )
        "version" =>
          Some(@value.checked_text_value("v1", field.contract).unwrap())
        _ => fail("unexpected declared field")
      },
    )
  }
  for _ in 0..<occurrences {
    @execution.append_admitted_input(input, cells.map(cell => cell.unwrap())).unwrap()
  }
  let captured = @execution.finish_admitted_input(input).unwrap()
  let (cursor, _) = @query.start_captured_keyed_request(
    owner,
    join,
    captured,
    0,
    request_caps(),
  ).unwrap()
  let mut complete = None
  for _ in 0..<10000 {
    match advance_keyed_row_request(cursor) {
      KeyedRowRequestContinue => ()
      KeyedRowRequestComplete(request) => {
        complete = Some(request)
        break
      }
      KeyedRowRequestFailed(_) => fail("issued key request failed")
    }
  }
  (complete.unwrap(), captured)
}

///|
fn keyed_file_run_limits() -> @rowhost.RowKeyedLimits {
  {
    page: { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_rows: 2, },
    retention: {
      max_nodes: 256,
      max_depth: 16,
      max_work: 10000,
      max_text_bytes: 10000,
    },
    request: request_caps(),
    wire: {
      max_columns: 4,
      max_order_work: 10000,
      max_bytes: 4096,
      max_nodes: 1024,
      max_depth: 64,
    },
  }
}

///|
fn keyed_file_ledger() -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 32768L,
    retained_bytes: 32768L,
    execution_bytes: 1000000L,
  }).unwrap()
}

///|
test "keyed physical RowRun retains exact right input and pending cleanup on the common ledger" {
  let (owner, facts, _) = keyed_file_checked_owner()
  let (declaration, _) = keyed_file_declared_catalog()
  let issuer = @value.bind_reference_issuer(
    (_, wire) => wire == keyed_file_reference_wire(),
    _ => true,
  )
  let (request, left) = keyed_file_request_fixture(
    owner,
    facts,
    issuer,
    occurrences=2,
  )
  let body = @utf8.encode(
    "[{\"p\":null,\"resource\":" +
    keyed_file_reference_wire() +
    ",\"version\":\"v1\"}]",
  )
  let acquisition = @rowhost.prepare_keyed_row_acquisition(
    owner,
    facts,
    request,
    declaration,
    keyed_file_run_limits(),
  ).unwrap()
  let ledger = keyed_file_ledger()
  let settled : Array[@rowhost.RowAttempt] = []
  let start = fn() {
    @rowhost.start_accounted_keyed_row_acquisition(
      acquisition,
      "physical-keyed-test",
      attempt => settled.any(actual => physical_equal(actual, attempt)),
      ledger,
      8192L,
      4096L,
      attempt => settled.any(actual => physical_equal(actual, attempt)),
    ).unwrap()
  }
  let run = start()
  @rowhost.begin_keyed_row_run(run, reference_issuer=Some(issuer)).unwrap()
  assert_true(@rowhost.capture_row_run(run) is Err(@rowhost.InvalidState))
  @rowhost.begin_row_run_keyed_page(run, body).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    match @rowhost.advance_row_run_keyed_page(run, 1).unwrap() {
      KeyedPageContinue(..) => ()
      KeyedPageComplete(rows=1, ..) => {
        complete = true
        break
      }
      _ => fail("keyed row cardinality")
    }
  }
  assert_true(complete)
  @rowhost.finish_row_run(run).unwrap()
  assert_true(
    @rowhost.retain_keyed_row_run(run)
    is Err(@rowhost.Evidence(@rowhost.UnverifiedTransport)),
  )
  let before = @resources.ledger_usage(ledger)
  assert_eq(before.transferred_bytes, body.length().to_int64())
  assert_true(before.reserved_retention_bytes > 0L)
  assert_true(before.reserved_execution_bytes > 0L)
  assert_eq(before.held_bytes, 0L)
  settled.push(@rowhost.row_run_attempt(run))
  let capture = @rowhost.retain_keyed_row_run(run).unwrap()
  let right = @rowhost.keyed_row_capture_read(capture).unwrap()
  assert_true(@execution.supplied_relation_read_available(right))
  assert_eq(@execution.supplied_relation_read_row_count(right), 1)
  assert_true(
    @execution.supplied_relation_read_cell(right, 0, 0) is Some(@value.Null),
  )
  let retained_usage = @resources.ledger_usage(ledger)
  // The authored body is canonical in schema-name order. One response is
  // retained, not a replayed JOIN output or one copy per left occurrence.
  assert_eq(retained_usage.held_bytes, body.length().to_int64())
  assert_eq(retained_usage.holdings, 1)
  assert_eq(retained_usage.reserved_retention_bytes, 0L)
  assert_eq(retained_usage.reserved_execution_bytes, 0L)
  @rowhost.retain_keyed_row_run(run).unwrap() |> ignore
  assert_eq(@resources.ledger_usage(ledger), retained_usage)
  let join = keyed_source_join(facts)
  let left_read = @execution.prepare_supplied_relation_read(
    owner,
    match keyed_join_left(join) {
      @pipeline.Input(index) => index
      _ => abort("left port")
    },
    left,
    () => true,
  ).unwrap()
  let values : @execution.ValueLimits = {
    max_nodes: 1000,
    max_depth: 100,
    max_work: 100000,
    max_text_bytes: 10000,
  }
  let step = keyed_join_step(join)
  let sequence = @lower.prepare_sequence_prefix(owner, step, {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
  let contracts = @execution.admit_relation_registry(
    registered_body(),
    registered_values(),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let generated = @execution.prepare_generated_sequence(
    contracts,
    sequence,
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), step).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let generated = @execution.select_generated_sequence_step(
    generated,
    keyed_join_step(join),
  ).unwrap()
  let session = @execution.start_bounded_join(
    @bounded.control(),
    generated,
    @execution.trusted_output_supplied_relation_input(left_read),
    @execution.trusted_output_supplied_relation_input(right),
    100,
    values,
    values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  let mut output = None
  for _ in 0..<100000 {
    match @execution.advance_bounded_join(session, 1).unwrap() {
      BoundedJoinContinue(..) => ()
      BoundedJoinComplete(value, ..) => {
        output = Some(value)
        break
      }
      _ => fail("live retained keyed JOIN")
    }
  }
  assert_eq(@execution.completed_row_count(output.unwrap()), 2)
  assert_true(@execution.cleanup_bounded_join(session).unwrap())
  @rowhost.close_accounted_row_run(run).unwrap()
  assert_false(@execution.supplied_relation_read_available(right))
  assert_true(
    @rowhost.keyed_row_capture_read(capture) is Err(@rowhost.InvalidState),
  )
  assert_eq(@execution.captured_row_count(left), 2)
  let released = @resources.ledger_usage(ledger)
  assert_eq(
    (
      released.held_bytes,
      released.reserved_retention_bytes,
      released.reserved_execution_bytes,
      released.reserved_transfer_bytes,
    ),
    (0L, 0L, 0L, 0L),
  )
  @rowhost.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger), released)

  // Positive admission work then cancel/close does not confirm physical stop.
  let cancelled = start()
  @rowhost.begin_keyed_row_run(cancelled, reference_issuer=Some(issuer)).unwrap()
  @rowhost.begin_row_run_keyed_page(cancelled, body).unwrap()
  assert_true(
    @rowhost.advance_row_run_keyed_page(cancelled, 1)
    is Ok(KeyedPageContinue(work=1)),
  )
  let pending = @resources.ledger_usage(ledger)
  assert_true(
    @rowhost.close_accounted_row_run(cancelled)
    is Err(@rowhost.Evidence(@rowhost.UnverifiedTransport)),
  )
  assert_eq(@resources.ledger_usage(ledger), pending)
  assert_true(
    @rowhost.retain_keyed_row_run(cancelled) is Err(@rowhost.InvalidState),
  )
  // Retry the same closed run with its retained physical-stop authority.
  settled.push(@rowhost.row_run_attempt(cancelled))
  @rowhost.close_accounted_row_run(cancelled).unwrap()
  let recovered = @resources.ledger_usage(ledger)
  assert_eq(
    (
      recovered.held_bytes,
      recovered.reserved_retention_bytes,
      recovered.reserved_execution_bytes,
      recovered.reserved_transfer_bytes,
    ),
    (0L, 0L, 0L, 0L),
  )
  assert_eq(@execution.captured_row_count(left), 2)
}

///|
test "keyed physical RowRun reserves the independent workspace bound and preserves failed cleanup" {
  let (owner, facts, _) = keyed_file_checked_owner()
  let (declaration, _) = keyed_file_declared_catalog()
  let issuer = @value.bind_reference_issuer(
    (_, wire) => wire == keyed_file_reference_wire(),
    _ => true,
  )
  let (request, left) = keyed_file_request_fixture(owner, facts, issuer)
  let acquisition = @rowhost.prepare_keyed_row_acquisition(
    owner,
    facts,
    request,
    declaration,
    keyed_file_run_limits(),
  ).unwrap()
  // Independent overlapping workspace: wire 4096 + page 4096 + retained
  // text 10000 + request text 100000 + physical scratch 4096 = 122288.
  // These are canonical/workspace units, not a whole-process heap/RSS bound.
  let budget : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 4096L,
    retained_bytes: 4096L,
    execution_bytes: 122288L,
  }
  for
    (limits, expected) in [
      ({ ..budget, execution_bytes: 122287L, }, @resources.ExecutionLimit),
      ({ ..budget, retained_bytes: 4095L, }, @resources.RetentionLimit),
    ] {
    let ledger = @resources.create_ledger(limits).unwrap()
    let before = @resources.ledger_usage(ledger)
    assert_true(
      @rowhost.start_accounted_keyed_row_acquisition(
        acquisition,
        "keyed-short-budget",
        _ => false,
        ledger,
        4096L,
        4096L,
        _ => false,
      )
      is Err(@rowhost.Physical(issue)) &&
      issue == expected,
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  for version in ["v1", "v2"] {
    let ledger = @resources.create_ledger(budget).unwrap()
    let settled = Ref(false)
    let stopped = Ref(false)
    let run = @rowhost.start_accounted_keyed_row_acquisition(
      acquisition,
      "keyed-exact-budget",
      _ => settled.val,
      ledger,
      4096L,
      4096L,
      _ => stopped.val,
    ).unwrap()
    let reserved = @resources.ledger_usage(ledger)
    assert_eq(reserved.reserved_execution_bytes, 122288L)
    assert_eq(reserved.reserved_retention_bytes, 4096L)
    assert_eq(reserved.reserved_transfer_bytes, 4096L)
    @rowhost.begin_keyed_row_run(run, reference_issuer=Some(issuer)).unwrap()
    let body = @utf8.encode(
      "[{\"p\":null,\"resource\":" +
      keyed_file_reference_wire() +
      ",\"version\":\"" +
      version +
      "\"}]",
    )
    @rowhost.begin_row_run_keyed_page(run, body).unwrap()
    let mut done = false
    let mut refused = false
    for _ in 0..<10000 {
      match @rowhost.advance_row_run_keyed_page(run, 1) {
        Ok(KeyedPageContinue(..)) => ()
        Ok(KeyedPageComplete(rows=1, ..)) => {
          done = true
          break
        }
        Err(@rowhost.Source(@rowhost.KeyedResponse(CorrelationMismatch(1)))) => {
          refused = true
          break
        }
        _ => fail("exact budget keyed poll")
      }
    }
    assert_eq((done, refused), (version == "v1", version == "v2"))
    let observed = @resources.ledger_usage(ledger)
    assert_eq(observed.transferred_bytes, body.length().to_int64())
    assert_eq(observed.reserved_execution_bytes, 122288L)
    assert_eq(observed.reserved_retention_bytes, 4096L)
    if done {
      @rowhost.finish_row_run(run).unwrap()
      settled.val = true
      stopped.val = true
      let capture = @rowhost.retain_keyed_row_run(run).unwrap()
      let reader = @rowhost.keyed_row_capture_read(capture).unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).held_bytes,
        body.length().to_int64(),
      )
      @rowhost.close_accounted_row_run(run).unwrap()
      assert_false(@execution.supplied_relation_read_available(reader))
    } else {
      assert_true(@rowhost.finish_row_run(run) is Err(@rowhost.InvalidState))
      assert_true(
        @rowhost.retain_keyed_row_run(run) is Err(@rowhost.InvalidState),
      )
      assert_true(
        @rowhost.close_accounted_row_run(run)
        is Err(@rowhost.Evidence(@rowhost.UnverifiedTransport)),
      )
      assert_eq(@resources.ledger_usage(ledger), observed)
      stopped.val = true
      @rowhost.close_accounted_row_run(run).unwrap()
      assert_false(
        settled.val,
        msg="physical stop does not issue successful response evidence",
      )
    }
    let released = @resources.ledger_usage(ledger)
    assert_eq(
      (
        released.held_bytes,
        released.reserved_retention_bytes,
        released.reserved_execution_bytes,
        released.reserved_transfer_bytes,
      ),
      (0L, 0L, 0L, 0L),
    )
    assert_eq(released.transferred_bytes, body.length().to_int64())
    @rowhost.close_accounted_row_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger), released)
  }
  assert_eq(@execution.captured_row_count(left), 1)
}

///|
test "keyed row reader uses common selected attempt authority without Direct substitution" {
  let (owner, facts, view) = keyed_file_checked_owner()
  let issuer = @value.bind_reference_issuer(
    (_, wire) => wire == keyed_file_reference_wire(),
    _ => true,
  )
  let (request, left) = keyed_file_request_fixture(owner, facts, issuer)
  let begin = fn() {
    @rowhost.begin_declared_keyed_row_read(
      owner,
      facts,
      request,
      "file-fixture",
      view,
      { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_rows: 2, },
      1,
      { max_nodes: 256, max_depth: 16, max_work: 10000, max_text_bytes: 10000, },
      request_caps(),
      reference_issuer=Some(issuer),
    ).unwrap()
  }
  let registry = @connector.prepare_capability_registry(
    [
      {
        name: "fixture",
        acquisition: true,
        fixed_compute: false,
        effect: false,
      },
    ],
    1,
    7,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let read = begin()
  let candidate = @planning.bind_acquisition_candidate(
    registration,
    facts,
    read,
    @cost.Unknown,
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
  ).unwrap()
  let selected = fn(candidate) {
    guard @planning.choose_acquisition_candidate(
        registry,
        facts,
        [@planning.prepared_acquisition_candidate(candidate)],
        Some([0]),
        10,
      ).unwrap()
      is @planning.Proposed(choice) else {
      abort("Host-prioritized original keyed candidate")
    }
    choice
  }
  let choice = selected(candidate)
  // Trusted physical-settlement double, not a public I/O acceptance claim.
  // Admission below cannot add itself to this exact settled-attempt set.
  let settled : Array[@rowhost.RowSourceRead] = []
  let attempt_owner = @planning.register_query_evidence_issuer(
    facts,
    facts,
    "keyed-test-process",
    128,
    "keyed-source-issuer",
    read => settled.any(actual => physical_equal(actual, read)),
  ).unwrap()
  let (payload, authority) = @planning.reserve_selected_query_evidence_attempt(
    attempt_owner,
    choice,
    candidate,
    read => @rowhost.keyed_row_read_facts(read).unwrap(),
  ).unwrap()
  assert_true(physical_equal(payload, read))
  assert_eq(@planning.query_evidence_attempt_number(authority), "0")
  assert_false(@planning.query_evidence_transport_matches(attempt_owner, read))
  let competing = @planning.bind_acquisition_candidate(
    registration,
    facts,
    begin(),
    @cost.Unknown,
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
  ).unwrap()
  assert_true(
    @planning.reserve_selected_query_evidence_attempt(
      attempt_owner,
      choice,
      competing,
      read => @rowhost.keyed_row_read_facts(read).unwrap(),
    )
    is Err(@planning.NotSelected),
  )
  let (_, foreign_facts, _) = keyed_file_checked_owner()
  assert_true(
    @planning.reserve_selected_query_evidence_attempt(
      attempt_owner,
      choice,
      candidate,
      _ => foreign_facts,
    )
    is Err(@planning.ForeignRequirement),
  )
  let foreign_candidate = @planning.bind_acquisition_candidate(
    registration,
    foreign_facts,
    read,
    @cost.Unknown,
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
  ).unwrap()
  assert_true(
    @planning.choose_acquisition_candidate(
      registry,
      facts,
      [@planning.prepared_acquisition_candidate(foreign_candidate)],
      Some([0]),
      10,
    )
    is Err(@planning.ForeignQuery(0)),
  )
  guard @planning.choose_acquisition_candidate(
      registry,
      foreign_facts,
      [@planning.prepared_acquisition_candidate(foreign_candidate)],
      Some([0]),
      10,
    ).unwrap()
    is @planning.Proposed(foreign_choice) else {
    fail("foreign original candidate")
  }
  // Even an incorrect provider accessor cannot hide the candidate's checked
  // requirement from the same shared registration owner.
  assert_true(
    @planning.reserve_selected_query_evidence_attempt(
      attempt_owner,
      foreign_choice,
      foreign_candidate,
      _ => facts,
    )
    is Err(@planning.ForeignRequirement),
  )
  @rowhost.accept_keyed_row_page(
    read,
    @utf8.encode(
      "[{\"p\":null,\"resource\":" +
      keyed_file_reference_wire() +
      ",\"version\":\"v1\"}]",
    ),
  ).unwrap()
  |> ignore
  let rows = @rowhost.complete_keyed_row_read(read).unwrap()
  assert_eq(@execution.captured_row_count(rows), 1)
  assert_true(
    @execution.captured_presence_cell(rows, 0, 0)
    is Ok(@execution.Present(@value.Null)),
  )
  assert_false(@planning.query_evidence_transport_matches(attempt_owner, read))
  settled.push(read)
  assert_true(@planning.query_evidence_transport_matches(attempt_owner, read))
  assert_false(
    @planning.query_evidence_transport_matches(attempt_owner, begin()),
  )
  let (_, next) = @planning.reserve_selected_query_evidence_attempt(
    attempt_owner,
    selected(competing),
    competing,
    read => @rowhost.keyed_row_read_facts(read).unwrap(),
  ).unwrap()
  assert_eq(@planning.query_evidence_attempt_number(next), "1")
  @planning.close_query_evidence_registration(attempt_owner)
  assert_false(@planning.query_evidence_transport_matches(attempt_owner, read))
  assert_true(
    @planning.reserve_selected_query_evidence_attempt(
      attempt_owner,
      choice,
      candidate,
      read => @rowhost.keyed_row_read_facts(read).unwrap(),
    )
    is Err(@planning.IssuerClosed),
  )
  assert_eq(@execution.captured_row_count(left), 1)
  assert_eq(@execution.captured_row_count(rows), 1)
  @connector.close_capability_registry(registry)
  assert_true(@planning.acquisition_choice_payload(choice, candidate) is None)
}

///|
fn keyed_file_filtered_output(
  owner : @lower.BoundPrepared,
  versions : Array[String],
  issuer : @value.ReferenceIssuer,
) -> @execution.CompletedOutput raise {
  let first = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  guard @lower.node_input_target(first, 0) is Some(@pipeline.Input(index)) else {
    fail("filter input")
  }
  let limits : @execution.ValueLimits = {
    max_nodes: 10000,
    max_depth: 100,
    max_work: 100000,
    max_text_bytes: 10000,
  }
  let schema = @lower.preparation_input_schema(
    @lower.bound_preparation(owner),
    index,
  ).unwrap()
  let admitted = @execution.prepare_admitted_input(
    owner,
    index,
    versions.length(),
    limits,
  ).unwrap()
  for version in versions {
    let cells = []
    for column in 0..<@row.field_count(schema) {
      let field = @row.field_at(schema, column).unwrap()
      cells.push(
        match @row.field_reference_name(field) {
          "resource" =>
            @value.issue_reference(
              issuer,
              field.contract,
              keyed_file_reference_wire(),
              {
                max_bytes: 4096,
                max_nodes: 256,
                max_depth: 16,
                max_text_units: 4096,
              },
            ).unwrap()
          "version" =>
            @value.checked_text_value(version, field.contract).unwrap()
          _ => fail("unexpected field")
        },
      )
    }
    @execution.append_admitted_input(admitted, cells).unwrap()
  }
  let captured = @execution.finish_admitted_input(admitted).unwrap()
  let input = @execution.prepare_supplied_relation_read(
    owner,
    index,
    captured,
    () => true,
  ).unwrap()
  // Only the actual first operation executes. The still-unacquired keyed right
  // input is not fabricated as an empty table or eagerly read before WHERE.
  let sequence = @lower.prepare_sequence_prefix(owner, 0, {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
  let registry_limits : @execution.RegistryLimits = {
    max_body_bytes: 100000,
    max_body_nodes: 10000,
    max_body_depth: 100,
  }
  let contracts = @execution.admit_relation_registry(
    registered_body(),
    registered_values(),
    registry_limits,
  ).unwrap()
  let fragments = @execution.admit_fragment_contract(
    contracts,
    registered_fragment(),
    registry_limits,
  ).unwrap()
  let fragment = @lower.prepare_fragment_pipeline(sequence, 0, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let request = @lower.prepare_fragment_request(fragment, 10L, 1000L).unwrap()
  let context = match
    @execution.prepare_runtime_fragment(
      request,
      fragments,
      {
        max_roots: 100,
        max_nodes: 1000,
        max_work: 100000,
        max_text_bytes: 100000,
        max_links: 10000,
      },
      registry_limits,
      {
        max_input_rows: 10L,
        max_value_bytes: 1000L,
        max_live_value_bytes: 10000L,
        max_work: 100000L,
      },
    ) {
    Ok(context) => context
    Err(@execution.Material(_)) => fail("filter context material")
    Err(@execution.Candidate(_)) => fail("filter context candidate")
    Err(@execution.Admission(_)) => fail("filter context admission")
    Err(@execution.Runtime(_)) => fail("filter context runtime")
  }
  let generated = @execution.prepare_generated_sequence(
    contracts,
    sequence,
    [context],
    [@lower.node_id(first)],
    100000,
    10000,
  ).unwrap()
  let generated = @execution.select_generated_sequence_step(generated, 0).unwrap()
  let session = @execution.start_bounded_binding_rows_supplied(
    @bounded.control(),
    generated,
    input,
    100,
    limits,
    limits,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  let mut output = None
  for _ in 0..<10000 {
    match @execution.advance_bounded_binding_rows(session, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(value, ..) => {
        output = Some(value)
        break
      }
      _ => fail("filter execution failed")
    }
  }
  assert_true(@execution.cleanup_bounded_binding_rows(session).unwrap())
  output.unwrap()
}

///|
test "one captured keyed response joins every original left occurrence" {
  for quantum in [1, 7, 64] {
    let (owner, facts, view) = keyed_file_checked_owner()
    let join = keyed_source_join(facts)
    let issuer = @value.bind_reference_issuer(
      (_, wire) => wire == keyed_file_reference_wire(),
      _ => true,
    )
    let (request, left) = keyed_file_request_fixture(
      owner,
      facts,
      issuer,
      occurrences=2,
    )
    let values : @execution.ValueLimits = {
      max_nodes: 10000,
      max_depth: 100,
      max_work: 100000,
      max_text_bytes: 10000,
    }
    let read = @rowhost.begin_declared_keyed_row_read(
      owner,
      facts,
      request,
      "file-fixture",
      view,
      { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_rows: 2, },
      1,
      values,
      request_caps(),
      reference_issuer=Some(issuer),
    ).unwrap()
    @rowhost.accept_keyed_row_page(
      read,
      @utf8.encode(
        "[{\"p\":null,\"resource\":" +
        keyed_file_reference_wire() +
        ",\"version\":\"v1\"}]",
      ),
    ).unwrap()
    |> ignore
    let right = @rowhost.complete_keyed_row_read(read).unwrap()
    assert_eq(@execution.captured_row_count(left), 2)
    assert_eq(@execution.captured_row_count(right), 1)
    let left_index = match keyed_join_left(join) {
      @pipeline.Input(index) => index
      _ => fail("expected original input occurrence")
    }
    let live = Ref(true)
    // This is the ordinary private Relation input boundary, not a fabricated
    // Source observation. Physical authorization/settlement remains a separate
    // Host obligation. Only the exact original owner and input can bind here.
    let left_read = @execution.prepare_supplied_relation_read(
      owner,
      left_index,
      left,
      () => live.val,
    ).unwrap()
    let right_read = @execution.prepare_supplied_relation_read(
      owner,
      keyed_join_input(join),
      right,
      () => live.val,
    ).unwrap()
    let step = keyed_join_step(join)
    let sequence = @lower.prepare_sequence_prefix(owner, step, {
      max_steps: 100,
      max_rows: 100,
      max_cells: 10000,
      max_bindings: 100,
      max_name_bytes: 10000,
      expressions: {
        max_nodes: 10000,
        max_work: 100000,
        max_depth: 100,
        max_literal_nodes: 10000,
        max_literal_text_bytes: 10000,
      },
    }).unwrap()
    let contracts = @execution.admit_relation_registry(
      registered_body(),
      registered_values(),
      { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
    ).unwrap()
    let generated = @execution.prepare_generated_sequence(
      contracts,
      sequence,
      [],
      [
        @lower.node_id(
          @lower.node_at(@lower.bound_preparation(owner), step).unwrap(),
        ),
      ],
      100000,
      10000,
    ).unwrap()
    let generated = @execution.select_generated_sequence_step(generated, step).unwrap()
    let control = @bounded.control()
    let start = fn() {
      @execution.start_bounded_join(
        control,
        generated,
        @execution.trusted_output_supplied_relation_input(left_read),
        @execution.trusted_output_supplied_relation_input(right_read),
        100,
        values,
        values,
        100000,
        100,
        10000,
        10000,
      ).unwrap()
    }
    let session = start()
    let mut output = None
    for _ in 0..<100000 {
      match @execution.advance_bounded_join(session, quantum).unwrap() {
        BoundedJoinContinue(..) => ()
        BoundedJoinComplete(value, ..) => {
          output = Some(value)
          break
        }
        _ => fail("checked keyed response failed in the existing JOIN")
      }
    }
    let output = output.unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_eq(@execution.completed_column_count(output), 3)
    for row in 0..<2 {
      for column in 0..<@execution.completed_column_count(output) {
        match @execution.completed_column_name(output, column) {
          Some("p") =>
            assert_true(
              @execution.completed_cell(output, row, column)
              is Some(@execution.Null),
            )
          Some("version") =>
            assert_true(
              @execution.completed_cell(output, row, column)
              is Some(@execution.Text("v1")),
            )
          Some("resource") => {
            guard @execution.completed_cell(output, row, column)
              is Some(@execution.Captured(@value.Reference(reference))) else {
              fail("typed resource identity was lost")
            }
            assert_eq(
              @value.reference_wire(reference),
              keyed_file_reference_wire(),
            )
          }
          _ => fail("unexpected JOIN output field")
        }
      }
    }
    assert_true(@execution.cleanup_bounded_join(session).unwrap())
    assert_false(@execution.bounded_join_cleanup_pending(session))
    assert_eq(@execution.completed_row_count(output), 2)
    assert_eq(@execution.captured_row_count(left), 2)
    assert_eq(@execution.captured_row_count(right), 1)
    // Stop after positive work. Cleanup closes only the execution workspace;
    // both captured inputs still belong to their original acquisition owner.
    let cancelled = start()
    assert_true(
      @execution.advance_bounded_join(cancelled, 1).unwrap()
      is BoundedJoinContinue(work=1L, ..),
    )
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @execution.advance_bounded_join(cancelled, 1).unwrap()
      is BoundedJoinStopped(@bounded.Cancelled, ..),
    )
    assert_true(@execution.cleanup_bounded_join(cancelled).unwrap())
    assert_false(@execution.bounded_join_cleanup_pending(cancelled))
    assert_true(@execution.supplied_relation_read_available(left_read))
    assert_true(@execution.supplied_relation_read_available(right_read))
    live.val = false
    assert_false(@execution.supplied_relation_read_available(left_read))
    assert_false(@execution.supplied_relation_read_available(right_read))
  }
}

///|
test "keyed request consumes only live completed WHERE rows and retains occurrences" {
  let (owner, facts, view) = keyed_file_checked_owner(filtered=true)
  let join = keyed_source_join(facts)
  assert_eq(keyed_join_left(join), @pipeline.Step(0))
  let issuer = @value.bind_reference_issuer(
    (_, wire) => wire == keyed_file_reference_wire(),
    _ => true,
  )
  let filtered = keyed_file_filtered_output(owner, ["v2", "v1", "v1"], issuer)
  assert_eq(@execution.completed_row_count(filtered), 2)
  let live = Ref(true)
  let restricted = @execution.restrict_completed_output(filtered, () => live.val)
  let bound = @execution.bind_completed_operation_input(
    owner,
    keyed_join_step(join),
    0,
    owner,
    restricted,
  ).unwrap()
  let left = @execution.prepare_producer_read(owner, bound, 100, 10000).unwrap()
  for row in 0..<2 {
    let (cursor, extraction_work) = @query.start_produced_keyed_request(
      owner,
      join,
      left,
      row,
      request_caps(),
    ).unwrap()
    // Owner visit 1 + two role visits 2 + resource lookup (1+8+8)
    // + version lookup (1+8+7)+(1+7+7) + two code units for converting
    // the computed Text("v1") representation. No value coincidence lookup.
    assert_eq(extraction_work, 53)
    let mut request = None
    for _ in 0..<10000 {
      match advance_keyed_row_request(cursor) {
        KeyedRowRequestContinue => ()
        KeyedRowRequestComplete(value) => {
          request = Some(value)
          break
        }
        KeyedRowRequestFailed(_) => fail("completed request failed")
      }
    }
    let request = request.unwrap()
    assert_eq(
      keyed_row_request_wire(request, 4096, 256, 16).unwrap(),
      "{\"resource\":" + keyed_file_reference_wire() + ",\"version\":\"v1\"}",
    )
    let read = @rowhost.begin_declared_keyed_row_read(
      owner,
      facts,
      request,
      "file-fixture",
      view,
      { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_rows: 2, },
      1,
      { max_nodes: 256, max_depth: 16, max_work: 10000, max_text_bytes: 10000, },
      request_caps(),
      reference_issuer=Some(issuer),
    ).unwrap()
    assert_eq(
      @rowhost.accept_keyed_row_page(
        read,
        @utf8.encode(
          "[{\"p\":null,\"resource\":" +
          keyed_file_reference_wire() +
          ",\"version\":\"v1\"}]",
        ),
      ).unwrap(),
      1,
    )
    assert_eq(
      @execution.captured_row_count(
        @rowhost.complete_keyed_row_read(read).unwrap(),
      ),
      1,
    )
  }
  assert_true(
    @query.start_produced_keyed_request(owner, join, left, 2, request_caps())
    is Err(@query.InvalidRow),
  )
  assert_true(
    @query.start_produced_keyed_request(owner, join, left, 0, {
      ..request_caps(),
      max_work: 50,
    })
    is Err(@query.WorkLimit),
  )
  let (foreign_owner, _, _) = keyed_file_checked_owner(filtered=true)
  assert_true(
    @query.start_produced_keyed_request(
      foreign_owner,
      join,
      left,
      0,
      request_caps(),
    )
    is Err(@query.ForeignPipeline),
  )
  let (cancelled, _) = @query.start_produced_keyed_request(
    owner,
    join,
    left,
    0,
    request_caps(),
  ).unwrap()
  advance_keyed_row_request(cancelled) |> ignore
  let consumed = keyed_row_request_work(cancelled)
  cancel_keyed_row_request(cancelled)
  assert_eq(keyed_row_request_work(cancelled), consumed)
  assert_true(@execution.producer_read_available(left))
  live.val = false
  assert_true(
    @query.start_produced_keyed_request(owner, join, left, 0, request_caps())
    is Err(@query.ForeignInput),
  )
  assert_eq(@execution.completed_row_count(filtered), 2)
  let empty = keyed_file_filtered_output(owner, ["v2"], issuer)
  assert_eq(@execution.completed_row_count(empty), 0)
  let empty_binding = @execution.bind_completed_operation_input(
    owner,
    keyed_join_step(join),
    0,
    owner,
    empty,
  ).unwrap()
  let empty_read = @execution.prepare_producer_read(
    owner, empty_binding, 100, 10000,
  ).unwrap()
  assert_true(
    @query.start_produced_keyed_request(
      owner,
      join,
      empty_read,
      0,
      request_caps(),
    )
    is Err(@query.InvalidRow),
  )
}

///|
test "keyed JOIN keeps the existing unsupported conditional-input refusal" {
  let (owner, facts, _) = keyed_file_checked_owner()
  let join = keyed_source_join(facts)
  guard keyed_join_left(join) is @pipeline.Input(index) else {
    fail("left port")
  }
  let schema = @lower.preparation_input_schema(
    @lower.bound_preparation(owner),
    index,
  ).unwrap()
  let fields = []
  for i in 0..<@row.field_count(schema) {
    let field = @row.field_at(schema, i).unwrap()
    fields.push((field.name, field.contract, @row.Required))
  }
  fields.push(
    (
      @row.Unqualified("p"),
      @contract.primitive(@contract.NumberType, nullable=true),
      @row.Conditional,
    ),
  )
  let sparse = @row.from_presence_fields(
    fields,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    @pipeline.check(
      keyed_input_row_cursor(
        (
          #|[{"join":{"with":"contents","on":["resource","version"],"select":{"version":"left.version"}}}]
        ),
      ),
      [("files", sparse), ("contents", schema)],
      None,
      Some(keyed_input_row_cursor("\"files\"")),
      {
        max_steps: 10,
        max_work: 100000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    )
    is Err({ kind: Operation(@relation.ConditionalInputNotImplemented), .. }),
  )
}

///|
test "keyed response binds the original Catalog schema and policy before admission" {
  let (owner, facts, view) = keyed_file_checked_owner()
  let issuer = @value.bind_reference_issuer(
    (_, wire) => wire == keyed_file_reference_wire(),
    _ => true,
  )
  let (request, left) = keyed_file_request_fixture(owner, facts, issuer)
  let metadata = @planning.keyed_source_evidence_facts(facts).unwrap()
  assert_eq(metadata.source_ref, "connector://file-fixture/contents#records")
  assert_eq(metadata.source_contract_cid, view.view_cid)
  assert_eq(metadata.carrier_schema_contract_cid, view.carrier_schema_cid)
  assert_eq(metadata.source_data_policy_cid, view.data_policy_cid)
  assert_eq(metadata.data_classification, "unknown")
  let members = @planning.keyed_source_evidence_members(facts).unwrap()
  assert_true(
    @environment.connector_source_evidence_supports(members, [
      @planning.query_evidence_contract_identity(),
    ]),
  )
  assert_false(
    @environment.connector_source_evidence_supports(members, [
      "sha256:" + "f".repeat(64),
    ]),
  )
  // Use the actual selected identity while changing one physical declaration
  // fact. Name/CID coincidence must not admit a foreign schema or policy.
  for
    (source, schema_cid, policy_cid) in [
      (
        "connector://file-fixture/files#records",
        view.carrier_schema_cid,
        view.data_policy_cid,
      ),
      (view.source_ref, "sha256:" + "f".repeat(64), view.data_policy_cid),
      (view.source_ref, view.carrier_schema_cid, "sha256:" + "f".repeat(64)),
    ] {
    let foreign = @rowhost.declared_row_view(
      view.resource,
      source,
      view.view_cid,
      view.fields,
      schema_cid,
      policy_cid,
    )
    assert_true(
      @rowhost.begin_declared_keyed_row_read(
        owner,
        facts,
        request,
        "file-fixture",
        foreign,
        { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_rows: 2, },
        1,
        {
          max_nodes: 256,
          max_depth: 16,
          max_work: 10000,
          max_text_bytes: 10000,
        },
        request_caps(),
        reference_issuer=Some(issuer),
      )
      is Err(@rowhost.UndeclaredSource),
    )
  }
  // Refusal owns no new acquisition and cannot close its borrowed left input.
  assert_eq(@execution.captured_row_count(left), 1)
}

///|
test "keyed resource version response preserves NULL and enforces exact cardinality" {
  let (owner, facts, view) = keyed_file_checked_owner()
  let live = Ref(true)
  let issuer = @value.bind_reference_issuer(
    (_, wire) => {
      wire == keyed_file_reference_wire() ||
      wire == keyed_file_reference_wire(identity="e")
    },
    _ => live.val,
  )
  let (request, left) = keyed_file_request_fixture(owner, facts, issuer)
  let begin = fn() {
    @rowhost.begin_declared_keyed_row_read(
      owner,
      facts,
      request,
      "file-fixture",
      view,
      { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_rows: 2, },
      1,
      { max_nodes: 256, max_depth: 16, max_work: 10000, max_text_bytes: 10000, },
      request_caps(),
      reference_issuer=Some(issuer),
    ).unwrap()
  }
  let row = fn(version : String, suffix : String) {
    "{\"resource\":" +
    keyed_file_reference_wire() +
    ",\"version\":\"" +
    version +
    "\"" +
    suffix +
    "}"
  }
  for (suffix, kind) in [(",\"p\":null", 1), (",\"p\":7", 2)] {
    let read = begin()
    assert_eq(
      @rowhost.accept_keyed_row_page(
        read,
        @utf8.encode("[" + row("v1", suffix) + "]"),
      ).unwrap(),
      1,
    )
    let captured = @rowhost.complete_keyed_row_read(read).unwrap()
    assert_eq(@execution.captured_row_count(captured), 1)
    assert_eq(
      @execution.captured_origin(captured),
      @execution.SuppliedInput(keyed_join_input(keyed_source_join(facts))),
    )
    match kind {
      1 =>
        assert_true(
          @execution.captured_presence_cell(captured, 0, 0)
          is Ok(@execution.Present(@value.Null)),
        )
      _ =>
        assert_true(
          @execution.captured_presence_cell(captured, 0, 0)
          is Ok(@execution.Present(@value.Number(7))),
        )
    }
    assert_false(@rowhost.cancel_keyed_row_read(read))
  }
  let missing = begin()
  assert_true(
    @rowhost.accept_keyed_row_page(
      missing,
      @utf8.encode("[" + row("v1", "") + "]"),
    )
    is Err(@rowhost.MissingField("p")),
  )
  assert_true(@rowhost.complete_keyed_row_read(missing) is Err(@rowhost.Closed))
  let zero = begin()
  assert_eq(
    @rowhost.accept_keyed_row_page(zero, @utf8.encode("[]")).unwrap(),
    0,
  )
  assert_true(
    @rowhost.complete_keyed_row_read(zero) is Err(@rowhost.KeyedCardinality),
  )
  let two = begin()
  assert_true(
    @rowhost.accept_keyed_row_page(
      two,
      @utf8.encode(
        "[" + row("v1", ",\"p\":null") + "," + row("v1", ",\"p\":null") + "]",
      ),
    )
    is Err(@rowhost.KeyedCardinality),
  )
  assert_true(@rowhost.complete_keyed_row_read(two) is Err(@rowhost.Closed))
  let wrong = begin()
  assert_true(
    @rowhost.accept_keyed_row_page(
      wrong,
      @utf8.encode("[" + row("v2", ",\"p\":null") + "]"),
    )
    is Err(@rowhost.KeyedResponse(CorrelationMismatch(1))),
  )
  let foreign = begin()
  assert_true(
    @rowhost.accept_keyed_row_page(
      foreign,
      @utf8.encode(
        "[{\"p\":null,\"resource\":" +
        keyed_file_reference_wire(identity="e") +
        ",\"version\":\"v1\"}]",
      ),
    )
    is Err(@rowhost.KeyedResponse(CorrelationMismatch(0))),
  )
  let denied = begin()
  live.val = false
  assert_true(
    @rowhost.accept_keyed_row_page(
      denied,
      @utf8.encode("[" + row("v1", ",\"p\":null") + "]"),
    )
    is Err(@rowhost.Value("resource")),
  )
  assert_true(@rowhost.complete_keyed_row_read(denied) is Err(@rowhost.Closed))
  assert_eq(@execution.captured_row_count(left), 1)
  assert_true(
    @execution.captured_presence_cell(left, 0, 0)
    is Ok(@execution.Present(@value.Reference(_))),
  )
}

///|
test "resumed keyed admission retains physical observations and rejects authority loss" {
  let (owner, facts, view) = keyed_file_checked_owner()
  let live = Ref(true)
  let issuer = @value.bind_reference_issuer(
    (_, wire) => wire == keyed_file_reference_wire(),
    _ => live.val,
  )
  let (request, left) = keyed_file_request_fixture(owner, facts, issuer)
  let begin = fn() {
    @rowhost.begin_declared_keyed_row_read(
      owner,
      facts,
      request,
      "file-fixture",
      view,
      { max_bytes: 4096, max_nodes: 256, max_depth: 16, max_rows: 2, },
      1,
      { max_nodes: 256, max_depth: 16, max_work: 10000, max_text_bytes: 10000, },
      request_caps(),
      reference_issuer=Some(issuer),
    ).unwrap()
  }
  let oversized = begin()
  let initial = @rowhost.keyed_row_read_usage(oversized).0
  assert_true(
    @rowhost.begin_keyed_row_page(oversized, @utf8.encode(" ".repeat(4097)))
    is Err(@rowhost.KeyedLimit("response_bytes_per_page")),
  )
  assert_eq(@rowhost.keyed_row_read_usage(oversized), (initial, 1L, 4097L))
  assert_true(
    @rowhost.complete_keyed_row_read(oversized) is Err(@rowhost.Closed),
  )
  let malformed = begin()
  assert_true(
    @rowhost.begin_keyed_row_page(malformed, @utf8.encode("["))
    is Err(@rowhost.InvalidPage),
  )
  assert_eq(@rowhost.keyed_row_read_usage(malformed), (initial, 1L, 1L))
  let interrupted = begin()
  let body = @utf8.encode(
    "[{\"p\":null,\"resource\":" +
    keyed_file_reference_wire() +
    ",\"version\":\"v1\"}]",
  )
  @rowhost.begin_keyed_row_page(interrupted, body).unwrap()
  assert_true(
    @rowhost.advance_keyed_row_page(interrupted, 1) is Ok(KeyedPageContinue(..)),
  )
  // The row was admitted under live authority. Neither admission nor a
  // decoded envelope lets a later recheck ignore revocation across polls.
  live.val = false
  let mut refused = false
  for _ in 0..<1000 {
    match @rowhost.advance_keyed_row_page(interrupted, 1) {
      Ok(KeyedPageContinue(..)) => ()
      Err(@rowhost.KeyedResponse(InvalidCorrelation(0))) => {
        refused = true
        break
      }
      _ => fail("revoked reference completed keyed capture")
    }
  }
  assert_true(refused)
  let usage = @rowhost.keyed_row_read_usage(interrupted)
  assert_true(usage.0 > initial)
  assert_eq((usage.1, usage.2), (1L, body.length().to_int64()))
  assert_true(
    @rowhost.complete_keyed_row_read(interrupted) is Err(@rowhost.Closed),
  )
  assert_false(@rowhost.cancel_keyed_row_read(interrupted))
  assert_eq(@rowhost.keyed_row_read_usage(interrupted), usage)
  assert_eq(@execution.captured_row_count(left), 1)
}
