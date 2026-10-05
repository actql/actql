///|
struct RetainedCoordinatorFixture {
  request : @remote.DispatchRequest
  record : @remote.CoordinatorDispatchIntentRecord
  evidence : @remote.RemoteExecutionEvidence
  subject : @remote.RemoteManagedOutputSubject
  measurement : @remote.RemoteManagedOutputMeasurement
  initial : @remote.DurableCoordinatorDispatchRecord
}

///|
fn retained_coordinator_fixture(
  edge : ClientRetainedInputEdge,
  attempt? : Int = 1,
) -> RetainedCoordinatorFixture {
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
  let ports = client_retained_input_edge_projection(edge)
  let (site_record, evidence, subject) = retained_input_completed(
    ports[0],
    ports[1],
    attempt,
    1,
    client_retained_input_edge_schema_cid(edge),
    measurement_cid=@remote.remote_managed_output_measurement_cid(measurement),
  )
  let request = @remote.dispatch_record_request(site_record)
  let admission = @remote.prepare_coordinator_dispatch_intent(
    @remote.create_coordinator_dispatch_journal("authority-a").unwrap(),
    request,
  ).unwrap()
  let initial = @remote.admit_durable_coordinator_dispatch_record(
    @utf8.encode(
      @remote.coordinator_dispatch_admission_durable_json(admission).unwrap(),
    ),
  ).unwrap()
  let (_, record) = @remote.commit_coordinator_dispatch_intent(admission, true).unwrap()
  { request, record, evidence, subject, measurement, initial, }
}

///|
fn retained_coordinator_complete(
  fixture : RetainedCoordinatorFixture,
) -> @remote.DurableCoordinatorDispatchRecord {
  let transition = @remote.prepare_coordinator_managed_output_observation(
    fixture.record,
    5,
    3,
    2,
    0,
    true,
    false,
    fixture.evidence,
    fixture.subject,
    fixture.measurement,
  ).unwrap()
  let saved = @remote.admit_durable_coordinator_dispatch_record(
    @utf8.encode(
      @remote.coordinator_dispatch_transition_durable_json(
        fixture.initial,
        transition,
        evidence=Some(fixture.evidence),
        subject=Some(fixture.subject),
        measurement=Some(fixture.measurement),
      ).unwrap(),
    ),
  ).unwrap()
  @remote.commit_coordinator_dispatch_transition(transition, true).unwrap()
  saved
}

///|
test "Coordinator retained producer requires committed exact managed output" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "coordinator-run",
  )
  let edge = prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, 1, 0,
  ).unwrap()
  let fixture = retained_coordinator_fixture(edge)
  let issue = fn() {
    prepare_client_coordinator_retained_input_producer(
      edge,
      fixture.request,
      fixture.evidence,
      fixture.subject,
      fixture.measurement,
      () => Some(fixture.record),
    )
  }
  // Site completion alone does not establish Coordinator durable receipt.
  assert_true(issue() is Err(ProducerUnavailable))
  let pending = @remote.prepare_coordinator_managed_output_observation(
    fixture.record,
    5,
    3,
    2,
    0,
    true,
    false,
    fixture.evidence,
    fixture.subject,
    fixture.measurement,
  ).unwrap()
  assert_true(
    @remote.commit_coordinator_dispatch_transition(pending, false)
    is Err(@remote.DurabilityUnconfirmed),
  )
  assert_true(issue() is Err(ProducerUnavailable))
  ignore(retained_coordinator_complete(fixture))
  let producer = issue().unwrap()
  assert_true(client_retained_input_producer_available(producer))
  assert_eq(
    @remote.dispatch_request_identity(
      client_retained_input_producer_dispatch(producer),
    ),
    @remote.dispatch_request_identity(fixture.request),
  )
  let foreign_measurement = @remote.prepare_remote_managed_output_measurement(
    1,
    0,
    0,
    0,
    [1],
    [2],
    [1],
    [1],
    [0],
    [10],
  ).unwrap()
  assert_true(
    prepare_client_coordinator_retained_input_producer(
      edge,
      fixture.request,
      fixture.evidence,
      fixture.subject,
      foreign_measurement,
      () => Some(fixture.record),
    )
    is Err(ProducerUnavailable),
  )
}

///|
test "Coordinator retained producer rechecks current custody after reconstruction" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "coordinator-recovery-run",
  )
  let edge = prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, 1, 0,
  ).unwrap()
  let fixture = retained_coordinator_fixture(edge)
  let saved = retained_coordinator_complete(fixture)
  let mut current = Some(fixture.record)
  let producer = prepare_client_coordinator_retained_input_producer(
    edge,
    fixture.request,
    fixture.evidence,
    fixture.subject,
    fixture.measurement,
    () => current,
  ).unwrap()
  let restored = @remote.restore_durable_coordinator_dispatch_record(
    @remote.create_coordinator_dispatch_journal("authority-a").unwrap(),
    saved,
  ).unwrap()
  current = Some(restored)
  assert_true(client_retained_input_producer_available(producer))
  current = None
  assert_false(client_retained_input_producer_available(producer))
  let other = retained_coordinator_fixture(edge, attempt=2)
  ignore(retained_coordinator_complete(other))
  current = Some(other.record)
  assert_false(client_retained_input_producer_available(producer))
  current = Some(restored)
  assert_true(client_retained_input_producer_available(producer))
  // Begin cleanup on the live Owner. Historical completion still exists,
  // but cannot authorize another retained input after this transition.
  @remote.commit_coordinator_dispatch_transition(
    @remote.prepare_coordinator_site_observation(
      restored,
      6,
      3,
      2,
      1,
      true,
      false,
      None,
    ).unwrap(),
    true,
  ).unwrap()
  assert_false(client_retained_input_producer_available(producer))
  @remote.commit_coordinator_dispatch_transition(
    @remote.prepare_coordinator_site_observation(
      restored,
      7,
      3,
      2,
      2,
      false,
      false,
      None,
    ).unwrap(),
    true,
  ).unwrap()
  assert_false(client_retained_input_producer_available(producer))
}
