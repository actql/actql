///|
// Pure projection of the actual returned Core issue. No state, current port,
// body decoder, validator or Model/Source operation is entered here.
test "original Model acquired failure kind projects the actual typed returned result" {
  let cases : Array[
    (@publication_host.ClientEffectAcquiredEvidenceIssue, String),
  ] = [
    (Invocation(MissingUnit), "invocation.missing_unit"),
    (Invocation(NotSourceFree), "invocation.not_source_free"),
    (Invocation(ForeignCapturedInput), "invocation.foreign_captured_input"),
    (Invocation(MissingCapturedInput), "invocation.missing_captured_input"),
    (
      Invocation(ForeignSourceObservation),
      "invocation.foreign_source_observation",
    ),
    (
      Invocation(IncompleteResultImports),
      "invocation.incomplete_result_imports",
    ),
    (Invocation(ForeignResultImport), "invocation.foreign_result_import"),
    (Invocation(Encoding), "invocation.encoding"),
    (Relation(WrongScope), "relation"),
    (Dependency(ForeignBody), "dependency"),
  ]
  for (issue, expected) in cases {
    let result : Result[
      @publication_host.ClientEffectModelAcquiredEvidence,
      @publication_host.ClientEffectAcquiredEvidenceIssue,
    ] = Err(issue)
    assert_eq(
      client_program_original_model_acquired_effect_evidence_issue_kind(result),
      Some(expected),
    )
  }
}
