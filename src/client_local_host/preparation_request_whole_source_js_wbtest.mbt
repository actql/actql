///|
let request_whole_source_document : String =
  #|{"version":"actql/0.1","id":"same-original-whole-join","stages":[{"id":"left","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"right","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"joined","inputs":{"left":{"result":{"stage":"left","result":"rows"}},"right":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"joined","result":"rows"}}}}

///|
fn request_whole_source_fixture(
  current? : () -> Bool = () => true,
  reserve_plan? : Bool = true,
  text? : String = request_whole_source_document,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
  @publication_host.ClientRequestIdentity,
) raise {
  let declaration = pure_provider_declaration()
  let (parent, child, _, input) = registration_parent_fixture(
    text~,
    environment=Some(pure_provider_environment(declaration)),
    current~,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("the original Whole Program must check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  continue_request_program_preparation(parent, input).unwrap() |> ignore
  if reserve_plan {
    reserve_request_program_plan(parent, input).unwrap()
  }
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-original-whole-join",
  ).unwrap()
  (parent, input, prepared, request)
}

///|
test "Project File Request keeps both Whole inputs sharing one Compute" {
  let text =
    #|{"version":"actql/0.1","id":"same-task-whole-join","stages":[{"id":"joined","inputs":{"left":{"connector":"pure-provider","resource":"records"},"right":{"connector":"pure-provider","resource":"records"}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"joined","result":"rows"}}}}
  let (parent, input, prepared, request) = request_whole_source_fixture(text~)
  guard prepare_request_file_source_inputs(parent, input, request, None).unwrap()
    is WholeSourceInputs(direct, sources) else {
    fail("both authenticated occurrences require Whole construction")
  }
  assert_eq(sources.length(), 2)
  let left = @publication_host.client_direct_acquisition_occurrence_at(
    direct, 0,
  ).unwrap()
  let right = @publication_host.client_direct_acquisition_occurrence_at(
    direct, 1,
  ).unwrap()
  assert_eq(left.0, right.0)
  assert_eq(left.2, right.2)
  assert_true(left.1 != right.1)
  for index in 0..<sources.length() {
    let (stage, source_index, _) = @publication_host.client_direct_acquisition_occurrence_at(
      direct, index,
    ).unwrap()
    assert_true(
      @publication_host.client_source_acquisition_matches_program(
        prepared,
        stage,
        source_index,
        sources[index],
      ),
    )
  }
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
// Exact shared Project data fixture, including other resources and controls.
let request_file_named_result_document : String = "{\n  \"salesforce\": {\n    \"Account\": {\n      \"key\": [\n        \"id\"\n      ],\n      \"rows\": [\n        {\n          \"id\": \"a1\",\n          \"group\": \"selected\",\n          \"value\": \"A-old\"\n        },\n        {\n          \"id\": \"a-control\",\n          \"group\": \"account-control\",\n          \"value\": \"keep-account\"\n        },\n        {\n          \"id\": \"a2\",\n          \"group\": \"other\",\n          \"value\": \"A2-old\"\n        }\n      ]\n    },\n    \"Contact\": {\n      \"key\": [\n        \"id\"\n      ],\n      \"rows\": [\n        {\n          \"id\": \"c1\",\n          \"group\": \"selected\",\n          \"value\": \"C-old\"\n        },\n        {\n          \"id\": \"c-control\",\n          \"group\": \"contact-control\",\n          \"value\": \"keep-contact\"\n        }\n      ]\n    }\n  },\n  \"control\": {\n    \"unchanged\": \"keep-physical-document\"\n  }\n}\n"

///|
test "Project File Request preserves two named Results over one original acquisition" {
  let text = "FROM salesforce.accounts |> SELECT id, value |> ORDER BY id |> RESULT original |> WHERE id = 'a2' |> RESULT selected\n"
  let schema =
    #|{"group":{"nullable":false,"type":"string"},"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}
  let declaration = @row_source_host.generate_relation_row_declaration(
    "salesforce",
    "mock_salesforce",
    "mock_salesforce/0.1",
    [
      {
        resource: "Account",
        resource_kind: "record",
        schema_wire: schema,
        schema_cid: "sha256:" + @sha.hex(@utf8.encode(schema)),
        request_schema_wire: None,
        facts_wire: Some("{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"),
        acquisition_wire: None,
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 3,
    },
    classifications=Some([@environment.Internal]),
  ).unwrap()
  let environment = pure_provider_environment(declaration)
  let view = declaration.views[0]
  let publication : Json = {
    "environmentCid": Json::string(
      @checked.checking_environment_cid(environment),
    ),
    "aliases": [
      {
        "name": "salesforce.accounts",
        "sourceRef": Json::string(view.source_ref),
        "sourceViewContractCid": Json::string(view.view_cid),
        "schemaContractCid": Json::string(view.carrier_schema_cid),
      },
    ],
  }
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    publication.stringify(),
  ).unwrap()
  let body : Json = {
    "kind": "aql",
    "input": { "format": "aql", "text": Json::string(text) },
    "parameters": null,
  }
  let wire = @identity.stringify_value(
    @identity.from_json(body, 8192, 64, 65536),
    65536,
    8192,
    64,
  )
  let authored = @publication_host.prepare_client_submitted_intent(
    wire, 65536, 8192, 64,
  ).unwrap()
  // The file remains unchanged before Check. The supplied row represents
  // the already-observed preparing Submission on the Project's own Journal.
  let scope = "sha256:" + "a".repeat(64)
  let token = @publication_host.admit_client_submission_epoch_token(
    "{\"authenticator\":\"" +
    "c".repeat(64) +
    "\",\"authorityScopeCid\":\"" +
    scope +
    "\",\"epochNonce\":\"" +
    "b".repeat(64) +
    "\",\"expiresAt\":1793318401000,\"notBefore\":1793318399000," +
    "\"version\":\"actql-submission-epoch/0.1\"}",
  ).unwrap()
  let reference = @publication_host.prepare_client_submission_reference_record(
    token, "file-named-results",
  ).unwrap()
  let request_id = @publication_host.client_submission_reference_record_request_id(
    reference,
  )
  let row = @publication_host.client_submitted_intent_journal_row_body(
    @publication_host.client_submission_reference_record_wire(reference),
    authored,
  ).unwrap()
  let reads = Ref(0)
  let observe = () => {
    @publication_host.read_client_saved_submission(
      reference,
      (table, key) => {
        reads.val += 1
        if table == "client_submitted_intents" && key == request_id {
          Ok(Some({ key, body: row, revision: 6L, }))
        } else {
          Err("foreign read")
        }
      },
      _ => Err("preparing original would not read a Run"),
      "foreign submission",
    )
    .unwrap()
    .unwrap()
  }
  let snapshot = observe()
  let saved = @publication_host.client_saved_submission_record(snapshot)
  assert_true(saved.run_admission is None)
  assert_eq(@publication_host.client_saved_submission_revision(snapshot), 6L)
  assert_eq(reads.val, 1)
  let intent = saved.intent
  assert_eq(@publication_host.client_submitted_intent_wire(intent), wire)
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  match
    check_request_retained_submitted_intent(
      parent,
      input,
      intent,
      environment,
      publication,
      public_primary=true,
    ) {
    Ok(_) => ()
    Err(Request(issue)) => {
      let cause : Error = issue
      fail("original File Project Check: " + @debug.to_string(cause))
    }
    Err(_) => fail("the original named File intent must enter the same Request")
  }
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  assert_eq(request_checked_pure_direct_source_count(parent, input), Some(1L))
  assert_true(request_checked_pure_direct_source_count(parent, [1]) is None)
  assert_true(
    inspect_request_whole_file_plan_original(parent, input, (_, _, _) => true)
    is None,
  )
  let prepared = parent.compiled_program.unwrap()
  reserve_request_program_plan(parent, input).unwrap()
  let intent_cid = @publication_host.client_submitted_intent_cid(intent)
  assert_true(
    physical_equal(
      request_submitted_intent_original(parent, input).unwrap(),
      intent,
    ),
  )
  assert_eq(@publication_host.prepared_client_result_count(prepared), 2)
  assert_eq(
    @publication_host.prepared_client_result_name(prepared, 0),
    Some("original"),
  )
  assert_eq(
    @publication_host.prepared_client_result_name(prepared, 1),
    Some("selected"),
  )
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let limits = installed_row_input_policy(100, 1048576, 4096, 32, 100)
  let manifests = request_program_module_manifests()
  let compilation_limits = request_program_compilation_limits(parent, input).unwrap()
  let provider_factory = _ => []
  let initial_usage = @resources.ledger_usage(parent.ledger)
  let duplicate = observe()
  assert_eq(@publication_host.client_saved_submission_revision(duplicate), 6L)
  assert_true(
    select_request_retained_whole_file(parent, input, duplicate, scope)
    is Err(ForeignFileSubmission),
  )
  assert_true(
    select_request_retained_whole_file(
      parent,
      input,
      snapshot,
      "sha256:" + "b".repeat(64),
    )
    is Err(ForeignFileSubmission),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), initial_usage)
  let (request, selected) = select_request_retained_whole_file(
    parent, input, snapshot, scope,
  ).unwrap_or_else(() => {
    fail("both named Results require the same complete original Source")
  })
  assert_eq(@publication_host.client_request_input_cid(request), intent_cid)
  assert_eq(@publication_host.client_request_caller_id(request), request_id)
  let quote : @execution.PreparationRepresentationUnits = {
    record_headers: 24L,
    reference_slots: 48L,
    scalar_words: 32L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let quoted = @execution.preparation_representation_cost(quote).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let (retained, execution) = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  let before_provider = @resources.ledger_usage(parent.ledger)
  assert_true(
    reserve_request_whole_file_provider_selection(parent, [1], selected, quote)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before_provider)
  reserve_request_whole_file_provider_selection(parent, input, selected, quote).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    (retained + quoted, execution + quoted),
  )
  assert_eq(
    @resources.ledger_usage(parent.ledger).attempts,
    before_provider.attempts,
  )
  assert_eq(
    @resources.ledger_usage(parent.ledger).transferred_bytes,
    before_provider.transferred_bytes,
  )
  let artifact = match
    prepare_request_program_compilation(
      parent,
      input,
      contracts,
      manifests~,
      compilation_limits~,
      retained_output=false,
      provider_factory~,
    ) {
    Ok(value) => value
    Err(TaskCompilation(Plan(TaskGraph(UnsupportedGraph)))) =>
      fail("the original two-Result compilation refused its graph")
    Err(TaskCompilation(Plan(TaskGraph(Fragment(Pipeline(Sequence(_))))))) =>
      fail("the original two-Result compilation refused its Fragment sequence")
    Err(TaskCompilation(_)) =>
      fail("the original two-Result task compilation failed")
    Err(_) =>
      fail("the original two-Result compilation failed before the module")
  }
  let source = client_request_whole_file_source(selected)
  assert_true(
    @publication_host.client_source_acquisition_matches_program(
      prepared, 0, 0, source,
    ),
  )
  let copied_request = @publication_host.prepare_client_request_identity(
    prepared, scope, request_id, intent_cid,
  ).unwrap()
  assert_true(
    @publication_host.client_request_identity_relation(request, copied_request)
    is @publication_host.SameRequest,
  )
  let usage = @resources.ledger_usage(parent.ledger)
  assert_true(
    prepare_request_whole_file_module(
      parent,
      input,
      copied_request,
      selected,
      declaration,
      contracts,
      limits,
      None,
      1048576L,
      1048576L,
      manifests~,
      retained_output=false,
      provider_factory~,
    )
    is Err(WholeFileModule(Preparation(ForeignOriginal))),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), usage)
  let construction = prepare_request_whole_file_module(
    parent,
    input,
    request,
    selected,
    declaration,
    contracts,
    limits,
    None,
    1048576L,
    1048576L,
    manifests~,
    retained_output=false,
    provider_factory~,
  )
  let capacity = match construction {
    Ok(value) => value
    Err(WholeFileCapacity(Unsupported)) =>
      fail(
        "the original Whole input does not match the sequence or declared row policy",
      )
    Err(WholeFileCapacity(_)) =>
      fail("the original Whole input capacity must admit")
    Err(WholeFilePlan(_)) =>
      fail("the original Whole capacity must construct the Run Plan")
    Err(WholeFileCompilerLimits(_)) =>
      fail("the original Request compiler limits must be live")
    Err(WholeFileModule(Preparation(_))) =>
      fail("the original Whole module must retain the Request preparation")
    Err(WholeFileModule(Installed(_))) =>
      fail("the original Whole module must retain the installed inputs")
    Err(WholeFileModule(CapacityExceeded(_))) =>
      fail("the original Whole module must fit the fixture Request reservation")
    Err(WholeFileModule(Construction(_))) =>
      fail("the original Whole module must construct execution material")
    Err(WholeFileModule(TaskCompilation(_))) =>
      fail("the original Whole module must compile its exact task graph")
    Err(WholeFileModule(_)) => fail("the original Whole module must compile")
  }
  guard artifact is @publication_host.Tasks(tasks) else {
    fail("the retained named File Plan must own the actual Tasks compiler")
  }
  let inspections = Ref(0)
  let inspect = (original, checked, compilation) => {
    inspections.val += 1
    physical_equal(original, request) &&
    physical_equal(checked, prepared) &&
    physical_equal(compilation, tasks)
  }
  let usage = @resources.ledger_usage(parent.ledger)
  assert_true(
    inspect_request_whole_file_plan_original(parent, [1], inspect) is None,
  )
  assert_eq(inspections.val, 0)
  assert_eq(
    inspect_request_whole_file_plan_original(parent, input, inspect),
    Some(true),
  )
  assert_eq(inspections.val, 1)
  assert_eq(@resources.ledger_usage(parent.ledger), usage)
  let at = "2026-10-30T00:00:00.000Z"
  let originals = @publication_host.client_local_product_common_originals(
    "/fixture/file-named-results", at, assets,
  ).unwrap()
  let profile = @publication_host.client_local_run_policy_profile(originals).unwrap()
  let retention = @publication_host.issue_client_local_run_retention_policy(
    profile, at,
  ).unwrap()
  let until = @publication.result_retention_available_until(retention).unwrap()
  let (compiled, definition, foreign_definition) = prepare_file_named_result_definition(
    prepared, request, tasks, until,
  )
  let materials = check_file_named_result_materials(
    parent, input, request, compiled, definition, foreign_definition, manifests,
  )
  let policy = @publication_host.bind_client_local_run_policy_original(
    profile,
    saved.reference,
    request,
    definition,
    retention,
    at,
    "sha256:" + "b".repeat(64),
    "sha256:" + "d".repeat(64),
  ).unwrap()
  check_file_named_result_first_run_rows(
    parent, input, snapshot, request, definition, materials, policy, 1793318400000.0,
  )
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  assert_true(
    inspect_request_whole_file_plan_original(parent, input, inspect) is None,
  )
  assert_eq(inspections.val, 1)
  assert_true(
    physical_equal(
      installed_managed_run_compilation_original(run, prepared).unwrap(),
      artifact,
    ),
  )
  let (read, original, acquisition, actual) = begin_installed_managed_whole_source_read(
    run, prepared, request, declaration,
  ).unwrap()
  assert_true(physical_equal(original, source))
  assert_true(physical_equal(actual, capacity))
  assert_true(
    @row_source_host.row_input_acquisition_matches_source(acquisition, original),
  )
  let ledger = run.ledger.unwrap()
  let before_read = @resources.ledger_usage(ledger)
  let original_attempt : Ref[@row_source_host.RowAttempt?] = Ref(None)
  let rows = start_installed_whole_source_read_rows(
    read,
    acquisition,
    "file-named-results",
    attempt => {
      match original_attempt.val {
        Some(pinned) => physical_equal(attempt, pinned)
        None => {
          original_attempt.val = Some(attempt)
          true
        }
      }
    },
    1048576L,
    1048576L,
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_attempts,
    before_read.reserved_attempts + 1,
  )
  let limits = @row_source_host.row_input_acquisition_limits(acquisition)
  @row_source_host.begin_row_run_with_page_limits(
    rows,
    limits.page,
    limits.max_rows,
  ).unwrap()
  let confirmations = Ref(0)
  let responses = @row_source_host.borrow_row_input_run_responses(
    rows, acquisition,
  ).unwrap()
  @row_source_host.bind_row_run_response_borrow_cleanup(responses, () => {
    confirmations.val += 1
    true
  }).unwrap()
  let bytes = @utf8.encode(request_file_named_result_document)
  assert_eq(
    @sha.hex(bytes),
    "5da59e60eb1b085f8dc45870d15445698473d9df88c81eb9c392bf2097114d59",
  )
  let charge = @row_source_host.charge_row_run_page(rows, bytes).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, before_read.attempts + 1)
  let document = @row_source_host.admit_relation_document(
    bytes,
    limits.page,
    16777216,
  ).unwrap()
  let target = @row_source_host.project_relation_target_document(
    document,
    declaration,
    "Account",
    ["salesforce", "Account", "rows"],
    Some(["salesforce", "Account", "key"]),
    "id",
    [],
  ).unwrap()
  @row_source_host.accept_charged_relation_input_document(
    rows, charge, acquisition, target, 16777216,
  ).unwrap()
  |> ignore
  @row_source_host.finish_row_run(rows).unwrap()
  assert_true(
    @row_source_host.discard_relation_target_document_original(target),
  )
  assert_true(@row_source_host.discard_relation_document_original(document))
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut complete = false
  for _ in 0..<1000 {
    if @row_source_host.advance_row_capture(rows, 8).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  let captured = @row_source_host.row_capture_source(capture).unwrap()
  assert_eq(@query.captured_source_row_count(captured), Some(3))
  let identity = bind_file_named_result_invocation(
    run, prepared, request, compiled, definition, foreign_definition, original, acquisition,
    capture, captured,
  )
  check_file_named_result_outputs(
    run, prepared, request, compiled, captured, capture, identity, retention, foreign_definition,
  )
  assert_true(
    physical_equal(
      original_attempt.val.unwrap(),
      @row_source_host.row_run_attempt(rows),
    ),
  )
  assert_eq(confirmations.val, 0)
  retire_installed_source_read(read).unwrap()
  assert_eq(confirmations.val, 1)
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
fn prepare_file_named_result_definition(
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compilation : @publication_host.ClientTaskCompilation,
  until : String,
) -> (
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication.PublicationContract,
) raise {
  let started = "2026-10-30T00:00:00.000Z"
  let scope = @publication_host.client_request_authority_scope_cid(request)
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    scope,
    "sha256:" + "b".repeat(64),
    until,
  ).unwrap()
  let caller = @publication_host.client_request_caller_id(request)
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "file-named-results", caller, started, until,
  ).unwrap()
  let foreign_compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    scope,
    "sha256:" + "b".repeat(64),
    until,
  ).unwrap()
  let foreign_definition = @publication_host.issue_client_compiled_run_definition(
    foreign_compiled, "file-named-results", caller, started, until,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(foreign_definition),
    @publication.publication_contract_identity(definition),
  )
  assert_false(physical_equal(foreign_definition, definition))
  (compiled, definition, foreign_definition)
}

