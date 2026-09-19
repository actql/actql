///|
test "remote dispatch response admits exact state and request binding" {
  let request = coordinator_request("dispatch-response", 21)
  let body = "{\"version\":\"actql-remote-dispatch-response/0.1\",\"dispatch_request_cid\":\"" +
    dispatch_request_identity(request) +
    "\",\"revision\":2,\"state\":[3,2,0,1,0]}"
  let response = admit_remote_dispatch_response_json(
    body,
    request,
    DispatchReply,
  ).unwrap()
  assert_eq(remote_dispatch_response_kind(response), DispatchReply)
  assert_eq(remote_dispatch_response_revision(response), 2)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(
    prepare_coordinator_dispatch_intent(journal, request).unwrap(),
    true,
  ).unwrap()
  let transition = prepare_coordinator_response_observation(record, response).unwrap()
  commit_coordinator_dispatch_transition(transition, true).unwrap()
  assert_true(!coordinator_completion_evidence_available(record))
}

///|
test "remote dispatch status encoder round trips an evidence-free record" {
  let request = coordinator_request("dispatch-status-encoder", 25)
  let site = @site.create_site(
    "site-a",
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  let journal = create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap()
  let (_, record) = commit_dispatch_acceptance(
    prepare_dispatch_acceptance(journal, request).unwrap(),
    true,
  ).unwrap()
  let body = remote_dispatch_status_json(record, None, None, None).unwrap()
  let response = admit_remote_dispatch_response_json(body, request, StatusReply).unwrap()
  assert_eq(remote_dispatch_response_revision(response), 0)
}

///|
test "remote status response admits the complete managed evidence tuple" {
  let request = coordinator_request("dispatch-status", 22)
  let (evidence, subject, measurement) = managed_output_for_coordinator(request)
  let evidence_wire = remote_execution_evidence_json(evidence).unwrap()
  let subject_wire = remote_managed_output_subject_json(subject).unwrap()
  let measurement_wire = remote_managed_output_measurement_json(measurement).unwrap()
  let writer = @encode.writer(524288, 64, 3)
  @encode.begin_object(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-remote-dispatch-status/0.1")
  @encode.key(writer, "dispatch_request_cid")
  @encode.string_value(writer, dispatch_request_identity(request))
  @encode.key(writer, "revision")
  @encode.number_value(writer, 5.0)
  @encode.key(writer, "state")
  @encode.begin_array(writer)
  for value in [3, 2, 0, 1, 0] {
    @encode.number_value(writer, value.to_double())
  }
  @encode.end_array(writer)
  @encode.key(writer, "evidence")
  @encode.begin_object(writer)
  @encode.key(writer, "cid")
  @encode.string_value(writer, remote_execution_evidence_cid(evidence))
  @encode.key(writer, "wire")
  @encode.string_value(writer, evidence_wire)
  @encode.end_object(writer)
  @encode.key(writer, "subject")
  @encode.begin_object(writer)
  @encode.key(writer, "cid")
  @encode.string_value(writer, remote_managed_output_subject_cid(subject))
  @encode.key(writer, "wire")
  @encode.string_value(writer, subject_wire)
  @encode.end_object(writer)
  @encode.key(writer, "measurement")
  @encode.begin_object(writer)
  @encode.key(writer, "cid")
  @encode.string_value(
    writer,
    remote_managed_output_measurement_cid(measurement),
  )
  @encode.key(writer, "wire")
  @encode.string_value(writer, measurement_wire)
  @encode.end_object(writer)
  @encode.end_object(writer)
  let response = admit_remote_dispatch_response_json(
    @encode.finish(writer),
    request,
    StatusReply,
  ).unwrap()
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(
    prepare_coordinator_dispatch_intent(journal, request).unwrap(),
    true,
  ).unwrap()
  let transition = prepare_coordinator_response_observation(record, response).unwrap()
  commit_coordinator_dispatch_transition(transition, true).unwrap()
  assert_true(coordinator_completion_evidence_available(record))
}

///|
test "remote response rejects foreign identity and partial evidence" {
  let request = coordinator_request("dispatch-invalid-response", 23)
  let foreign = coordinator_request("dispatch-foreign-response", 24)
  let response = "{\"version\":\"actql-remote-dispatch-response/0.1\",\"dispatch_request_cid\":\"" +
    dispatch_request_identity(foreign) +
    "\",\"revision\":0,\"state\":[0,0,0,0,0]}"
  assert_true(
    admit_remote_dispatch_response_json(response, request, DispatchReply)
    is Err(InvalidDispatch),
  )
  let partial = "{\"version\":\"actql-remote-dispatch-status/0.1\",\"dispatch_request_cid\":\"" +
    dispatch_request_identity(request) +
    "\",\"revision\":0,\"state\":[0,0,0,0,0],\"evidence\":null,\"subject\":null}"
  assert_true(
    admit_remote_dispatch_response_json(partial, request, StatusReply)
    is Err(InvalidDispatch),
  )
}
