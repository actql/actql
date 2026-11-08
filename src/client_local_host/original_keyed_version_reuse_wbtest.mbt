///|
// Authored version-history rows in an ordinary Relation Source. No FILES
// listing receipt admits contradictory observations for the same Resource.
fn original_keyed_version_row(index : Int, columns : Array[String]) -> String {
  let fields = columns.map(name => {
    let value = match name {
      "name" => "\"" + ["a", "b", "c"][index] + "\""
      "resource" => original_keyed_child_resource(0)
      "version" => if index == 1 { "\"v2\"" } else { "\"v1\"" }
      "media_type" => "\"application/pdf\""
      "modified_at" => "null"
      "path" => "\"same.pdf\""
      "size_bytes" => "8"
      _ => abort("unexpected authored version Source column")
    }
    "\"" + name + "\":" + value
  })
  "{" + fields.join(",") + "}"
}

///|
// Expected right rows are independent of emitted requests/results. Version
// changes, Resource identity does not; the two Content CIDs are authored.
fn original_keyed_version_response(index : Int) -> String {
  "{\"content\":" +
  original_keyed_child_content(index) +
  ",\"resource\":" +
  original_keyed_child_resource(0) +
  ",\"version\":\"" +
  (if index == 0 { "v1" } else { "v2" }) +
  "\"}"
}