///|
fn check_file_named_result_materials(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  foreign_definition : @publication.PublicationContract,
  manifests : @publication_host.ClientCompilationManifests,
) -> @publication_host.ClientCapturedTaskRunMaterials raise {
  let purposes : Array[String] = []
  let positive_geometry = Ref(true)
  let issue = (definition, allowed) => {
    issue_request_whole_file_run_materials(
      parent,
      input,
      request,
      compiled,
      definition,
      (purpose, bytes, nodes, depth) => {
        positive_geometry.val = positive_geometry.val &&
          bytes > 0 &&
          nodes > 0 &&
          depth > 0
        purposes.push(purpose)
        allowed
      },
    )
  }
  assert_true(issue(foreign_definition, true) is Err(RunMismatch))
  assert_eq(purposes.length(), 0)
  assert_true(
    issue(definition, false)
    is Err(Input(MaterialsConstructionRefused("program"))),
  )
  assert_eq(purposes, ["program"])
  purposes.clear()
  let materials = match issue(definition, true) {
    Ok(value) => value
    Err(RunMismatch) => fail("the original File Plan lost its Task materials")
    Err(Input(MaterialsConstructionRefused(name))) =>
      fail("funded File Task material construction refused: " + name)
    Err(_) => fail("funded File Task materials could not be issued")
  }
  assert_eq(purposes, [
    "program", "environment", "run_definition_read", "run_materials",
  ])
  assert_true(positive_geometry.val)
  let admitted = match
    @publication_host.admit_client_task_run_materials(
      @publication_host.client_captured_task_run_materials_wire(materials),
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      manifests,
      {
        preparation: @publication_host.client_standard_program_preparation_limits(),
        sequence: @publication_host.client_standard_values_sequence_limits(),
        max_sequence_steps: 32,
        max_sequence_work: 64,
        max_evidence_bytes: 1000000,
        max_evidence_nodes: 100000,
        max_evidence_depth: 64,
      },
    ) {
    Ok(value) => value
    Err(Compilation(_)) =>
      fail("the existing inverse could not compile the saved File task")
    Err(Input(MaterialsProgram(_))) =>
      fail("the existing inverse could not check the saved File Program")
    Err(Input(MaterialsEnvironment)) =>
      fail("the existing inverse refused the retained File Checker")
    Err(Input(_)) =>
      fail("the existing inverse could not decode the File materials")
    Err(RunMismatch) =>
      fail("the existing inverse produced a different File Run")
    Err(_) => fail("the existing inverse could not admit the original File Run")
  }
  assert_eq(
    @publication_host.client_task_compilation_result_names(admitted.compilation),
    ["original", "selected"],
  )
  let restored = @publication_host.client_task_run_materials_compiled_original(
    admitted,
  ).unwrap()
  assert_true(
    @publication_host.client_compiled_run_has_original_definition(
      restored,
      admitted.run_definition,
    ),
  )
  assert_eq(
    @publication.publication_contract_identity(admitted.run_definition),
    @publication.publication_contract_identity(definition),
  )
  materials
}

