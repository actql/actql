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

///|
fn subgraph_projection_source(call : String) -> String {
  "WITH n AS (SELECT 2 AS node_key, 20 AS p UNION ALL SELECT 1 AS node_key, IF(TRUE, 10, CAST(NULL AS FLOAT64)) AS p) , e AS (SELECT 11 AS edge_key, 1 AS src_key, 2 AS dst_key, 20 AS w UNION ALL SELECT 10 AS edge_key, 1 AS src_key, 2 AS dst_key, 10 AS w UNION ALL SELECT 13 AS edge_key, 2 AS src_key, 2 AS dst_key, 30 AS w) , g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p)) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src_key) REFERENCES N DESTINATION KEY (dst_key) REFERENCES N LABEL R PROPERTIES (w)))) , selected AS (FROM g |> node_rows() |> SELECT id, node_key) FROM g |> " +
  call +
  " |> node_rows() |> SELECT node_key, p |> ORDER BY node_key |> RESULT answer"
}

///|
test "checked Subgraph support gap retains its original implementation-limit category" {
  let context = @source_frontend.bind_query_context([], "visible-environment").unwrap()
  let text = subgraph_projection_source(
    "subgraph(nodes: {where: {literal: true}})",
  )
  let issue = match @source_frontend.lower(text, Text, Some(context)) {
    Err(issue) => issue
    Ok(_) => fail("the original where selector is not implemented")
  }
  assert_true(
    issue
    is QueryLowering(
      BindingPreparation(
        LocalProgram(
          Pipeline(
            _,
            { kind: GraphMatch(Structure(UnsupportedGraphOperation)), .. }
          )
        )
      )
    ),
  )
  assert_eq(
    client_source_preparation_issue_code(Frontend(issue)),
    "source_implementation_limit",
  )
  let annotated = match
    @source_frontend.lower_with_source(
      text,
      Text,
      Some(context),
      source_path="submitted.aql",
    ) {
    Err(issue) => issue
    Ok(_) => fail("diagnostic origins cannot change the support gap")
  }
  assert_true(
    annotated
    is QueryLowering(
      BindingPreparationSource(
        LocalProgram(
          Pipeline(
            _,
            { kind: GraphMatch(Structure(UnsupportedGraphOperation)), .. }
          )
        ),
        _
      )
    ),
  )
  assert_eq(
    client_source_preparation_issue_code(Frontend(annotated)),
    "source_implementation_limit",
  )
}

///|
test "checked malformed Subgraph and protected bindings do not become support gaps" {
  let context = @source_frontend.bind_query_context([], "visible-environment").unwrap()
  for
    call in [
      "subgraph()", "subgraph(nodes: {ids: []})", "subgraph(nodes: {from: selected, id: `node_key`})",
      "subgraph(nodes: {from: selected, id: `id`}, edges: {literal: 1})",
    ] {
    let issue = match
      @source_frontend.lower(
        subgraph_projection_source(call),
        Text,
        Some(context),
      ) {
      Err(issue) => issue
      Ok(_) => fail("the original malformed selector must remain rejected")
    }
    assert_true(
      issue is QueryLowering(BindingPreparation(LocalProgram(Pipeline(_, _)))),
    )
    assert_eq(
      client_source_preparation_issue_code(Frontend(issue)),
      "source_rejected",
    )
  }
  assert_eq(
    client_source_preparation_issue_code(
      Frontend(QueryLowering(InvalidContext)),
    ),
    "source_rejected",
  )
  assert_eq(
    client_source_preparation_issue_code(Publication),
    "source_rejected",
  )
  assert_eq(
    client_source_preparation_issue_code(Declarations),
    "source_declarations",
  )
}