///|
fn original_keyed_version_history(
  suffix? : Bool = false,
  content? : Bool = false,
  typed_content? : Bool = false,
  same_ledger_consumer? : Bool = false,
  one_short_census? : Bool = false,
  unknown_left_rows? : Bool = false,
  request_retention_boundary? : Int = 0,
) -> Unit raise {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let same_ledger_consumer = same_ledger_consumer || one_short_census
  let typed_content = typed_content || same_ledger_consumer
  let content = content || typed_content
  let suffix = suffix || content
  let (declaration, prepared, compiled, definition, plan, keyed, requirement) = original_keyed_run_fixture(
    relation_versions=true,
    unknown_left_rows~,
    serialization_max_bytes=if suffix { 4470 } else { 4096 },
    typed_content_input=typed_content,
  )
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 3,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: source_capture_values(),
      output_values: source_capture_values(),
    },
    max_work: 100000,
    max_frames: 100,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let prefix_capacity = client_original_keyed_left_prefix_capacity(
    prepared,
    keyed,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
  ).unwrap()
  let suffix_capacity = if content {
    client_original_keyed_content_suffix_capacity(
      prepared,
      keyed,
      0,
      7,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      execution,
      measurement,
      original_keyed_content_workspace(),
      { cancel: () => true, stopped: () => true, cleanup: () => Ok(true), },
      _ => true,
    ).unwrap()
  } else if suffix {
    client_original_keyed_serialization_suffix_capacity(
      prepared,
      keyed,
      0,
      7,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      execution,
      measurement,
    ).unwrap()
  } else {
    @execution.execution_capacity(0L, 0L).unwrap()
  }
  let workspace = {
    ..content_workspace_fixture(),
    generation_bytes: 4470,
    generation_nodes: 1000,
    generation_depth: 32,
    generation_frames: 100,
  }
  let workspace_capacity = if suffix && !content {
    client_serialization_workspace_capacity(workspace).unwrap()
  } else {
    @execution.execution_capacity(0L, 0L).unwrap()
  }
  let facts = @planning.query_requirement_source_evidence_facts(requirement).unwrap()
  let view = @row_source_host.row_declaration_view(
    declaration,
    facts.source_ref,
  ).unwrap()
  let source = @row_source_host.prepare_declared_row_source(
    requirement, "content-fixture", view,
  ).unwrap()
  let acquisition = @row_source_host.prepare_declared_row_acquisition(
    source, "fixture-original-version-history", original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
  ).unwrap()
  let columns = @row_source_host.row_acquisition_columns(acquisition)
  let page = @utf8.encode(
    "[" +
    [0, 1, 2].map(index => original_keyed_version_row(index, columns)).join(",") +
    "]",
  )
  // Existing assembly layout for three left occurrences, not two unique keys:
  // retained = 4096*8 + 3*64 + 4096 + 3*(4096*2) = 61632;
  // workspace = 100000*32 + 4096*8 + 4096 = 3236864.
  // Child logical allowances remain 8192/81920, not a normal physical profile.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: if suffix {
      6
    } else {
      5
    },
    holdings: if content {
      5
    } else {
      4
    },
    transfer_bytes: page.length().to_int64() + 8192L,
    retained_bytes: @row_source_host.row_acquisition_retained_capacity(
      acquisition,
    ) +
    61632L +
    16384L +
    @execution.execution_capacity_retained_bytes(prefix_capacity) +
    @execution.execution_capacity_retained_bytes(suffix_capacity) +
    @execution.execution_capacity_retained_bytes(workspace_capacity) +
    3L +
    // Nominal API-only read7 + handoff10, not a physical Model profile.
    (if same_ledger_consumer { 17L } else { 0L }),
    execution_bytes: @row_source_host.row_acquisition_execution_capacity(
      acquisition,
    ) +
    4096L +
    3236864L +
    163840L +
    @execution.execution_capacity_execution_bytes(prefix_capacity) +
    @execution.execution_capacity_execution_bytes(suffix_capacity) +
    @execution.execution_capacity_execution_bytes(workspace_capacity) +
    2L +
    (if same_ledger_consumer { 10L } else { 0L }),
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled,
    definition,
    plan,
    ledger,
    bootstrap,
    (if suffix { 6 } else { 5 }) +
    // The same finite census also records byte-only read and handoff tokens.
    // These two actual roles do not change attempts/holding/byte limits.
    (if one_short_census { 1 } else if same_ledger_consumer { 2 } else { 0 }) +
    // One explicit test-only spare-capacity blocker, no new physical attempt.
    (if request_retention_boundary != 0 { 1 } else { 0 }),
    if content {
      5
    } else {
      4
    },
    0,
  ).unwrap()
  let direct = start_client_original_keyed_direct_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    acquisition,
    "original-version-history",
    _ => true,
    page.length().to_int64(),
    4096L,
  ).unwrap()
  let permits = wire => {
    wire == original_keyed_child_resource(0) ||
    wire == original_keyed_child_content(0) ||
    wire == original_keyed_child_content(1)
  }
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => permits(wire),
    permits,
  )
  @row_source_host.begin_row_run(
    direct,
    4096,
    3,
    3,
    reference_issuer=Some(issuer),
  ).unwrap()
  assert_eq(@row_source_host.accept_row_run_page(direct, page).unwrap(), 3)
  @row_source_host.finish_row_run(direct).unwrap()
  @row_source_host.begin_row_capture(direct).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(direct, 1).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(direct).unwrap()
  assert_eq(
    @query.captured_source_row_count(
      @row_source_host.row_capture_source(capture).unwrap(),
    ),
    Some(3),
  )
  let prefix = start_client_original_keyed_prefix_input(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    capture,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
    100,
    4096,
  ).unwrap()
  // It is not legal to substitute the earlier Step1 capture for Step4.
  assert_true(
    start_client_original_keyed_prefix_lookup_input(
      prefix, scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096,
      4096, 100000,
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  complete = false
  for _ in 0..<10000 {
    match advance_client_original_keyed_prefix_input(prefix, 1).unwrap() {
      @local.Complete(_, ..) => {
        complete = true
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original version-history prefix did not complete")
    }
  }
  assert_true(complete)
  assert_true(
    @query.captured_source_matches_segment_input(
      prefix.source.unwrap(),
      prefix.input.unwrap(),
    ),
  )
  assert_true(
    @execution.completed_output_matches_segment_input(
      prefix.output.unwrap(),
      prefix.input.unwrap(),
    ),
  )
  // Same original rows/owner/port, but a freshly rebound read did NOT feed
  // this execution. Equal data cannot replace its exact producer identity.
  let owner = @publication_host.client_keyed_acquisition_owner(keyed)
  let rebound = @execution.prepare_producer_read(
    owner,
    @query.bind_captured_source_operation(prefix.source.unwrap(), owner, 2, 0).unwrap(),
    100,
    4096,
  ).unwrap()
  assert_true(
    @query.captured_source_matches_segment_input(
      prefix.source.unwrap(),
      rebound,
    ),
  )
  assert_false(
    @execution.completed_output_matches_segment_input(
      prefix.output.unwrap(),
      rebound,
    ),
  )
  let prefixed_lookup = match
    start_client_original_keyed_prefix_lookup_input(
      prefix, scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096,
      4096, 100000,
    ) {
    Ok(value) => value
    Err(issue) => {
      let cause = match issue {
        Original(@publication_host.ForeignRun) => "foreign_original"
        Original(@publication_host.Resource(_)) => "original_custody"
        Original(@publication_host.InvalidBootstrap) => "bootstrap"
        Capture(_) => "source_capture"
        Lookup(@publication_host.Capture(_)) => "left_capture_binding"
        Lookup(@publication_host.Read(_)) => "producer_read"
        Lookup(@publication_host.Assembly(reason)) => "assembly:" + reason
        Lookup(_) => "keyed_left"
      }
      // Keep the success expectation. On a rejected left port, retire the
      // actual original capture/census; do not reacquire or fake a completion.
      assert_true(cleanup_client_original_keyed_prefix_input(prefix).unwrap())
      @row_source_host.close_accounted_row_run(direct).unwrap()
      assert_true(
        @publication_host.finish_client_model_read_scope(
          scope, compiled, definition, plan, true,
        ).unwrap(),
      )
      assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
      fail("original keyed version prefix unavailable: " + cause)
    }
  }
  let lookup = @publication_host.client_original_keyed_prefix_lookup_input(
    prefixed_lookup,
  ).unwrap()
  let borrowed = @resources.ledger_usage(ledger)
  assert_false(cleanup_client_original_keyed_prefix_input(prefix).unwrap())
  assert_eq(@resources.ledger_usage(ledger), borrowed)
  let stopped = Ref(false)
  let children : Array[@row_source_host.RowRun] = []
  let requested : Array[String] = []
  let mut first_request_retained = 0L
  let mut retained_refusal = false
  for row in 0..<3 {
    let preparation = @publication_host.start_client_keyed_lookup_request(
      lookup, row,
    ).unwrap()
    let mut selected = None
    for _ in 0..<10000 {
      match
        @publication_host.advance_client_keyed_lookup_request(
          lookup, preparation,
        ) {
        @publication_host.ClientKeyedRequestContinue(..) => ()
        @publication_host.ClientKeyedRequestComplete(value, ..) => {
          selected = Some(value)
          break
        }
        @publication_host.ClientKeyedRequestFailed(_, ..) =>
          fail("original version-history request preparation failed")
      }
    }
    let request = selected.unwrap()
    let index = @publication_host.find_client_keyed_lookup_response(
      lookup, request,
    ).unwrap()
    assert_eq(index, if row == 2 { 0 } else { -1 })
    let wire = @publication_host.client_keyed_request_wire(
      request, 4096, 2000, 32,
    ).unwrap()
    assert_eq(
      wire,
      "{\"resource\":" +
      original_keyed_child_resource(0) +
      ",\"version\":\"" +
      (if row == 1 { "v2" } else { "v1" }) +
      "\"}",
    )
    if index >= 0 {
      let before = @resources.ledger_usage(ledger)
      assert_true(
        start_client_original_keyed_prefix_row_acquisition(
          scope,
          compiled,
          definition,
          plan,
          prepared,
          keyed,
          prefixed_lookup,
          request,
          declaration,
          original_keyed_child_limits(),
          "no-third-child",
          _ => true,
          4096L,
          4096L,
          _ => stopped.val,
        )
        is Err(
          Lookup(@publication_host.Assembly("original_child_custody_changed"))
        ),
      )
      assert_eq(@resources.ledger_usage(ledger), before)
      @publication_host.reuse_client_keyed_lookup_response(
        lookup, request, index,
      ).unwrap()
      assert_eq(@resources.ledger_usage(ledger), before)
      continue
    }
    requested.push(wire)
    let child = start_client_original_keyed_prefix_row_acquisition(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      keyed,
      prefixed_lookup,
      request,
      declaration,
      original_keyed_child_limits(),
      "original-version-" + row.to_string(),
      _ => true,
      4096L,
      4096L,
      _ => stopped.val,
    ).unwrap()
    children.push(child)
    @publication_host.observe_client_keyed_request_attempt(
      request,
      wire.length().to_int64(),
      0L,
    ).unwrap()
    @row_source_host.begin_keyed_row_run(child, reference_issuer=Some(issuer)).unwrap()
    let reply = "[" + original_keyed_version_response(row) + "]"
    @publication_host.observe_client_keyed_response(
      request,
      reply.length().to_int64(),
      reply.length().to_int64(),
      0L,
    ).unwrap()
    @row_source_host.begin_row_run_keyed_page(child, @utf8.encode(reply)).unwrap()
    complete = false
    for _ in 0..<10000 {
      match @row_source_host.advance_row_run_keyed_page(child, 1).unwrap() {
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
    let retained = @row_source_host.retain_keyed_row_run(child).unwrap()
    @publication_host.finish_client_keyed_request_io(request, 0L).unwrap()
    let before_transfer = @resources.ledger_usage(ledger)
    let boundary = if row == 1 && request_retention_boundary != 0 {
      let available = @resources.ledger_limits(ledger).retained_bytes -
        before_transfer.held_bytes -
        before_transfer.reserved_retention_bytes
      assert_true(available >= first_request_retained)
      // SAME admitted Ledger; occupy only unrelated spare retention. The
      // second equal-shaped distinct key must fund its whole Request again.
      Some(
        @resources.reserve_capacity(
          ledger,
          available -
          first_request_retained +
          (if request_retention_boundary == 2 { 1L } else { 0L }),
          0L,
        ).unwrap(),
      )
    } else {
      None
    }
    let transfer = begin_client_original_keyed_lookup_response(
      keyed, lookup, request, retained,
    )
    if request_retention_boundary == 2 && row == 1 {
      assert_true(
        transfer
        is Err(Lookup(@publication_host.Physical(@resources.RetentionLimit))),
      )
      assert_true(
        @publication_host.client_keyed_lookup_input_identity(lookup) is None,
      )
      retained_refusal = true
    } else {
      transfer.unwrap()
      let after_transfer = @resources.ledger_usage(ledger)
      let actual_retained = after_transfer.reserved_retention_bytes -
        before_transfer.reserved_retention_bytes
      // Discount the explicit test-only blocker from this observation.
      let actual_retained = if boundary is Some(_) {
        actual_retained -
        (
          @resources.ledger_limits(ledger).retained_bytes -
          before_transfer.held_bytes -
          before_transfer.reserved_retention_bytes -
          first_request_retained
        )
      } else {
        actual_retained
      }
      if row == 0 && request_retention_boundary != 0 {
        // Actual schema has three required cells. The response/cache carrier
        // is6H33R4W; this Request adds8H29R5W (two field pairs/two checked
        // wrappers/fields Array/original record). Existing payloads are borrowed.
        let expected = @execution.preparation_representation_cost({
          record_headers: 14L,
          reference_slots: 62L,
          scalar_words: 9L,
          owned_utf16_units: wire.length().to_int64(),
          owned_wire_bytes: 0L,
        }).unwrap()
        assert_eq(actual_retained, expected)
        first_request_retained = expected
      } else if row == 1 && request_retention_boundary == 1 {
        assert_eq(actual_retained, first_request_retained)
      }
    }
    if boundary is Some(boundary) {
      @resources.settle_capacity(ledger, boundary).unwrap()
    }
    if retained_refusal {
      break
    }
    complete = false
    for _ in 0..<10000 {
      if @publication_host.advance_client_keyed_lookup_input(lookup, 1).unwrap() {
        complete = true
        break
      }
    }
    assert_true(complete)
  }
  assert_eq(requested.length(), 2)
  assert_true(requested[0] != requested[1])
  if !retained_refusal {
    let read = @publication_host.finish_client_keyed_lookup_input(lookup).unwrap()
    assert_eq(@execution.supplied_relation_read_row_count(read), 2)
    for index in 0..<2 {
      assert_eq(
        @execution.supplied_relation_read_row_wire(
          read,
          index,
          original_keyed_child_limits().wire,
        ).unwrap(),
        original_keyed_version_response(index),
      )
    }
    assert_eq(
      @query.captured_source_row_count(
        @row_source_host.row_capture_source(capture).unwrap(),
      ),
      Some(3),
    )
    if content {
      original_keyed_version_content(
        scope,
        compiled,
        definition,
        plan,
        prepared,
        keyed,
        prefixed_lookup,
        prefix,
        acquisition,
        capture,
        requirement,
        execution,
        measurement,
        ledger,
        typed_content~,
        same_ledger_consumer~,
        one_short_census~,
      )
    } else if suffix {
      original_keyed_version_serialize(
        scope, compiled, definition, plan, prepared, keyed, prefixed_lookup, prefix,
        execution, measurement, workspace_capacity, ledger,
      )
    }
  } else {
    // No completion, retry or third request is fabricated after refusal.
    assert_true(
      @publication_host.finish_client_keyed_lookup_input(lookup) is Err(_),
    )
  }
  // One Direct page and two distinct keyed provider responses are consumed.
  // Prefix, assembly and serialization reservations are live capacity only.
  assert_eq(@resources.ledger_usage(ledger).attempts, 3)
  // The Content helper has released its separate byte allocation already.
  // Direct capture, two keyed children and the lookup still retain four slots.
  assert_eq(
    @resources.ledger_usage(ledger).holdings,
    if retained_refusal {
      3
    } else {
      4
    },
  )
  complete = false
  for _ in 0..<10000 {
    if @publication_host.cleanup_client_original_keyed_prefix_lookup(
        prefixed_lookup, 1,
      ).unwrap() {
      complete = true
      break
    }
  }
  assert_true(complete)
  assert_true(
    @publication_host.client_original_keyed_prefix_lookup_input(prefixed_lookup)
    is None,
  )
  let pending = @resources.ledger_usage(ledger)
  // Assembly cleanup does not stand in for either physical child's ACK.
  assert_false(cleanup_client_original_keyed_prefix_input(prefix).unwrap())
  assert_eq(@resources.ledger_usage(ledger), pending)
  for child in children {
    assert_true(
      @row_source_host.close_accounted_row_run(child)
      is Err(@row_source_host.Evidence(@row_source_host.UnverifiedTransport)),
    )
  }
  assert_eq(@resources.ledger_usage(ledger), pending)
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, false,
    ).unwrap(),
  )
  stopped.val = true
  for child in children {
    @row_source_host.close_accounted_row_run(child).unwrap()
  }
  assert_true(cleanup_client_original_keyed_prefix_input(prefix).unwrap())
  assert_true(
    prefix.output is None &&
    prefix.source is None &&
    prefix.input is None &&
    prefix.lookup is None &&
    prefix.scope is None &&
    prefix.keyed is None &&
    prefix.prefix is None,
  )
  assert_true(
    start_client_original_keyed_prefix_lookup_input(
      prefix, scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096,
      4096, 100000,
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  @row_source_host.close_accounted_row_run(direct).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  let final_usage = @resources.ledger_usage(ledger)
  assert_eq(final_usage.attempts, 3)
  assert_eq(final_usage.reserved_attempts, 0)
  assert_eq(final_usage.holdings, 0)
  assert_eq(final_usage.held_bytes, 0L)
  assert_eq(final_usage.reserved_retention_bytes, 0L)
  assert_eq(final_usage.reserved_execution_bytes, 0L)
}

///|
test "original keyed version history keeps three left occurrences but acquires only two exact Resource version children" {
  original_keyed_version_history()
}

///|
test "original keyed exact versions feed the checked JOIN and whole SERIALIZE suffix without replaying acquisition or left prefix" {
  original_keyed_version_history(suffix=true)
}

///|
test "original keyed versions complete one Content generation through the same managed family and Ledger" {
  original_keyed_version_history(content=true)
}

///|
test "original keyed Content generation feeds the actual document reference into typed INFER input preparation" {
  original_keyed_version_history(typed_content=true)
}

///|
test "original keyed Content input enters once and hands off through the same original Ledger" {
  original_keyed_version_history(same_ledger_consumer=true)
}

///|
test "original keyed Content input keeps the original ticket when the handoff census is one slot short" {
  original_keyed_version_history(one_short_census=true)
}

///|
test "unknown Source rows retain their original keyed JOIN multiplicity and cleanup without a take bound" {
  original_keyed_version_history(unknown_left_rows=true)
}

///|
test "unknown Source rows feed Content through the same keyed Run without a take bound" {
  original_keyed_version_history(content=true, unknown_left_rows=true)
}

///|
test "distinct keyed Requests retain full carriers at exact capacity and refuse one short while physical children remain pending" {
  original_keyed_version_history(request_retention_boundary=1)
  original_keyed_version_history(request_retention_boundary=2)
}
