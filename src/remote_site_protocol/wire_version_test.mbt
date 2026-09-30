///|
// Fixed expectations come from independent canonical JSON/SHA-256 vectors.
// The negative version is constructed only to exercise historical rejection.
test "current Remote Site wires reject obsolete labels and field sets" {
  let request_body = "{\"budget_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"connector_registration\":\"local\",\"connector_revision\":\"local/1\",\"coordinator_authority\":\"coordinator-a\",\"dispatch_id\":\"dispatch-a\",\"evidence_issuer_capability_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"grant_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_binding_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"obligations_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"run_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"runtime_bundle_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"site_generation\":1,\"site_key\":\"site-a\",\"strategy_revision\":\"strategy/1\",\"task_attempt\":1,\"task_key\":\"task-a\",\"version\":\"actql-remote-dispatch-request/0.1\"}"
  let request_cid = "sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1"
  let subject_body = "{\"dispatch_request_cid\":\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\",\"holding_evidence_cid\":\"sha256:0d53447b5b3e1a626b9bee01eca67067dd5465f4900e4b2a2573dc40336d331a\",\"logical_view_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"managed_profile_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"material_generation\":\"material-generation-a\",\"measurement_evidence_cid\":\"sha256:eecf2bab4ef5dc77dc89eee5b6bcc3c5d75d457d9d28d58fac85d5c0a6306a51\",\"physical_manifest_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"representation_codec_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"result_schema_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"retained_bytes\":\"8\",\"row_count\":2,\"version\":\"actql-remote-managed-output-subject/0.1\"}"
  let subject_cid = "sha256:2831143cda2a560c07ede897807dcd160716d096f5a7a586410c6c8b705fe287"
  let poll_body = "{\"dispatch_request_cid\":\"sha256:b940a6c947444f8d848ee0f9f563a3d02ab8ddb84812ed4ed35b9b65fe3af56b\",\"input_binding_cid\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"input_binding_json\":\"{}\",\"request_json\":\"{\\\"budget_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"connector_registration\\\":\\\"local\\\",\\\"connector_revision\\\":\\\"local/1\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"dispatch_id\\\":\\\"dispatch-a\\\",\\\"evidence_issuer_capability_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"grant_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"input_binding_cid\\\":\\\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\\\",\\\"obligations_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"run_definition_cid\\\":\\\"sha256:0000000000000000000000000000000000000000000000000000000000000000\\\",\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"site_generation\\\":1,\\\"site_key\\\":\\\"site-a\\\",\\\"strategy_revision\\\":\\\"strategy/1\\\",\\\"task_attempt\\\":1,\\\"task_key\\\":\\\"task-a\\\",\\\"version\\\":\\\"actql-remote-dispatch-request/0.1\\\"}\",\"version\":\"actql-remote-poll-dispatch/0.1\"}"
  let dispatch = admit_dispatch_request_json(request_body, request_cid).unwrap()
  assert_eq(dispatch_request_json(dispatch), Ok(request_body))
  let subject = admit_remote_managed_output_subject_json(
    subject_body, subject_cid, dispatch,
  ).unwrap()
  assert_eq(remote_managed_output_subject_json(subject), Ok(subject_body))
  let poll = admit_remote_poll_dispatch_json(poll_body).unwrap()
  assert_eq(
    remote_poll_dispatch_json(
      remote_poll_dispatch_request(poll),
      remote_poll_dispatch_input_binding(poll),
    ),
    Ok(poll_body),
  )
  let obsolete = "0.2"
  let old_request = request_body.replace(
    old="actql-remote-dispatch-request/0.1",
    new="actql-remote-dispatch-request/" + obsolete,
  )
  assert_true(
    admit_dispatch_request_json(
      old_request,
      "sha256:" + @sha.text_hex(old_request).unwrap(),
    )
    is Err(_),
  )
  let old_subject = subject_body.replace(
    old="actql-remote-managed-output-subject/0.1",
    new="actql-remote-managed-output-subject/" + obsolete,
  )
  assert_true(
    admit_remote_managed_output_subject_json(
      old_subject,
      "sha256:" + @sha.text_hex(old_subject).unwrap(),
      dispatch,
    )
    is Err(_),
  )
  assert_true(
    admit_remote_poll_dispatch_json(
      poll_body.replace(
        old="actql-remote-poll-dispatch/0.1",
        new="actql-remote-poll-dispatch/" + obsolete,
      ),
    )
    is Err(_),
  )
  let incomplete_request = request_body.replace(
    old="\"input_binding_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",",
    new="",
  )
  let incomplete_subject = subject_body.replace(
    old="\"measurement_evidence_cid\":\"sha256:eecf2bab4ef5dc77dc89eee5b6bcc3c5d75d457d9d28d58fac85d5c0a6306a51\",",
    new="",
  )
  let incomplete_poll = poll_body.replace(
    old="\"input_binding_json\":\"{}\",",
    new="",
  )
  assert_true(
    admit_dispatch_request_json(
      incomplete_request,
      "sha256:" + @sha.text_hex(incomplete_request).unwrap(),
    )
    is Err(_),
  )
  assert_true(
    admit_remote_managed_output_subject_json(
      incomplete_subject,
      "sha256:" + @sha.text_hex(incomplete_subject).unwrap(),
      dispatch,
    )
    is Err(_),
  )
  assert_true(admit_remote_poll_dispatch_json(incomplete_poll) is Err(_))
}

