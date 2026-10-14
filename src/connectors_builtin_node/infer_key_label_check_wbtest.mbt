///|
fn infer_key_label_check_report(
  issue : @query_program.InferKeyLabelIssue,
  origin : @source_origin.Origin?,
) -> String {
  check_outcome_json(
    [check_query_finding(QueryLowering(InferKeyLabel(issue, origin)))],
    Report,
    "ctx:infer-key-label",
    "corr:infer-key-label",
    {
      scope: BoundInput,
      structured_program: false,
      program_pointer: None,
      source_revision: "rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      source_bytes: 14,
      declarations_revision: None,
      declarations_bytes: 0,
      parameters_revision: None,
      parameters_bytes: 0,
    },
  )
}

///|
test "INFER missing correspondence and duplicate slots retain located implementation limits" {
  // UTF-8 bytes, rather than UTF-16 offsets: the emoji precedes a CRLF.
  let document = @source_origin.document("-- 😀\r\nINFER", 14).unwrap()
  let origin = @source_origin.range(document, 9, 14).unwrap()
  let issues : Array[@query_program.InferKeyLabelIssue] = [
    MissingCorrespondence,
    DuplicateSlot,
  ]
  for issue in issues {
    assert_true(
      check_query_finding(QueryLowering(InferKeyLabel(issue, Some(origin))))
      is LocatedImplementationLimit(Some((9, 14))),
    )
    let report = infer_key_label_check_report(issue, Some(origin))
    assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
    assert_true(
      report.contains(
        "\"limits\":[{\"code\":\"implementation_limit\",\"location\":{\"document_id\":\"source\",\"end_byte\":14,\"kind\":\"text\",\"precision\":\"exact\",\"revision\":\"rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"start_byte\":9}}]",
      ),
      msg=report,
    )
    assert_true(report.contains("\"reasons\":[]"), msg=report)
    assert_true(!report.contains("\"facts\""), msg=report)
    assert_true(!report.contains("function_lowering_unresolved"), msg=report)
    assert_eq(
      client_source_preparation_issue_code(
        Frontend(QueryLowering(InferKeyLabel(issue, Some(origin)))),
      ),
      "source_rejected",
    )
  }
}

///|
test "INFER label conflicts project existing invalid arguments with authored byte locations" {
  let document = @source_origin.document("-- 😀\r\nINFER", 14).unwrap()
  let origin = @source_origin.range(document, 9, 14).unwrap()
  let issues : Array[@query_program.InferKeyLabelIssue] = [
    EmptyOrAmbiguousLabel,
    ReservedRole,
    DuplicateLabel,
  ]
  for issue in issues {
    assert_true(
      check_query_finding(QueryLowering(InferKeyLabel(issue, Some(origin))))
      is ExpressionViolation("invalid_arguments", Some((9, 14))),
    )
    let report = infer_key_label_check_report(issue, Some(origin))
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(report.contains("\"limits\":[]"), msg=report)
    assert_true(
      report.contains(
        "\"reasons\":[{\"code\":\"query_expression_invalid\",\"facts\":{\"issue\":\"invalid_arguments\"},\"location\":{\"document_id\":\"source\",\"end_byte\":14,\"kind\":\"text\",\"precision\":\"exact\",\"revision\":\"rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"start_byte\":9}}]",
      ),
      msg=report,
    )
    assert_true(!report.contains("implementation_limit"), msg=report)
    assert_true(!report.contains("function_lowering_unresolved"), msg=report)
    assert_eq(
      client_source_preparation_issue_code(
        Frontend(QueryLowering(InferKeyLabel(issue, Some(origin)))),
      ),
      "source_invalid_input",
    )
  }
}

///|
test "INFER projection withholds generated and absent origins for all label issues" {
  let document = @source_origin.document("-- 😀\r\nINFER", 14).unwrap()
  let generated = @source_origin.range(document, 9, 14, kind=Generated).unwrap()
  let cases : Array[(@query_program.InferKeyLabelIssue, String, String)] = [
    (MissingCorrespondence, "undetermined", "source_rejected"),
    (DuplicateSlot, "undetermined", "source_rejected"),
    (EmptyOrAmbiguousLabel, "invalid", "source_invalid_input"),
    (ReservedRole, "invalid", "source_invalid_input"),
    (DuplicateLabel, "invalid", "source_invalid_input"),
  ]
  for origin in [Some(generated), None] {
    for (issue, verdict, source_code) in cases {
      let finding = check_query_finding(
        QueryLowering(InferKeyLabel(issue, origin)),
      )
      assert_eq(check_verdict([finding]), verdict)
      assert_true(
        finding
        is (LocatedImplementationLimit(None)
        | ExpressionViolation("invalid_arguments", None)),
      )
      let report = infer_key_label_check_report(issue, origin)
      assert_true(!report.contains("\"location\""), msg=report)
      assert_true(!report.contains("\"start_byte\""), msg=report)
      assert_true(!report.contains("\"pointer\""), msg=report)
      assert_true(!report.contains("function_lowering_unresolved"), msg=report)
      assert_eq(
        client_source_preparation_issue_code(
          Frontend(QueryLowering(InferKeyLabel(issue, origin))),
        ),
        source_code,
      )
    }
  }
}

///|
test "explicit INFER key refusals retain the unlocated unsupported projection" {
  let text = "/*😀é*/\r\nSELECT DISTINCT 'id' AS `VaLuE` |> INFER `model-task:risk-score.v1` ITEM KEY (`VaLuE`) INPUT (text = 'urgent') AS assessment"
  let context = @source_frontend.bind_query_context([], "visible-environment").unwrap()
  for format in ["sql", "aql-text"] {
    let selected = @source_frontend.select_format(format).unwrap()
    guard @source_frontend.lower(text, selected, Some(context))
      is Err(QueryLowering(UnsupportedInfer)) else {
      fail("the explicit authored tuple must retain UnsupportedInfer")
    }
    let report = binding_check_report(text, format)
    assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
    assert_true(
      report.contains("\"limits\":[{\"code\":\"implementation_limit\"}]"),
      msg=report,
    )
    assert_true(report.contains("\"reasons\":[]"), msg=report)
    assert_true(!report.contains("\"location\""), msg=report)
    assert_true(!report.contains("\"facts\""), msg=report)
  }
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(QueryLowering(UnsupportedInfer)),
    ),
    "source_rejected",
  )
}
