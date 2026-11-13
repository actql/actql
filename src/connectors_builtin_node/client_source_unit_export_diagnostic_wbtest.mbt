///|
// Pure DATA projection of the returned Result, without entering any runtime
// owner or including a body, compiler constructor name or caller message.
test "Source Unit export diagnostic projects actual returned issue only" {
  let cases : Array[
    (@client_local_host.ClientEffectUnitPreparationIssue, String),
  ] = [
    (Run(ForeignOriginal), "run"),
    (Export(MissingResult), "export.missing_result"),
    (Export(ForeignOutput), "export.foreign_output"),
    (Export(Export(Unavailable)), "export.completed.unavailable"),
    (
      Export(Export(NotCellRepresentation)),
      "export.completed.not_cell_representation",
    ),
    (Export(Export(InvalidTarget)), "export.completed.invalid_target"),
    (Export(Export(NotFinished)), "export.completed.not_finished"),
    (Export(Export(Closed)), "export.completed.closed"),
    (Export(Export(ForeignMaterial)), "export.completed.foreign_material"),
    (Export(Export(CanonicalRow)), "export.completed.canonical_row"),
  ]
  for (issue, expected) in cases {
    let result : Result[
      @strategy.CapturedEffectLocalResultExport,
      @client_local_host.ClientEffectUnitPreparationIssue,
    ] = Err(issue)
    assert_eq(
      client_program_effect_model_unit_result_export_issue_kind(result),
      Some(expected),
    )
  }
}

///|
test "Source Unit artifact diagnostic retains the original typed failure family" {
  let cases : Array[
    (@client_local_host.ClientEffectUnitPreparationIssue, String),
  ] = [
    (Run(ForeignOriginal), "run.foreign_original"),
    (Run(InsufficientCapacity), "run.insufficient_capacity"),
    (Run(Retired), "run.retired"),
    (Artifact(ForeignOwner), "artifact.foreign_owner"),
    (Artifact(ForeignDefinition), "artifact.foreign_definition"),
    (Artifact(ForeignExport), "artifact.foreign_export"),
    (Artifact(ForeignRun), "artifact.foreign_run"),
  ]
  for (issue, expected) in cases {
    let result : Result[
      @publication_host.ClientEffectLocalResultArtifact,
      @client_local_host.ClientEffectUnitPreparationIssue,
    ] = Err(issue)
    assert_eq(
      client_program_effect_model_unit_result_artifact_issue_kind(result),
      Some(expected),
    )
  }
}

///|
test "actual Model component call-scope issue retains its typed original family" {
  let cases : Array[(@publication_host.ClientInferCallScopeIssue, String)] = [
    (ForeignOwner, "call_scope.foreign_owner"),
    (ForeignInput, "call_scope.foreign_input"),
    (UnsupportedBindings, "call_scope.unsupported_bindings"),
    (Encoding, "call_scope.encoding"),
  ]
  for (issue, expected) in cases {
    assert_eq(
      client_program_infer_call_scope_issue_kind(
        @infer_host.Issue::CallScope(issue),
      ),
      Some(expected),
    )
  }
  assert_true(
    client_program_infer_call_scope_issue_kind(
      @infer_host.Issue::InvalidAdvance,
    )
    is None,
  )
}
