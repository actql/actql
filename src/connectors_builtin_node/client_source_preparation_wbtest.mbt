///|
test "Source preparation retains known lowerer input violations for disclosure" {
  let issues : Array[@query_program.Issue] = [
    InvalidQuery,
    GraphExpected(None),
    RangeAliasRequiresRelation,
    UnknownColumn,
    AmbiguousColumn,
    AmbiguousRelation,
    DuplicateOutput,
  ]
  for issue in issues {
    assert_eq(
      client_source_preparation_issue_code(Frontend(QueryLowering(issue))),
      "source_invalid_input",
    )
  }
}

///|
test "Source-free UNNEST probe rejection is an input violation before submission" {
  let context = @source_frontend.bind_query_context([], "visible-environment").unwrap()
  let issue = match
    @source_frontend.lower(
      "SELECT element.* FROM UNNEST(@missing.items) element",
      Sql,
      Some(context),
      source_path="submitted.sql",
    ) {
    Err(issue) => issue
    Ok(_) => fail("an undeclared parameter cannot establish UNNEST fields")
  }
  assert_true(
    issue
    is QueryLowering(
      ExpressionTyping({ kind: UnknownParameter("missing"), .. })
    ),
  )
  assert_eq(
    client_source_preparation_issue_code(Frontend(issue)),
    "source_invalid_input",
  )
}

///|
test "Source preparation does not classify protected resolution as invalid input" {
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(QueryLowering(UnknownRelation)),
    ),
    "source_unresolved",
  )
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(QueryLowering(InvalidContext)),
    ),
    "source_rejected",
  )
  assert_eq(client_source_preparation_issue_code(Limit), "source_limit")
}

///|
test "Source preparation keeps unsupported forms separate from input violations" {
  let issues : Array[@query_program.Issue] = [
    UnsupportedProjection,
    UnsupportedGrouping,
    UnsupportedAggregate,
    UnsupportedHaving,
    UnsupportedOrdering,
    UnsupportedAnalytic,
    UnsupportedSet,
    UnsupportedJoin,
    UnsupportedCte,
    UnsupportedGraph,
  ]
  for issue in issues {
    assert_eq(
      client_source_preparation_issue_code(Frontend(QueryLowering(issue))),
      "source_implementation_limit",
    )
  }
  // Unsupported carriers remain distinct from these recognized frontend
  // forms and from the typed authored-input violations checked above.
  for
    issue in [
      UnsupportedCarrier,
      CommandTargetOriginalsUnavailable,
      RecordTargetOriginalsUnavailable,
    ] {
    assert_eq(client_source_preparation_issue_code(issue), "source_unsupported")
  }
}

///|
test "original scalar function refusal keeps its implementation-limit category" {
  let context = @source_frontend.bind_query_context([], "visible-environment").unwrap()
  let issue = match
    @source_frontend.lower(
      "SELECT UNKNOWN_FUNCTION(1) AS n",
      Sql,
      Some(context),
    ) {
    Err(issue) => issue
    Ok(_) => fail("the original unsupported function must remain a refusal")
  }
  assert_true(
    issue is QueryLowering(Expression({ issue: UnsupportedFunction, .. })),
  )
  assert_eq(
    client_source_preparation_issue_code(Frontend(issue)),
    "source_implementation_limit",
  )
}

///|
test "original frontend construction budget keeps its analysis-limit category" {
  let context = @source_frontend.bind_query_context([], "visible-environment").unwrap()
  let text = "SELECT 1 AS n" + " UNION ALL SELECT 1 AS n".repeat(50)
  let issue = match @source_frontend.lower(text, Sql, Some(context)) {
    Err(issue) => issue
    Ok(_) => fail("the unchanged original construction bound must refuse")
  }
  assert_true(issue is QueryLowering(Admission(Structure(StageLimit, ..))))
  assert_eq(
    client_source_preparation_issue_code(Frontend(issue)),
    "source_analysis_limit",
  )
}
