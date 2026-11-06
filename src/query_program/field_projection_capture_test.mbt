///|
fn field_projection_capture_context() -> Context {
  let declaration = @wire.admit(
    @source.parse_json(
      (
        #|{"carrier":"relation","schema":{"Id":{"type":"string","nullable":false},"Name":{"type":"string","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"city":{"type":"string","nullable":true}}}}}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..fixture_context(),
    captured_stage: Some("capture"),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: Captured(declaration),
        visible_fields: ["Id", "Name", "payload"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "captured field projection does not publish an unselected structured column" {
  let actual = compile(
    @query.parse_query(
      "SELECT r.Id AS Id, r.Name AS previous_name FROM records AS r WHERE r.Id = 'selected'",
      syntax_limits(),
    ).unwrap(),
    field_projection_capture_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_true(body.contains("\"fields\":[\"Id\",\"previous_name\"]"))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("a projected scalar Result has no unresolved order")
  }
}

///|
test "captured parameter projection retains its one original declaration" {
  let actual = compile(
    @query.parse_query(
      "SELECT r.Id AS Id, @p AS next_value FROM records AS r WHERE r.Id = 'selected'",
      syntax_limits(),
    ).unwrap(),
    {
      ..field_projection_capture_context(),
      parameter_declarations: Some(number_parameter_declarations()),
    },
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_eq(body.split("\"$param\":\"p\"").length(), 2)
  assert_true(body.contains("\"fields\":[\"Id\",\"next_value\"]"))
  match
    @check.check_parsed(
      actual,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the same supplied Parameter remains bound")
  }
}

///|
test "captured structured publication still requires a real order witness" {
  let actual = compile(
    @query.parse_query("SELECT payload FROM records", syntax_limits()).unwrap(),
    field_projection_capture_context(),
    construction_limits(),
  ).unwrap()
  guard @check.check_parsed(actual, check_environment(), None, check_limits())
    is Rejected(issue) else {
    fail("projection cannot make an object CanonicalOrderable")
  }
  guard @check.diagnostic_cause(issue)
    is Source(SourceView(Program(Program(Order(0, ResultOrder(order)))))) else {
    raise @check.diagnostic_cause(issue)
  }
  assert_true(order.kind is UnresolvedOrder)
}

///|
test "later projections and function calls keep their original capture placement" {
  for
    text in [
      "FROM records |> SELECT Id, payload |> SELECT Id", "SELECT Id, LOWER(Name) AS name FROM records",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      field_projection_capture_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_true(body.contains("\"fields\":[\"Id\",\"Name\",\"payload\"]"))
    guard @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(issue) else {
      fail("the nonselected placement keeps the original full capture")
    }
    guard @check.diagnostic_cause(issue)
      is Source(SourceView(Program(Program(Order(0, ResultOrder(order)))))) else {
      raise @check.diagnostic_cause(issue)
    }
    assert_true(order.kind is UnresolvedOrder)
  }
}