///|
test "unknown execution restoration rejects obsolete nested dispatch" {
  let source = journal()
  let dispatch = request(
    "wire-unknown",
    73,
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let (_, record) = accept(source, dispatch)
  provision(record)
  execute(record)
  commit_dispatch_transition(
    prepare_mark_execution_unknown(record).unwrap(),
    true,
  ).unwrap()
  let body = dispatch_record_durable_json(record).unwrap()
  let restored = restore_durable_dispatch_record(
    journal(),
    admit_durable_dispatch_record(@utf8.encode(body)).unwrap(),
  ).unwrap()
  assert_eq(dispatch_record_durable_json(restored), Ok(body))
  let (execution, _, _, _, _) = dispatch_record_state(restored)
  assert_eq(execution, ExecutionUnknown)
  let old_body = body.replace(
    old="actql-remote-dispatch-request/0.1",
    new="actql-remote-dispatch-request/" + "0.2",
  )
  assert_true(
    admit_durable_dispatch_record(@utf8.encode(old_body)) is Err(InvalidJournal),
  )
  // Rejection cannot mutate the retained current owner or authorize execution.
  assert_eq(dispatch_record_durable_json(record), Ok(body))
}

///|
test "dispatch envelope carries typed run materials as a separate body" {
  let request_body = "{\"budget_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"connector_registration\":\"local\",\"connector_revision\":\"local/1\",\"coordinator_authority\":\"coordinator-a\",\"dispatch_id\":\"dispatch-a\",\"evidence_issuer_capability_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"grant_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_binding_cid\":\"sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a\",\"obligations_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"run_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"runtime_bundle_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"site_generation\":1,\"site_key\":\"site-a\",\"strategy_revision\":\"strategy/1\",\"task_attempt\":1,\"task_key\":\"task-a\",\"version\":\"actql-remote-dispatch-request/0.1\"}"
  let request = admit_dispatch_request_json(
    request_body,
    "sha256:" + @sha.text_hex(request_body).unwrap(),
  ).unwrap()
  let binding = prepare_remote_input_binding("{}", 16).unwrap()
  let plain = admit_remote_poll_dispatch_json(
    remote_poll_dispatch_json(request, binding).unwrap(),
  ).unwrap()
  assert_true(remote_poll_dispatch_run_materials(plain) is None)
  let materials = "{\"version\":\"materials-under-test\"}"
  let body = remote_poll_dispatch_materials_json(request, binding, materials).unwrap()
  // Keys are canonical: the materials sit beside, not inside, the binding.
  assert_true(
    body.has_suffix(
      ",\"run_materials_json\":\"{\\\"version\\\":\\\"materials-under-test\\\"}\",\"version\":\"actql-remote-poll-dispatch-materials/0.1\"}",
    ),
  )
  let admitted = admit_remote_poll_dispatch_json(body).unwrap()
  assert_eq(remote_poll_dispatch_run_materials(admitted), Some(materials))
  assert_eq(
    dispatch_request_identity(remote_poll_dispatch_request(admitted)),
    dispatch_request_identity(request),
  )
  assert_eq(
    remote_input_binding_body(remote_poll_dispatch_input_binding(admitted)),
    "{}",
  )
  // Each version admits exactly its own field set.
  assert_true(
    admit_remote_poll_dispatch_json(
      body.replace(
        old="actql-remote-poll-dispatch-materials/0.1",
        new="actql-remote-poll-dispatch/0.1",
      ),
    )
    is Err(_),
  )
  let plain_body = remote_poll_dispatch_json(request, binding).unwrap()
  assert_true(
    admit_remote_poll_dispatch_json(
      plain_body.replace(
        old="actql-remote-poll-dispatch/0.1",
        new="actql-remote-poll-dispatch-materials/0.1",
      ),
    )
    is Err(_),
  )
  // Materials are bounded and never empty.
  assert_true(
    remote_poll_dispatch_materials_json(request, binding, "") is Err(_),
  )
  let oversized = "x".repeat(REMOTE_RUN_MATERIALS_MAX_BYTES + 1)
  assert_true(
    remote_poll_dispatch_materials_json(request, binding, oversized) is Err(_),
  )
  assert_true(
    admit_remote_poll_dispatch_json(
      body.replace(old=materials.escape(quote=false), new=oversized),
    )
    is Err(_),
  )
  // Exactly at the cap the materials are carried and admitted; the outer
  // envelope grows past the inner size when the materials need escaping,
  // and the envelope's own bound still covers it.
  let at_cap = "\"".repeat(REMOTE_RUN_MATERIALS_MAX_BYTES)
  let capped = remote_poll_dispatch_materials_json(request, binding, at_cap).unwrap()
  assert_true(capped.length() > 2 * REMOTE_RUN_MATERIALS_MAX_BYTES)
  assert_eq(
    remote_poll_dispatch_run_materials(
      admit_remote_poll_dispatch_json(capped).unwrap(),
    ),
    Some(at_cap),
  )
}
