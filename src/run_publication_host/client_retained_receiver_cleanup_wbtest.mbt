///|
fn receiver_cleanup_plan(
  f : RetainedCleanupFixture,
) -> (@remote.RemoteRetainedInputIntent, @remote.RemoteRetainedInputResult) {
  let producer = prepare_client_retained_input_producer(
    f.edge,
    f.producer,
    f.producer_evidence,
    f.producer_subject,
  ).unwrap()
  let fields = @transfer.request_projection(f.transfer)
  let intent = prepare_client_retained_input_intent(producer, {
    destination_grant_cid: fields[11],
    route_capability_cid: fields[12],
    source_grant_cid: fields[10],
    transfer_attempt: @transfer.request_journal_key(f.transfer)[3],
    transfer_expires_unix_ms: 4102444800000L,
    transfer_max_bytes: 8L,
  }).unwrap()
  let plan = @remote.prepare_remote_retained_input_plan(
    intent,
    f.producer_subject,
    f.producer_evidence,
    f.transfer,
  ).unwrap()
  let result = @remote.prepare_remote_retained_input_result(
    plan,
    f.transfer_record,
    f.receipt,
  ).unwrap()
  (intent, result)
}

///|
fn receiver_cleanup_cancelled(
  request : @remote.DispatchRequest,
  generation? : Int = 1,
) -> @remote.DispatchRecord {
  let scope = @remote.dispatch_request_execution_scope(request)
  let site = @site.create_site(
    scope[0],
    generation,
    scope[2],
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let journal = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let record = @remote.commit_dispatch_acceptance(
      @remote.prepare_dispatch_acceptance(journal, request).unwrap(),
      true,
    ).unwrap().1
  @remote.commit_dispatch_transition(
    @remote.prepare_confirm_execution_cancelled(record).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_remote_release(record).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_confirm_remote_release(record).unwrap(),
    true,
  ).unwrap()
  record
}

///|
fn receiver_cleanup_admit(
  f : RetainedCleanupFixture,
  intent : @remote.RemoteRetainedInputIntent,
  result : @remote.RemoteRetainedInputResult,
  original : @remote.DispatchRequest,
  cancelled : @remote.DispatchRecord,
  max_binding_bytes? : Int = 100000,
  max_chunks? : Int = 4,
  max_referenced_bytes? : Int64 = 8L,
) -> Result[ClientRetainedInputCleanup, ClientRetainedTaskInputIssue] {
  prepare_client_retained_receiver_cleanup_from_plan(
    f.edge,
    f.producer,
    f.producer_evidence,
    f.producer_subject,
    f.measurement,
    intent,
    result,
    original,
    cancelled,
    max_binding_bytes,
    max_chunks,
    4096,
    max_referenced_bytes,
  )
}

///|
test "recorded graph receiver cleanup admits original materials and preserves the exact cancelled receiver" {
  let f = retained_cleanup_fixture()
  let materials = f.materials
  let identity = prepared_client_identity(materials.prepared)
  let recorded = @publication.prepare_recorded_run_publication(
    materials.admission,
    materials.run_definition,
    @publication.prepare_result_definition(
      identity.program_definition_cid,
      "answer",
    ).unwrap(),
  ).unwrap()
  let environment = admit_client_check_environment(
    multi_source_environment,
    prepared_client_check_environment_cid(materials.prepared),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let wire = issue_client_run_materials_input(
    materials.prepared,
    materials.admission,
    materials.run_definition,
    environment,
    multi_source_environment,
    retained_input_program,
    None,
  ).unwrap()
  let source = @planning.query_source_evidence_fact_values(
    prepared_client_source_evidence_facts(materials.prepared, 0, 0).unwrap(),
  )
  let graph = admit_recorded_client_source_cleanup_graph(
    wire,
    @publication.recorded_run_publication_run_cid(recorded),
    recorded,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_limits(),
    source[0],
    source[1],
  ).unwrap()
  let (intent, result) = receiver_cleanup_plan(f)
  let original = @remote.dispatch_record_request(f.consumer)
  let cancelled = receiver_cleanup_cancelled(original)
  let cleanup = prepare_recorded_client_retained_receiver_cleanup_from_plan(
    graph,
    f.producer,
    f.producer_evidence,
    f.producer_subject,
    f.measurement,
    intent,
    result,
    original,
    cancelled,
    100000,
    4,
    4096,
    8L,
  ).unwrap()
  assert_eq(
    @transfer.request_cid(client_retained_input_cleanup_transfer(cleanup)),
    @transfer.request_cid(f.transfer),
  )
  assert_eq(
    client_retained_input_cleanup_reader_id(cleanup),
    @remote.dispatch_request_identity(original),
  )
}

///|
test "receiver cleanup before consumer delivery preserves the original address after producer release" {
  let f = retained_cleanup_fixture()
  let (intent, result) = receiver_cleanup_plan(f)
  let original = @remote.dispatch_record_request(f.consumer)
  let cancelled = receiver_cleanup_cancelled(original)
  // No consumer completion evidence or accepted input envelope is needed.
  // This is cleanup-address admission, not physical stop or public acceptance.
  for released in [false, true] {
    if released {
      @remote.commit_dispatch_transition(
        @remote.prepare_begin_remote_release(f.producer).unwrap(),
        true,
      ).unwrap()
      @remote.commit_dispatch_transition(
        @remote.prepare_confirm_remote_release(f.producer).unwrap(),
        true,
      ).unwrap()
    }
    let revision = @remote.dispatch_record_revision(f.producer)
    let cleanup = receiver_cleanup_admit(f, intent, result, original, cancelled).unwrap()
    assert_eq(
      @transfer.request_cid(client_retained_input_cleanup_transfer(cleanup)),
      @transfer.request_cid(f.transfer),
    )
    assert_eq(
      client_retained_input_cleanup_receipt_cid(cleanup),
      @transfer.destination_receipt_cid(f.receipt),
    )
    assert_eq(
      client_retained_input_cleanup_reader_id(cleanup),
      @remote.dispatch_request_identity(original),
    )
    ignore(
      receiver_cleanup_admit(f, intent, result, original, cancelled).unwrap(),
    )
    assert_eq(@remote.dispatch_record_revision(f.producer), revision)
  }
}

///|
test "receiver cleanup refuses a replaced consumer attempt and an unconfirmed consumer" {
  let f = retained_cleanup_fixture()
  let (intent, result) = receiver_cleanup_plan(f)
  let original = @remote.dispatch_record_request(f.consumer)
  let accepted = retained_cleanup_accepted(original)
  assert_true(
    receiver_cleanup_admit(f, intent, result, original, accepted)
    is Err(InvalidBinding),
  )
  let cancelled = receiver_cleanup_cancelled(original)
  let foreign = @remote.dispatch_record_request(f.producer)
  assert_true(
    receiver_cleanup_admit(f, intent, result, foreign, cancelled)
    is Err(InvalidBinding),
  )
  let ports = client_retained_input_edge_projection(f.edge)
  let replacement = retained_input_completed(
      ports[0],
      ports[5],
      2,
      1,
      client_retained_input_edge_schema_cid(f.edge),
    ).0
  let replacement_request = @remote.dispatch_record_request(replacement)
  assert_true(
    receiver_cleanup_admit(
      f,
      intent,
      result,
      original,
      receiver_cleanup_cancelled(replacement_request),
    )
    is Err(InvalidBinding),
  )
}

///|
test "receiver cleanup rejects a different Run or Site generation even with a matching cancelled record" {
  let f = retained_cleanup_fixture()
  let (intent, result) = receiver_cleanup_plan(f)
  let ports = client_retained_input_edge_projection(f.edge)
  for (run, generation) in [(retained_input_cid("f"), 1), (ports[0], 2)] {
    let record = retained_input_completed(
        run,
        ports[5],
        1,
        generation,
        client_retained_input_edge_schema_cid(f.edge),
      ).0
    let request = @remote.dispatch_record_request(record)
    assert_true(
      receiver_cleanup_admit(
        f,
        intent,
        result,
        request,
        receiver_cleanup_cancelled(request, generation~),
      )
      is Err(InvalidBinding),
    )
  }
}

///|
test "receiver cleanup refuses an intent for a different checked input port" {
  let f = retained_cleanup_fixture()
  let (intent, result) = receiver_cleanup_plan(f)
  let altered = @remote.prepare_remote_retained_input_intent(
    @remote.dispatch_record_request(f.producer),
    {
      ..@remote.remote_retained_input_intent_projection(intent),
      consumer_input_port: "other-input",
    },
  ).unwrap()
  let original = @remote.dispatch_record_request(f.consumer)
  assert_true(
    receiver_cleanup_admit(
      f,
      altered,
      result,
      original,
      receiver_cleanup_cancelled(original),
    )
    is Err(InvalidBinding),
  )
}

///|
test "receiver cleanup preserves bounds and refuses a foreign producer plan" {
  let f = retained_cleanup_fixture()
  let (intent, result) = receiver_cleanup_plan(f)
  let original = @remote.dispatch_record_request(f.consumer)
  let cancelled = receiver_cleanup_cancelled(original)
  assert_true(
    receiver_cleanup_admit(
      f,
      intent,
      result,
      original,
      cancelled,
      max_binding_bytes=0,
    )
    is Err(InvalidBinding),
  )
  assert_true(
    receiver_cleanup_admit(f, intent, result, original, cancelled, max_chunks=0)
    is Err(InvalidBinding),
  )
  assert_true(
    receiver_cleanup_admit(
      f,
      intent,
      result,
      original,
      cancelled,
      max_referenced_bytes=7L,
    )
    is Err(InvalidBinding),
  )
  let altered = retained_input_completed(
    client_retained_input_edge_projection(f.edge)[0],
    client_retained_input_edge_projection(f.edge)[1],
    2,
    1,
    client_retained_input_edge_schema_cid(f.edge),
  )
  assert_true(
    receiver_cleanup_admit(
      {
        ..f,
        producer: altered.0,
        producer_evidence: altered.1,
        producer_subject: altered.2,
      },
      intent,
      result,
      original,
      cancelled,
    )
    is Err(_),
  )
}
