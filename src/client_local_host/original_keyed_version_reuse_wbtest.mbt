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
test "original keyed version history keeps three left occurrences but acquires only two exact Resource version children" {
  let (declaration, prepared, compiled, definition, plan, keyed, requirement) = original_keyed_run_fixture(
    relation_versions=true,
  )
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
    attempts: 4,
    holdings: 4,
    transfer_bytes: page.length().to_int64() + 8192L,
    retained_bytes: @row_source_host.row_acquisition_retained_capacity(
      acquisition,
    ) +
    61632L +
    16384L +
    3L,
    execution_bytes: @row_source_host.row_acquisition_execution_capacity(
      acquisition,
    ) +
    4096L +
    3236864L +
    163840L +
    2L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 4, 4, 0,
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
  let lookup = start_client_original_keyed_lookup(
    scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096, 4096,
    100000,
  ).unwrap()
  let stopped = Ref(false)
  let children : Array[@row_source_host.RowRun] = []
  let requested : Array[String] = []
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
        start_client_original_keyed_row_acquisition(
          scope,
          compiled,
          definition,
          plan,
          prepared,
          keyed,
          lookup,
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
    let child = start_client_original_keyed_row_acquisition(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      keyed,
      lookup,
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
    begin_client_original_keyed_lookup_response(
      keyed, lookup, request, retained,
    ).unwrap()
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
  assert_eq(@resources.ledger_usage(ledger).attempts, 4)
  assert_eq(@resources.ledger_usage(ledger).holdings, 4)
  complete = false
  for _ in 0..<10000 {
    if @publication_host.cleanup_client_keyed_lookup_input(lookup, 1).unwrap() {
      complete = true
      break
    }
  }
  assert_true(complete)
  let pending = @resources.ledger_usage(ledger)
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
  @row_source_host.close_accounted_row_run(direct).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  let final_usage = @resources.ledger_usage(ledger)
  assert_eq(final_usage.attempts, 4)
  assert_eq(final_usage.holdings, 4)
  assert_eq(final_usage.held_bytes, 0L)
  assert_eq(final_usage.reserved_retention_bytes, 0L)
  assert_eq(final_usage.reserved_execution_bytes, 0L)
}