///|
fn check_file_named_result_first_run_rows(
  parent : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  snapshot : @publication_host.ClientSavedSubmissionSnapshot,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  materials : @publication_host.ClientCapturedTaskRunMaterials,
  policy : @publication_host.ClientLocalRunPolicyOriginal,
  now : Double,
) -> Unit raise {
  let preparing = @publication_host.client_saved_submission_row(snapshot)
  let scans = Ref(0)
  let quotes = Ref(0)
  let task_text_bytes = @utf8.encode(
      @publication_host.client_captured_task_run_materials_wire(materials),
    )
    .length()
    .to_int64()
  let cancellation = Ref(0)
  let retained : Ref[@publication_host.ClientJournalPhysicalRow?] = Ref(None)
  let revision = Ref(preparing.revision)
  let quote_allowed = Ref(true)
  let packet_quote_allowed = Ref(true)
  let packet_quotes = Ref(0)
  let census_quote_allowed = Ref(true)
  let census_quotes = Ref(0)
  let row_quote_allowed = Ref(true)
  let row_quotes = Ref(0)
  let change_while_quoting = Ref(false)
  let wire_quote_allowed = Ref(true)
  let offered_wire : Ref[String?] = Ref(None)
  let issued_revision = Ref(4L)
  let preparing_body = Ref(preparing.body)
  let locator_present = Ref(false)
  let original_locator : Ref[(String, Bytes)?] = Ref(None)
  let cancel_issue : Ref[String?] = Ref(None)
  fn scan(
    table : String,
    key : String,
  ) -> Result[@publication_host.ClientJournalPhysicalRow?, String] {
    scans.val += 1
    if table == "client_run_custody" && key.is_empty() {
      Ok(Some({ key: "issued", revision: issued_revision.val, body: b"0", }))
    } else {
      Ok(None)
    }
  }
  fn read(
    table : String,
    key : String,
  ) -> Result[@publication_host.ClientJournalPhysicalRow?, String] {
    match table {
      "client_submitted_intents" if key == preparing.key =>
        Ok(
          Some({
            ..preparing,
            revision: revision.val,
            body: preparing_body.val,
          }),
        )
      "client_runs" if key ==
        @publication_host.client_request_scope_cid(request) => Ok(retained.val)
      "client_run_custody" if key == "issued" =>
        Ok(Some({ key, revision: issued_revision.val, body: b"0", }))
      "client_run_reference_index" if original_locator.val is Some((name, body)) &&
        key == name =>
        if locator_present.val {
          Ok(Some({ key, revision: 0L, body, }))
        } else {
          Ok(None)
        }
      _ => Err("foreign read")
    }
  }
  fn inspect(
    row : @publication_host.ClientJournalPhysicalRow,
  ) -> Result[@publication_host.ClientRunJournalInspection, String] {
    match
      @publication_host.decode_client_run_journal_row_with_observation_originals(
        row.body,
      ) {
      Ok((row, _, _)) =>
        Ok({
          request: row.request,
          definition: row.definition,
          checkpoint: None,
          cancellation_head: row.cancellation_head,
          task_materials_cid: row.task_materials_cid,
        })
      Err(_) => Err("invalid run row")
    }
  }
  fn confirm_cancellation() -> Result[Unit, String] {
    cancellation.val += 1
    match cancel_issue.val {
      Some(reason) => Err(reason)
      None => Ok(())
    }
  }
  fn fund_task_indexes(bytes : Int64) -> Result[Unit, String] {
    guard bytes > 0L else { return Err("invalid index quote") }
    census_quotes.val += 1
    if census_quote_allowed.val {
      Ok(())
    } else {
      Err("journal index reservation refused")
    }
  }
  let project = selected => {
    prepare_request_whole_file_first_journal_rows(
      parent,
      selected,
      snapshot,
      materials,
      policy,
      now,
      1024,
      scan,
      read,
      inspect,
      confirm_cancellation,
      "custody lost",
      (retained, scratch) => {
        guard retained >= 2L * task_text_bytes && scratch > task_text_bytes else {
          return Err("invalid Task material quote")
        }
        quotes.val += 1
        if change_while_quoting.val {
          revision.val += 1L
        }
        if quote_allowed.val {
          Ok(())
        } else {
          Err("no Task material backing")
        }
      },
      {
        before_collection: () => true,
        before_measure: (keys, depth) => keys > 0 && depth > 0,
        before_emit: (bytes, nodes, depth) => {
          bytes > 0 && nodes > 0 && depth > 0
        },
        before_admit: (bytes, nodes, depth) => {
          bytes > 0 && nodes > 0 && depth > 0
        },
        before_validate: (entries, _) => entries > 0,
        current: () => true,
      },
      (retained, scratch) => {
        guard retained > 0L && scratch > 0L else {
          return Err("invalid policy packet quote")
        }
        packet_quotes.val += 1
        if packet_quote_allowed.val {
          Ok(())
        } else {
          Err("policy packet reservation refused")
        }
      },
      fund_task_indexes,
      _ => Err("unexpected historical Task read"),
      (retained, scratch) => {
        guard retained > 0L && scratch > 0L else {
          return Err("invalid row quote")
        }
        row_quotes.val += 1
        if row_quote_allowed.val {
          Ok(())
        } else {
          Err("row encoding reservation refused")
        }
      },
      stage_wire=Some(
        (
          bytes => {
            guard bytes > 0L else { return Err("invalid candidate wire quote") }
            if wire_quote_allowed.val {
              Ok(())
            } else {
              Err("no candidate wire backing")
            }
          },
          body => {
            offered_wire.val = Some(body)
            Ok(())
          },
        ),
      ),
    )
  }
  assert_true(project(input.copy()) is Err(InvalidOriginal))
  assert_eq((scans.val, quotes.val, cancellation.val), (0, 0, 0))
  revision.val += 1L
  assert_true(project(input) is Err(Observation("custody lost")))
  assert_eq((scans.val, quotes.val, cancellation.val), (0, 0, 0))
  revision.val = preparing.revision
  quote_allowed.val = false
  assert_true(project(input) is Err(Observation("no Task material backing")))
  assert_eq((scans.val, quotes.val, cancellation.val), (0, 1, 0))
  assert_eq(packet_quotes.val, 0)
  quote_allowed.val = true
  packet_quote_allowed.val = false
  assert_true(
    project(input) is Err(Observation("policy packet reservation refused")),
  )
  assert_eq(packet_quotes.val, 1)
  assert_eq(offered_wire.val, None)
  packet_quote_allowed.val = true
  census_quote_allowed.val = false
  assert_true(
    project(input) is Err(Observation("journal index reservation refused")),
  )
  assert_eq(census_quotes.val, 1)
  assert_eq(cancellation.val, 0)
  assert_eq(offered_wire.val, None)
  census_quote_allowed.val = true
  assert_eq(row_quotes.val, 0)
  row_quote_allowed.val = false
  assert_true(
    project(input) is Err(Observation("row encoding reservation refused")),
  )
  assert_eq(row_quotes.val, 1)
  assert_eq(offered_wire.val, None)
  row_quote_allowed.val = true
  change_while_quoting.val = true
  assert_true(project(input) is Err(Observation("custody lost")))
  assert_true(scans.val > 0)
  revision.val = preparing.revision
  change_while_quoting.val = false
  wire_quote_allowed.val = false
  assert_true(project(input) is Err(Observation("no candidate wire backing")))
  assert_eq(offered_wire.val, None)
  wire_quote_allowed.val = true
  let candidate = match project(input) {
    Ok(value) => value
    Err(Observation(reason)) => fail("File first-ready observation: " + reason)
    Err(InvalidOriginal) => fail("File first-ready lost its original")
    Err(Encoding(_)) => fail("File first-ready could not encode its successor")
    Err(_) => fail("File first-ready did not assemble")
  }
  let (key, run, expected_issued_revision, issued) = @publication_host.client_run_journal_append_rows(
    candidate.run,
  )
  assert_eq((expected_issued_revision, issued), (4L, b"1"))
  original_locator.val = Some(candidate.locator)
  fn check_current() -> Result[
    Unit,
    @publication_host.ClientRunJournalAppendIssue[String],
  ] {
    @publication_host.check_client_captured_task_first_run_rows_current(
      candidate,
      materials,
      1024,
      scan,
      read,
      inspect,
      confirm_cancellation,
      "custody lost",
      fund_task_indexes,
      _ => Err("unexpected historical Task read"),
    )
  }
  let original_quote_count = quotes.val
  assert_true(check_current() is Ok(_))
  census_quote_allowed.val = false
  assert_true(
    check_current() is Err(Observation("journal index reservation refused")),
  )
  census_quote_allowed.val = true
  revision.val += 1L
  assert_true(check_current() is Err(Observation("custody lost")))
  revision.val = preparing.revision
  preparing_body.val = b"a different preparing body with the same revision"
  assert_true(check_current() is Err(Observation("custody lost")))
  preparing_body.val = preparing.body
  cancel_issue.val = Some("cancelled before commit")
  issued_revision.val += 1L
  assert_true(check_current() is Err(Observation("cancelled before commit")))
  cancel_issue.val = None
  assert_true(check_current() is Err(Observation("custody lost")))
  issued_revision.val = expected_issued_revision
  locator_present.val = true
  assert_true(check_current() is Err(Observation("custody lost")))
  locator_present.val = false
  retained.val = Some({ key, body: run, revision: 0L, })
  assert_true(check_current() is Err(ForeignRun))
  retained.val = None
  assert_true(check_current() is Ok(_))
  assert_eq(quotes.val, original_quote_count)
  let (row, local_policy, observation) = @publication_host.decode_client_run_journal_row_with_observation_originals(
    run,
  ).unwrap()
  assert_true(local_policy is Some(_) && observation is Some(_))
  assert_false(
    row.dispatch_reserved ||
    row.physical_start_claimed ||
    row.cancellation_requested(),
  )
  assert_true(row.checkpoint is None && row.effect_material_originals is None)
  let chunks = @publication_host.client_task_materials_original_chunks(
    candidate.task_materials,
  )
  assert_eq(
    row.task_materials_cid,
    Some(
      @publication_host.client_task_materials_original_cid(
        candidate.task_materials,
      ),
    ),
  )
  assert_eq(
    chunks.map(chunk => chunk.1).join(""),
    @publication_host.client_captured_task_run_materials_wire(materials),
  )
  let ready = @publication_host.decode_client_submitted_journal_row(
    candidate.ready,
  ).unwrap()
  assert_eq(ready.run_state_observation, Some((0L, None)))
  assert_eq(
    ready.run_admission,
    Some((request, @publication.publication_contract_identity(definition), 0L)),
  )
  let transport = @publication_host.client_captured_task_first_run_rows_wire(
    candidate,
  ).unwrap()
  assert_eq(offered_wire.val, Some(transport))
  let retained_bytes = @publication_host.client_captured_task_first_run_rows_retained(
    candidate,
  ).unwrap()
  let physical_rows = run.length().to_int64() +
    issued.length().to_int64() +
    candidate.ready.length().to_int64() +
    candidate.locator.1.length().to_int64()
  let mut chunk_units = 0L
  for (name, text) in chunks {
    chunk_units += name.length().to_int64() + text.length().to_int64()
  }
  assert_true(retained_bytes > physical_rows + 2L * chunk_units)
  assert_true(transport.contains("\"preparing_revision\":\"6\""))
  assert_true(transport.contains("\"task_materials\":["))
  assert_true(transport.contains("\"reference_locator\":"))
  let locator : @publication_host.ClientJournalPhysicalRow = {
    key: candidate.locator.0,
    body: candidate.locator.1,
    revision: 0L,
  }
  fn saved_rows(
    ready_revision : Int64,
    run_revision : Int64,
  ) -> @publication_host.ClientSavedSubmissionSnapshot {
    @publication_host.read_client_saved_run_reference(
      @publication.run_definition_namespace(definition).unwrap(),
      @publication_host.client_request_authority_scope_cid(request),
      @publication.publication_contract_identity(definition),
      (table, name) => {
        match table {
          "client_run_reference_index" if name == locator.key =>
            Ok(Some(locator))
          "client_submitted_intents" if name == preparing.key =>
            Ok(
              Some({
                ..preparing,
                revision: ready_revision,
                body: candidate.ready,
              }),
            )
          "client_runs" if name == key =>
            Ok(Some({ key, revision: run_revision, body: run, }))
          "client_task_run_materials" => {
            for (chunk_key, chunk) in chunks {
              if chunk_key == name {
                return Ok(
                  Some({ key: name, revision: 0L, body: @utf8.encode(chunk), }),
                )
              }
            }
            Ok(None)
          }
          _ => Err("foreign read")
        }
      },
      physical => {
        guard physical.key == key &&
          physical.body == run &&
          row.checkpoint is None else {
          return Err("foreign Run row")
        }
        Ok({
          request: row.request,
          definition: row.definition,
          checkpoint: None,
          cancellation_head: row.cancellation_head,
          task_materials_cid: row.task_materials_cid,
        })
      },
      "custody lost",
    ).unwrap()
  }
  let first = saved_rows(preparing.revision + 1L, 0L)
  let saved_originals = (saved, index) => {
    @publication_host.client_first_captured_task_saved_rows(
      snapshot, saved, materials, candidate, index,
    )
  }
  let returned = saved_originals(first, locator).unwrap()
  assert_eq(
    (returned.run.key, returned.run.revision, returned.run.body),
    (key, 0L, run),
  )
  assert_eq(
    (
      returned.submitted.key,
      returned.submitted.revision,
      returned.submitted.body,
    ),
    (preparing.key, preparing.revision + 1L, candidate.ready),
  )
  assert_true(
    saved_originals(saved_rows(preparing.revision + 1L, 1L), locator)
    is Err(CustodyLost),
  )
  assert_true(
    saved_originals(first, { ..locator, body: b"foreign", }) is Err(CustodyLost),
  )
  let admit = (saved, index) => {
    @publication_host.client_first_captured_task_saved_admission_wire(
      snapshot, saved, materials, candidate, index,
    )
  }
  assert_eq(
    admit(first, locator).unwrap(),
    @publication_host.client_saved_submission_admission_wire(first).unwrap(),
  )
  assert_true(
    admit(saved_rows(preparing.revision + 2L, 0L), locator) is Err(CustodyLost),
  )
  assert_true(
    admit(saved_rows(preparing.revision + 1L, 1L), locator) is Err(CustodyLost),
  )
  assert_true(admit(first, { ..locator, revision: 1L, }) is Err(CustodyLost))
  assert_true(
    admit(first, { ..locator, body: b"foreign", }) is Err(CustodyLost),
  )
  retained.val = Some({ key, revision: 0L, body: run, })
  let before = (scans.val, quotes.val, cancellation.val)
  assert_true(project(input) is Err(ForeignRun))
  assert_eq((scans.val, quotes.val, cancellation.val), before)
}

