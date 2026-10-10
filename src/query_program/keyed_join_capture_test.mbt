///|
test "Pipe JOIN right input stays in its consumer instead of a standalone capture" {
  let base = fixture_context()
  let right = {
    ..base.inputs[0],
    name: "contents",
    relation: [{ value: "contents", quoted: false, }],
  }
  let context = {
    ..base,
    inputs: [base.inputs[0], right],
    captured_stage: Some("capture"),
  }
  // The schema fixture establishes only structural lowering. Actual keyed
  // acquisition and byte custody are exercised by the installed public tests.
  // A right Source may need the left row's keys; SELECTing it in another Stage
  // would replace its JoinRight occurrence with an invalid direct StepInput.
  for
    text in [
      "FROM orders AS o |> WHERE o.id IS NOT NULL |> JOIN contents AS c ON o.id = c.id |> SELECT o.id AS id, c.amount AS amount",
      "FROM orders AS o |> WHERE o.id IS NOT NULL |> JOIN contents AS c ON o.id = c.id |> WHERE c.amount > 0 |> SELECT o.id AS id, c.amount AS amount",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(@program.stage_count(program), 2)
    let body = semantic(program)
    assert_true(body.contains("\"contents\":{\"carrier\":\"relation\""))
    assert_true(body.contains("\"with\":\"contents\""))
    assert_false(body.contains("\"id\":\"capture_1\""))
    match
      @check.check_parsed(
        program,
        data_acquisition_environment(),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) => fail("structural schema inputs are fully declared")
    }
  }
}

///|
test "Installed LIST_FILES Pipe keeps pre-capture WHERE and keyed JOIN in one Stage" {
  let base = file_query_context(all=true)
  let right = @wire.admit(
    @source.parse_json(
      "{\"connector\":\"fixture/files\",\"resource\":\"mount\",\"view\":\"contents\"}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..base,
    captured_stage: Some("capture"),
    inputs: [
      base.inputs[0],
      {
        relation: [
          { value: "docs", quoted: false, },
          { value: "contents", quoted: false, },
        ],
        name: "contents",
        source: Captured(right),
        visible_fields: ["resource", "version", "content"],
        graph_bindings: [],
      },
    ],
  }
  // LIST_FILES resolves an input whose name includes its request identity.
  // Single-use analysis must use the original publication name instead of
  // mistaking that derived name for a shared Stage boundary. This is a
  // structural fixture, not admission of the contents SourceView contract.
  let program = compile_query_script(
    @query.parse_query_script(
      "FROM LIST_FILES(docs.invoices, paths => ['invoice.pdf']) AS f |> WHERE f.name = 'invoice.pdf' |> JOIN docs.contents AS c ON f.resource = c.resource AND f.version = c.version |> SELECT f.name AS name, c.content AS content",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(program), 1)
  let body = semantic(program)
  assert_true(body.contains("\"view\":\"listing\""))
  assert_true(body.contains("\"view\":\"contents\""))
  assert_false(body.contains("\"id\":\"capture\""))
  guard @json.parse(body) is Object(root) &&
    root["stages"] is Array(stages) &&
    stages[0] is Object(stage) &&
    stage["steps"] is Array(steps) else {
    fail("one actual consumer Stage")
  }
  let mut filter = -1
  let mut capture = -1
  let mut join = -1
  for index in 0..<steps.length() {
    if steps[index] is Object(step) {
      if step.contains("filter") {
        filter = index
      }
      if step.get("as") is Some(String("aql_join_captured")) {
        capture = index
      }
      if step.contains("join") {
        join = index
      }
    }
  }
  assert_true(filter >= 0 && filter < join)
  assert_true(filter < capture && capture < join)
  // The existing capture boundary copies all visible listing fields; it
  // must not project the right Source before its per-row keys are available.
  assert_true(body.contains("\"content\":\"right.content\""))
}
