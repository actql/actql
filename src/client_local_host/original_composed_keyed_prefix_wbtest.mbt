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
test "downstream Model retains complete original keyed Source provenance without reusing its live lookup" {
  original_composed_keyed_consumer(following=true)
}

///|
test "complete keyed Source closure refuses a same-graph non-ancestor Model" {
  original_composed_keyed_consumer(following=true, parallel=true)
}

///|
fn original_composed_keyed_consumer(
  prepare_parent? : ((String, @checked.CheckEnvironment) -> (
    ClientRequestPreparation[Array[Int]],
    Array[Int],
    @publication_host.PreparedClientEffectComputation,
  ) raise)? = None,
  foreign_run? : (() -> @publication_host.PreparedClientEffectRun raise)? = None,
  following? : Bool = false,
  parallel? : Bool = false,
  whole? : Bool = false,
  restored? : Bool = false,
  native_keyed? : Bool = false,
  keyed_start_observer? : ((ClientInstalledKeyedSourceRead) -> Unit)? = None,
  retained_input_root? : Bool = false,
  large_lookup_policy? : Bool = false,
  publication_identity? : Bool = false,
  publication_early? : Bool = false,
  source_identity_bodies? : Bool = false,
  keyed_identity_bodies? : Bool = false,
  keyed_body_reentry? : Bool = false,
  keyed_body_stop? : Bool = false,
  direct_effect_evidence? : Bool = false,
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
  let mut document =
    #|{"version":"actql/0.1","id":"two-direct-keyed-model","stages":[{"id":"left","inputs":{"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["name","resource","version"]}}},{"id":"right","inputs":{"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["name","resource","version"]}}},{"id":"classify","inputs":{"a":{"result":{"stage":"left","result":"rows"}},"b":{"result":{"stage":"right","result":"rows"}},"contents":{"connector":"content-fixture","resource":"contents"}},"steps":[{"from":"a","join":{"with":"b","kind":"inner","on":[{"left":"name","right":"name"}],"select":{"name":"left.name","resource":"left.resource","version":"left.version"}},"as":"joined"},{"from":"joined","join":{"with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"captured"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"},{"derive":{"id":{"literal":1}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"classify","result":"rows"}}}}
  if following {
    let parsed = @json.parse(document)
    guard parsed is Object(fields) && fields["stages"] is Array(stages) else {
      fail("the original keyed document is required")
    }
    guard stages[2] is Object(first) &&
      first["results"] is Object(results) &&
      results["rows"] is Object(rows) &&
      rows["fields"] is Array(output_fields) else {
      fail("the original first Model Result is required")
    }
    output_fields.push(Json::string("name"))
    let independent =
      #|{"id":"following","inputs":{"rows":{"result":{"stage":"right","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"assessed"},{"derive":{"id":{"literal":1}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","name","outcome"]}}}
    let dependent =
      #|{"id":"following","inputs":{"rows":{"result":{"stage":"classify","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"name"}}},"as":"assessed"}],"results":{"rows":{"from":"assessed","fields":["id","outcome"]}}}
    let next = @json.parse(if parallel { independent } else { dependent })
    guard next is Object(next_fields) else {
      fail("the downstream Model stage is required")
    }
    // The original write remains after the selected computation. A Result
    // consumed by the next Model must not also be an unresolved Effect receipt.
    let effects = first["effects"]
    first.remove("effects")
    stages.push(next)
    if parallel {
      // Both independent Model outputs remain selected by the original write;
      // this target has no data edge from the keyed Model into the other Model.
      let combine_wire =
        #|{"id":"combine","inputs":{"a":{"result":{"stage":"classify","result":"rows"}},"b":{"result":{"stage":"following","result":"rows"}}},"steps":[{"from":"a","join":{"with":"b","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}
      let combine = @json.parse(combine_wire)
      guard combine is Object(combined) else {
        fail("the original write join is required")
      }
      combined["effects"] = effects
      stages.push(combine)
      fields["results"] = @json.parse(
        "{\"rows\":{\"from\":{\"stage\":\"combine\",\"result\":\"rows\"}}}",
      )
    } else {
      next_fields["effects"] = effects
      fields["results"] = @json.parse(
        "{\"rows\":{\"from\":{\"stage\":\"following\",\"result\":\"rows\"}}}",
      )
    }
    document = parsed.stringify()
  }
  if whole {
    guard @json.parse(document) is Object(fields) &&
      fields["stages"] is Array(stages) &&
      stages[2] is Object(unit) &&
      unit["inputs"] is Object(inputs) else {
      fail("whole fixture")
    }
    inputs["a"] = @json.parse(
      "{\"connector\":\"content-fixture\",\"resource\":\"files\"}",
    )
    inputs["b"] = inputs["a"]
    let retained = [stages[2]]
    for index in 3..<stages.length() {
      retained.push(stages[index])
    }
    fields["stages"] = Json::array(retained)
    document = Json::object(fields).stringify()
  }
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
        Err(@publication_host.Graph(issue)) =>
          fail("two-Direct keyed Model graph: " + @debug.to_string(issue))
        Err(@publication_host.Candidate(_)) =>
          fail("two-Direct keyed Model candidate")
        Err(@publication_host.Stage(_)) => fail("two-Direct keyed Model stage")
        Err(@publication_host.Static(_)) =>
          fail("two-Direct keyed Model static")
        Err(_) => fail("two-Direct keyed Model fixture preparation")
      }
  }
  if whole && !following {
    let limits = @publication_host.client_standard_effect_computation_limits()
    assert_true(
      @publication_host.prepare_client_effect_computation(
        document,
        Json,
        environment,
        None,
        [],
        { ..limits, program: { ..limits.program, max_tasks: 0, }, },
      )
      is Err(@publication_host.Graph(@strategy.GraphIssue::TaskLimit)),
    )
    // A later public output cannot stand in for an earlier private Effect Step
    // on an unsplit captured root. Keep its exact target until real splitting.
    guard @json.parse(document) is Object(fields) &&
      fields["stages"] is Array(stages) &&
      stages[0] is Object(unit) &&
      unit["steps"] is Array(steps) &&
      unit["results"] is Object(results) else {
      fail("private Whole source fixture")
    }
    steps.push(
      @json.parse(
        "{\"from\":\"selected\",\"select\":[\"id\"],\"as\":\"public_output\"}",
      ),
    )
    results["public_rows"] = @json.parse(
      "{\"from\":\"public_output\",\"fields\":[\"id\"]}",
    )
    fields["results"] = @json.parse(
      "{\"rows\":{\"from\":{\"stage\":\"classify\",\"result\":\"public_rows\"}}}",
    )
    assert_true(
      @publication_host.prepare_client_effect_computation(
        Json::object(fields).stringify(),
        Json,
        environment,
        None,
        [],
        limits,
      )
      is Err(
        @publication_host.Graph(
          @strategy.GraphIssue::UnsupportedEffectSource(0)
        )
      ),
    )
  }
  // These are three distinct checked response originals even though the two
  // Direct occurrences select the same SourceView. The keyed response is not
  // one of those Direct roots and cannot be dropped from the whole Run policy.
  let checked_program = @strategy.graph_program(
    @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ),
  )
  let final_publication = @checked.unit_publication_at(
    checked_program,
    if whole {
      0
    } else {
      2
    },
    0,
  ).unwrap()
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
  let graphs = if following {
    @publication_host.prepared_client_effect_infer_occurrences(prepared)
    .unwrap()
    .map(occurrence => {
      @publication_host.issue_installed_client_composed_infer_plan_graph(
        occurrence,
        effect_model_plan_execution(occurrence),
        @publication_host.client_standard_values_sequence_limits(),
        1000000,
        100000,
        100,
      ).unwrap()
    })
  } else {
    []
  }
  let (_, request, contracts, model) = effect_model_plan_for_prepared(
    prepared,
    acquired=true,
    infers=graphs,
  )
  let keyed = @publication_host.select_client_effect_composed_model_keyed_acquisition(
      prepared,
      model.graph,
    )
    .unwrap()
    .unwrap()
  let prefix = if retained_input_root {
    let installed = original_composed_keyed_installed_plan(
      prepared, request, contracts, model, declaration,
    )
    let sequence = prepared_installed_effect_model_sequence(
      installed,
      model.graph,
    ).unwrap()
    let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
      model._occurrence,
    )
    assert_true(@execution.generated_sequence_step_count(sequence) > step)
    assert_true(
      physical_equal(
        sequence,
        prepared_installed_effect_model_sequence(installed, model.graph).unwrap(),
      ),
    )
    sequence
  } else {
    prepare_client_composed_infer_prefix(
      model.graph.owner,
      model._occurrence,
      contracts,
      source_query_original_values,
      fragment_body=Some(source_query_original_fragment),
    ).unwrap()
  }
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
  let body_lookup : Ref[@publication_host.ClientKeyedLookupInput?] = Ref(None)
  let body_armed = Ref(false)
  let body_observed = Ref(false)
  let body_reentry_refused = Ref(false)
  let body_cleanup_deferred = Ref(false)
  let accepted = wire => {
    // The keyset emits Resource references; the one body scan emits the
    // actual Content reference. No callback-count or fabricated current proof.
    if body_armed.val && wire == original_keyed_child_content(0) {
      body_armed.val = false
      body_observed.val = true
      if body_lookup.val is Some(lookup) {
        if keyed_body_stop {
          body_cleanup_deferred.val = @publication_host.cleanup_client_keyed_lookup_input(
              lookup, 10000,
            )
            is Ok(false)
        } else if keyed_body_reentry {
          body_reentry_refused.val = @publication_host.finish_client_keyed_lookup_input(
              lookup,
            )
            is Err(_) &&
            @publication_host.finish_client_keyed_lookup_publication_input(
              lookup,
              16384,
              1024,
              20,
              retain_body=true,
            )
            is Err(_)
        }
      }
    }
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
  let whole_capacities = []
  let closed_inputs = []
  let restorations = []
  let whole_observations = []
  let whole_identities : Array[@query.CapturedSourceRelationIdentity] = []
  let direct_effect_originals : Ref[
    Array[@publication_host.ClientEffectAcquiredEvidence],
  ] = Ref([])
  for task in 0..<2 {
    let run = if whole {
      let selected = @publication_host.prepare_client_effect_source_acquisition(
        prepared, 0, task,
      ).unwrap()
      let policy = installed_row_input_policy(2, 4096, 10000, 32, 2)
      let acquisition = @row_source_host.prepare_row_input_acquisition(
        selected,
        @checked.source_identity(checked_program),
        @execution.generated_prepared_sequence(prefix),
        contracts.original.value.contracts,
        declaration,
        policy,
      ).unwrap()
      let capacity = installed_whole_source_capture_capacity(
        selected,
        acquisition,
        None,
      ).unwrap()
      whole_capacities.push(capacity)
      @row_source_host.start_accounted_row_input_acquisition(
        acquisition,
        None,
        "whole-original-" + task.to_string(),
        _ => true,
        ledger,
        4096L,
        4096L,
      ).unwrap()
    } else {
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
      requirements.push(requirement)
      acquisitions.push(acquisition)
      run
    }
    if !restored {
      runs.push(run)
    }
    if whole {
      @row_source_host.begin_row_run_with_page_limits(
        run,
        @row_source_host.row_input_acquisition_limits(
          whole_capacities[task].acquisition,
        ).page,
        1,
        reference_issuer=Some(issuer),
      ).unwrap()
    } else {
      @row_source_host.begin_row_run(
        run,
        4096,
        1,
        1,
        reference_issuer=Some(issuer),
      ).unwrap()
    }
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
    let captured = @row_source_host.capture_row_run(run).unwrap()
    captures.push(captured)
    if whole {
      let capacity = whole_capacities[task]
      let source = @row_source_host.row_capture_source(captured).unwrap()
      let limits = original_keyed_content_workspace().export_limits
      let identity = if source_identity_bodies {
        let scan = @query.start_captured_source_cell_identity(
          source,
          1,
          limits.values,
          limits.payload_wire,
          limits.logical_wire,
          limits.schema,
          1000000,
          100000,
          16777216,
        ).unwrap()
        let mut complete = false
        for _ in 0..<100000 {
          let next = @query.captured_source_cell_identity_next_capacity(scan).unwrap()
          if @query.advance_captured_source_cell_identity(scan, 7, next).unwrap().0 {
            complete = true
            break
          }
        }
        assert_true(complete)
        let identity = @query.finish_captured_source_cell_identity(scan).unwrap()
        let (body, schema) = @query.captured_source_relation_dependency_bodies(
          identity, source,
        ).unwrap()
        assert_true(body.has_prefix("{\"sort\":\"relation\",\"value\":["))
        assert_true(schema.contains("resource"))
        assert_true(
          @query.captured_source_relation_identity_matches_source(
            identity, source,
          ),
        )
        identity
      } else {
        @query.identify_captured_source_relation(
          source,
          1,
          limits.values,
          limits.payload_wire,
          limits.logical_wire,
          limits.schema,
          limits.max_batch_bytes,
        ).unwrap()
      }
      whole_identities.push(identity)
      let logical = @publication_host.issue_captured_whole_source_input_logical(
        @strategy.checked_effect_computation_graph(
          @publication_host.prepared_client_effect_computation_graph(prepared),
        ),
        source,
        identity,
        capacity.original,
        task=0,
      ).unwrap()
      let facts = @planning.source_acquisition_evidence_facts(capacity.original).unwrap()
      let observation = @row_source_host.issue_row_input_source_evidence(
        capacity.acquisition,
        captured,
        identity,
        logical,
        "sha256:" + "2".repeat(64),
        facts.source_data_policy_cid,
        "2026-11-05T00:00:01.000Z",
      ).unwrap()
      whole_observations.push((logical, observation))
      if restored {
        let (saved_identity, schema, rows_cid, rows) = export_client_whole_source_capture(
          source, capacity, "same-composed-input",
        ).unwrap()
        @row_source_host.close_accounted_row_run(run).unwrap()
        let saved = restore_accounted_client_whole_source_capture(
          capacity,
          "same-composed-input",
          "same-composed-input",
          saved_identity,
          schema,
          rows_cid,
          rows,
          ledger,
          () => true,
          reference_issuer=issuer,
        ).unwrap()
        closed_inputs.push(
          accounted_client_source_capture_input(saved).unwrap(),
        )
        restorations.push(saved)
      } else {
        closed_inputs.push(
          @row_source_host.row_capture_input(captured).unwrap(),
        )
      }
    }
  }
  assert_eq(@resources.ledger_usage(ledger).attempts, prior_attempts + 2)
  let (execution, measurement, mapping) = original_composed_keyed_test_limits()
  let start_prefix = (rows : Array[@row_source_host.RowSourceCapture]) => {
    if whole {
      let selected = rows.map(row => {
        let mut selected = None
        for index, capture in captures {
          if physical_equal(row, capture) {
            selected = Some(closed_inputs[index])
          }
        }
        selected.unwrap()
      })
      start_client_original_composed_keyed_input_prefix(
        scope,
        model.compiled,
        model.definition,
        model.graph,
        keyed,
        selected,
        prefix,
        execution,
        measurement,
      )
    } else {
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
  }
  let before_refusal = @resources.ledger_usage(ledger)
  assert_true(start_prefix([captures[1], captures[0]]) is Err(_))
  assert_true(start_prefix([captures[0]]) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), before_refusal)
  if whole {
    assert_true(
      @row_source_host.borrow_row_captured_input_originals(
        closed_inputs, ledger, 100000,
      )
      is Some(_),
    )
  } else {
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
  }
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
  let selected_inputs = if whole {
    @publication_host.borrow_client_original_composed_keyed_input_captures(
      scope,
      model.compiled,
      model.definition,
      model.graph,
      keyed,
      closed_inputs,
      installed=true,
    )
  } else if shared {
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
    Err(Provider(@connector.Execution(@execution.InputSet))) =>
      fail("prefix provider InputSet")
    Err(Provider(@connector.Execution(@execution.InputOwnership))) =>
      fail("prefix provider InputOwnership")
    Err(Provider(@connector.InputUnavailable)) =>
      fail("prefix provider InputUnavailable")
    Err(Provider(@connector.ComputeUnsupported)) =>
      fail("prefix provider ComputeUnsupported")
    Err(Provider(@connector.Execution(_))) =>
      fail("prefix provider other Execution")
    Err(Provider(_)) => fail("prefix provider other")
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
  let before_lookup = @resources.ledger_usage(ledger)
  let lookup = match
    @publication_host.start_client_original_composed_keyed_lookup_input(
      left,
      if large_lookup_policy {
        2147483647
      } else {
        4096
      },
      if large_lookup_policy {
        2147483647
      } else {
        10000
      },
    ) {
    Ok(value) => value
    Err(issue) => {
      let reason = match issue {
        @publication_host.ForeignLeft => "ForeignLeft"
        @publication_host.Assembly(reason) => "Assembly:" + reason
        @publication_host.Physical(_) => "Physical"
        _ => "Other"
      }
      fail("original Model Scope lookup: " + reason)
    }
  }

  if large_lookup_policy {
    let after_lookup = @resources.ledger_usage(ledger)
    // The two actual empty assembly buffers fit the existing small fixture
    // allowance even with large logical quotas. The complete expected keyed
    // input/Model mapping below still executes; no row or byte cap is lowered.
    assert_true(
      after_lookup.reserved_execution_bytes -
      before_lookup.reserved_execution_bytes <
      1048576L,
    )
    assert_true(
      after_lookup.reserved_retention_bytes -
      before_lookup.reserved_retention_bytes <
      1048576L,
    )
  }
  assert_true(
    @publication_host.client_composed_keyed_lookup_matches_model_parent(
      lookup,
      model.compiled,
      model.definition,
      model.graph,
      ledger,
    ),
  )
  // The SAME left cannot open another assembly, even with identical bounds.
  assert_true(
    @publication_host.start_client_original_composed_keyed_lookup_input(
      left, 4096, 10000,
    )
    is Err(_),
  )
  if retained_input_root {
    let before = @resources.ledger_usage(ledger)
    // No completed right input exists yet. An omitted duplicate vector never
    // substitutes for the original lookup's completed-input association.
    assert_true(
      start_client_composed_infer_input(
        model._occurrence,
        prefix,
        [],
        execution,
        measurement,
        mapping,
        keyed=Some(lookup),
      )
      is Err(UnsupportedProgram),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
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
  let (native_read, acquisition, child) = if native_keyed {
    guard managed is Some((owner, _)) else {
      fail("original managed keyed parent")
    }
    let read = begin_installed_managed_model_keyed_source_read(
      owner,
      keyed,
      request,
      declaration,
      original_keyed_child_limits(),
    ).unwrap()
    let acquisition = installed_keyed_source_read_acquisition(read).unwrap()
    assert_true(
      installed_keyed_source_read_acquisition_matches(read, acquisition),
    )
    assert_false(
      installed_keyed_source_read_acquisition_matches({ ..read, }, acquisition),
    )
    @row_source_host.check_row_keyed_acquisition_original(
      acquisition, declaration,
    ).unwrap()
    let (foreign_declaration, _) = original_keyed_declaration_environment(
      relation_versions=true,
    )
    assert_true(
      @row_source_host.check_row_keyed_acquisition_original(
        acquisition, foreign_declaration,
      )
      is Err(@row_source_host.ForeignDeclaration),
    )
    if keyed_start_observer is Some(observe) {
      observe(read)
    }
    let child = start_installed_keyed_source_read_rows(
      read,
      acquisition,
      "same-native-keyed-child",
      _ => true,
      8192L,
      4096L,
      _ => true,
    ).unwrap()
    (Some(read), acquisition, child)
  } else {
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
    (None, acquisition, child)
  }
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
  if native_keyed {
    let before = @resources.ledger_usage(ledger)
    @row_source_host.begin_keyed_row_run_response_attempt(child, acquisition).unwrap()
    assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts + 1)
    // The original latch never spends a second attempt on a repeated entrance.
    @row_source_host.begin_keyed_row_run_response_attempt(child, acquisition).unwrap()
    assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts + 1)
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      before.transferred_bytes,
    )
  }
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
  body_lookup.val = Some(lookup)
  body_armed.val = keyed_body_reentry || keyed_body_stop
  let right_result = if publication_early {
    @publication_host.finish_client_keyed_lookup_publication_input(
      lookup,
      16384,
      1024,
      20,
      retain_body=keyed_identity_bodies,
    )
  } else {
    @publication_host.finish_client_keyed_lookup_input(lookup)
  }
  if keyed_body_reentry {
    assert_true(body_observed.val && body_reentry_refused.val)
  }
  if keyed_body_stop {
    assert_true(body_observed.val && body_cleanup_deferred.val)
    assert_true(right_result is Err(_))
    assert_true(
      @publication_host.client_keyed_lookup_input_identity(lookup) is None,
    )
    @row_source_host.close_accounted_row_run(child).unwrap()
    assert_true(
      @publication_host.cleanup_client_keyed_lookup_input(lookup, 10000).unwrap(),
    )
    assert_true(cleanup_client_serialization_prefix(original.prefix).unwrap())
    for run in runs {
      @row_source_host.close_accounted_row_run(run).unwrap()
    }
    assert_true(restorations.is_empty() && managed is None)
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
    assert_eq(@resources.ledger_usage(ledger).attempts, prior_attempts + 3)
    return
  }
  let right = right_result.unwrap()

  if publication_identity {
    let keys = match
      @publication_host.client_keyed_lookup_request_identity(
        lookup, 16384, 1024, 20,
      ) {
      Ok(value) => value
      Err(@publication_host.Identity(issue)) =>
        fail("actual key-set contract: " + @debug.to_string(issue))
      Err(@publication_host.Assembly(reason)) =>
        fail("actual key-set assembly: " + reason)
      Err(_) => fail("actual key-set refused outside contract/assembly")
    }
    if publication_early {
      assert_true(
        physical_equal(
          keys,
          @publication_host.client_keyed_lookup_request_identity(
            lookup, 16384, 1024, 20,
          ).unwrap(),
        ),
      )
    }
    assert_true(
      @publication_host.client_keyed_lookup_request_identity_matches(
        keys, lookup,
      ),
    )
    let parts = @publication_host.client_keyed_lookup_request_identity_parts(
      keys,
    )
    assert_eq(parts.1, "{}")
    assert_eq(
      parts.2,
      "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
    )
    let scope_wire = @publication.publication_contract_json(parts.3)
    assert_true(
      scope_wire.contains(
        "\"request_key_set_cid\":\"" +
        @publication.publication_contract_identity(parts.0) +
        "\"",
      ),
    )
    assert_true(
      scope_wire.contains("\"request_values_cid\":\"" + parts.2 + "\""),
    )
    let wire = @publication.publication_contract_json(parts.0)
    assert_false(wire.contains("$actql_ref"))
    assert_false(wire.contains("issuer_evidence"))
    guard @json.parse(wire) is Object(fields) &&
      fields["tuples"] is Array(tuples) &&
      tuples.length() == 1 &&
      tuples[0] is Array(cells) &&
      cells.length() == 2 else {
      fail("actual Resource/version request tuple")
    }
    assert_true(
      @publication.admit_publication_effect_dependency_body(
        "request_key_set", wire, 16384, 1024, 20,
      )
      is Ok(_),
    )
  }
  if whole {
    let original_graph = @strategy.checked_effect_computation_graph(
      @publication_host.prepared_client_effect_computation_graph(prepared),
    )
    let supplied = @strategy.prepare_source_inputs_dag(
      original_graph,
      whole_capacities.map(capacity => capacity.original),
    ).unwrap()
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
    let checked = @publication_host.prepared_client_effect_run_graph(bound)
    assert_true(
      @strategy.open_source_inputs_effect_run_dag(
        checked, supplied, sources, ledger,
      )
      is Err(_),
    )
    let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
      model._occurrence,
    )
    let complete = @strategy.graph_with_completed_keyed_model_input(
      supplied, task, step, right,
    ).unwrap()
    assert_eq(complete.supplied_slots_count(), 3)
    assert_true(
      @strategy.open_source_inputs_effect_run_dag(
        checked, complete, sources, ledger,
      )
      is Err(_),
    )
    assert_true(
      physical_equal(
        @strategy.graph_with_completed_keyed_model_input(
          complete, task, step, right,
        ).unwrap(),
        complete,
      ),
    )
    let captured = @strategy.open_source_inputs_effect_run_dag(
      checked,
      complete,
      sources,
      ledger,
      keyed=Some((task, step, right)),
    ).unwrap()
    let dag = @strategy.captured_effect_run_dag(captured)
    assert_true(
      @strategy.captured_effect_run_matches_preparation(captured, dag, supplied),
    )
    assert_false(@strategy.captured_task_completed(dag, task))
    @strategy.stop_captured_dag(dag)
    assert_true(@strategy.retire_captured_task_outputs(dag))
  }

  let authority = "sha256:" + "2".repeat(64)
  let started = "2026-11-05T00:00:00.000Z"
  let completed = "2026-11-05T00:00:01.000Z"
  let limits = original_keyed_content_workspace().export_limits
  let identities = []
  let logicals = []
  let observations = []
  for task, source in sources {
    let identity = if source_identity_bodies && whole {
      let identity = whole_identities[task]
      assert_true(
        @query.captured_source_relation_dependency_bodies(identity, source)
        is Some(_),
      )
      identity
    } else {
      @query.identify_captured_source_relation(
        source,
        1,
        limits.values,
        limits.payload_wire,
        limits.logical_wire,
        limits.schema,
        limits.max_batch_bytes,
      ).unwrap()
    }
    let (logical, observation) = if whole {
      whole_observations[task]
    } else {
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
      (logical, observation)
    }
    identities.push(identity)
    logicals.push(logical)
    observations.push(observation)
  }
  let keyed_observation = @publication_host.issue_client_keyed_lookup_observation(
    lookup, authority, completed,
  ).unwrap()
  if keyed_identity_bodies {
    let bodies = @publication_host.client_keyed_lookup_observation_dependency_bodies(
      keyed_observation,
    ).unwrap()
    let row = original_keyed_child_expected_row(0)
    let expected = "{\"sort\":\"relation\",\"value\":[" + row + "]}"
    assert_eq(bodies.0, expected)
    let (_, _, logical) = @publication_host.client_keyed_lookup_observation_originals(
      keyed_observation,
    ).unwrap()
    assert_eq(logical, "sha256:" + @sha.text_hex(expected).unwrap())
    assert_eq(
      @publication_host.client_keyed_lookup_input_identity(lookup),
      Some("sha256:" + @sha.text_hex("[" + row + "]").unwrap()),
    )
    // The second original-observation projection consumes the SAME receipt;
    // it opens no new reservation, allocation, response or identity scan.
    let usage = @resources.ledger_usage(ledger)
    let again = @publication_host.issue_client_keyed_lookup_observation(
      lookup, authority, completed,
    ).unwrap()
    assert_eq(
      @publication_host.client_keyed_lookup_observation_dependency_bodies(again),
      Some(bodies),
    )
    assert_eq(@resources.ledger_usage(ledger), usage)
  }
  let admit_sources = (
    selected,
    selected_identities,
    selected_logicals,
    selected_evidence,
    lookup,
  ) => {
    if whole {
      @publication_host.admit_client_infer_composed_whole_sources(
        model._occurrence,
        selected,
        selected_identities,
        whole_capacities.map(capacity => capacity.original),
        selected_logicals,
        selected_evidence,
        authority,
        started,
        completed,
        keyed=lookup,
      )
    } else {
      @publication_host.admit_client_infer_composed_sources(
        model._occurrence,
        selected,
        selected_identities,
        requirements,
        selected_logicals,
        selected_evidence,
        authority,
        started,
        completed,
        keyed=lookup,
      )
    }
  }
  assert_true(
    admit_sources(sources, identities, logicals, observations, None) is Err(_),
  )
  assert_true(
    admit_sources(
      [sources[1], sources[0]],
      identities,
      logicals,
      observations,
      Some(keyed_observation),
    )
    is Err(_),
  )
  let source_closure = admit_sources(
    sources,
    identities,
    logicals,
    observations,
    Some(keyed_observation),
  ).unwrap()
  assert_true(
    @publication_host.client_infer_composed_sources_matches(
      source_closure,
      model._occurrence,
    ),
  )
  if following {
    assert_eq(graphs.length(), 2)
    let second = graphs[1].occurrence
    assert_true(
      @publication_host.select_client_effect_composed_model_keyed_acquisition(
        prepared,
        graphs[1],
      )
      is Ok(None),
    )
    assert_true(
      @publication_host.admit_client_infer_composed_sources(
        model._occurrence,
        [sources[0]],
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
    assert_eq(
      @publication_host.client_infer_composed_sources_matches(
        source_closure, second,
      ),
      !parallel,
    )
    assert_true(
      @publication_host.client_infer_composed_keyed_lookup(
        source_closure, second,
      )
      is None,
    )
    assert_eq(
      @publication_host.client_infer_composed_source_observations(
        source_closure,
      ).length(),
      3,
    )
    let foreign = @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap()
    let foreign_second = @publication_host.prepared_client_effect_infer_occurrences(
        foreign,
      ).unwrap()[1]
    assert_false(
      @publication_host.client_infer_composed_sources_matches(
        source_closure, foreign_second,
      ),
    )
  }
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
    if retained_input_root {
      []
    } else {
      inputs
    },
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
  if direct_effect_evidence {
    let completed_input = client_infer_completed_input(input).unwrap()
    let scan = @execution.start_completed_relation_identity_scan(
      completed_input,
      20,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      10000,
      10000,
    ).unwrap()
    while !@execution.advance_completed_relation_identity_scan(scan, 7).unwrap().0 {
      ()
    }
    let receipt = @execution.finish_completed_relation_identity_scan(scan).unwrap()
    let call_scope = @publication_host.issue_client_infer_occurrence_call_scope(
      model._occurrence,
      model.graph,
      completed_input,
      receipt,
      1000000,
      100000,
      100,
      sources=Some(source_closure),
    ).unwrap()
    let artifact = @publication_host.client_infer_call_scope_artifact(
      call_scope,
    )
    guard @json.parse(@publication.run_evidence_value_json(artifact))
      is Object(fields) &&
      fields["unit_definition_cid"] is String(unit) else {
      fail("actual original Model input")
    }
    let (logical, schema) = @publication.model_input_artifact_relation_identities(
      artifact,
    ).unwrap()
    let ordinal = @publication_host.client_infer_occurrence_coordinates(
        model._occurrence,
      ).2
    // Only semantic projection is exercised here. These authored outcome CIDs
    // do NOT attest an accepted Model/provider/OutputUse or physical completion.
    let preimage = "{\"input_logical_relation_cid\":\"" +
      logical +
      "\",\"input_relation_schema_cid\":\"" +
      schema +
      "\",\"outcome_logical_relation_cid\":\"sha256:" +
      "e".repeat(64) +
      "\",\"outcome_relation_schema_cid\":\"sha256:" +
      "f".repeat(64) +
      "\",\"source_ordinal\":" +
      ordinal.to_string() +
      ",\"unit_definition_cid\":\"" +
      unit +
      "\",\"version\":\"actql-local-model-observation/0.1\"}"
    let body = @publication.admit_local_effect_dependency_body(
      "local_model_observation",
      preimage.replace(
        old=",\"source_ordinal\":",
        new=",\"self_cid\":\"sha256:" +
          @sha.text_hex(preimage).unwrap() +
          "\",\"source_ordinal\":",
      ),
      10000,
      1000,
      32,
    ).unwrap()
    let retention = @publication.seal_publication_contract(
      "result_retention_policy",
      "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"sha256:" +
      "1".repeat(64) +
      "\",\"effective_data_policy_cid\":\"sha256:" +
      "2".repeat(64) +
      "\",\"available_until\":\"2026-11-06T01:00:00.000Z\",\"delete_by\":\"2026-11-06T02:00:00.000Z\",\"extension_ceiling_at\":\"2026-11-06T03:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:" +
      "3".repeat(64) +
      "\",\"metadata_delete_by\":\"2026-11-06T04:00:00.000Z\",\"clock_contract_cid\":\"sha256:" +
      "4".repeat(64) +
      "\"}",
      10000,
      1000,
      32,
    ).unwrap()
    let issued_direct = @publication_host.issue_single_model_client_effect_direct_source_evidence(
      model.compiled,
      call_scope,
      body,
      source_closure,
      retention,
      16384,
      1024,
      20,
    )
    if !whole {
      let program = @checked.effect_program_static_checked_computation(
        @publication_host.prepared_client_effect_computation_candidate(prepared),
      )
      assert_true(
        @checked.unit_result_import_count(
          program,
          @publication_host.client_infer_occurrence_coordinates(
            model._occurrence,
          ).1,
        ).unwrap() >
        0,
      )
      assert_true(
        issued_direct
        is Err(
          @publication_host.Invocation(
            @publication_host.ForeignSourceObservation
          )
        ),
      )
    } else {
      let (invocation, direct) = issued_direct.unwrap()
      assert_eq(direct.length(), 2)
      direct_effect_originals.val = direct
      for index, evidence in direct {
        if source_identity_bodies {
          let raw = @publication_host.client_effect_acquired_relation_dependency_bodies(
            evidence,
          ).unwrap()
          let source_raw = @query.captured_source_relation_dependency_bodies(
            whole_identities[index],
            sources[index],
          ).unwrap()
          assert_eq(raw, [
            ("relation_value", source_raw.0),
            ("relation_schema", source_raw.1),
          ])
        }
        assert_true(
          physical_equal(
            @publication_host.client_effect_acquired_invocation(evidence),
            invocation,
          ),
        )
        let bodies = @publication_host.client_effect_acquired_dependency_bodies(
          evidence,
        )
        assert_eq(
          bodies.iter().find_first(pair => pair.0 == "request_values").unwrap().1,
          "{}",
        )
        assert_true(bodies.iter().any(pair => pair.0 == "acquisition_relation"))
        assert_true(bodies.iter().any(pair => pair.0 == "source_evidence"))
      }
      assert_eq(
        @publication_host.client_infer_composed_source_observations(
          source_closure,
        ).length(),
        3,
      )
      // Two Direct relations do not stand in for the third/keyed Source proof.
      assert_true(
        @publication_host.client_infer_composed_keyed_lookup(
          source_closure,
          model._occurrence,
        )
        is Some(_),
      )
    }
  }

  if following {
    let completed_input = client_infer_completed_input(input).unwrap()
    let scan = @execution.start_completed_relation_identity_scan(
      completed_input,
      20,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      10000,
      10000,
    ).unwrap()
    while !@execution.advance_completed_relation_identity_scan(scan, 7).unwrap().0 {
      ()
    }
    let receipt = @execution.finish_completed_relation_identity_scan(scan).unwrap()
    let call_scope = @publication_host.issue_client_infer_occurrence_call_scope(
      model._occurrence,
      model.graph,
      completed_input,
      receipt,
      1000000,
      100000,
      100,
      sources=Some(source_closure),
    ).unwrap()
    let snapshot = @publication_host.client_infer_call_scope_snapshot(
      call_scope,
    ).unwrap()
    let saved = @publication_host.read_client_infer_saved_call_scope(
      model.compiled,
      model.definition,
      model._occurrence,
      model.graph,
      snapshot,
      authority,
      () => true,
    ).unwrap()
    assert_eq(
      @publication_host.client_infer_saved_source_originals(
        saved,
        model.compiled,
        model.definition,
        model._occurrence,
        model.graph,
      )
      .unwrap()
      .length(),
      3,
    )
    assert_true(
      @publication_host.read_client_infer_saved_call_scope(
        model.compiled,
        model.definition,
        model._occurrence,
        model.graph,
        snapshot,
        authority,
        () => false,
      )
      is Err(_),
    )
  }

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
  if source_identity_bodies {
    for identity in whole_identities {
      @query.clear_captured_source_relation_dependency_bodies(identity)
    }
    for evidence in direct_effect_originals.val {
      assert_true(
        @publication_host.client_effect_acquired_relation_dependency_bodies(
          evidence,
        )
        is None,
      )
    }
    for index, source in sources {
      assert_true(
        @query.captured_source_relation_dependency_bodies(
          whole_identities[index],
          source,
        )
        is None,
      )
    }
  }
  @row_source_host.close_accounted_row_run(child).unwrap()
  if native_read is Some(read) {
    assert_true(
      @row_source_host.begin_keyed_row_run_response_attempt(child, acquisition)
      is Err(_),
    )
    retire_installed_keyed_source_read(read).unwrap()
    assert_false(
      installed_keyed_source_read_acquisition_matches(read, acquisition),
    )
  }
  assert_true(
    @publication_host.cleanup_client_keyed_lookup_input(lookup, 10000).unwrap(),
  )
  if keyed_identity_bodies {
    assert_true(
      @publication_host.client_keyed_lookup_observation_dependency_bodies(
        keyed_observation,
      )
      is None,
    )
  }
  if publication_identity {
    assert_true(
      @publication_host.client_keyed_lookup_request_identity(
        lookup, 16384, 1024, 20,
      )
      is Err(_),
    )
  }
  assert_true(cleanup_client_serialization_prefix(original.prefix).unwrap())
  for run in runs {
    @row_source_host.close_accounted_row_run(run).unwrap()
  }
  for saved in restorations {
    let mut closed = false
    for _ in 0..<10000 {
      if close_accounted_client_source_capture(saved, quantum=7) {
        closed = true
        break
      }
    }
    assert_true(closed)
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

///|
test "same-stage two Whole Inputs feed actual keyed and Model mapping on one Ledger" {
  original_composed_keyed_consumer(whole=true)
}

///|
#cfg(target="js")
test "restored same-stage two Whole Inputs retain actual custody through keyed and Model mapping" {
  original_composed_keyed_consumer(whole=true, restored=true)
}

///|
test "two dependent Models retain the exact Whole keyed Source closure" {
  original_composed_keyed_consumer(whole=true, following=true)
}

///|
fn start_client_original_composed_keyed_input_prefix(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  keyed : @publication_host.ClientKeyedAcquisition,
  rows : Array[@row_source_host.RowCapturedInput],
  input_prefix : @execution.GeneratedSequence,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[ClientOriginalComposedKeyedPrefix, ClientSerializationPrefixIssue] {
  start_client_original_composed_keyed_prefix_owned(
    scope,
    compiled,
    definition,
    plan,
    keyed,
    rows,
    input_prefix,
    execution,
    measurement,
    None,
    borrowed_inputs=true,
  )
}

///|
#cfg(target="js")
test "restored Whole inputs preserve two dependent Model Source snapshots" {
  original_composed_keyed_consumer(whole=true, restored=true, following=true)
}

///|
test "original composed keyed root maps its retained input originals without a duplicate producer vector" {
  original_composed_keyed_consumer(retained_input_root=true)
}

///|
test "large keyed logical quotas preserve actual input without an all-key upfront reservation" {
  original_composed_keyed_consumer(whole=true, large_lookup_policy=true)
}

///|
test "actual two Whole Sources retain the original keyed request identity through Model input and retire it" {
  original_composed_keyed_consumer(whole=true, publication_identity=true)
}

///|
test "actual two Whole Sources prepare one canonical keyed publication input before original Model input" {
  original_composed_keyed_consumer(
    whole=true,
    publication_identity=true,
    publication_early=true,
  )
}

///|
test "actual Whole Sources retain one scanned body through same keyed Model input and retire it" {
  original_composed_keyed_consumer(
    whole=true,
    publication_identity=true,
    publication_early=true,
    source_identity_bodies=true,
  )
}

///|
test "actual keyed Source retains one receipt and raw bodies before Model Read and retires them" {
  original_composed_keyed_consumer(
    whole=true,
    publication_identity=true,
    publication_early=true,
    keyed_identity_bodies=true,
  )
}

///|
test "keyed body original Content callback cannot reenter identity or supplied read finalization" {
  original_composed_keyed_consumer(
    whole=true,
    publication_identity=true,
    publication_early=true,
    keyed_identity_bodies=true,
    keyed_body_reentry=true,
  )
}

///|
test "keyed body reentrant cleanup defers backing retirement and preserves spent attempts" {
  original_composed_keyed_consumer(
    whole=true,
    publication_identity=true,
    publication_early=true,
    keyed_identity_bodies=true,
    keyed_body_stop=true,
  )
}

///|
test "actual Whole Source originals supply Model Direct acquisition evidence without Query conversion" {
  original_composed_keyed_consumer(
    whole=true,
    source_identity_bodies=true,
    direct_effect_evidence=true,
  )
}

///|
test "Query Result-import Model retains its existing direct-only Invocation refusal" {
  original_composed_keyed_consumer(direct_effect_evidence=true)
}
