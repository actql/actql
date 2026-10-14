///|
fn nearest_continuation_checked(text : String) -> @program.Program raise {
  let actual = match with_carrier_program(text, nearest_context()) {
    Err(InvalidQuery) => fail("NEAREST continuation: InvalidQuery")
    Err(UnsupportedNearest) => fail("NEAREST continuation: UnsupportedNearest")
    Err(UnsupportedProjection) =>
      fail("NEAREST continuation: UnsupportedProjection")
    other => with_demand_program(other)
  }
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) =>
      match @check.diagnostic_cause(issue) {
        Source(SourceView(Program(Program(Pipeline(stage, failure))))) =>
          fail(
            "nearest prefix pipeline stage \{stage}: " +
            @debug.to_string(failure.kind),
          )
        Source(
          SourceView(Program(Program(Order(stage, PipelineOrder(failure)))))
        ) =>
          fail(
            "nearest prefix order stage \{stage}: " +
            @debug.to_string(failure.kind),
          )
        Source(SourceView(Program(Program(Results(stage, failure))))) =>
          fail(
            "nearest Result stage \{stage}: " + @debug.to_string(failure.kind),
          )
        Source(Checks(BudgetExceeded)) => fail("nearest source checks budget")
        other => raise other
      }
    NeedsInputs(_) => fail("independent inputs are closed typed Values")
  }
  actual
}

///|
test "Relation WHERE and LIMIT reach NEAREST with intrinsic candidate Vectors roles" {
  let actual = nearest_continuation_checked(
    "WITH cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM queries AS q |> WHERE q.note IS NULL |> LIMIT 1 |> NEAREST cv AS c QUERY KEY (q.request_id) VECTOR q.embedding METRIC dot K 2 KEEP (q.note, c.label) AS hit |> ORDER BY hit.rank",
  )
  let body = semantic(actual)
  // Authored predicate and limit stay in the same query path; neither may be
  // replaced by TRUE, dropped or applied to the candidate input instead.
  assert_true(body.contains("\"filter\":{\"is_null\":{\"field\":\"note\"}}"))
  assert_true(body.contains("\"take\":{\"count\":1,\"offset\":0}"))
  assert_eq(body.split("\"to_vectors\":{").length(), 3)
  assert_eq(body.split("\"nearest\":{").length(), 2)
  assert_eq(body.split("\"values\":{").length(), 3)
}

///|
test "typed NEAREST set head consumes both operands once and retains shared original inputs" {
  let prefix = "WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) "
  let term = "FROM qv |> NEAREST cv AS c METRIC dot K 2 AS hit |> SELECT hit.rank AS rank"
  let actual = nearest_continuation_checked(
    prefix + term + " |> UNION ALL (" + term + ") |> ORDER BY rank",
  )
  let body = semantic(actual)
  assert_eq(body.split("\"nearest\":{").length(), 3)
  assert_eq(body.split("\"append\":{").length(), 2)
  assert_eq(body.split("\"values\":{").length(), 3)
  assert_eq(body.split("\"to_vectors\":{").length(), 3)
  assert_true(!body.contains("\"vectors\":true"))
  let stage = @program.stages(actual)[0]
  let steps = @wire.required(
    @wire.open_object(@program.stage_body(stage)).unwrap(),
    "steps",
  ).unwrap()
  assert_true(
    @wire.array_length(steps).unwrap() <=
    check_limits().compilation.structure.steps,
  )
}
