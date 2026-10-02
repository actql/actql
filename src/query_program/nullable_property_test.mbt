///|
test "nullable object projection reaches checked common property lowering without infer" {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"payload":{"type":"object","nullable":true,"fields":{"risk":{"type":"string","nullable":false},"reason":{"type":"string","nullable":true}}}},"rows":[{"payload":{"risk":"high","reason":null}},{"payload":null}]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["payload"],
        graph_bindings: [],
      },
    ],
  }
  let program = compile(
    @query.parse_query(
      "FROM objects |> SELECT payload.risk AS risk",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  let checked = match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(owner) => owner
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed Values input")
  }
  let pipeline = @check.unit_pipeline(checked, 0).unwrap()
  let prepared = @lower.prepare(pipeline, {
    max_nodes: 1000,
    max_references: 1000,
    max_work: 10000,
    max_identifier_bytes: 10000,
  }).unwrap()
  let bound = @lower.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=10000,
  ).unwrap()
  let expression = @lower.lower_expression(bound, 1, 0, {
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }).unwrap()
  assert_true(
    @lower.expression_body(expression) is @lower.Property(_, "risk", 1),
  )
  assert_true(@lower.expression_contract(expression).nullable)
}
