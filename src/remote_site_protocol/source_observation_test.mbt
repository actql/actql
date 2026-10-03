///|
// Protocol fixtures prove admission and durable binding only. Actual Native
// acquisition is exercised separately under the physical capture owner.
fn source_observation_fixture(
  request : DispatchRequest,
  snapshot? : String = "snapshot-1",
) -> RemoteSourceObservation raise {
  let contract = "sha256:" + "b".repeat(64)
  let other = "sha256:" + "d".repeat(64)
  let input = @publication.seal_run_evidence_value(
    "source_input_logical",
    "{\"version\":\"actql-source-input-logical/0.1\"," +
    "\"logical_relation_cid\":\"" +
    other +
    "\"," +
    "\"relation_schema_cid\":\"" +
    other +
    "\"," +
    "\"source_contract_cid\":\"" +
    contract +
    "\"," +
    "\"completeness\":\"complete\"," +
    "\"ordering_evidence\":{\"stable\":false,\"keys\":[]}}",
    8192,
    256,
    16,
  ).unwrap()
  let writer = @encode.writer(8192, 256, 16)
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("version", "actql-source-evidence/0.1"),
      ("source_ref", "connector://crm/main/r#v"),
      ("input_logical_cid", @publication.run_evidence_value_identity(input)),
      ("source_contract_cid", contract),
      ("schema_evidence_cid", other),
      ("capability_evidence_cid", other),
      ("authority_scope_cid", "sha256:" + "c".repeat(64)),
      ("source_data_policy_cid", other),
      ("effective_data_policy_cid", other),
      ("data_classification", "internal"),
      ("source_view_contract_cid", contract),
      ("output_carrier", "relation"),
      ("read_mode", "snapshot"),
      ("observed_at", "2026-10-03T00:00:01.000Z"),
      ("snapshot_ref", snapshot),
      ("completeness", "complete"),
      ("consistency_level", "snapshot"),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, value)
  }
  @encode.key(writer, "ordering_evidence")
  @encode.begin_object(writer)
  @encode.key(writer, "stable")
  @encode.bool_value(writer, false)
  @encode.key(writer, "keys")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.end_object(writer)
  let source = @publication.seal_run_evidence_value(
    "source_evidence",
    @encode.finish(writer),
    8192,
    256,
    16,
  ).unwrap()
  prepare_remote_source_observation(
    request, 0, source, input, "2026-10-03T00:00:00.000Z", "2026-10-03T00:00:01.000Z",
  ).unwrap()
}

///|
test "completed Source candidate preserves original bytes and rejects substitution" {
  let request = coordinator_request("source-observation", 61)
  let candidate = source_observation_fixture(request)
  let wire = remote_source_observation_json(candidate)
  let restored = admit_remote_source_observation_json(wire, request).unwrap()
  assert_eq(
    remote_source_observation_projection(restored),
    remote_source_observation_projection(candidate),
  )
  assert_true(
    admit_remote_source_observation_json(
      wire,
      coordinator_request("source-observation-foreign", 62),
    )
    is Err(_),
  )
  assert_true(
    admit_remote_source_observation_json(wire + " ", request) is Err(_),
  )
  assert_true(
    admit_remote_source_observation_json(
      wire.replace(old="snapshot-1", new="snapshot-2"),
      request,
    )
    is Err(_),
  )
  assert_true(
    admit_remote_source_observation_json(
      wire.replace(old="\"task_ordinal\":0", new="\"task_ordinal\":-1"),
      request,
    )
    is Err(_),
  )
}

///|
test "Coordinator preserves completed Source with output and refuses replacement after restore" {
  let request = coordinator_request("durable-source-observation", 63)
  let candidate = source_observation_fixture(request)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let initial = admit_durable_coordinator_dispatch_record(
    @utf8.encode(
      coordinator_dispatch_admission_durable_json(admission).unwrap(),
    ),
  ).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  let (evidence, subject, measurement) = managed_output_for_coordinator(request)
  let transition = prepare_coordinator_managed_output_observation(
    record, 5, 3, 2, 0, true, false, evidence, subject, measurement,
  ).unwrap()
  let next = coordinator_dispatch_transition_durable_json(
    initial,
    transition,
    evidence=Some(evidence),
    subject=Some(subject),
    measurement=Some(measurement),
    source_observation=Some(candidate),
  ).unwrap()
  let durable = admit_durable_coordinator_dispatch_record(@utf8.encode(next)).unwrap()
  assert_eq(
    remote_source_observation_json(
      durable_coordinator_dispatch_record_source_observation(durable).unwrap(),
    ),
    remote_source_observation_json(candidate),
  )
  let restored = restore_durable_coordinator_dispatch_record(
    create_coordinator_dispatch_journal("coordinator-a").unwrap(),
    durable,
  ).unwrap()
  let replay = prepare_coordinator_managed_output_observation(
    restored, 5, 3, 2, 0, true, false, evidence, subject, measurement,
  ).unwrap()
  assert_true(coordinator_dispatch_transition_is_replay(replay))
  assert_eq(
    coordinator_dispatch_transition_durable_json(
      durable,
      replay,
      evidence=Some(evidence),
      subject=Some(subject),
      measurement=Some(measurement),
      source_observation=Some(candidate),
    ),
    Ok(next),
  )
  assert_true(
    coordinator_dispatch_transition_durable_json(
      durable,
      replay,
      evidence=Some(evidence),
      subject=Some(subject),
      measurement=Some(measurement),
      source_observation=Some(
        source_observation_fixture(request, snapshot="snapshot-2"),
      ),
    )
    is Err(StateCollision),
  )
}
