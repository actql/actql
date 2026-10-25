///|
// Fixed authored wire inputs; independent Node SHA-256 preimages are retained
// in reviews/2026-10-13-c-keyed-capture-independent-inputs.json. Neither this
// helper nor parsing the envelope establishes actual Store/Source authority.
fn original_keyed_child_resource(index : Int) -> String {
  if index == 0 {
    "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"content-fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}"
  } else {
    "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"content-fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}"
  }
}

///|
fn original_keyed_child_content(index : Int) -> String {
  if index == 0 {
    "{\"$actql_ref\":\"content\",\"content_ref_cid\":\"sha256:47d3281cea0ae2c62b082a6617b2ed53145c822037a37d7179a2f447351c96d9\",\"media_type\":\"application/pdf\",\"metadata\":{\"availability_evidence_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:f79c623f18207b93d5e90ec7942ee5eff11e1aa6055df67e496e1d98a60ca8a2\",\"content_store_id\":\"fixture\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"issuer_evidence\":{\"capture_authority_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"content_cid\":\"sha256:f79c623f18207b93d5e90ec7942ee5eff11e1aa6055df67e496e1d98a60ca8a2\",\"content_store_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"evidence_cid\":\"sha256:232594f96193e5251333ddd17a9dc1810a9915a31848dae367fa2b37cbe53a08\",\"issuer_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"issuer_kind\":\"connector_capture\",\"version\":\"actql-content-issuer-evidence/0.1\",\"workspace_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"},\"media_type\":\"application/pdf\",\"retention_class\":\"fixture\",\"size_bytes\":8,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-content-ref/0.1\"}"
  } else {
    "{\"$actql_ref\":\"content\",\"content_ref_cid\":\"sha256:ca5a7a880d1a0ddfebe2a28e7d0cc10ca86872988d273ff396cfdcd6e692e974\",\"media_type\":\"application/pdf\",\"metadata\":{\"availability_evidence_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:4c389a11737b6fb04eb746c0c0356c0ef6193cd1f9dc1e6770fc657be643b48a\",\"content_store_id\":\"fixture\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"issuer_evidence\":{\"capture_authority_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"content_cid\":\"sha256:4c389a11737b6fb04eb746c0c0356c0ef6193cd1f9dc1e6770fc657be643b48a\",\"content_store_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"evidence_cid\":\"sha256:b95ecd238ba2a1b66bdcb0357691205b4f562be3e32a933c2f1e3f6e8605d2f6\",\"issuer_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"issuer_kind\":\"connector_capture\",\"version\":\"actql-content-issuer-evidence/0.1\",\"workspace_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"},\"media_type\":\"application/pdf\",\"retention_class\":\"fixture\",\"size_bytes\":8,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-content-ref/0.1\"}"
  }
}

///|
fn original_keyed_child_expected_row(index : Int) -> String {
  if index == 0 {
    "{\"content\":{\"$actql_ref\":\"content\",\"content_ref_cid\":\"sha256:47d3281cea0ae2c62b082a6617b2ed53145c822037a37d7179a2f447351c96d9\",\"media_type\":\"application/pdf\",\"metadata\":{\"availability_evidence_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:f79c623f18207b93d5e90ec7942ee5eff11e1aa6055df67e496e1d98a60ca8a2\",\"content_store_id\":\"fixture\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"issuer_evidence\":{\"capture_authority_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"content_cid\":\"sha256:f79c623f18207b93d5e90ec7942ee5eff11e1aa6055df67e496e1d98a60ca8a2\",\"content_store_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"evidence_cid\":\"sha256:232594f96193e5251333ddd17a9dc1810a9915a31848dae367fa2b37cbe53a08\",\"issuer_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"issuer_kind\":\"connector_capture\",\"version\":\"actql-content-issuer-evidence/0.1\",\"workspace_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"},\"media_type\":\"application/pdf\",\"retention_class\":\"fixture\",\"size_bytes\":8,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-content-ref/0.1\"},\"resource\":{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"content-fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"},\"version\":\"v1\"}"
  } else {
    "{\"content\":{\"$actql_ref\":\"content\",\"content_ref_cid\":\"sha256:ca5a7a880d1a0ddfebe2a28e7d0cc10ca86872988d273ff396cfdcd6e692e974\",\"media_type\":\"application/pdf\",\"metadata\":{\"availability_evidence_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:4c389a11737b6fb04eb746c0c0356c0ef6193cd1f9dc1e6770fc657be643b48a\",\"content_store_id\":\"fixture\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"issuer_evidence\":{\"capture_authority_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"content_cid\":\"sha256:4c389a11737b6fb04eb746c0c0356c0ef6193cd1f9dc1e6770fc657be643b48a\",\"content_store_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"evidence_cid\":\"sha256:b95ecd238ba2a1b66bdcb0357691205b4f562be3e32a933c2f1e3f6e8605d2f6\",\"issuer_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"issuer_kind\":\"connector_capture\",\"version\":\"actql-content-issuer-evidence/0.1\",\"workspace_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"},\"media_type\":\"application/pdf\",\"retention_class\":\"fixture\",\"size_bytes\":8,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-content-ref/0.1\"},\"resource\":{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"content-fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"},\"version\":\"v2\"}"
  }
}

