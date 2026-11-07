///|
// Independent fixtures use the existing row schemas and Python hashlib for
// the Run Definition preimage. No expected bytes are read from product output.
let journal_encoding_definition = "{\"authorization_context_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"created_at\":\"2026-09-18T00:00:00.000Z\",\"input_artifact_set_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"invocation_template_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"run_definition_cid\":\"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc\",\"run_id\":\"run\",\"scope_id\":\"scope\",\"valid_until\":\"2099-01-01T00:00:00.000Z\",\"version\":\"actql-run-definition/0.1\"}"

///|
fn journal_encoding_original() -> ClientRunJournalEncoding {
  let (request, _, _) = admit_client_submitted_run_admission_wire(
    submitted_run_record_fixture,
  ).unwrap()
  {
    request,
    definition: @publication.admit_publication_contract(
      "run_definition", journal_encoding_definition, 65536, 4096, 64,
    ).unwrap(),
    dispatch_reserved: false,
    physical_start_claimed: false,
    cancellation_requested: false,
    publication_binding: None,
    publication_policy_originals: None,
    effect_material_originals: None,
    task_materials_cid: None,
    checkpoint: None,
  }
}

///|
test "original journal row codec preserves absent private fields and exact original identity" {
  let body = client_run_journal_row_body(journal_encoding_original()).unwrap()
  assert_eq(
    @utf8.decode(body),
    "{\"cancellation_requested\":false,\"checkpoint\":null,\"dispatch_reserved\":false,\"physical_start_claimed\":false,\"publication_binding\":null,\"request\":\"{\\\"authority_scope_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"caller_input_intent_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"caller_request_id\\\":\\\"caller-é\\\",\\\"intent_fingerprint_cid\\\":\\\"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010\\\",\\\"logical_request_scope_cid\\\":\\\"sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6\\\",\\\"parameter_values_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"program_definition_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"}\",\"run_definition\":\"{\\\"authorization_context_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"compiled_plan_cid\\\":\\\"sha256:1111111111111111111111111111111111111111111111111111111111111111\\\",\\\"created_at\\\":\\\"2026-09-18T00:00:00.000Z\\\",\\\"input_artifact_set_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"invocation_template_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"run_definition_cid\\\":\\\"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc\\\",\\\"run_id\\\":\\\"run\\\",\\\"scope_id\\\":\\\"scope\\\",\\\"valid_until\\\":\\\"2099-01-01T00:00:00.000Z\\\",\\\"version\\\":\\\"actql-run-definition/0.1\\\"}\",\"version\":\"actql-native-client-run-row/0.1\"}",
  )
}

///|
test "original journal row codec preserves raw originals checkpoint Unicode and newlines" {
  let record = {
    ..journal_encoding_original(),
    cancellation_requested: true,
    dispatch_reserved: true,
    physical_start_claimed: true,
    checkpoint: Some("{\"text\":\"é\\r\\n\"}"),
    publication_binding: Some("original-store-é"),
    effect_material_originals: Some("{\"value\":null,\"é\":\"é\"}"),
    publication_policy_originals: Some("{\"text\":\"é\\r\\n\"}"),
  }
  assert_eq(
    @utf8.decode(client_run_journal_row_body(record).unwrap()),
    "{\"cancellation_requested\":true,\"checkpoint\":\"{\\\"text\\\":\\\"é\\\\r\\\\n\\\"}\",\"dispatch_reserved\":true,\"effect_material_originals\":\"{\\\"value\\\":null,\\\"é\\\":\\\"é\\\"}\",\"physical_start_claimed\":true,\"publication_binding\":\"original-store-é\",\"publication_policy_originals\":\"{\\\"text\\\":\\\"é\\\\r\\\\n\\\"}\",\"request\":\"{\\\"authority_scope_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"caller_input_intent_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"caller_request_id\\\":\\\"caller-é\\\",\\\"intent_fingerprint_cid\\\":\\\"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010\\\",\\\"logical_request_scope_cid\\\":\\\"sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6\\\",\\\"parameter_values_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"program_definition_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"}\",\"run_definition\":\"{\\\"authorization_context_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"compiled_plan_cid\\\":\\\"sha256:1111111111111111111111111111111111111111111111111111111111111111\\\",\\\"created_at\\\":\\\"2026-09-18T00:00:00.000Z\\\",\\\"input_artifact_set_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"invocation_template_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"run_definition_cid\\\":\\\"sha256:7a12ebea352eee2a7d88bf6df5c5b6d7b56d6383f7e6e5fc9231fef79412fafc\\\",\\\"run_id\\\":\\\"run\\\",\\\"scope_id\\\":\\\"scope\\\",\\\"valid_until\\\":\\\"2099-01-01T00:00:00.000Z\\\",\\\"version\\\":\\\"actql-run-definition/0.1\\\"}\",\"version\":\"actql-native-client-run-row/0.1\"}",
  )
}

///|
test "original journal codecs retain capacity refusal without admission or dispatch" {
  for field in ["checkpoint", "effect", "policy", "binding"] {
    let original = "x".repeat(131073)
    let record = journal_encoding_original()
    let record = match field {
      "checkpoint" => { ..record, checkpoint: Some(original), }
      "effect" => { ..record, effect_material_originals: Some(original), }
      "policy" => { ..record, publication_policy_originals: Some(original), }
      _ => { ..record, publication_binding: Some(original), }
    }
    assert_eq(client_run_journal_row_body(record), Err(CapacityExceeded))
  }
  let intent = prepare_client_submitted_intent(
    "{\"input\":{\"value\":\"" +
    "x".repeat(65536) +
    "\"},\"kind\":\"program\",\"parameters\":null}",
    131072,
    64,
    8,
  ).unwrap()
  assert_eq(
    client_submitted_intent_journal_row_body("original-reference", intent),
    Err(CapacityExceeded),
  )
}

