///|
// Real checked two-Direct/Keyed/Model owners and actual in-memory Row runs.
// The exact authored reference issuer is the existing component fixture;
// this test supplies no installed physical provider or Model send permission.
test "two original Direct captures execute one keyed prefix and feed the same Model input without replay" {
  original_composed_keyed_consumer()
}

///|
#cfg(target="js")
test "adopted Effect Model borrows shared Source tokens and its original prefix exactly once" {
  original_composed_keyed_consumer(
    prepare_parent=Some((wire, selectedEnvironment) => {
      let (parent, child, _, input) = registration_parent_fixture(
        text=wire,
        environment=Some(selectedEnvironment),
        effect_limits=Some(
          @publication_host.client_standard_effect_computation_limits(),
        ),
      )
      finish_effect_program_check_preparation(child).unwrap() |> ignore
      let prepared = compile_effect_program_check_preparation(child).unwrap()
      assert_true(
        physical_equal(
          continue_request_effect_preparation(parent, input).unwrap(),
          prepared,
        ),
      )
      (parent, input, prepared)
    }),
    foreign_run=Some(() => {
      let (prepared, _, _) = effect_operation_plan_inputs()
      effect_parent_bound_run(prepared)
    }),
  )
}

///|
fn original_composed_keyed_consumer(
  prepare_parent? : ((String, @checked.CheckEnvironment) -> (
    ClientRequestPreparation[Array[Int]],
    Array[Int],
    @publication_host.PreparedClientEffectComputation,
  ) raise)? = None,
  foreign_run? : (() -> @publication_host.PreparedClientEffectRun raise)? = None,
) -> Unit raise {
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
  let shared = prepare_parent is Some(_)
  let request_parent = match prepare_parent {
    None => None
    Some(prepare) => Some(prepare(document, environment))
  }
  let prepared = match request_parent {
    Some((_, _, prepared)) => prepared
    None =>
      match
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
  }
  // These are three distinct checked response originals even though the two
  // Direct occurrences select the same SourceView. The keyed response is not
  // one of those Direct roots and cannot be dropped from the whole Run policy.
  let checked_program = @strategy.graph_program(
    @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ),
  )
  let final_publication = @checked.unit_publication_at(checked_program, 2, 0).unwrap()
  let policy = @checked.publication_source_policy(final_publication).unwrap()
  assert_eq(@checked.publication_policy_source_count(policy), 3)
  assert_eq(
    @publication_host.prepared_client_effect_publication_data_policy_cid(
      prepared,
    ),
    Some(policy.cid),
  )
  let bodies = @publication_host.prepared_client_effect_publication_policy_bodies(
    prepared, 1000000, 100000, 64,
  ).unwrap()
  assert_eq(bodies[0].1, policy.cid)
  for index in 0..<@checked.publication_policy_source_count(policy) {
    let original = @checked.publication_policy_source_at(policy, index).unwrap()
    assert_true(
      bodies.any(body => {
        body.0 == "data_policy" &&
        body.1 ==
        @checked.source_execution_subject(original).response_policy_cid
      }),
    )
  }
  let (_, request, contracts, model) = effect_model_plan_for_prepared(
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
  let ledger = match request_parent {
    Some((parent, _, _)) => parent.ledger
    None =>
      @resources.create_ledger({
        planning_work: 100000,
        attempts: 16,
        holdings: 16,
        transfer_bytes: 1048576L,
        retained_bytes: 536870912L,
        execution_bytes: 536870912L,
      }).unwrap()
  }
  @resources.configure_quantities(ledger, {
    tokens: 128L,
    cost_units: 0L,
    duration_ms: 1000L,
  }).unwrap()
  let original_quantities = @resources.quantity_usage(ledger)
  let managed = match request_parent {
    None => None
    Some((parent, input, _)) => {
      let construction = borrow_request_effect_plan_input(parent, input).unwrap()
      let installed = original_composed_keyed_installed_plan(
        prepared, request, contracts, model, declaration,
      )
      let scope = prepare_request_effect_model_read_scope(
        parent, input, installed,
      ).unwrap()
      complete_request_effect_preparation(parent, input, installed).unwrap()
      @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
      let owner = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
      retain_installed_effect_operation_controls_before_construction(
        owner, prepared, request, installed,
      ).unwrap()
      |> ignore
      Some((owner, scope))
    }
  }
  let scope = match managed {
    Some((_, scope)) => scope
    None => {
      let bootstrap = @resources.reserve_capacity(ledger, 4096L, 4096L).unwrap()
      @publication_host.begin_client_model_read_scope(
        model.compiled,
        model.definition,
        model.graph,
        ledger,
        bootstrap,
        16,
        16,
        0,
      ).unwrap()
    }
  }
  let prior_attempts = @resources.ledger_usage(ledger).attempts
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
  assert_eq(@resources.ledger_usage(ledger).attempts, prior_attempts + 2)
  let (execution, measurement, mapping) = original_composed_keyed_test_limits()
  let start_prefix = rows => {
    match managed {
      Some((owner, _)) =>
        start_installed_original_composed_keyed_prefix(
          owner,
          scope,
          model.compiled,
          model.definition,
          model.graph,
          keyed,
          rows,
          execution,
          measurement,
        )
      None =>
        start_client_original_composed_keyed_prefix(
          scope,
          model.compiled,
          model.definition,
          model.graph,
          keyed,
          rows,
          prefix,
          execution,
          measurement,
        )
    }
  }
  let before_refusal = @resources.ledger_usage(ledger)
  assert_true(start_prefix([captures[1], captures[0]]) is Err(_))
  assert_true(start_prefix([captures[0]]) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), before_refusal)
  if shared {
    assert_true(
      @row_source_host.retain_row_captured_inputs(captures, ledger, 100000)
      is None,
    )
  } else {
    assert_true(
      @row_source_host.retain_row_captured_inputs(captures, ledger, 100000)
      is Some(_),
    )
  }
  assert_true(
    @row_source_host.borrow_row_captured_inputs(captures, ledger, 100000)
    is Some(_),
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
  let selected_inputs = if shared {
    @publication_host.borrow_client_original_composed_keyed_captures(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      keyed,
      captures,
    )
  } else {
    @publication_host.retain_client_original_composed_keyed_captures(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      keyed,
      captures,
    )
  }
  let (_, row_inputs, sources) = selected_inputs.unwrap()
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
  let original = match start_prefix(captures) {
    Ok(value) => value
    Err(Original(@publication_host.ForeignRun)) =>
      fail("prefix original foreign Run")
    Err(Original(@publication_host.Resource(issue))) =>
      fail("prefix original resource: " + @debug.to_string(issue))
    Err(Unavailable) => fail("prefix original input unavailable")
    Err(Physical(issue)) => fail("prefix capacity: " + @debug.to_string(issue))
    Err(_) => fail("prefix original child refusal")
  }
  if shared {
    let before_duplicate = @resources.ledger_usage(ledger)
    assert_true(start_prefix(captures) is Err(Unavailable))
    assert_eq(@resources.ledger_usage(ledger), before_duplicate)
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
  let keyed_current = Ref(true)
  let restricted_right = @execution.restrict_supplied_relation_read(right, () => {
    keyed_current.val
  })
  assert_false(physical_equal(restricted_right, right))
  assert_true(
    @execution.supplied_relation_read_same_binding(restricted_right, right),
  )
  inputs.push(@local.managed_provider_supplied_relation_input(restricted_right))
  let before = @resources.ledger_usage(ledger)
  let foreign_read = @row_source_host.keyed_row_capture_read(captured).unwrap()
  assert_eq(@execution.supplied_relation_read_row_count(foreign_read), 1)
  assert_false(
    @execution.supplied_relation_read_same_binding(foreign_read, right),
  )
  let foreign_inputs = inputs.copy()
  foreign_inputs[foreign_inputs.length() - 1] = @local.managed_provider_supplied_relation_input(
    foreign_read,
  )
  assert_true(
    start_client_composed_infer_input(
      model._occurrence,
      prefix,
      foreign_inputs,
      execution,
      measurement,
      mapping,
      keyed=Some(lookup),
    )
    is Err(UnsupportedProgram),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  keyed_current.val = false
  assert_true(
    start_client_composed_infer_input(
      model._occurrence,
      prefix,
      inputs,
      execution,
      measurement,
      mapping,
      keyed=Some(lookup),
    )
    is Err(UnsupportedProgram),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  keyed_current.val = true
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
  assert_eq(@resources.ledger_usage(ledger).attempts, prior_attempts + 3)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 1)
  assert_eq(@resources.quantity_usage(ledger), original_quantities)
  if managed is Some((owner, _)) {
    let allowed = @publication_host.issue_client_effect_allowed_run(
      model._compilation,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2027-01-01T00:00:00.000Z",
    ).unwrap()
    let bound = @publication_host.bind_client_effect_compiled_run(
      prepared,
      allowed,
      model.definition,
    ).unwrap()
    guard owner.preparation is Some(PlannedEffectManaged(_, installed)) else {
      fail("the same adopted Effect Plan remains retained")
    }
    let (model_task, _, model_step) = @publication_host.client_infer_occurrence_coordinates(
      model._occurrence,
    )
    // This component has a deliberately fail-closed future Model provider.
    // Bind the actual completed keyed view to its real selected Local module;
    // it neither claims a physical Model result nor selects an empty offer.
    let captured = @strategy.open_multi_captured_effect_run_keyed_dag(
      @publication_host.prepared_client_effect_run_graph(bound),
      Array::makei(sources.length(), index => (index, sources[index])),
      ledger,
      model_task,
      model_step,
      right,
    ).unwrap()
    let dag = @strategy.captured_effect_run_dag(captured)
    let original_graph = installed.configuration.graph
    assert_false(
      physical_equal(@strategy.captured_dag_graph(dag), original_graph),
    )
    assert_true(
      @strategy.captured_effect_run_matches_preparation(
        captured, dag, original_graph,
      ),
    )
    let driver = @host_driver.open_dispatch_driver(dag)
    assert_true(physical_equal(@host_driver.dispatch_driver_run(driver), dag))
    // The legacy entry still rejects the distinct runtime view. Only the
    // actual checked Effect owner supplies the exact preparation association.
    assert_true(
      @local_driver.bind_local_dispatch_plan(
        driver,
        installed.configuration.dispatch,
      )
      is Err(_),
    )
    let configured_local = @local_driver.bind_local_effect_dispatch_plan(
      driver,
      installed.configuration.dispatch,
      captured,
    ).unwrap()
    assert_true(
      physical_equal(
        @local_driver.local_dispatch_original_preparation(configured_local).unwrap(),
        installed.configuration.dispatch,
      ),
    )
    assert_true(physical_equal(@strategy.captured_dag_ledger(dag), ledger))
    let make_foreign = foreign_run.unwrap()
    let foreign_bound = make_foreign()
    let foreign_graph = @strategy.checked_effect_run_graph(
      @publication_host.prepared_client_effect_run_graph(foreign_bound),
    )
    assert_false(
      @strategy.captured_effect_run_matches_preparation(
        captured, dag, foreign_graph,
      ),
    )
    let foreign_captured = @strategy.open_source_free_effect_run_dag(
      @publication_host.prepared_client_effect_run_graph(foreign_bound),
      ledger,
    ).unwrap()
    let foreign_dag = @strategy.captured_effect_run_dag(foreign_captured)
    assert_false(
      @strategy.captured_effect_run_matches_preparation(
        captured, foreign_dag, original_graph,
      ),
    )
    assert_true(
      @local_driver.bind_local_effect_dispatch_plan(
        driver,
        installed.configuration.dispatch,
        foreign_captured,
      )
      is Err(_),
    )
    @strategy.stop_captured_dag(foreign_dag)
    assert_true(@strategy.retire_captured_task_outputs(foreign_dag))
    assert_eq(@resources.ledger_usage(ledger).attempts, prior_attempts + 3)
    assert_eq(@resources.quantity_usage(ledger), original_quantities)
    // Configuration runs no future Model or UPDATE provider. Stop the actual
    // captured child before its existing owner and Scope perform retirement.
    @strategy.stop_captured_dag(dag)
    assert_true(@strategy.retire_captured_task_outputs(dag))
  }
  if !shared {
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
  }
  assert_true(cleanup_client_infer_input(input).unwrap())
  @row_source_host.close_accounted_row_run(child).unwrap()
  assert_true(
    @publication_host.cleanup_client_keyed_lookup_input(lookup, 10000).unwrap(),
  )
  assert_true(cleanup_client_serialization_prefix(original.prefix).unwrap())
  for run in runs {
    @row_source_host.close_accounted_row_run(run).unwrap()
  }
  if managed is Some((owner, _)) {
    quiesce_installed_managed_run(owner).unwrap()
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
  if managed is Some((owner, _)) {
    retire_installed_managed_run(owner).unwrap()
  }
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, prior_attempts + 3)
}

///|
fn original_composed_keyed_installed_plan(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  contracts : ClientInstalledSequenceContracts,
  model : ClientInstalledEffectModelDemand,
  declaration : @row_source_host.RowDeclaration,
) -> ClientInstalledEffectManagedPlan {
  // This component never starts its future UPDATE or physical Model provider.
  // Its actual selected construction member fails closed if invoked.
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(3L, 5L).unwrap(),
    7L,
    true,
  ).unwrap()
  let operation = prepare_installed_effect_operation_demand(
    prepared,
    2,
    "save",
    [extent],
    [extent],
  ).unwrap()
  prepare_installed_effect_managed_plan(
    prepared,
    request,
    [declaration, declaration],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [4096L, 4096L],
    [4096L, 4096L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [operation],
    model=Some(model),
    provider_factory=capacity => {
      [
        @local.managed_provider(_ => true, _ => Some(capacity), (_, _, _, _, _) => {
          Err(@connector.ComputeUnsupported)
        }),
      ]
    },
  ).unwrap()
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
