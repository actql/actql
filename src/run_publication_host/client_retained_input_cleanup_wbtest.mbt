///|
struct RetainedCleanupFixture {
  materials : ClientRunMaterials
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
fn retained_cleanup_fixture() -> RetainedCleanupFixture raise {
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
    @transfer.DirectStream,
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
    @transfer.prepare_source_settled(transfer_record, true, false).unwrap(),
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
    producer, transfer_record, receipt, "direct-destination", current, 100000,
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
    materials: {
      prepared,
      compilation: Tasks(compilation),
      admission,
      run_definition: definition,
    },
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
    100000,
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
test "retained cleanup refuses unconfirmed completion measurement" {
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
}

///|
test "retained cleanup keeps the same address after both task releases" {
  let f = retained_cleanup_fixture()
  let original = retained_cleanup_admit(f).unwrap()
  for record in [f.producer, f.consumer] {
    @remote.commit_dispatch_transition(
      @remote.prepare_begin_remote_release(record).unwrap(),
      true,
    ).unwrap()
    assert_true(retained_cleanup_admit(f) is Ok(_))
    @remote.commit_dispatch_transition(
      @remote.prepare_confirm_remote_release(record).unwrap(),
      true,
    ).unwrap()
  }
  let before = [
    @remote.dispatch_record_revision(f.producer),
    @remote.dispatch_record_revision(f.consumer),
  ]
  for _ in 0..<2 {
    let restored = retained_cleanup_admit(f).unwrap()
    assert_eq(
      @transfer.request_cid(client_retained_input_cleanup_transfer(restored)),
      @transfer.request_cid(client_retained_input_cleanup_transfer(original)),
    )
    assert_eq(
      client_retained_input_cleanup_receipt_cid(restored),
      client_retained_input_cleanup_receipt_cid(original),
    )
    assert_eq(
      client_retained_input_cleanup_reader_id(restored),
      client_retained_input_cleanup_reader_id(original),
    )
  }
  assert_eq(
    [
      @remote.dispatch_record_revision(f.producer),
      @remote.dispatch_record_revision(f.consumer),
    ],
    before,
  )
  assert_true(@remote.remote_runtime_record_released(f.producer))
  assert_true(@remote.remote_runtime_record_released(f.consumer))
}

///|
fn retained_source_cleanup_admit(
  f : RetainedCleanupFixture,
) -> Result[ClientRetainedSourceCleanup, ClientRetainedTaskInputIssue] {
  prepare_client_retained_source_cleanup(
    f.materials,
    f.binding,
    f.producer,
    f.producer_evidence,
    f.producer_subject,
    f.measurement,
    f.consumer,
    f.consumer_evidence,
    f.consumer_subject,
    f.measurement,
    100000,
    4,
    4096,
    1024L,
  )
}

///|
test "retained source cleanup binds the sole checked consumer after release" {
  let f = retained_cleanup_fixture()
  let permit = retained_source_cleanup_admit(f).unwrap()
  let requests = client_retained_source_cleanup_requests(permit)
  assert_eq(
    @remote.dispatch_request_identity(requests.0),
    @remote.dispatch_request_identity(
      @remote.dispatch_record_request(f.producer),
    ),
  )
  for record in [f.producer, f.consumer] {
    @remote.commit_dispatch_transition(
      @remote.prepare_begin_remote_release(record).unwrap(),
      true,
    ).unwrap()
    @remote.commit_dispatch_transition(
      @remote.prepare_confirm_remote_release(record).unwrap(),
      true,
    ).unwrap()
  }
  let revisions = [
    @remote.dispatch_record_revision(f.producer),
    @remote.dispatch_record_revision(f.consumer),
  ]
  for _ in 0..<2 {
    verify_client_retained_source_cleanup_observation(
      permit,
      f.producer,
      f.producer_evidence,
      f.producer_subject,
      f.measurement,
      f.consumer,
      f.consumer_evidence,
      f.consumer_subject,
      f.measurement,
      100000,
      4,
      4096,
      1024L,
    ).unwrap()
  }
  assert_eq(
    [
      @remote.dispatch_record_revision(f.producer),
      @remote.dispatch_record_revision(f.consumer),
    ],
    revisions,
  )
  assert_false(@remote.remote_runtime_record_startable(f.producer))
  assert_false(@remote.remote_runtime_record_startable(f.consumer))
}

///|
test "retained source cleanup refuses a foreign Run and producer Result retention" {
  let f = retained_cleanup_fixture()
  let (prepared, compilation, admission, definition) = retained_input_run(
    "foreign-cleanup-run",
  )
  assert_true(
    retained_source_cleanup_admit({
      ..f,
      materials: {
        prepared,
        compilation: Tasks(compilation),
        admission,
        run_definition: definition,
      },
    })
    is Err(InvalidBinding),
  )
  let retained_producer_program = retained_input_program.replace(
    old="\"results\":{\"answer\":{\"from\":{\"stage\":\"compute\",\"result\":\"rows\"}}}",
    new="\"results\":{\"producer\":{\"from\":{\"stage\":\"acquire\",\"result\":\"rows\"}},\"answer\":{\"from\":{\"stage\":\"compute\",\"result\":\"rows\"}}}",
  )
  let prepared = multi_source_prepared(retained_producer_program)
  assert_eq(prepared_client_result_count(prepared), 2)
  assert_true(
    retained_source_cleanup_admit({
      ..f,
      materials: { ..f.materials, prepared, },
    })
    is Err(InvalidBinding),
  )
}

///|
test "retained source cleanup refuses a physical address with substituted logical edge" {
  let f = retained_cleanup_fixture()
  guard f.materials.compilation is Tasks(compilation) else {
    fail("task compilation required")
  }
  let edge = prepare_client_retained_input_edge(
    f.materials.prepared,
    compilation,
    f.materials.admission,
    f.materials.run_definition,
    1,
    0,
  ).unwrap()
  let body = @remote.remote_input_binding_body(f.binding).replace(
    old="\"consumer_logical_cid\":\"" + edge.consumer.logical_cid + "\"",
    new="\"consumer_logical_cid\":\"" + retained_input_cid("f") + "\"",
  )
  let binding = @remote.prepare_remote_input_binding(body, 100000).unwrap()
  assert_false(
    @remote.remote_input_binding_cid(binding) ==
    @remote.remote_input_binding_cid(f.binding),
  )
  let ports = client_retained_input_edge_projection(edge)
  let (consumer, consumer_evidence, consumer_subject) = retained_input_completed(
    ports[0],
    ports[5],
    1,
    1,
    client_retained_input_edge_schema_cid(edge),
    measurement_cid=@remote.remote_managed_output_measurement_cid(f.measurement),
    input_binding_cid=@remote.remote_input_binding_cid(binding),
  )
  let changed = { ..f, binding, consumer, consumer_evidence, consumer_subject, }
  assert_true(retained_cleanup_admit(changed) is Ok(_))
  assert_true(retained_source_cleanup_admit(changed) is Err(InvalidBinding))
}