///|
fn original_keyed_child_limits() -> @row_source_host.RowKeyedLimits {
  {
    page: { max_bytes: 4096, max_nodes: 2000, max_depth: 32, max_rows: 2, },
    retention: {
      max_nodes: 2000,
      max_depth: 32,
      max_text_bytes: 32768,
      max_work: 100000,
    },
    request: {
      max_work: 100000,
      max_pairs: 4,
      values: { max_nodes: 2000, max_depth: 32, max_text_bytes: 32768, },
    },
    wire: {
      max_bytes: 8192,
      max_nodes: 2000,
      max_columns: 10,
      max_order_work: 100000,
      max_depth: 32,
    },
  }
}

///|
test "original keyed children share original custody and retain failed physical cleanup without Source reacquisition" {
  let (declaration, prepared, compiled, definition, plan, keyed, requirement) = original_keyed_run_fixture(
    selector_free=true,
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
    source, "fixture-original-two-keyed-children", original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
  ).unwrap()
  // Existing canonical layout quantities are independently expanded here:
  // assembly(2,4096,100000) = (53376,3236864);
  // one keyed child = (8192,8192+4096+32768+32768+4096) = (8192,81920).
  // Test setup funds these simultaneous logical allowances, not a normal Node
  // physical upper bound or permission to use arbitrary bootstrap slack.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 12288L,
    retained_bytes: @row_source_host.row_acquisition_retained_capacity(
      acquisition,
    ) +
    53376L +
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
  let verifies = Ref(0)
  let direct = start_client_original_keyed_direct_row_acquisition(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    keyed,
    acquisition,
    "original-two-child-listing",
    _ => {
      verifies.val += 1
      true
    },
    4096L,
    4096L,
  ).unwrap()
  // This deterministic fixture admits only four exact authored references and
  // their identities. It is not an actual durable Store/Model admission test.
  let reference_issuer = @admitted.bind_reference_issuer(
    (_, wire) => {
      wire == original_keyed_child_resource(0) ||
      wire == original_keyed_child_resource(1) ||
      wire == original_keyed_child_content(0) ||
      wire == original_keyed_child_content(1)
    },
    wire => {
      // The existing ReferenceIssuer authorizer receives canonical WIRE,
      // not identity CID. Keep exact fixture authorization, never allow-all.
      wire == original_keyed_child_resource(0) ||
      wire == original_keyed_child_resource(1) ||
      wire == original_keyed_child_content(0) ||
      wire == original_keyed_child_content(1)
    },
  )
  @row_source_host.begin_row_run(
    direct,
    4096,
    3,
    3,
    reference_issuer=Some(reference_issuer),
  ).unwrap()
  @row_source_host.begin_row_run_listing_request(direct, None, 0L).unwrap()
  let listing = "{\"items\":[{\"media_type\":\"application/pdf\",\"modified_at\":null,\"name\":\"a.pdf\",\"path\":\"a.pdf\",\"resource\":" +
    original_keyed_child_resource(0) +
    ",\"size_bytes\":8,\"version\":\"v1\"},{\"media_type\":\"application/pdf\",\"modified_at\":null,\"name\":\"b.pdf\",\"path\":\"b.pdf\",\"resource\":" +
    original_keyed_child_resource(1) +
    ",\"size_bytes\":8,\"version\":\"v2\"}],\"request_token\":null,\"next_token\":null}"
  @row_source_host.begin_row_run_listing_page(direct, @utf8.encode(listing), 0L).unwrap()
  let mut done = false
  for _ in 0..<10000 {
    let poll = match
      @row_source_host.advance_row_run_listing_page(direct, 1, 0L) {
      Ok(value) => value
      Err(@row_source_host.Source(@row_source_host.Value(field))) =>
        fail("listing rejected value: " + field)
      Err(@row_source_host.Source(@row_source_host.MissingField(field))) =>
        fail("listing missing field: " + field)
      Err(@row_source_host.Source(@row_source_host.UnexpectedField(field))) =>
        fail("listing unexpected field: " + field)
      Err(@row_source_host.Source(@row_source_host.ListingLimit(limit))) =>
        fail("listing limit: " + limit)
      Err(_) => fail("listing failed before child acquisition")
    }
    match poll {
      @row_source_host.ListingPageContinue(_) => ()
      @row_source_host.ListingPageComplete(rows~, ..) => {
        assert_eq(rows, 2)
        done = true
        break
      }
    }
  }
  assert_true(done)
  @row_source_host.finish_row_run(direct).unwrap()
  @row_source_host.begin_row_capture(direct).unwrap()
  done = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(direct, 1).unwrap().0 {
      done = true
      break
    }
  }
  assert_true(done)
  let capture = @row_source_host.capture_row_run(direct).unwrap()
  let lookup = start_client_original_keyed_lookup(
    scope, compiled, definition, plan, prepared, keyed, capture, 100, 4096, 4096,
    100000,
  ).unwrap()
  let stops = Ref(false)
  let children : Array[@row_source_host.RowRun] = []
  for index in 0..<2 {
    let preparation = @publication_host.start_client_keyed_lookup_request(
      lookup, index,
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
          fail("actual keyed request preparation failed")
      }
    }
    let request = selected.unwrap()
    assert_eq(
      @publication_host.find_client_keyed_lookup_response(lookup, request).unwrap(),
      -1,
    )
    let expected_request = "{\"resource\":" +
      original_keyed_child_resource(index) +
      ",\"version\":\"" +
      (if index == 0 { "v1" } else { "v2" }) +
      "\"}"
    let request_wire = @publication_host.client_keyed_request_wire(
      request, 4096, 2000, 32,
    ).unwrap()
    assert_eq(request_wire, expected_request)
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
      "original-child-" + index.to_string(),
      _ => true,
      4096L,
      4096L,
      _ => stops.val,
    ).unwrap()
    children.push(child)
    assert_eq(@resources.ledger_usage(ledger).attempts, index + 1)
    assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 2)
    let before_repeat = @resources.ledger_usage(ledger)
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
        "forbidden-duplicate-child",
        _ => true,
        4096L,
        4096L,
        _ => stops.val,
      )
      is Err(
        Lookup(@publication_host.Assembly("original_child_custody_changed"))
      ),
    )
    assert_eq(@resources.ledger_usage(ledger), before_repeat)
    @publication_host.observe_client_keyed_request_attempt(
      request,
      request_wire.length().to_int64(),
      0L,
    ).unwrap()
    @row_source_host.begin_keyed_row_run(
      child,
      reference_issuer=Some(reference_issuer),
    ).unwrap()
    let reply = "[" + original_keyed_child_expected_row(index) + "]"
    @publication_host.observe_client_keyed_response(
      request,
      reply.length().to_int64(),
      reply.length().to_int64(),
      0L,
    ).unwrap()
    @row_source_host.begin_row_run_keyed_page(child, @utf8.encode(reply)).unwrap()
    done = false
    for _ in 0..<10000 {
      match @row_source_host.advance_row_run_keyed_page(child, 1).unwrap() {
        @row_source_host.KeyedPageContinue(..) => ()
        @row_source_host.KeyedPageComplete(rows~, ..) => {
          assert_eq(rows, 1)
          done = true
          break
        }
      }
    }
    assert_true(done)
    @row_source_host.finish_row_run(child).unwrap()
    let retained = @row_source_host.retain_keyed_row_run(child).unwrap()
    @publication_host.finish_client_keyed_request_io(request, 0L).unwrap()
    begin_client_original_keyed_lookup_response(
      keyed, lookup, request, retained,
    ).unwrap()
    done = false
    for _ in 0..<10000 {
      if @publication_host.advance_client_keyed_lookup_input(lookup, 1).unwrap() {
        done = true
        break
      }
    }
    assert_true(done)
    assert_true(@row_source_host.keyed_row_capture_read(retained) is Ok(_))
  }
  let read = @publication_host.finish_client_keyed_lookup_input(lookup).unwrap()
  assert_eq(@execution.supplied_relation_read_row_count(read), 2)
  for index in 0..<2 {
    assert_eq(
      @execution.supplied_relation_read_row_wire(
        read,
        index,
        original_keyed_child_limits().wire,
      ).unwrap(),
      original_keyed_child_expected_row(index),
    )
  }
  assert_eq(@resources.ledger_usage(ledger).attempts, 3)
  assert_eq(@resources.ledger_usage(ledger).holdings, 4)
  done = false
  for _ in 0..<10000 {
    if @publication_host.cleanup_client_keyed_lookup_input(lookup, 1).unwrap() {
      done = true
      break
    }
  }
  assert_true(done)
  assert_false(@execution.supplied_relation_read_available(read))
  assert_true(@row_source_host.row_capture_source(capture) is Ok(_))
  let before_failed_close = @resources.ledger_usage(ledger)
  for child in children {
    assert_true(
      @row_source_host.close_accounted_row_run(child)
      is Err(@row_source_host.Evidence(@row_source_host.UnverifiedTransport)),
    )
  }
  // False physical close invalidates access, not the actual retained allocation.
  assert_eq(@resources.ledger_usage(ledger), before_failed_close)
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, false,
    ).unwrap(),
  )
  stops.val = true
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
  assert_eq(final_usage.attempts, 3)
  assert_eq(final_usage.reserved_attempts, 0)
  assert_eq(final_usage.holdings, 0)
  assert_eq(final_usage.held_bytes, 0L)
  assert_eq(final_usage.reserved_retention_bytes, 0L)
  assert_eq(final_usage.reserved_execution_bytes, 0L)
}