///|
test "original submitted row codec retains preparing and ready bytes and exact Int64 revision" {
  let intent = prepare_client_submitted_intent(
    "{\"input\":{\"text\":\"é\\r\\n\",\"é\":null},\"kind\":\"program\",\"parameters\":null}",
    65536, 64, 8,
  ).unwrap()
  let reference = "{\"epoch\":\"original-é\",\"nonce\":\"é\\r\\n\"}"
  assert_eq(
    @utf8.decode(
      client_submitted_intent_journal_row_body(reference, intent).unwrap(),
    ),
    "{\"intent\":\"{\\\"input\\\":{\\\"text\\\":\\\"é\\\\r\\\\n\\\",\\\"é\\\":null},\\\"kind\\\":\\\"program\\\",\\\"parameters\\\":null}\",\"phase\":\"preparing\",\"reference\":\"{\\\"epoch\\\":\\\"original-é\\\",\\\"nonce\\\":\\\"é\\\\r\\\\n\\\"}\",\"version\":\"actql-native-client-submitted-intent-row/0.1\"}",
  )
  let original = admit_client_submitted_run_admission_wire(
    submitted_run_record_fixture,
  ).unwrap()
  assert_eq(
    @utf8.decode(
      client_submitted_intent_journal_row_body(
        reference,
        intent,
        run_admission=Some(original),
      ).unwrap(),
    ),
    "{\"intent\":\"{\\\"input\\\":{\\\"text\\\":\\\"é\\\\r\\\\n\\\",\\\"é\\\":null},\\\"kind\\\":\\\"program\\\",\\\"parameters\\\":null}\",\"phase\":\"ready\",\"reference\":\"{\\\"epoch\\\":\\\"original-é\\\",\\\"nonce\\\":\\\"é\\\\r\\\\n\\\"}\",\"run_admission\":\"{\\\"admitted_revision\\\":\\\"9007199254740993\\\",\\\"request\\\":\\\"{\\\\\\\"authority_scope_cid\\\\\\\":\\\\\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\\\\\",\\\\\\\"caller_input_intent_cid\\\\\\\":\\\\\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\\\\\",\\\\\\\"caller_request_id\\\\\\\":\\\\\\\"caller-é\\\\\\\",\\\\\\\"intent_fingerprint_cid\\\\\\\":\\\\\\\"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010\\\\\\\",\\\\\\\"logical_request_scope_cid\\\\\\\":\\\\\\\"sha256:11db8fa880c5aaf9c54a60dffecdb102d4b7c0cfbeb4ea3c0b86eb8b46f0b2c6\\\\\\\",\\\\\\\"parameter_values_cid\\\\\\\":\\\\\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\\\\\",\\\\\\\"program_definition_cid\\\\\\\":\\\\\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\\\\\"}\\\",\\\"run_definition_cid\\\":\\\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\\\"}\",\"version\":\"actql-native-client-submitted-intent-row/0.1\"}",
  )
}

///|
test "observed submitted row requests original constructor backing before encoding large admitted intent" {
  let intent = prepare_client_submitted_intent(
    "{\"input\":{\"text\":\"" +
    "x".repeat(70000) +
    "\"},\"kind\":\"aql\",\"parameters\":null}",
    100000,
    64,
    8,
  ).unwrap()
  // The old explicit finite codec route stays exact. A retained intent is
  // not itself a constructor debit or permission to ignore that profile.
  assert_eq(
    client_submitted_intent_journal_row_body("original-reference", intent),
    Err(CapacityExceeded),
  )
  let calls : Array[(Int, Int, Int)] = []
  let denied = client_submitted_intent_journal_row_body(
    "original-reference",
    intent,
    before_construction=Some((bytes, nodes, depth) => {
      calls.push((bytes, nodes, depth))
      Err(CapacityExceeded)
    }),
  )
  assert_eq(denied, Err(CapacityExceeded))
  assert_eq(calls.length(), 1)
  assert_true(calls[0].0 > intent.wire_bytes)
  assert_eq((calls[0].1, calls[0].2), (16, 2))
  // Explicit constructor port only; this fixture does not establish Native
  // Read backing, its physical allocator, COMMIT or normal acceptance.
  let body = client_submitted_intent_journal_row_body(
    "original-reference",
    intent,
    before_construction=Some((bytes, nodes, depth) => {
      if (bytes, nodes, depth) == calls[0] {
        Ok(())
      } else {
        Err(Encoding)
      }
    }),
  ).unwrap()
  let expected = "{\"intent\":\"{\\\"input\\\":{\\\"text\\\":\\\"" +
    "x".repeat(70000) +
    "\\\"},\\\"kind\\\":\\\"aql\\\",\\\"parameters\\\":null}\",\"phase\":\"preparing\",\"reference\":\"original-reference\",\"version\":\"actql-native-client-submitted-intent-row/0.1\"}"
  assert_eq(body, @utf8.encode(expected))
}

///|
test "finite submitted row preserves earlier output overflow before invalid admission" {
  let intent = prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":{},\"parameters\":null}", 4096, 64, 8,
  ).unwrap()
  let record = journal_encoding_original()
  assert_eq(
    client_submitted_intent_journal_row_body(
      "r".repeat(262145),
      intent,
      run_admission=Some((record.request, "invalid-definition", 0L)),
    ),
    Err(CapacityExceeded),
  )
}
