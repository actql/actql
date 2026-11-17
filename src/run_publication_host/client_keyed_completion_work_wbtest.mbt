///|
// A canonical candidate and explicit codec-fixture issuer, not a Store ACK.
fn keyed_completion_content() -> String {
  let binding : @publication.GeneratedContentBinding = {
    content_store_id: "fixture",
    content_store_cid: "sha256:" + "1".repeat(64),
    workspace_scope_cid: "sha256:" + "2".repeat(64),
    storage_scope: "workspace",
    retention_class: "fixture",
    expires_at: None,
    availability_evidence_cid: "sha256:" + "3".repeat(64),
    effective_data_policy_cid: "sha256:" + "4".repeat(64),
    data_classification: "internal",
    issuer_contract_cid: "sha256:" + "5".repeat(64),
    capture_authority_cid: "sha256:" + "6".repeat(64),
  }
  let candidate = @publication.prepare_captured_content_reference(
    binding,
    "application/pdf",
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    0,
    { max_bytes: 4096, max_nodes: 256, max_depth: 32, max_text_units: 4096, },
  ).unwrap()
  @publication.captured_content_reference_wire(candidate)
}

///|
test "generic captured 101 Ref lookup completes dependency closure within the original work bound" {
  let resources = Array::makei(101, index => {
    let cid = "sha256:" +
      @sha.text_hex("component-file:" + index.to_string()).unwrap()
    keyed_work_resource().replace(old="sha256:" + "d".repeat(64), new=cid)
  })
  let listing = "[" +
    Array::makei(101, row => {
      "{\"path\":\"file-" +
      row.to_string() +
      ".txt\",\"resource\":" +
      resources[row] +
      ",\"version\":\"v" +
      row.to_string() +
      "\"}"
    }).join(",") +
    "]"
  let (lookup, cleanup, declaration) = keyed_work_original_fixture(
    listing,
    101,
    1000000,
    completion=true,
    resources=Some(resources),
  )
  let children : Array[@row_host.RowRun] = []
  defer {
    for child in children {
      @row_host.close_accounted_row_run(child) |> ignore
    }
    cleanup() |> ignore
  }
  let content = keyed_completion_content()
  let issuer = @values.bind_reference_issuer(
    (_, wire) => resources.contains(wire) || wire == content,
    _ => true,
  )
  let keyed = lookup.left.acquisition
  guard lookup.left.composed is Some(original) &&
    original.origin is SourceEffectOrigin(parent) else {
    fail("original parent")
  }
  let child_limits : @row_host.RowKeyedLimits = {
    page: { max_bytes: 4096, max_nodes: 1000, max_depth: 32, max_rows: 1, },
    retention: {
      max_work: 100000,
      max_nodes: 2000,
      max_text_bytes: 32768,
      max_depth: 32,
    },
    request: {
      max_work: 100000,
      max_pairs: 10,
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
  for row in 0..<101 {
    let request = keyed_work_request(lookup, row)
    assert_eq(find_client_keyed_lookup_response(lookup, request).unwrap(), -1)
    let selected = @row_host.prepare_keyed_row_acquisition(
      client_keyed_acquisition_owner(keyed),
      client_keyed_acquisition_facts(keyed),
      request.request,
      declaration,
      child_limits,
    ).unwrap()
    let child = match
      @row_host.start_accounted_keyed_row_acquisition(
        selected,
        "component-keyed-response",
        _ => true,
        lookup.ledger,
        8192L,
        4096L,
        _ => true,
      ) {
      Ok(value) => value
      Err(@row_host.Physical(issue)) =>
        fail("keyed child row=\{row} physical=\{@debug.to_string(issue)}")
      Err(_) => fail("keyed child row=\{row} nonphysical refusal")
    }
    children.push(child)
    let response = @utf8.encode(
      "[{\"content\":" +
      content +
      ",\"media_type\":\"application/pdf\",\"path\":\"file-" +
      row.to_string() +
      ".txt\",\"resource\":" +
      resources[row] +
      ",\"version\":\"v" +
      row.to_string() +
      "\"}]",
    )
    observe_client_keyed_request_attempt(request, 0L, 0L).unwrap()
    @row_host.begin_keyed_row_run(child, reference_issuer=Some(issuer)).unwrap()
    match
      observe_client_keyed_response(
        request,
        response.length().to_int64(),
        response.length().to_int64(),
        0L,
      ) {
      Ok(_) => ()
      Err(LookupLimit(reason)) =>
        fail(
          "response row=\{row} limit=\{reason} work=\{client_keyed_lookup_input_work(lookup)}",
        )
      Err(_) => fail("response row=\{row} other refusal")
    }
    @row_host.begin_row_run_keyed_page(child, response).unwrap()
    while @row_host.advance_row_run_keyed_page(child, 31).unwrap()
          is @row_host.KeyedPageContinue(..) {

    }
    @row_host.finish_row_run(child).unwrap()
    let capture = @row_host.retain_keyed_row_run(child).unwrap()
    finish_client_keyed_request_io(request, 0L).unwrap()
    begin_client_keyed_lookup_response(
      lookup,
      request,
      @row_host.keyed_row_capture_read(capture).unwrap(),
      capture=Some(capture),
    ).unwrap()
    while !advance_client_keyed_lookup_input(lookup, 31).unwrap() {

    }
  }
  let before = client_keyed_lookup_input_work(lookup)
  let result = finish_client_effect_keyed_generic_publication_input(
    parent, lookup, "2026-11-15T00:00:02.000Z", 1000000, 100000, 100,
  )
  let stage = match result {
    Ok(_) => "complete"
    Err(LookupLimit(reason)) => "lookup_limit:" + reason
    Err(Assembly(reason)) => "assembly:" + reason
    Err(_) => "other_refusal"
  }
  let input_work = lookup.work.to_int64() +
    lookup.input
    .map(value => @execution.admitted_input_work(value).to_int64())
    .unwrap_or(0L)
  println(
    "KEYED_COMPLETION work_before=\{before} work_after=\{client_keyed_lookup_input_work(lookup)} input_work=\{input_work} identity_work=\{lookup.identity_work} input_bound=1000000 stage=\{stage}",
  )
  result.unwrap() |> ignore
  assert_true(input_work <= 1000000L)
  assert_true(lookup.identity_work <= 1000000L)
  for child in children {
    @row_host.close_accounted_row_run(child).unwrap()
  }
  children.clear()
  assert_true(cleanup())
  let usage = @resources.ledger_usage(lookup.ledger)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}
