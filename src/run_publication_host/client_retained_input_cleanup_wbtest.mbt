///|
struct RetainedCleanupFixture {
  edge : ClientRetainedInputEdge
  binding : @remote.RemoteInputBinding
  producer : @remote.DispatchRecord
  producer_evidence : @remote.RemoteExecutionEvidence
  producer_subject : @remote.RemoteManagedOutputSubject
  consumer : @remote.DispatchRecord
  consumer_evidence : @remote.RemoteExecutionEvidence
  consumer_subject : @remote.RemoteManagedOutputSubject
  measurement : @remote.RemoteManagedOutputMeasurement
  transfer : @transfer.RemoteTransferRequest
  receipt : @transfer.RemoteTransferDestinationReceipt
}

///|
fn retained_cleanup_fixture(
  route? : @transfer.RemoteTransferRoute = @transfer.DirectStream,
  destination_use_id? : String = "direct-destination",
) -> RetainedCleanupFixture raise {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "cleanup-run",
  )
  let edge = prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, 1, 0,
  ).unwrap()
  let ports = client_retained_input_edge_projection(edge)
  let measurement = @remote.prepare_remote_managed_output_measurement(
    1,
    0,
    0,
    0,
    [1],
    [1],
    [1],
    [1],
    [0],
    [10],
  ).unwrap()
  let manifest = @cleanup_manifest.admit(
    "actql-managed-physical-manifest/0.1",
    client_retained_input_edge_schema_cid(edge),
    retained_input_cid("7"),
    retained_input_cid("8"),
    1,
    [retained_input_cid("9")],
    [8L],
    [1],
    4,
    4096,
    8L,
  ).unwrap()
  let (record, evidence, subject) = retained_input_completed(
    ports[0],
    ports[1],
    1,
    1,
    client_retained_input_edge_schema_cid(edge),
    measurement_cid=@remote.remote_managed_output_measurement_cid(measurement),
    manifest_cid=@cleanup_manifest.manifest_cid(manifest),
  )
  let producer = prepare_client_retained_input_producer(
    edge, record, evidence, subject,
  ).unwrap()
  let facts = @remote.remote_managed_output_subject_projection(subject)
  let request = @transfer.prepare_request(
    "authority-a",
    "cleanup-transfer",
    route,
    "site-a",
    1,
    "site-a",
    1,
    facts[1],
    manifest,
    8L,
    4102444800000L,
    retained_input_cid("a"),
    retained_input_cid("b"),
    retained_input_cid("c"),
  ).unwrap()
  let transfer_record = @transfer.open_record(request)
  @transfer.commit_transition(
    @transfer.prepare_start(transfer_record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_source_settled(
      transfer_record,
      true,
      route == @transfer.TransferStore,
    ).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_destination_commit(transfer_record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  let receipt = @transfer.prepare_destination_receipt(
    request, "receiver-original",
  ).unwrap()
  let current = install_client_retained_input_owner_current(
    (key, generation, bundle) => {
      key == "site-a" && generation == "1" && bundle == retained_input_cid("a")
    },
    () => "authority-a",
    () => 1791200000000L,
    (_, _) => true,
  )
  let input = prepare_client_retained_task_input(
    producer, transfer_record, receipt, destination_use_id, current, 100000,
  ).unwrap()
  let binding = client_retained_task_input_binding(input)
  let (consumer, consumer_evidence, consumer_subject) = retained_input_completed(
    ports[0],
    ports[5],
    1,
    1,
    client_retained_input_edge_schema_cid(edge),
    measurement_cid=@remote.remote_managed_output_measurement_cid(measurement),
    input_binding_cid=@remote.remote_input_binding_cid(binding),
  )
  {
    edge,
    binding,
    producer: record,
    producer_evidence: evidence,
    producer_subject: subject,
    consumer,
    consumer_evidence,
    consumer_subject,
    measurement,
    transfer: request,
    receipt,
  }
}

///|
fn retained_cleanup_admit(
  f : RetainedCleanupFixture,
  max_binding_bytes? : Int = 100000,
) -> Result[ClientRetainedInputCleanup, ClientRetainedTaskInputIssue] {
  prepare_client_retained_input_cleanup(
    f.binding,
    f.producer,
    f.producer_evidence,
    f.producer_subject,
    f.measurement,
    f.consumer,
    f.consumer_evidence,
    f.consumer_subject,
    f.measurement,
    max_binding_bytes,
    4,
    4096,
    8L,
  )
}

///|
test "retained cleanup restores the exact completed receiver without current execution authority" {
  let f = retained_cleanup_fixture()
  assert_true(
    @remote.restore_remote_runtime_completed_custody(
      f.producer,
      f.producer_evidence,
      f.producer_subject,
      f.measurement,
    )
    is Ok(_),
  )
  assert_true(
    @remote.restore_remote_runtime_completed_custody(
      f.consumer,
      f.consumer_evidence,
      f.consumer_subject,
      f.measurement,
    )
    is Ok(_),
  )
  let value = match retained_cleanup_admit(f) {
    Ok(value) => value
    Err(ProducerUnavailable) => fail("completed custody refused")
    Err(ForeignTransfer) => fail("original transfer refused")
    Err(InvalidBinding) => fail("original binding refused")
    Err(_) => fail("unexpected cleanup refusal")
  }
  assert_eq(
    @transfer.request_cid(client_retained_input_cleanup_transfer(value)),
    @transfer.request_cid(f.transfer),
  )
  assert_eq(
    client_retained_input_cleanup_receipt_cid(value),
    @transfer.destination_receipt_cid(f.receipt),
  )
  assert_eq(
    client_retained_input_cleanup_reader_id(value),
    @remote.dispatch_request_identity(
      @remote.dispatch_record_request(f.consumer),
    ),
  )
  // This value is an address for the physical cleanup Owner, not proof of stop,
  // borrow return, receiver reclamation, capacity return or formal release.
  assert_false(@remote.remote_runtime_record_released(f.consumer))
}

///|
test "retained cleanup refuses substituted producer attempt generation or binding" {
  let f = retained_cleanup_fixture()
  let (run, task) = @remote.dispatch_request_task_scope(
    @remote.dispatch_record_request(f.producer),
  )
  for
    (foreign_run, attempt, generation) in [
      (retained_input_cid("f"), 1, 1),
      (run, 2, 1),
      (run, 1, 2),
    ] {
    let (producer, producer_evidence, producer_subject) = retained_input_completed(
      foreign_run,
      task,
      attempt,
      generation,
      @remote.remote_managed_output_subject_projection(f.producer_subject)[4],
      measurement_cid=@remote.remote_managed_output_measurement_cid(
        f.measurement,
      ),
    )
    assert_true(
      retained_cleanup_admit({
        ..f,
        producer,
        producer_evidence,
        producer_subject,
      })
      is Err(_),
    )
  }
  let binding = @remote.prepare_remote_input_binding("{}", 100000).unwrap()
  assert_true(retained_cleanup_admit({ ..f, binding, }) is Err(InvalidBinding))
}

///|
test "retained cleanup refuses an unconfirmed consumer and changed completion measurement" {
  let f = retained_cleanup_fixture()
  let measurement = @remote.prepare_remote_managed_output_measurement(
    1,
    1,
    0,
    0,
    [1],
    [1],
    [1],
    [1],
    [0],
    [10],
  ).unwrap()
  assert_true(
    retained_cleanup_admit({ ..f, measurement, }) is Err(ProducerUnavailable),
  )
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_remote_release(f.consumer).unwrap(),
    true,
  ).unwrap()
  assert_true(retained_cleanup_admit(f) is Err(ProducerUnavailable))
}

///|
fn retained_cleanup_route(
  f : RetainedCleanupFixture,
) -> ClientRetainedTaskRoute {
  admit_client_retained_task_route(
    f.binding,
    f.edge,
    @remote.dispatch_record_request(f.consumer),
    100000,
    4,
    4096,
    8L,
  ).unwrap()
}

///|
fn retained_cleanup_address(
  f : RetainedCleanupFixture,
  route : ClientRetainedTaskRoute,
  consumer : @remote.DispatchRecord,
) -> Result[ClientRetainedInputCleanup, ClientRetainedTaskInputIssue] {
  prepare_client_retained_input_cleanup_for_route(
    route,
    f.producer,
    f.producer_evidence,
    f.producer_subject,
    f.measurement,
    consumer,
  )
}

///|
/// Protocol records only. These fixtures do not prove Native physical stop,
/// reader return, capacity release, or successful Source/Compute execution.
fn retained_cleanup_accepted(
  request : @remote.DispatchRequest,
) -> @remote.DispatchRecord {
  let site = @site.create_site(
    "site-a",
    1,
    retained_input_cid("a"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let journal = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  @remote.commit_dispatch_acceptance(
    @remote.prepare_dispatch_acceptance(journal, request).unwrap(),
    true,
  ).unwrap().1
}

///|
test "historical cleanup address survives consumer outcomes and release without changing records" {
  for outcome in ["accepted", "failed", "cancelled", "completed"] {
    let f = retained_cleanup_fixture()
    let route = retained_cleanup_route(f)
    let request = @remote.dispatch_record_request(f.consumer)
    let consumer = if outcome == "completed" {
      f.consumer
    } else {
      retained_cleanup_accepted(request)
    }
    if outcome == "failed" {
      @remote.commit_dispatch_transition(
        @remote.prepare_mark_execution_unknown(consumer).unwrap(),
        true,
      ).unwrap()
      @remote.commit_dispatch_transition(
        @remote.prepare_reconcile_failed_execution(consumer).unwrap(),
        true,
      ).unwrap()
    } else if outcome == "cancelled" {
      @remote.commit_dispatch_transition(
        @remote.prepare_confirm_execution_cancelled(consumer).unwrap(),
        true,
      ).unwrap()
    }
    let producer = prepare_client_retained_input_producer(
      f.edge,
      f.producer,
      f.producer_evidence,
      f.producer_subject,
    ).unwrap()
    @remote.commit_dispatch_transition(
      @remote.prepare_begin_remote_release(f.producer).unwrap(),
      true,
    ).unwrap()
    // Historical address admission works while producer release is pending.
    assert_true(retained_cleanup_address(f, route, consumer) is Ok(_))
    assert_false(client_retained_input_producer_available(producer))
    @remote.commit_dispatch_transition(
      @remote.prepare_confirm_remote_release(f.producer).unwrap(),
      true,
    ).unwrap()
    assert_false(client_retained_input_producer_available(producer))
    assert_true(
      @remote.restore_remote_runtime_completed_custody(
        f.producer,
        f.producer_evidence,
        f.producer_subject,
        f.measurement,
      )
      is Err(_),
    )
    for phase in 0..<3 {
      if phase == 1 {
        @remote.commit_dispatch_transition(
          @remote.prepare_begin_remote_release(consumer).unwrap(),
          true,
        ).unwrap()
      } else if phase == 2 {
        @remote.commit_dispatch_transition(
          @remote.prepare_confirm_remote_release(consumer).unwrap(),
          true,
        ).unwrap()
      }
      let before_producer = @remote.dispatch_record_durable_json(f.producer).unwrap()
      let before_consumer = @remote.dispatch_record_durable_json(consumer).unwrap()
      for _ in 0..<2 {
        let address = retained_cleanup_address(f, route, consumer).unwrap()
        assert_eq(
          @transfer.request_cid(client_retained_input_cleanup_transfer(address)),
          @transfer.request_cid(f.transfer),
        )
        assert_eq(
          client_retained_input_cleanup_receipt_cid(address),
          @transfer.destination_receipt_cid(f.receipt),
        )
        assert_eq(
          client_retained_input_cleanup_reader_id(address),
          @remote.dispatch_request_identity(request),
        )
      }
      assert_eq(
        @remote.dispatch_record_durable_json(f.producer).unwrap(),
        before_producer,
      )
      assert_eq(
        @remote.dispatch_record_durable_json(consumer).unwrap(),
        before_consumer,
      )
    }
    assert_true(retained_cleanup_admit(f) is Err(ProducerUnavailable))
  }
}

///|
test "historical cleanup address requires original producer durable evidence and measurement" {
  let f = retained_cleanup_fixture()
  let route = retained_cleanup_route(f)
  let consumer = retained_cleanup_accepted(
    @remote.dispatch_record_request(f.consumer),
  )
  let unconfirmed = retained_cleanup_accepted(
    @remote.dispatch_record_request(f.producer),
  )
  assert_true(
    retained_cleanup_address({ ..f, producer: unconfirmed, }, route, consumer)
    is Err(ProducerUnavailable),
  )
  let changed = @remote.prepare_remote_managed_output_measurement(
    1,
    1,
    0,
    0,
    [1],
    [1],
    [1],
    [1],
    [0],
    [10],
  ).unwrap()
  assert_true(
    retained_cleanup_address({ ..f, measurement: changed, }, route, consumer)
    is Err(ProducerUnavailable),
  )
  let (run, task) = @remote.dispatch_request_task_scope(
    @remote.dispatch_record_request(f.producer),
  )
  let (replacement, evidence, subject) = retained_input_completed(
    run,
    task,
    1,
    1,
    client_retained_input_edge_schema_cid(f.edge),
    measurement_cid=@remote.remote_managed_output_measurement_cid(changed),
    manifest_cid=@transfer.request_manifest(f.transfer).manifest_cid,
  )
  // Same dispatch request, but another durable evidence tuple cannot replace
  // the history bound by the original accepted input body.
  assert_eq(
    @remote.dispatch_request_identity(
      @remote.dispatch_record_request(replacement),
    ),
    @remote.dispatch_request_identity(
      @remote.dispatch_record_request(f.producer),
    ),
  )
  assert_true(
    retained_cleanup_address({ ..f, producer: replacement, }, route, consumer)
    is Err(ProducerUnavailable),
  )
  assert_true(
    retained_cleanup_address(
      {
        ..f,
        producer: replacement,
        producer_evidence: evidence,
        producer_subject: subject,
        measurement: changed,
      },
      route,
      consumer,
    )
    is Err(InvalidBinding),
  )
}

///|
test "historical cleanup address refuses substituted consumer attempt run and accepted binding" {
  let f = retained_cleanup_fixture()
  let route = retained_cleanup_route(f)
  let (run, task) = @remote.dispatch_request_task_scope(
    @remote.dispatch_record_request(f.consumer),
  )
  let wrong_binding = @remote.prepare_remote_input_binding("{}", 100000).unwrap()
  for
    (selected_run, attempt, binding_cid) in [
      (run, 2, @remote.remote_input_binding_cid(f.binding)),
      (retained_input_cid("f"), 1, @remote.remote_input_binding_cid(f.binding)),
      (run, 1, @remote.remote_input_binding_cid(wrong_binding)),
    ] {
    let (consumer, _, _) = retained_input_completed(
      selected_run,
      task,
      attempt,
      1,
      client_retained_input_edge_schema_cid(f.edge),
      input_binding_cid=binding_cid,
    )
    assert_true(
      retained_cleanup_address(f, route, consumer) is Err(InvalidBinding),
    )
  }
  assert_true(
    retained_cleanup_address(f, route, f.producer) is Err(InvalidBinding),
  )
}

///|
test "cleanup route keeps checked edge admission and completed constructor error order" {
  let f = retained_cleanup_fixture()
  let altered = @remote.prepare_remote_input_binding(
    @remote.remote_input_binding_body(f.binding).replace(
      old="\"consumer_input_port\":\"input\"",
      new="\"consumer_input_port\":\"other\"",
    ),
    100000,
  ).unwrap()
  assert_false(
    @remote.remote_input_binding_cid(altered) ==
    @remote.remote_input_binding_cid(f.binding),
  )
  let (run, task) = @remote.dispatch_request_task_scope(
    @remote.dispatch_record_request(f.consumer),
  )
  let (consumer, _, _) = retained_input_completed(
    run,
    task,
    1,
    1,
    client_retained_input_edge_schema_cid(f.edge),
    input_binding_cid=@remote.remote_input_binding_cid(altered),
  )
  assert_true(
    admit_client_retained_task_route(
      altered,
      f.edge,
      @remote.dispatch_record_request(consumer),
      100000,
      4,
      4096,
      8L,
    )
    is Err(InvalidBinding),
  )
  assert_true(
    retained_cleanup_admit(f, max_binding_bytes=0) is Err(InvalidBinding),
  )
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_remote_release(f.consumer).unwrap(),
    true,
  ).unwrap()
  let malformed = @remote.prepare_remote_input_binding("{}", 100000).unwrap()
  assert_true(
    retained_cleanup_admit({ ..f, binding: malformed, }, max_binding_bytes=0)
    is Err(ProducerUnavailable),
  )
}

///|
test "historical cleanup address preserves direct receiver profile restrictions" {
  for
    (selected_route, destination_use_id) in [
      (@transfer.TransferStore, "direct-destination"),
      (@transfer.DirectStream, "another-destination-use"),
    ] {
    let f = retained_cleanup_fixture(route=selected_route, destination_use_id~)
    let route = retained_cleanup_route(f)
    assert_true(
      retained_cleanup_address(f, route, f.consumer) is Err(ForeignTransfer),
    )
    assert_true(retained_cleanup_admit(f) is Err(ForeignTransfer))
  }
}
