///|
test "INFER submission classification retains the original source refusal" {
  let document = @source_origin.document("-- 😀\r\nINFER", 14).unwrap()
  let origin = @source_origin.range(document, 9, 14).unwrap()
  let issues : Array[(@query_program.InferKeyLabelIssue, String)] = [
    (MissingCorrespondence, "source_rejected"),
    (DuplicateSlot, "source_rejected"),
    (EmptyOrAmbiguousLabel, "source_invalid_input"),
    (ReservedRole, "source_invalid_input"),
    (DuplicateLabel, "source_invalid_input"),
  ]
  let generated = @source_origin.range(document, 9, 14, kind=Generated).unwrap()
  for origin in [Some(origin), Some(generated), None] {
    for (issue, expected) in issues {
      assert_eq(
        client_source_preparation_issue_code(
          Frontend(QueryLowering(InferKeyLabel(issue, origin))),
        ),
        expected,
      )
    }
  }
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(QueryLowering(UnsupportedInfer)),
    ),
    "source_rejected",
  )
}
