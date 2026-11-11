///|
// DATA-only token shape from the independently pinned Common vector. This
// codec test neither authenticates that tag nor opens a Journal/physical Host.
fn submitted_row_construction_reference() -> NativeClientSubmissionReference {
  let token = "{\"authenticator\":\"" +
    "c".repeat(64) +
    "\",\"authorityScopeCid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"epochNonce\":\"" +
    "b".repeat(64) +
    "\",\"expiresAt\":2000,\"notBefore\":1000,\"version\":\"actql-submission-epoch/0.1\"}"
  admit_native_client_submission_reference(
    "{\"epoch\":" + token + ",\"nonce\":\"original-submit\"}",
  ).unwrap()
}

///|
fn submitted_row_construction_intent() -> @host.ClientSubmittedIntent {
  @host.prepare_client_submitted_intent(
    "{\"input\":{\"text\":\"" +
    "x".repeat(70000) +
    "\"},\"kind\":\"aql\",\"parameters\":null}",
    100000,
    64,
    8,
  ).unwrap()
}

///|
test "Native original submitted emission retains constructor backing through ready and saved CAS bodies" {
  let reference = submitted_row_construction_reference()
  let intent = submitted_row_construction_intent()
  let (_, _, request, _, definition) = submitted_run_test_input(
    reference, "original-row-construction",
  )
  let admission : NativeClientSubmittedRunAdmission = {
    request,
    run_definition_cid: @publication.publication_contract_identity(definition),
    revision: 4294967297L,
  }
  let calls : Array[(Int, Int, Int)] = []
  let reserve = Some((bytes, nodes, depth) => {
    if bytes <= @host.client_submitted_intent_wire(intent).length() ||
      nodes != 16 ||
      depth != 2 {
      return Err(@host.ClientJournalEncodingIssue::Encoding)
    }
    calls.push((bytes, nodes, depth))
    Ok(())
  })
  for state in [None, Some("original state text")] {
    let observation = if state is Some(_) {
      Some((1L, Some("original-observation")))
    } else {
      Some((0L, None))
    }
    let before = calls.length()
    let actual = submitted_intent_body(
      reference,
      intent,
      run_admission=Some(admission),
      run_state_original=state,
      run_state_observation=observation,
      before_construction=reserve,
    ).unwrap()
    assert_true(calls.length() > before)
    let expected = @host.client_submitted_intent_journal_row_body(
      reference.wire,
      intent,
      run_admission=Some((request, admission.run_definition_cid, 4294967297L)),
      run_state_original=state,
      run_state_observation=observation,
      before_construction=reserve,
    ).unwrap()
    assert_eq(actual, expected)
  }
}

///|
test "Native submitted emission preserves legacy refusal and original constructor denial" {
  let reference = submitted_row_construction_reference()
  let intent = submitted_row_construction_intent()
  assert_true(submitted_intent_body(reference, intent) is Err(CapacityExceeded))
  let calls = Ref(0)
  let denied = submitted_intent_body(
    reference,
    intent,
    before_construction=Some((_, _, _) => {
      calls.val += 1
      Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
    }),
  )
  assert_true(denied is Err(CapacityExceeded))
  assert_eq(calls.val, 1)
  assert_true(@host.client_submitted_intent_wire(intent).length() > 70000)
  // No transaction, Run acceptance, CAS or physical cleanup ACK is issued by
  // either this codec or its explicit component constructor callback.
}
