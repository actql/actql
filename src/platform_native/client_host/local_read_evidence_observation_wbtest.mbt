///|
// Real legacy SQLite/Crypto supplies the initial committed evidence. Controlled
// command flags exercise only private DATA matching/retirement below; they do
// not supply an operational Read pair, receiver or permission to disclose.
test "confirmed read evidence facts match only the same command binding and target" {
  let (host, binding, original, facts, _) = read_evidence_fixture(
    "read-evidence-operation-facts",
  )
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let admission = binding
    .retain_read_admission(original, facts, policy)
    .unwrap()
  let bodies = binding
    .read_admission_preimages(original, facts, policy)
    .unwrap()
  let capture = prepare_native_local_journal_capture(
    host.session,
    local_journal_test_library(),
    binding.crypto,
    100.0,
    8,
    8388608L,
  )
  capture.opening = JournalAcquired(host)
  let selected = { ..binding, capture: Some(capture), }
  // A committed packet alone cannot enter a command that is not active.
  selected.remember_read_evidence(original, facts, bodies, admission)
  assert_eq(capture.read_evidence.length(), 0)
  capture.read_callback_active = true
  capture.read_facts_valid = true
  host.journal.operation_active = true
  selected.remember_read_evidence(original, facts, bodies, admission)
  selected.remember_read_evidence(original, facts, bodies, admission)
  assert_eq(capture.read_evidence.length(), 1)
  assert_true(
    selected.observed_read_evidence(original, facts, bodies) is Some(value) &&
    value.egress_admission_cid == admission.egress_admission_cid,
  )
  let foreign_binding = { ..selected, connection: selected.connection, }
  assert_true(
    foreign_binding.observed_read_evidence(original, facts, bodies) is None,
  )
  assert_true(
    selected.observed_read_evidence(
      original,
      { ..facts, request: { ..facts.request, namespace_id: "foreign", }, },
      bodies,
    )
    is None,
  )
  assert_true(
    selected.observed_read_evidence(
      original,
      { ..facts, request: { ..facts.request, attempt_id: "foreign", }, },
      bodies,
    )
    is None,
  )
  assert_true(
    selected.observed_read_evidence(original, facts, {
      ..bodies,
      egress: { ..bodies.egress, wire: "changed", },
    })
    is None,
  )
  // A relevant mutation spends the observation even if its old typed key is
  // offered again. Failure/end additionally cuts all operation references.
  selected.forget_read_evidence()
  assert_eq(capture.read_evidence.capacity(), 0)
  assert_true(selected.observed_read_evidence(original, facts, bodies) is None)
  selected.remember_read_evidence(original, facts, bodies, admission)
  capture.clear_read_operation_facts()
  capture.read_facts_valid = true
  assert_true(selected.observed_read_evidence(original, facts, bodies) is None)
  assert_eq(capture.read_evidence.capacity(), 0)
  capture.read_callback_active = false
  host.journal.operation_active = false
  host.close().unwrap()
}
