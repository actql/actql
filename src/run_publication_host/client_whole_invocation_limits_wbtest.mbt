///|
// The Run is genuinely bound; no Source capture or callback is needed to
// reject invalid limits before selecting its Direct acquisition inventory.
test "Whole invocation preserves invalid-limit precedence before Source selection" {
  let prepared = multi_source_prepared(pure_three_source_document)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let run = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    run, "whole-limit-order", "original-run", "2026-11-11T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let invoke = (bytes, nodes, depth) => {
    issue_client_compiled_whole_sources_invocation(
      run,
      definition,
      [],
      [],
      [],
      [],
      [],
      "sha256:" + "a".repeat(64),
      prepared_client_publication_data_policy_cid(prepared).unwrap(),
      "2026-11-11T00:00:00.000Z",
      "2026-11-11T00:00:01.000Z",
      bytes,
      nodes,
      depth,
    )
  }
  for
    (bytes, nodes, depth) in [
      (0, 100000, 100),
      (-1, 100000, 100),
      (1000000, 0, 100),
      (1000000, -1, 100),
      (1000000, 100000, 0),
      (1000000, 100000, -1),
    ] {
    assert_true(
      invoke(bytes, nodes, depth) is Err(@publication.RunEvidenceInvalidLimits),
    )
  }
  // With valid limits this same empty inventory must still be refused;
  // neither the limit check nor metadata selection creates observations.
  assert_true(
    invoke(1000000, 100000, 100)
    is Err(@publication.RunEvidenceReferenceMismatch("source_coverage")),
  )
}