///|
fn bind_file_named_result_invocation(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  foreign_definition : @publication.PublicationContract,
  source : @sourceviews.SourceAcquisition,
  acquisition : @row_source_host.RowInputAcquisition,
  capture : @row_source_host.RowSourceCapture,
  captured : @query.CapturedInputSource,
) -> @query.CapturedSourceRelationIdentity raise {
  let started = "2026-10-30T00:00:00.000Z"
  let completed = "2026-10-30T00:00:01.000Z"
  let scope = @publication_host.client_request_authority_scope_cid(request)
  let bounds = @row_source_host.row_input_acquisition_limits(acquisition)
  let values = bounds.retention
  let wire = bounds.wire
  let workspace = @query.captured_source_cell_identity_workspace_slots(
    captured, values, wire, wire,
  ).unwrap()
  let scan = @query.start_captured_source_cell_identity(
    captured,
    bounds.max_rows,
    values,
    wire,
    wire,
    {
      max_fields: wire.max_columns,
      max_bytes: wire.max_bytes,
      max_nodes: wire.max_nodes,
      max_depth: wire.max_depth,
    },
    values.max_work,
    workspace,
    wire.max_bytes,
  ).unwrap_or_else(() => fail("the File capture must open a cell identity scan"))
  let mut complete = false
  for _ in 0..<1000 {
    let next = @query.captured_source_cell_identity_next_capacity(scan).unwrap()
    if @query.advance_captured_source_cell_identity(scan, 31, next).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let identity = @query.finish_captured_source_cell_identity(scan).unwrap()
  let (graph, _, _, _) = installed_managed_capture_publication_geometry_original(
    owner, prepared, request,
  ).unwrap()
  let logical = @publication_host.issue_captured_whole_source_input_logical(
    graph, captured, identity, source,
  ).unwrap_or_else(() => {
    fail("the complete File input must bind to its checked task")
  })
  let facts = @row_source_host.row_input_acquisition_facts(acquisition)
  let evidence = @row_source_host.issue_row_input_source_evidence(
    acquisition,
    capture,
    identity,
    logical,
    scope,
    facts.source_data_policy_cid,
    completed,
  ).unwrap()
  let policy = @publication_host.prepared_client_publication_data_policy_cid(
    prepared,
  ).unwrap()
  let issue = definition => {
    issue_program_whole_source_publication_invocation(
      owner, prepared, compiled, definition, capture, identity, evidence, logical,
      scope, policy, started, completed, 65536, 8192, 64,
    )
  }
  assert_true(issue(foreign_definition) is Err(ForeignOriginal))
  assert_true(owner.publication_invocation is None)
  let (observation, invocation) = match issue(definition) {
    Ok(value) => value
    Err(ForeignOriginal) => fail("the whole-file invocation lost its original")
    Err(WrongPhase) => fail("the foreign Definition consumed the issuance")
    Err(PublicationInvocation(_)) =>
      fail("the original invocation evidence was refused")
    Err(_) => fail("the whole-file invocation could not bind")
  }
  assert_true(physical_equal(owner.request, request))
  assert_true(physical_equal(owner.publication_definition.unwrap(), definition))
  assert_true(physical_equal(owner.publication_invocation.unwrap(), invocation))
  assert_true(
    @publication.run_evidence_value_json(observation).contains(
      @publication.run_evidence_value_identity(evidence),
    ),
  )
  assert_true(issue(definition) is Err(WrongPhase))
  identity
}

///|
// Match both actual checked occurrences to the task that supplied them.
// Expected rows and column contracts are from the shared independent oracle.
fn check_file_named_result_outputs(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  captured : @query.CapturedInputSource,
  capture : @row_source_host.RowSourceCapture,
  identity : @query.CapturedSourceRelationIdentity,
  retention : @publication.PublicationContract,
  foreign_definition : @publication.PublicationContract,
) -> Unit raise {
  let plan = owner.captured_preparation.unwrap()
  let (host, dag, _) = open_installed_managed_capture_host(
    owner,
    prepared,
    request,
    [captured],
  ).unwrap()
  let invocation = owner.publication_invocation.unwrap()
  let definition = owner.publication_definition.unwrap()
  let first = @strategy.next_captured_task(dag)
  let check_source = selected => {
    installed_single_whole_publication_source(
      owner, prepared, request, compiled, selected, invocation, capture, identity,
    )
  }
  assert_true(check_source(foreign_definition) is Err(ForeignOriginal))
  let (bound, input_cid) = check_source(definition).unwrap()
  assert_true(physical_equal(bound, dag))
  assert_eq(input_cid, @query.captured_source_relation_logical_cid(identity))
  let data_policy = @publication_host.prepared_client_publication_data_policy_cid(
    prepared,
  ).unwrap()
  let result_retention = @publication.issue_result_retention_for_data_policy(
    retention, data_policy, 8192, 64, 8,
  ).unwrap()
  let computation = @publication.publication_contract_identity(
    @publication_host.client_compiled_run_plan(compiled),
  )
  let scope = @publication.publication_contract_identity(definition)
  let authority = @publication_host.client_request_authority_scope_cid(request)
  assert_eq(@strategy.next_captured_task(dag), first)
  let execution = execute_installed_whole_source_values_guarded(
    owner,
    prepared,
    request,
    host,
    64,
    10000,
    () => true,
  ).unwrap_or_else(() => fail("the original captured File must execute"))
  let limits = installed_managed_publication_limits(owner, prepared, 16777216).unwrap()
  let schema =
    #|{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}
  let expected = [
    (
      "original", "[{\"id\":\"a-control\",\"value\":\"keep-account\"},{\"id\":\"a1\",\"value\":\"A-old\"},{\"id\":\"a2\",\"value\":\"A2-old\"}]",
    ),
    ("selected", "[{\"id\":\"a2\",\"value\":\"A2-old\"}]"),
  ]
  let program_cid = @strategy.graph_program_definition_cid(
    @strategy.captured_dag_graph(dag),
  )
  let preflight_definitions = expected.map(pair => {
    @publication.result_definition_contract(
      @publication.prepare_result_definition(program_cid, pair.0).unwrap(),
    )
  })
  let copy_quotes = Ref(0)
  let reserve_copy = (bytes, scratch) => {
    copy_quotes.val += 1
    bytes >= 0L && scratch >= 0L
  }
  assert_true(
    start_installed_whole_named_result_export(
      owner,
      prepared,
      request,
      compiled,
      invocation,
      execution,
      expected.length(),
      preflight_definitions[0],
      limits.payload_wire.max_bytes,
      reserve_copy,
    )
    is Err(UnknownResult),
  )
  assert_true(
    start_installed_whole_named_result_export(
      owner,
      prepared,
      request,
      compiled,
      invocation,
      execution,
      0,
      preflight_definitions[1],
      limits.payload_wire.max_bytes,
      reserve_copy,
    )
    is Err(Transformation(@publication_host.ForeignSelection)),
  )
  assert_eq(copy_quotes.val, 0)
  let refused_quotes = Ref(0)
  let refused = start_installed_whole_named_result_export(
    owner,
    prepared,
    request,
    compiled,
    invocation,
    execution,
    0,
    preflight_definitions[0],
    limits.payload_wire.max_bytes,
    (_, _) => {
      refused_quotes.val += 1
      false
    },
  ).unwrap()
  assert_true(refused.advance(1) is Err(MissingOutput))
  assert_eq(refused_quotes.val, 1)
  assert_true(refused.advance(1) is Err(Export(@publication_host.InvalidState)))
  refused.close()
  assert_eq(refused_quotes.val, 1)
  let definitions : Array[String] = []
  for index, pair in expected {
    let (name, expected_rows) = pair
    let selection = @publication_host.prepare_client_compiled_result_transformation(
      compiled, index, 65536, 8192, 64,
    ).unwrap()
    assert_eq(
      @publication_host.client_result_transformation_name(selection),
      name,
    )
    let task = @publication_host.client_result_transformation_task(selection)
    assert_true(@strategy.captured_task_completed(dag, task))
    let (operations, completed) = execution
      .publication_original_for_task(task)
      .unwrap()
    let (bridge, output) = execution
      .prepare_publication_bridge_for_original(
        operations,
        completed,
        plan.capacity_plan.imports.row,
        plan.capacity_plan.metadata.bridge_entries,
        plan.capacity_plan.metadata.name_bytes,
        limits,
      )
      .unwrap()
    assert_true(
      @publication_host.start_captured_managed_result_transformation(
        selection,
        dag,
        1 - index,
        completed,
        bridge,
        output,
        limits,
      )
      is Err(ForeignSelection),
    )
    @execution.close_managed_publication_bridge(bridge)
    let previous = copy_quotes.val
    let preparation = start_installed_whole_named_result_export(
      owner,
      prepared,
      request,
      compiled,
      invocation,
      execution,
      index,
      preflight_definitions[index],
      limits.payload_wire.max_bytes,
      reserve_copy,
    ).unwrap()
    assert_eq(copy_quotes.val, previous)
    let mut ready = false
    for _ in 0..<1000 {
      let (done, work) = preparation.advance(1).unwrap()
      assert_true(work >= 0 && work <= 1)
      if done {
        ready = true
        break
      }
    }
    assert_true(ready)
    let stream = preparation.finish().unwrap()
    assert_true(
      physical_equal(stream.definition().unwrap(), preflight_definitions[index]),
    )
    assert_true(copy_quotes.val > previous)
    let wire = StringBuilder()
    while stream.next().unwrap() is Some(chunk) {
      wire.write_string(chunk)
    }
    wire.write_string(stream.finish().unwrap())
    assert_eq(@json.parse(wire.to_string()), @json.parse(expected_rows))
    let graph = @strategy.captured_dag_graph(dag)
    let occurrence = @strategy.graph_result_occurrence(graph, index).unwrap()
    let foreign_occurrence = @strategy.graph_result_occurrence(graph, 1 - index).unwrap()
    assert_true(
      stream.snapshot_original_extent(dag, occurrence) is Err(InvalidState),
    )
    stream
    .issue_result_evidence(
      computation,
      [input_cid],
      scope,
      data_policy,
      authority,
      65536,
      8192,
      64,
    )
    .unwrap()
    stream
    .issue_artifact(invocation, result_retention, 65536, 8192, 64)
    .unwrap()
    |> ignore
    assert_true(
      stream.snapshot_original_extent(dag, foreign_occurrence)
      is Err(InvalidState),
    )
    let (snapshot_bytes, snapshot_nodes, snapshot_rows, snapshot_depth) = stream
      .snapshot_original_extent(dag, occurrence)
      .unwrap()
    assert_eq(snapshot_rows, if index == 0 { 3 } else { 1 })
    assert_true(
      snapshot_bytes > 0 && snapshot_nodes > snapshot_rows && snapshot_depth > 0,
    )
    assert_eq(
      stream.snapshot_original_extent(dag, occurrence).unwrap(),
      (snapshot_bytes, snapshot_nodes, snapshot_rows, snapshot_depth),
    )
    assert_eq(stream.result_fields().unwrap(), ["id", "value"])
    assert_eq(
      @json.parse(stream.result_schema_wire().unwrap()),
      @json.parse(schema),
    )
    let published = stream.definition().unwrap()
    let selected = @publication_host.client_result_transformation_definition(
      selection,
    )
    assert_eq(
      @publication.publication_contract_json(published),
      @publication.publication_contract_json(selected),
    )
    definitions.push(@publication.publication_contract_identity(published))
    preparation.close()
  }
  assert_true(definitions[0] != definitions[1])
  assert_true(execution.close())
}

///|
test "Request Whole quotation scratch is reserved before its first domain grow" {
  // Independent fixed constructor inventory: H232/R104/W468 under the
  // existing16/8/8 logical representation tariff, not a policy allowance.
  assert_eq(request_whole_source_initial_quotation_bytes, 8288L)
  for axis in 0..<2 {
    for shortage in [0L, 1L] {
      let (parent, input, _, _) = request_whole_source_fixture(
        reserve_plan=false,
      )
      let (r, e) = request_program_plan_quote(parent, input).unwrap()
      let (old_r, old_e) = @resources.preparation_capacity_working_extents(
        parent.program_capacity.unwrap(),
        input,
      ).unwrap()
      let additional = if axis == 0 { r - old_r } else { e - old_e }
      assert_true(additional >= request_whole_source_initial_quotation_bytes)
      let usage = @resources.ledger_usage(parent.ledger)
      let limits = @resources.ledger_limits(parent.ledger)
      let available = if axis == 0 {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes
      }
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if axis == 0 {
          available - additional + shortage
        } else {
          0L
        },
        if axis == 1 {
          available - additional + shortage
        } else {
          0L
        },
      ).unwrap()
      let result = reserve_request_program_plan(parent, input)
      if shortage == 0L {
        assert_true(result is Ok(_))
        assert_true(parent.phase == ProgramPlanReserved)
      } else {
        assert_true(result is Err(Capacity(_)))
        assert_true(parent.phase == ProgramPlanQuoted)
      }
      assert_true(parent.program_domain_quote is None)
      assert_true(!parent.program_body_attempted)
      @resources.settle_capacity(parent.ledger, blocker).unwrap()
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}

///|
test "Request Whole domain retains each original route before its plural Plan" {
  let (parent, input, prepared, request) = request_whole_source_fixture()
  let original_capacity = parent.program_capacity.unwrap()
  let (direct, sources) = reserve_request_whole_source_construction(
    parent, input, request,
  ).unwrap()
  assert_eq(sources.length(), 2)
  assert_true(parent.phase == ProgramPlanReserved)
  assert_true(parent.program_domain_quote is None)
  assert_true(
    physical_equal(original_capacity, parent.program_capacity.unwrap()),
  )
  for index in 0..<sources.length() {
    let (stage, source_index, _) = @publication_host.client_direct_acquisition_occurrence_at(
      direct, index,
    ).unwrap()
    assert_true(
      @publication_host.client_source_acquisition_matches_program(
        prepared,
        stage,
        source_index,
        sources[index],
      ),
    )
  }
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let declaration = pure_provider_declaration()
  let capacities = sources.map(source => {
    prepare_installed_whole_source_capacity(
      prepared,
      source,
      declaration,
      contracts,
      installed_row_input_policy(4, 4096, 256, 16, 4),
      None,
    ).unwrap()
  })
  let plan = prepare_installed_managed_whole_sources_plan(
    prepared,
    request,
    capacities,
    [4096L, 4096L],
    [4096L, 4096L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=true,
    provider_factory=_ => [],
    runtime_admission=true,
  ).unwrap()
  assert_eq(plan.whole_sources.length(), 2)
  assert_eq(plan.captures.length(), 0)
  for index in 0..<capacities.length() {
    assert_true(
      physical_equal(
        prepared_installed_managed_whole_source_capacity(plan, index).unwrap(),
        capacities[index],
      ),
    )
    assert_true(
      prepared_installed_managed_capture_acquisition(plan, index) is None,
    )
  }
  assert_true(
    prepared_installed_managed_whole_source_capacity(plan, -1) is None,
  )
  assert_true(
    prepared_installed_managed_whole_source_capacity(plan, capacities.length())
    is None,
  )
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let owner = begin_request_capture_managed_run(parent, request).unwrap()
  let logical_graph = @publication_host.prepared_client_graph(prepared)
  assert_true(@strategy.graph_captured_prefix(logical_graph) > 0)
  assert_true(source_input_local_tasks_control_capacity(logical_graph) is None)
  let (physical_graph, _, _, _) = installed_managed_capture_publication_geometry_original(
    owner, prepared, request,
  ).unwrap()
  assert_true(
    @strategy.source_inputs_dag_matches_original(physical_graph, logical_graph),
  )
  assert_eq(@strategy.graph_captured_prefix(physical_graph), 0)
  assert_true(
    source_input_local_tasks_control_capacity(physical_graph) is Some(_),
  )
  // No DAG was opened and no physical Source exists in this component. Port
  // retirement may report that narrow absence; it must not accept Query's
  // distinct purpose or retire/reissue the managed Run/request itself.
  assert_true(owner.source_free_captured is None)
  assert_true(retire_installed_whole_source_ports(owner, prepared, request))
  assert_false(retire_installed_query_capture_ports(owner, prepared, request))
  assert_true(owner.original is Some(_))
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request Whole domain exact and one-short keep the same original reservation" {
  for axis in 0..<2 {
    for shortage in [0L, 1L] {
      let (parent, input, prepared, request) = request_whole_source_fixture()
      let direct = installed_direct_occurrences_owned(Pure(prepared)).unwrap()
      let count = @publication_host.client_direct_acquisition_occurrence_count(
        direct,
      )
      let bound = @checked.source_execution_count(
        @strategy.graph_program(
          @publication_host.prepared_client_graph(prepared),
        ),
      )
      let (old_r, old_e) = installed_direct_occurrences_layout(
        @strategy.graph_captured_prefix(
          @publication_host.prepared_client_graph(prepared),
        ),
      ).unwrap()
      let (new_r, new_e) = installed_direct_occurrences_layout(bound).unwrap()
      let mut bytes = Int64::max(
        Int64::max(0L, new_r - old_r),
        Int64::max(0L, new_e - old_e),
      )
      bytes += request_whole_source_observer_bytes().unwrap()
      bytes += request_whole_source_route_frontier_bytes(
        count,
        request_whole_source_route_scan_count(prepared, direct).unwrap(),
      ).unwrap()
      for index in 0..<count {
        let (stage, source_index, _) = @publication_host.client_direct_acquisition_occurrence_at(
          direct, index,
        ).unwrap()
        guard select_installed_source_input(
            prepared, request, stage, source_index,
          ).unwrap()
          is @sourceviews.WholeInputRoute(source) else {
          fail("the original complete input cannot be rewritten as Query")
        }
        bytes += request_whole_source_input_construction_bytes(source).unwrap()
      }
      let usage = @resources.ledger_usage(parent.ledger)
      let limits = @resources.ledger_limits(parent.ledger)
      let available = if axis == 0 {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes
      }
      assert_true(available >= bytes)
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if axis == 0 {
          available - bytes + shortage
        } else {
          0L
        },
        if axis == 1 {
          available - bytes + shortage
        } else {
          0L
        },
      ).unwrap()
      let result = reserve_request_whole_source_construction(
        parent, input, request,
      )
      if shortage == 0L {
        assert_true(result is Ok(_))
        assert_true(parent.phase == ProgramPlanReserved)
      } else {
        assert_true(result is Err(Preparation(Capacity(_))))
        assert_true(parent.phase == ProgramBodyFailed)
      }
      @resources.settle_capacity(parent.ledger, blocker).unwrap()
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}

///|
test "Request Whole domain does not revive its original after current loss" {
  let current = Ref(true)
  let (parent, input, _, request) = request_whole_source_fixture(current=() => {
    current.val
  })
  current.val = false
  assert_true(
    reserve_request_whole_source_construction(parent, input, request) is Err(_),
  )
  assert_true(parent.phase != ProgramPlanReserved)
  current.val = true
  assert_true(
    reserve_request_whole_source_construction(parent, input, request) is Err(_),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Native file Request keeps both Whole inputs sharing one Compute" {
  let text =
    #|{"version":"actql/0.1","id":"same-task-whole-join","stages":[{"id":"joined","inputs":{"left":{"connector":"pure-provider","resource":"records"},"right":{"connector":"pure-provider","resource":"records"}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"joined","result":"rows"}}}}
  let (parent, input, prepared, request) = request_whole_source_fixture(text~)
  guard prepare_request_native_file_source_inputs(parent, input, request, None).unwrap()
    is WholeSourceInputs(direct, sources) else {
    fail("both authenticated occurrences require Whole construction")
  }
  assert_eq(sources.length(), 2)
  let left = @publication_host.client_direct_acquisition_occurrence_at(
    direct, 0,
  ).unwrap()
  let right = @publication_host.client_direct_acquisition_occurrence_at(
    direct, 1,
  ).unwrap()
  assert_eq(left.0, right.0)
  assert_eq(left.2, right.2)
  assert_true(left.1 != right.1)
  for index in 0..<sources.length() {
    let (stage, source_index, _) = @publication_host.client_direct_acquisition_occurrence_at(
      direct, index,
    ).unwrap()
    assert_true(
      @publication_host.client_source_acquisition_matches_program(
        prepared,
        stage,
        source_index,
        sources[index],
      ),
    )
  }
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "static JOIN Plan describes the original Sources without preparing a Run" {
  let (parent, input, prepared, _) = request_whole_source_fixture()
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 2)
  let before = parent.phase
  let wire = request_prepared_static_plan_view(
    parent,
    input,
    request_program_module_manifests(),
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(wire.contains("actql-plan-view/0.1"), msg=wire)
  assert_true(wire.contains("\"compiled_plan_cid\""), msg=wire)
  assert_true(!wire.contains("\"run_ref\""), msg=wire)
  assert_true(parent.phase == before)
  assert_true(parent.submitted_intent is None)
  assert_true(!parent.program_body_attempted)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
