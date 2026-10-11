///|
fn distinct_order_receiver_seed() -> String {
  (
    #|{"values":{"schema":{"score":{"type":"number","nullable":true}},"rows":[{"score":10},{"score":20},{"score":10},{"score":null}]},"as":"objects"}
  )
}

///|
fn distinct_order_receiver_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      distinct_order_receiver_seed(),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["score"],
        graph_bindings: [],
      },
    ],
  }
}

///|
// Both oracles project and DISTINCT numeric outputs before the ORDER helper.
// Only the invalid one asks the shared checker for a numeric object's member.
fn distinct_order_receiver_expected(invalid : Bool) -> @program.Program {
  let receiver = if invalid {
    (
      #|{"property":{"name":"score","value":{"field":"payload"}}}
    )
  } else {
    (
      #|{"field":"original_score"}
    )
  }
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    distinct_order_receiver_seed() +
    (
      #|,{"from":"objects","derive":{"aql_query_expr_1":{"negate":{"field":"score"}}}},{"select":[{"original_score":"score"},{"payload":"aql_query_expr_1"}]},{"distinct":["original_score","payload"]},{"derive":{"aql_pipe_sort_4":{"add":[
    ) +
    receiver +
    (
      #|,{"literal":1}]}}},{"sort":[{"field":"aql_pipe_sort_4","dir":"asc","nulls":"last"}]},{"select":["original_score","payload"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["original_score","payload"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn assert_distinct_order_receiver_type_refusal(
  program : @program.Program,
) -> Unit raise {
  guard @check.check_parsed(program, check_environment(), None, check_limits())
    is Rejected(error) else {
    fail("a numeric output's property must reach the common type rejection")
  }
  guard @check.diagnostic_cause(error)
    is Source(SourceView(Program(Program(Pipeline(stage, issue))))) else {
    raise @check.diagnostic_cause(error)
  }
  assert_eq(stage, 0)
  assert_eq(
    issue.kind,
    @pipeline.Operation(
      @relation.Expression(@typing.TypeMismatch("closed object receiver")),
    ),
  )
}

///|
test "DISTINCT ORDER shadowed range preserves a numeric alias's property type rejection" {
  let expected = distinct_order_receiver_expected(true)
  assert_distinct_order_receiver_type_refusal(expected)
  for receiver_path in ["payload.score", "(payload).score", "`PAYLOAD`.`score`"] {
    let actual = compile(
      @query.parse_query(
        "SELECT DISTINCT score AS original_score, -score AS payload FROM objects AS payload ORDER BY " +
        receiver_path +
        " + 1 NULLS LAST",
        syntax_limits(),
      ).unwrap(),
      distinct_order_receiver_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=receiver_path)
    assert_distinct_order_receiver_type_refusal(actual)
  }
}

///|
test "DISTINCT ORDER keeps a selected input path when its range is not shadowed" {
  let expected = distinct_order_receiver_expected(false)
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  let actual = compile(
    @query.parse_query(
      "SELECT DISTINCT score AS original_score, -score AS payload FROM objects AS original ORDER BY original.score + 1 NULLS LAST",
      syntax_limits(),
    ).unwrap(),
    distinct_order_receiver_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}
