///|
/// Physical journal checks only, not public Run or runtime restoration proof.
test "failed completed successor restoration cannot settle missing or pending custody" {
  let (_, journal, request, _, _) = cleanup_test_open(
    "completed-successor-failed",
  )
  let task = new_holder_task_custody(
    request,
    None,
    None,
    Some("original-producer"),
  )
  task.restoration_failed = true
  assert_false(holder_completed_restoration_settled(task, journal))
  ignore(journal.accept(request).unwrap())
  assert_false(holder_completed_restoration_settled(task, journal))
  ignore(journal.request_cancellation(request).unwrap())
  assert_false(holder_completed_restoration_settled(task, journal))
  assert_true(confirm_unstarted_consumer_cleanup(journal, request))
  assert_true(holder_completed_restoration_settled(task, journal))
  assert_true(journal.close())
}

///|
test "completed successor selection rejects absent accepted and producer-only envelopes" {
  let (journal, request, _, _, _, _, _) = completed_output_custody_fixture(
    "completed-successor-not-consumer",
  )
  let admission : @resident_host.ResidentRunAdmission = {
    expressions: { text_time: false, veca: false, },
    operations: {
      rela: true,
      sga: false,
      tea: false,
      calendar: false,
      text_rank: false,
    },
    manifests: @host.admit_client_compilation_manifests(
      @environment.compiler_grammar_manifest_wire(),
      @environment.compiler_barrier_contract_manifest_wire(),
      10000,
      1000,
      20,
    ).unwrap(),
    limits: {
      preparation: @host.client_standard_program_preparation_limits(),
      sequence: @host.client_standard_values_sequence_limits(),
      max_sequence_steps: 1000,
      max_sequence_work: 1000,
      max_evidence_bytes: 1000000,
      max_evidence_nodes: 100000,
      max_evidence_depth: 100,
    },
    source: None,
  }
  let (_, missing, incoming, _, _) = cleanup_test_open(
    "completed-successor-no-envelope",
  )
  assert_eq(
    completed_holder_successor_parent(
      missing, admission, incoming, "2026-10-06T00:00:00.000Z",
    ),
    None,
  )
  ignore(missing.accept(incoming).unwrap())
  assert_eq(
    completed_holder_successor_parent(
      missing, admission, incoming, "2026-10-06T00:00:00.000Z",
    ),
    None,
  )
  assert_true(missing.close())
  assert_eq(
    completed_holder_successor_parent(
      journal, admission, request, "2026-10-06T00:00:00.000Z",
    ),
    None,
  )
  assert_true(journal.close())
}
