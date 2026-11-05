///|
// Real checked two-Direct/Keyed/Model owners and actual in-memory Row runs.
// The exact authored reference issuer is the existing component fixture;
// this test supplies no installed physical provider or Model send permission.
test "two original Direct captures execute one keyed prefix and feed the same Model input without replay" {
  let (declaration, keyed_environment) = original_keyed_declaration_environment(
    relation_versions=true,
  )
  guard @json.parse(keyed_environment) is Object(fields) &&
    fields["host_policy_profile"] is Object(policy) else {
    fail("the original finite keyed policy is required")
  }
  let (environment, _) = effect_model_plan_source(
    declaration=Some(declaration),
    lookup_policy=Some(policy["lookup_execution"]),
  )
  let document =
    #|{"version":"actql/0.1","id":"two-direct-keyed-model","stages":[{"id":"left","inputs":{"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["name","resource","version"]}}},{"id":"right","inputs":{"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["name","resource","version"]}}},{"id":"classify","inputs":{"a":{"result":{"stage":"left","result":"rows"}},"b":{"result":{"stage":"right","result":"rows"}},"contents":{"connector":"content-fixture","resource":"contents"}},"steps":[{"from":"a","join":{"with":"b","kind":"inner","on":[{"left":"name","right":"name"}],"select":{"name":"left.name","resource":"left.resource","version":"left.version"}},"as":"joined"},{"from":"joined","join":{"with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"captured"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"},{"derive":{"id":{"literal":1}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"classify","result":"rows"}}}}
  let prepared = match
    @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      @publication_host.client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(_) => fail("two-Direct keyed Model fixture preparation")
  }
  let (_, _, contracts, model) = effect_model_plan_for_prepared(
    prepared,
    acquired=true,
  )
  let keyed = @publication_host.select_client_effect_composed_model_keyed_acquisition(
      prepared,
      model.graph,
    )
    .unwrap()
    .unwrap()
  let prefix = prepare_client_composed_infer_prefix(
    model.graph.owner,
    model._occurrence,
    contracts,
    source_query_original_values,
    fragment_body=Some(source_query_original_fragment),
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 100000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 1048576L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  @resources.configure_quantities(ledger, {
    tokens: 128L,
    cost_units: 0L,
    duration_ms: 1000L,
  }).unwrap()
  let original_quantities = @resources.quantity_usage(ledger)
  let bootstrap = @resources.reserve_capacity(ledger, 4096L, 4096L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    model.compiled,
    model.definition,
    model.graph,
    ledger,
    bootstrap,
    16,
    16,
    0,
  ).unwrap()
  let accepted = wire => {
    wire == original_keyed_child_resource(0) ||
    wire == original_keyed_child_content(0)
  }
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => accepted(wire),
    accepted,
  )
  let page = @utf8.encode(
    "[{\"name\":\"a.pdf\",\"resource\":" +
    original_keyed_child_resource(0) +
    ",\"version\":\"v1\",\"media_type\":\"application/pdf\",\"path\":\"a.pdf\",\"size_bytes\":8,\"modified_at\":null}]",
  )
  let runs = []
  let captures = []
  let requirements = []
  let acquisitions = []
  for task in 0..<2 {
    let requirement = prepare_effect_local_query_requirement(
      prepared,
      task,
      0,
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    ).unwrap()
    let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
    let view = @row_source_host.row_declaration_view(
      declaration,
      facts.source_ref,
    ).unwrap()
    let source = @row_source_host.prepare_declared_row_source(
      requirement, "content-fixture", view,
    ).unwrap()
    let acquisition = @row_source_host.prepare_declared_row_acquisition(
      source, "two-direct-keyed-model", original_row_query_contract_fixture, original_row_evidence_contract_fixture,
    ).unwrap()
    let run = @row_source_host.start_accounted_row_acquisition(
      acquisition,
      "original-" + task.to_string(),
      _ => true,
      ledger,
      4096L,
      4096L,
    ).unwrap()
    runs.push(run)
    @row_source_host.begin_row_run(
      run,
      4096,
      1,
      1,
      reference_issuer=Some(issuer),
    ).unwrap()
    assert_eq(@row_source_host.accept_row_run_page(run, page).unwrap(), 1)
    @row_source_host.finish_row_run(run).unwrap()
    @row_source_host.begin_row_capture(run).unwrap()
    let mut complete = false
    for _ in 0..<10000 {
      if @row_source_host.advance_row_capture(run, 7).unwrap().0 {
        complete = true
        break
      }
    }
    assert_true(complete)
    captures.push(@row_source_host.capture_row_run(run).unwrap())
    requirements.push(requirement)
    acquisitions.push(acquisition)
  }
  assert_eq(@resources.ledger_usage(ledger).attempts, 2)
  let (execution, measurement, mapping) = original_composed_keyed_test_limits()
  let before_refusal = @resources.ledger_usage(ledger)
  assert_true(
    start_client_original_composed_keyed_prefix(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      keyed,
      [captures[1], captures[0]],
      prefix,
      execution,
      measurement,
    )
    is Err(_),
  )
  assert_true(
    start_client_original_composed_keyed_prefix(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      keyed,
      [captures[0]],
      prefix,
      execution,
      measurement,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before_refusal)
  assert_true(
    @row_source_host.retain_row_captured_inputs(captures, ledger, 100000)
    is Some(_),
    msg="same original Row capture inventory",
  )
  let (_, _, join_step) = @publication_host.client_keyed_acquisition_coordinates(
    keyed,
  ).unwrap()
  let keyed_owner = @publication_host.client_keyed_acquisition_owner(keyed)
  let keyed_node = @lower.node_at(
    @lower.bound_preparation(keyed_owner),
    join_step,
  ).unwrap()
  guard @lower.node_input_target(keyed_node, 0)
    is Some(@pipeline.Step(left_step)) else {
    fail("keyed left is an original Step")
  }
  let left_sequence = @execution.select_generated_sequence_range(
    prefix, 0, left_step,
  ).unwrap()
  let selected_provider = @local.local_bounded_relation_provider(
    execution, measurement, left_sequence,
  )
  assert_true(
    selected_provider is Some(_),
    msg="existing bounded left prefix provider",
  )
  assert_true(
    @local.managed_provider_capacity(selected_provider.unwrap(), left_sequence)
    is Some(_),
    msg="existing bounded left prefix capacity",
  )
  let (_, row_inputs, sources) = @publication_host.retain_client_original_composed_keyed_captures(
    scope,
    model.compiled,
    model.definition,
    model.graph,
    keyed,
    captures,
  ).unwrap()
  let _ = match
    @publication_host.prepare_client_original_composed_keyed_inputs(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      keyed,
      sources,
      row_inputs,
      left_sequence,
      10000,
      10000,
    ) {
    Ok(value) => value
    Err(@publication_host.ForeignLeft) =>
      fail("original two-input binding ownership")
    Err(@publication_host.Capture(_)) =>
      fail("original two-input Source binding")
    Err(_) => fail("original two-input read construction")
  }
  let original = match
    start_client_original_composed_keyed_prefix(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      keyed,
      captures,
      prefix,
      execution,
      measurement,
    ) {
    Ok(value) => value
    Err(Original(@publication_host.ForeignRun)) =>
      fail("prefix original foreign Run")
    Err(Original(@publication_host.Resource(issue))) =>
      fail("prefix original resource: " + @debug.to_string(issue))
    Err(Unavailable) => fail("prefix original input unavailable")
    Err(Physical(issue)) => fail("prefix capacity: " + @debug.to_string(issue))
    Err(_) => fail("prefix original child refusal")
  }
  let mut complete = false
  for _ in 0..<10000 {
    match advance_client_original_composed_keyed_prefix(original, 7).unwrap() {
      @local.Complete(_, ..) => {
        complete = true
        break
      }
      @local.Continue(..) => ()
      _ => fail("the two original inputs must complete their left prefix")
    }
  }
  assert_true(complete)
  let work = client_serialization_prefix_work(original.prefix).unwrap()
  assert_true(work > 0L)
  let left = complete_client_original_composed_keyed_prefix(
    original, 10000, 4096,
  ).unwrap()
  assert_true(
    complete_client_original_composed_keyed_prefix(original, 10000, 4096)
    is Err(_),
  )
  let lookup = @publication_host.start_client_keyed_lookup_input(
    left, ledger, 4096, 10000,
  ).unwrap()
  let preparation = @publication_host.start_client_keyed_lookup_request(
    lookup, 0,
  ).unwrap()
  let mut request = None
  for _ in 0..<10000 {
    match
      @publication_host.advance_client_keyed_lookup_request(lookup, preparation) {
      @publication_host.ClientKeyedRequestContinue(..) => ()
      @publication_host.ClientKeyedRequestComplete(value, ..) => {
        request = Some(value)
        break
      }
      _ => fail("the original checked keyed request must complete")
    }
  }
  let request = request.unwrap()
  assert_eq(
    @publication_host.find_client_keyed_lookup_response(lookup, request).unwrap(),
    -1,
  )
  assert_true(
    @publication_host.client_composed_keyed_request_matches_model_parent(
      request,
      model.compiled,
      model.definition,
      model.graph,
      ledger,
    ),
  )
  assert_eq(
    @publication_host.client_composed_keyed_request_model_rows(
      request,
      model.compiled,
      model.definition,
      model.graph,
      ledger,
    ),
    Some(1),
  )
  let request_value = @publication_host.client_keyed_request_value(
    request, keyed,
  ).unwrap()
  let acquisition = @row_source_host.prepare_keyed_row_acquisition(
    @publication_host.client_keyed_acquisition_owner(keyed),
    @publication_host.client_keyed_acquisition_facts(keyed),
    request_value,
    declaration,
    original_keyed_child_limits(),
    input_available=Some(() => {
      @publication_host.client_composed_keyed_request_retained_model_parent(
        request,
        model.compiled,
        model.definition,
        model.graph,
        ledger,
      )
    }),
  ).unwrap()
  let child = @row_source_host.start_accounted_keyed_row_acquisition(
    acquisition,
    "same-keyed-child",
    _ => true,
    ledger,
    8192L,
    4096L,
    _ => true,
  ).unwrap()
  let response = @utf8.encode("[" + original_keyed_child_expected_row(0) + "]")
  @publication_host.observe_client_keyed_request_attempt(
    request,
    @publication_host.client_keyed_request_wire(request, 4096, 2000, 32)
    .unwrap()
    .length()
    .to_int64(),
    0L,
  ).unwrap()
  @row_source_host.begin_keyed_row_run(child, reference_issuer=Some(issuer)).unwrap()
  @publication_host.observe_client_keyed_response(
    request,
    response.length().to_int64(),
    response.length().to_int64(),
    0L,
  ).unwrap()
  @row_source_host.begin_row_run_keyed_page(child, response).unwrap()
  complete = false
  for _ in 0..<10000 {
    match @row_source_host.advance_row_run_keyed_page(child, 7).unwrap() {
      @row_source_host.KeyedPageContinue(..) => ()
      @row_source_host.KeyedPageComplete(rows~, ..) => {
        assert_eq(rows, 1)
        complete = true
        break
      }
    }
  }
  assert_true(complete)
  @row_source_host.finish_row_run(child).unwrap()
  let captured = @row_source_host.retain_keyed_row_run(child).unwrap()
  @publication_host.finish_client_keyed_request_io(request, 0L).unwrap()
  begin_client_original_keyed_lookup_response(keyed, lookup, request, captured).unwrap()
  for _ in 0..<10000 {
    if @publication_host.advance_client_keyed_lookup_input(lookup, 7).unwrap() {
      break
    }
  }
  let right = @publication_host.finish_client_keyed_lookup_input(lookup).unwrap()
  let authority = "sha256:" + "2".repeat(64)
  let started = "2026-11-05T00:00:00.000Z"
  let completed = "2026-11-05T00:00:01.000Z"
  let limits = original_keyed_content_workspace().export_limits
  let identities = []
  let logicals = []
  let observations = []
  for task, source in sources {
    let identity = @query.identify_captured_source_relation(
      source,
      1,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      limits.max_batch_bytes,
    ).unwrap()
    let logical = @publication_host.issue_captured_source_input_logical(
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      ),
      source,
      identity,
      requirements[task],
      task~,
    ).unwrap()
    let facts = @planning.query_requirement_source_evidence_facts(
      requirements[task],
    ).unwrap()
    let observation = @row_source_host.issue_row_source_evidence(
      acquisitions[task],
      captures[task],
      identity,
      logical,
      authority,
      facts.source_data_policy_cid,
      completed,
    ).unwrap()
    identities.push(identity)
    logicals.push(logical)
    observations.push(observation)
  }
  let keyed_observation = @publication_host.issue_client_keyed_lookup_observation(
    lookup, authority, completed,
  ).unwrap()
  assert_true(
    @publication_host.admit_client_infer_composed_sources(
      model._occurrence,
      sources,
      identities,
      requirements,
      logicals,
      observations,
      authority,
      started,
      completed,
    )
    is Err(_),
  )
  assert_true(
    @publication_host.admit_client_infer_composed_sources(
      model._occurrence,
      [sources[1], sources[0]],
      identities,
      requirements,
      logicals,
      observations,
      authority,
      started,
      completed,
      keyed=Some(keyed_observation),
    )
    is Err(_),
  )
  let source_closure = @publication_host.admit_client_infer_composed_sources(
    model._occurrence,
    sources,
    identities,
    requirements,
    logicals,
    observations,
    authority,
    started,
    completed,
    keyed=Some(keyed_observation),
  ).unwrap()
  assert_true(
    @publication_host.client_infer_composed_sources_matches(
      source_closure,
      model._occurrence,
    ),
  )
  let inputs = original.inputs.map(value => {
    @local.managed_provider_relation_input(value.2)
  })
  inputs.push(@local.managed_provider_supplied_relation_input(right))
  let before = @resources.ledger_usage(ledger)
  let input = start_client_composed_infer_input(
    model._occurrence,
    prefix,
    inputs,
    execution,
    measurement,
    mapping,
    keyed=Some(lookup),
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  let mut rows = None
  for _ in 0..<10000 {
    match advance_client_infer_input(input, 7).unwrap() {
      Complete(value, ..) => {
        rows = Some(value)
        break
      }
      Continue(..) => ()
      _ => fail("the original keyed input must reach Model mapping")
    }
  }
  assert_eq(@execution.prepared_infer_rows_count(rows.unwrap()), 1)
  assert_true(input.work >= work)
  // Only the two Direct reads and the keyed response are actual attempts.
  // The completed assembly settled its unused attempt; the live prefix still
  // retains its one unsent constructor reservation until cleanup.
  assert_eq(@resources.ledger_usage(ledger).attempts, 3)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
  assert_eq(@resources.quantity_usage(ledger), original_quantities)
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      false,
    ).unwrap(),
  )
  assert_false(
    @publication_host.client_composed_keyed_request_retained_model_parent(
      request,
      model.compiled,
      model.definition,
      model.graph,
      ledger,
    ),
  )
  assert_false(
    @publication_host.client_infer_composed_sources_matches(
      source_closure,
      model._occurrence,
    ),
  )
  assert_true(cleanup_client_infer_input(input).unwrap())
  @row_source_host.close_accounted_row_run(child).unwrap()
  assert_true(
    @publication_host.cleanup_client_keyed_lookup_input(lookup, 10000).unwrap(),
  )
  assert_true(cleanup_client_serialization_prefix(original.prefix).unwrap())
  for run in runs {
    @row_source_host.close_accounted_row_run(run).unwrap()
  }
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 3)
}

///|
fn original_composed_keyed_test_limits() -> (
  @execution.SequenceExecutionLimits,
  @execution.FixedInputGuardMeasureLimits,
  @execution.InferPreparationLimits,
) {
  let values = source_capture_values()
  (
    {
      rows: {
        max_rows: 3,
        metadata_entries: 10000,
        retained_entries: 10000,
        operation_entries: 10000,
        input_values: values,
        output_values: values,
      },
      max_work: 100000,
      max_frames: 100,
    },
    { max_work: 100000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    {
      max_items: 3,
      max_work: 100000,
      max_frames: 100,
      max_workspace_slots: 10000,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 10000, },
      logical: {
        max_input_rows: 3L,
        max_value_bytes: 10000L,
        max_live_value_bytes: 100000L,
        max_work: 100000L,
      },
    },
  )
}
