///|
// Genuine common Whole RowRun, original source/input custody, actual empty
// typed key set and lookup holding. This component fixture has no physical
// provider/Store IO and claims no Native transport or durable ACK.
test "generic Whole lookup freezes its genuine empty response closure before holding and retires once" {
  run_original_source_completion(false)
}

///|
test "installed identity RowSource retains the full lookup witness closure and refuses missing work" {
  // resource-case-id: installed_row_lookup_full_closure
  run_original_source_completion(true)
}

///|
test "installed identity RowSource retains distinct Whole and keyed static request originals" {
  run_original_source_completion(true, distinct_requests=true)
}

///|
fn run_original_source_completion(
  installed_rows : Bool,
  distinct_requests? : Bool = false,
) -> Unit raise {
  // Installation-owned policy leaves are outside each lookup's cached bodies,
  // just as in ordinary publication. Use their real preimages and identities.
  let retention_dependencies = if installed_rows {
    let common = product_common_test_originals(at="2026-11-15T00:00:00.000Z")
    guard @json.parse(@utf8.decode(common.retention_dependencies))
      is Array(entries) else {
      fail("original retention dependencies")
    }
    entries.map(entry => {
      guard entry is Object(fields) &&
        fields.get("kind") is Some(String(kind)) &&
        fields.get("cid") is Some(String(cid)) &&
        fields.get("wire") is Some(String(wire)) else {
        abort("original retention member")
      }
      @publication.admit_captured_effect_dependency_body(
        kind,
        Some(cid),
        wire,
        8192,
        512,
        8,
      ).unwrap()
    })
  } else {
    []
  }
  let retention_leaf = (kind : String) => {
    retention_dependencies
    .iter()
    .find_first(body => {
      @publication.captured_effect_dependency_body_kind(body) == kind
    })
    .map(@publication.captured_effect_dependency_body_cid)
    .unwrap()
  }
  let (prepared, keyed, declaration) = generic_file_effect_fixture(
    whole=true,
    installed_rows~,
    whole_request=distinct_requests,
  )
  let measured = if installed_rows {
    let profile = @row_host.row_declaration_file_read_profile(
      declaration,
      declaration.views
      .iter()
      .find_first(view => view.resource == "contents")
      .unwrap().source_ref,
    ).unwrap()
    measure_client_effect_keyed_plan_construction(
      prepared,
      keyed,
      profile,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ).unwrap()
  } else {
    measure_client_effect_generic_keyed_plan_construction(
      prepared,
      keyed,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ).unwrap()
  }
  let graph = issue_client_effect_keyed_plan_graph(
    measured, 1000000, 100000, 100,
  ).unwrap()
  let joined_sequence = match graph.component {
    GenericKeyedPlan(component) => component.original.fragments.joined.sequence
    NativeKeyedPlan(component) => component.original.fragments.joined.sequence
  }
  let generated = @execution.prepare_generated_sequence(
    whole_source_capture_contracts(),
    joined_sequence,
    [],
    [],
    10000,
    1000000,
  ).unwrap()
  let limits = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "generic-scope", "generic-original", "2026-11-15T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = client_effect_allowed_keyed_run(allowed, graph, definition).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "generic-whole",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 100,
    holdings: 100,
    transfer_bytes: 1000000L,
    retained_bytes: 67108864L,
    execution_bytes: 67108864L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 100000L, 100000L).unwrap()
  let inventory = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 50, 50, 0,
  ).unwrap()
  let parent = bind_client_effect_keyed_original(
    prepared, compilation, compiled, definition, request, graph, keyed, ledger, inventory,
  ).unwrap()
  let original = prepare_client_effect_source_acquisition(prepared, 0, 0).unwrap()
  let owner = @strategy.graph_task_owner(
    @strategy.checked_effect_computation_graph(prepared.graph),
    0,
  ).unwrap()
  let sequence = @lower.prepare_sequence_prefix(owner, 0, limits.sequence).unwrap()
  let selected = @row_host.prepare_row_input_acquisition(
    original,
    @checked.source_identity(
      @strategy.graph_program(
        @strategy.checked_effect_computation_graph(prepared.graph),
      ),
    ),
    sequence,
    whole_source_capture_contracts(),
    declaration,
    {
      max_rows: 1,
      page: { max_bytes: 4096, max_nodes: 1000, max_depth: 20, max_rows: 1, },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire: {
        max_columns: 10,
        max_order_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      },
    },
  ).unwrap()
  let settled = Ref(false)
  let stopped = Ref(false)
  let run = @row_host.start_accounted_row_input_acquisition(
    selected,
    None,
    "generic-source",
    _ => settled.val,
    ledger,
    4096L,
    4096L,
  ).unwrap()
  @row_host.begin_row_run_with_page_limits(
    run,
    { max_bytes: 4096, max_nodes: 1000, max_depth: 20, max_rows: 1, },
    1,
  ).unwrap()
  let responses = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(responses, () => stopped.val).unwrap()
  let bytes = @utf8.encode("[]")
  let charge = @row_host.charge_row_run_page(run, bytes).unwrap()
  assert_eq(
    @row_host.accept_charged_row_run_page(run, charge, bytes).unwrap(),
    0,
  )
  @row_host.finish_row_run(run).unwrap()
  settled.val = true
  assert_true(whole_row_validate(run))
  let capture = @row_host.capture_row_run(run).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  let rows = @row_host.row_capture_input(capture).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let identity = @query.identify_captured_source_relation(
    source,
    1,
    {
      max_nodes: 10000,
      max_text_bytes: 20000,
      max_depth: 20,
      max_work: 1000000,
    },
    wire,
    wire,
    { max_fields: 10, max_bytes: 20000, max_nodes: 10000, max_depth: 20, },
    20000,
    retain_body_bytes=20000,
  ).unwrap()
  let logical = issue_captured_whole_source_input_logical(
    @strategy.checked_effect_computation_graph(prepared.graph),
    source,
    identity,
    original,
    task=0,
  ).unwrap()
  let observation = @row_host.issue_row_input_source_evidence(
    selected,
    capture,
    identity,
    logical,
    client_request_authority_scope_cid(request),
    @planning.source_acquisition_evidence_facts(original).unwrap().source_data_policy_cid,
    "2026-11-15T00:00:01.000Z",
  ).unwrap()
  let lookup = start_client_effect_keyed_capture_lookup_input(
    parent,
    [rows],
    10000,
    10000,
    1000000,
    1000000,
    source_sequence=Some(generated),
  ).unwrap()
  assert_true(client_keyed_left_source_matches(lookup.left, source))
  assert_true(client_effect_keyed_lookup_matches_parent(lookup, parent, ledger))
  guard lookup.left.composed is Some(composed) else {
    fail("same Source-only composed original")
  }
  // A genuine other capture is not this listing, even while both originals
  // are live. No File IO or replacement Source is performed by the matcher.
  let (_, _, foreign_selected) = whole_row_selection()
  let foreign_settled = Ref(true)
  let foreign_stopped = Ref(false)
  let (foreign_run, foreign_ledger) = whole_row_run(
    foreign_selected, foreign_settled, foreign_stopped,
  )
  let foreign_bytes = @utf8.encode("[]")
  let foreign_charge = @row_host.charge_row_run_page(foreign_run, foreign_bytes).unwrap()
  @row_host.accept_charged_row_run_page(
    foreign_run, foreign_charge, foreign_bytes,
  ).unwrap()
  |> ignore
  @row_host.finish_row_run(foreign_run).unwrap()
  assert_true(whole_row_validate(foreign_run))
  let foreign_capture = @row_host.capture_row_run(foreign_run).unwrap()
  let foreign_source = @row_host.row_capture_source(foreign_capture).unwrap()
  assert_false(client_keyed_left_source_matches(lookup.left, foreign_source))
  assert_false(
    client_keyed_left_source_matches({ ..lookup.left, source: None, }, source),
  )
  assert_false(
    client_keyed_left_source_matches(
      { ..lookup.left, source: Some(foreign_source), },
      source,
    ),
  )
  assert_false(
    client_keyed_left_source_matches(
      { ..lookup.left, acquisition: { ..keyed, }, },
      source,
    ),
  )
  assert_false(
    client_keyed_left_source_matches(
      {
        ..lookup.left,
        composed: Some({ ..composed, sources: [source, source], }),
      },
      source,
    ),
  )
  let (model_scope, model_compiled, model_definition, model_plan) = model_read_frame_scope_fixture()
  assert_false(
    client_keyed_left_source_matches(
      {
        ..lookup.left,
        composed: Some({
          ..composed,
          origin: ModelOrigin(model_scope, model_plan),
        }),
      },
      source,
    ),
  )
  assert_true(
    finish_client_model_read_scope(
      model_scope, model_compiled, model_definition, model_plan, true,
    ).unwrap(),
  )
  foreign_stopped.val = true
  @row_host.close_accounted_row_run(foreign_run).unwrap()
  assert_eq(@resources.ledger_usage(foreign_ledger).held_bytes, 0L)
  let retention = if installed_rows {
    require_source_fixture(
      prepare_client_keyed_native_left_identity(
        lookup,
        1,
        {
          max_nodes: 10000,
          max_text_bytes: 20000,
          max_depth: 20,
          max_work: 1000000,
        },
        wire,
        wire,
        { max_fields: 10, max_bytes: 20000, max_nodes: 10000, max_depth: 20, },
        1000000,
        100000,
      ),
      "left identity",
    )
    |> ignore
    let retention = match
      prepare_client_keyed_declared_file_retention(
        lookup,
        request,
        retention_leaf("retention_contract"),
        "2099-01-01T00:00:00.000Z",
        "2099-01-02T00:00:00.000Z",
        "2099-01-03T00:00:00.000Z",
        retention_leaf("metadata_retention_policy"),
        retention_leaf("clock_contract"),
        1000000,
      ) {
      Ok(value) => value
      Err(Assembly(reason)) => fail("installed retention: " + reason)
      Err(Physical(issue)) =>
        fail("installed retention physical: " + @debug.to_string(issue))
      Err(_) => fail("installed retention: other typed refusal")
    }
    // The distinct-request component selects a finite codec envelope for its
    // tiny metadata; the existing ledger and ordinary fixture stay unchanged.
    let source_metadata_bytes = if distinct_requests { 8192 } else { 1000000 }
    let source_metadata_nodes = if distinct_requests { 1024 } else { 100000 }
    match
      bind_client_keyed_whole_source_metadata(
        lookup, 0, identity, logical, observation, request, retention, source_metadata_bytes,
        source_metadata_nodes, 100,
      ) {
      Ok(_) => ()
      Err(Assembly(reason)) => fail("installed source metadata: " + reason)
      Err(Physical(issue)) =>
        fail("installed source metadata physical: " + @debug.to_string(issue))
      Err(SourceLogical(Admission(issue))) =>
        fail("installed source logical: " + @debug.to_string(issue))
      Err(SourceLogical(_)) => fail("installed source logical")
      Err(_) => fail("installed source metadata: other typed refusal")
    }
    require_source_fixture(
      prepare_client_keyed_native_left_relation(
        lookup,
        request,
        retention,
        client_request_authority_scope_cid(request),
        1000000,
        100000,
        100,
      ),
      "left relation",
    )
    |> ignore
    require_source_fixture(
      bind_client_keyed_declared_file_physical_source(lookup, [declaration]),
      "physical source",
    )
    require_source_fixture(
      start_client_keyed_declared_file_request_plan(
        lookup,
        "2026-11-15T00:00:01.000Z",
        0L,
        client_request_authority_scope_cid(request),
      ),
      "request plan",
    )
    require_source_fixture(
      finish_client_keyed_capture_request_plan(lookup, 1000000, 100000, 100),
      "closed request plan",
    )
    retention
  } else {
    match
      prepare_client_effect_keyed_generic_source_metadata(
        parent,
        lookup,
        identity,
        logical,
        observation,
        "sha256:" + "d".repeat(64),
        "2099-01-01T00:00:00.000Z",
        "2099-01-02T00:00:00.000Z",
        "2099-01-03T00:00:00.000Z",
        "sha256:" + "e".repeat(64),
        "sha256:" + "f".repeat(64),
        1000000,
        100000,
        100,
      ) {
      Ok(value) => value
      Err(Assembly(reason)) => fail("generic metadata: " + reason)
      Err(_) => fail("generic metadata: typed refusal")
    }
  }
  assert_true(
    client_effect_keyed_cached_dependency_bodies(parent, lookup, retention)
    is None,
  )
  let before_invalid = @resources.ledger_usage(ledger)
  assert_true(
    finish_client_effect_keyed_generic_publication_input(
      parent, lookup, "not-a-time", 1000000, 100000, 100,
    )
    is Err(Assembly("foreign_generic_completion")),
  )
  assert_eq(@resources.ledger_usage(ledger), before_invalid)
  let read = match
    (if installed_rows {
      finish_client_keyed_lookup_publication_input(
        lookup,
        1000000,
        100000,
        100,
        retain_body=true,
        native_completion=Some(("2026-11-15T00:00:02.000Z", 0L)),
      )
    } else {
      finish_client_effect_keyed_generic_publication_input(
        parent, lookup, "2026-11-15T00:00:02.000Z", 1000000, 100000, 100,
      )
    }) {
    Ok(value) => value
    Err(Assembly(reason)) => fail("generic completion: " + reason)
    Err(LookupLimit(reason)) => fail("generic completion limit: " + reason)
    Err(Dependency(Dependency(issue))) =>
      fail("generic dependency admission: " + @debug.to_string(issue))
    Err(Dependency(Static(issue))) =>
      fail("generic dependency catalog: " + @debug.to_string(issue))
    Err(Dependency(ForeignInput)) => fail("generic dependency foreign input")
    Err(Dependency(ConstructionRefused)) =>
      fail("generic dependency construction refused")
    Err(Dependency(_)) => fail("generic completion dependency")
    Err(_) => fail("generic completion: typed refusal")
  }
  assert_true(@execution.supplied_relation_read_available(read))
  assert_true(
    if installed_rows {
      lookup.native_sources is Some(_) && lookup.native_completion is Some(_)
    } else {
      lookup.native_sources is None && lookup.native_completion is None
    },
  )
  let observed = issue_client_keyed_lookup_observation(
    lookup,
    client_request_authority_scope_cid(request),
    "2026-11-15T00:00:02.000Z",
  ).unwrap()
  if !installed_rows {
    assert_true(
      parent.generic is Some(state) &&
      state.completed is Some(completed) &&
      physical_equal(observed, completed.observation),
    )
  }
  let bodies = client_effect_keyed_cached_dependency_bodies(
    parent, lookup, retention,
  ).unwrap()
  assert_true(bodies.length() > 0)
  if installed_rows {
    let identity = lookup.publication_identity.unwrap()
    let static_request = bodies
      .iter()
      .find_first(body => {
        @publication.captured_effect_dependency_body_kind(body) ==
        "request_values" &&
        @publication.captured_effect_dependency_body_cid(body) ==
        identity.static_request_cid
      })
      .unwrap()
    assert_eq(
      @publication.captured_effect_dependency_body_json(static_request),
      identity.static_request,
    )
    if distinct_requests {
      let source = lookup.native_sources.unwrap().sources[0]
      assert_true(source.request_cid != identity.static_request_cid)
      assert_eq(identity.static_request, "{}")
      assert_eq(
        identity.static_request_cid,
        "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
      )
      assert_true(
        bodies.any(body => {
          @publication.captured_effect_dependency_body_kind(body) ==
          "request_values" &&
          @publication.captured_effect_dependency_body_cid(body) ==
          source.request_cid &&
          @publication.captured_effect_dependency_body_json(body) ==
          @encode.document_text(source.request)
        }),
      )
    }
    let transport = lookup.native_transport.unwrap()
    let (bytes, nodes, _) = @publication.publication_contract_wire_usage(
      transport,
    ).unwrap()
    // Independent tree counting checks the original encoder receipt. The
    // collector must forward this SAME original, never one node per wire byte.
    assert_eq(
      nodes,
      source_dependency_json_nodes(
        @json.parse(@publication.publication_contract_json(transport)),
      ),
    )
    assert_true(nodes < bytes)
    let quotes : Array[(Int, Int)] = []
    let collected = client_keyed_lookup_native_dependency_bodies(
      lookup,
      retention,
      {
        max_entries: 4096,
        max_total_bytes: 16777216,
        max_references: 65536,
        max_depth: 100,
      },
      100000,
      100,
      physical_source=lookup.native_sources.unwrap().physical_source,
      before_body=Some((b, n, _) => {
        quotes.push((b, n))
        true
      }),
    ).unwrap()
    assert_true(quotes.contains((bytes, nodes)))
    assert_eq(
      collected.map(@publication.captured_effect_dependency_body_cid),
      bodies.map(@publication.captured_effect_dependency_body_cid),
    )
    let before_refusal = @resources.ledger_usage(ledger)
    assert_true(
      client_keyed_lookup_native_dependency_bodies(
        lookup,
        retention,
        {
          max_entries: 4096,
          max_total_bytes: 16777216,
          max_references: 65536,
          max_depth: 100,
        },
        100000,
        100,
        physical_source=lookup.native_sources.unwrap().physical_source,
        before_body=Some((_, _, _) => false),
      )
      is Err(ConstructionRefused),
    )
    assert_eq(@resources.ledger_usage(ledger), before_refusal)
  }
  let before_cached = @resources.ledger_usage(ledger)
  assert_true(
    physical_equal(
      bodies,
      client_effect_keyed_cached_dependency_bodies(parent, lookup, retention).unwrap(),
    ),
  )
  if !installed_rows {
    assert_true(
      physical_equal(
        read,
        finish_client_effect_keyed_generic_publication_input(
          parent, lookup, "2026-11-15T00:00:02.000Z", 1000000, 100000, 100,
        ).unwrap(),
      ),
    )
  }
  assert_eq(@resources.ledger_usage(ledger), before_cached)
  if !installed_rows {
    assert_true(
      issue_client_keyed_lookup_observation(
        lookup,
        "sha256:" + "9".repeat(64),
        "2026-11-15T00:00:02.000Z",
      )
      is Err(Assembly("foreign_generic_observation_authority")),
    )
  }
  assert_true(
    client_effect_keyed_cached_dependency_bodies(
      parent,
      lookup,
      product_expiry_original_retention(product_test_originals()),
    )
    is None,
  )
  if installed_rows {
    let root = bodies
      .iter()
      .find_first(body => {
        @publication.captured_effect_dependency_body_kind(body) ==
        "lookup_evidence"
      })
      .unwrap()
    let closure = [..bodies, ..retention_dependencies]
    match
      @publication.prepare_captured_effect_dependency_inventory(
        closure,
        [root],
        1000000,
        100,
        _ => true,
      ) {
      Ok(_) => ()
      Err(issue) => fail("lookup closure: " + @debug.to_string(issue))
    }
    if distinct_requests {
      let identity = lookup.publication_identity.unwrap()
      let missing = closure.filter(body => {
        !(@publication.captured_effect_dependency_body_kind(body) ==
        "request_values" &&
        @publication.captured_effect_dependency_body_cid(body) ==
        identity.static_request_cid)
      })
      assert_true(
        @publication.prepare_captured_effect_dependency_inventory(
          missing,
          [root],
          1000000,
          100,
          _ => true,
        )
        is Err(@publication.MissingDependency),
      )
      // Same canonical DATA and CID under another admitted kind cannot
      // discharge the original scope's typed request-values obligation.
      let wrong_kind = @publication.admit_captured_effect_dependency_body(
        "parameter_declarations",
        Some(identity.static_request_cid),
        identity.static_request,
        1000000,
        100000,
        100,
      ).unwrap()
      missing.push(wrong_kind)
      assert_true(
        @publication.prepare_captured_effect_dependency_inventory(
          missing,
          [root],
          1000000,
          100,
          _ => true,
        )
        is Err(@publication.WrongDependencyKind),
      )
    }
    assert_true(
      @publication.prepare_captured_effect_dependency_inventory(
        bodies,
        [root],
        1000000,
        100,
        _ => true,
      )
      is Err(@publication.MissingDependency),
    )
    assert_true(
      @publication.prepare_captured_effect_dependency_inventory(
        closure,
        [root],
        1000000,
        100,
        _ => false,
      )
      is Err(@publication.ReferenceLimit),
    )
  }
  for body in bodies {
    let kind = @publication.captured_effect_dependency_body_kind(body)
    if !installed_rows {
      assert_false(kind.has_prefix("native_file_"))
      assert_false(kind == "acquisition_attempt_receipt")
    }
  }
  stop_client_keyed_lookup_input(lookup)
  assert_true(
    client_effect_keyed_cached_dependency_bodies(parent, lookup, retention)
    is None,
  )
  while !cleanup_client_keyed_lookup_input(lookup, 64).unwrap() {

  }
  assert_true(parent.generic is None)
  assert_false(@execution.supplied_relation_read_available(read))
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_false(client_keyed_left_source_matches(lookup.left, source))
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
fn[T] require_source_fixture(
  value : Result[T, ClientKeyedRequestIssue],
  label : String,
) -> T raise {
  match value {
    Ok(value) => value
    Err(Assembly(reason)) => fail(label + ": " + reason)
    Err(Physical(issue)) => fail(label + ": " + @debug.to_string(issue))
    Err(Identity(issue)) => fail(label + ": " + @debug.to_string(issue))
    Err(Derivation(issue)) => fail(label + ": " + @debug.to_string(issue))
    Err(CompletedIdentity(issue)) => {
      let reason = match issue {
        @execution.Unavailable => "unavailable"
        @execution.NotCellRepresentation => "not cells"
        @execution.InvalidTarget => "invalid target"
        @execution.NotFinished => "not finished"
        @execution.Closed => "closed"
        @execution.ForeignMaterial => "foreign"
        _ => "other"
      }
      fail(label + ": " + reason)
    }
    Err(_) => fail(label + ": other typed refusal")
  }
}
