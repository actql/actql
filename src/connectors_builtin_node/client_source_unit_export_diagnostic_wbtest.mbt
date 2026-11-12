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
