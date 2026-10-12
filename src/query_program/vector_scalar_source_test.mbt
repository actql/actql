///|
fn vector_scalar_seed() -> String {
  (
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"left_vector":{"type":"vector","dimensions":2,"nullable":false},"right_vector":{"type":"vector","dimensions":2,"nullable":true}},"rows":[{"id":1,"left_vector":[3,4],"right_vector":[0,0]},{"id":2,"left_vector":[1,0],"right_vector":[0,1]},{"id":3,"left_vector":[1,1],"right_vector":null}]},"as":"vectors"}
  )
}

///|
fn vector_scalar_context() -> Context {
  let step = @wire.admit(
    @source.parse_json(
      vector_scalar_seed(),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "vectors", quoted: false, }],
        name: "vectors",
        source: GeneratedValues(step),
        visible_fields: ["id", "left_vector", "right_vector"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn vector_scalar_control(expression : String) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.vector_scalar\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    vector_scalar_seed() +
    ",{\"from\":\"vectors\",\"derive\":{\"value\":" +
    expression +
    "}},{\"select\":[\"id\",\"value\"]},{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn vector_scalar_expressions() -> Array[(String, String)] {
  [
    (
      "VECTOR_COSINE_SIMILARITY", "{\"vector_score\":{\"left\":{\"field\":\"left_vector\"},\"right\":{\"field\":\"right_vector\"},\"metric\":\"cosine\"}}",
    ),
    (
      "VECTOR_INNER_PRODUCT", "{\"vector_score\":{\"left\":{\"field\":\"left_vector\"},\"right\":{\"field\":\"right_vector\"},\"metric\":\"dot\"}}",
    ),
    (
      "VECTOR_L2_DISTANCE", "{\"negate\":{\"vector_score\":{\"left\":{\"field\":\"left_vector\"},\"right\":{\"field\":\"right_vector\"},\"metric\":\"l2\"}}}",
    ),
    (
      "VECTOR_CONCAT", "{\"vector_concat\":[{\"field\":\"left_vector\"},{\"field\":\"right_vector\"}]}",
    ),
  ]
}

///|
test "independent vector scalar Programs reach the existing VecA common checker" {
  for (_, expression) in vector_scalar_expressions() {
    match
      @check.check_parsed(
        vector_scalar_control(expression),
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed typed vector control")
    }
  }
}

///|
test "adopted vector scalar text preserves common expression bodies without a vector cast" {
  for (name, expression) in vector_scalar_expressions() {
    let actual = compile(
      @query.parse_query(
        "SELECT id, " +
        name +
        "(left_vector,right_vector) AS value FROM vectors ORDER BY id",
        syntax_limits(),
      ).unwrap(),
      vector_scalar_context(),
      construction_limits(),
    ).unwrap()
    guard @json.parse(with_carrier_argument(actual, "derive")) is Object(fields) else {
      fail("one derived scalar object")
    }
    assert_eq(fields.length(), 1)
    for (_, value) in fields {
      assert_eq(value, @json.parse(expression))
    }
    match
      @check.check_parsed(
        actual,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(checked) => {
        let schema = @pipeline.output_schema(
          @check.unit_pipeline(checked, 0).unwrap(),
        ).unwrap()
        assert_eq(@schema.field_count(schema), 2)
        assert_eq(@schema.field_reference_name_at(schema, 0), Some("id"))
        assert_eq(@schema.field_reference_name_at(schema, 1), Some("value"))
        let expected_contract = if name == "VECTOR_CONCAT" {
          "{\"dimensions\":4,\"element_type\":\"f32\",\"nullable\":true,\"type\":\"vector\"}"
        } else {
          "{\"nullable\":true,\"type\":\"number\"}"
        }
        assert_eq(
          @contract.stringify_checked(
            @schema.lookup(schema, Unqualified("value")).unwrap(),
            1000,
            100,
            10,
          ),
          expected_contract,
        )
      }
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("closed typed vector source")
    }
  }
}

///|
test "vector scalar text keeps the common typed vector refusal for ordinary arrays" {
  let actual = compile(
    @query.parse_query(
      "SELECT id, VECTOR_INNER_PRODUCT([1,0], left_vector) AS value FROM vectors ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    vector_scalar_context(),
    construction_limits(),
  ).unwrap()
  guard @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    )
    is Rejected(diagnostic) else {
    fail("an ordinary ARRAY is not a typed Vector")
  }
  guard @check.diagnostic_cause(diagnostic)
    is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
    raise @check.diagnostic_cause(diagnostic)
  }
  assert_true(issue.kind is Operation(Expression(TypeMismatch("typed vector"))))
}

///|
test "vector scalar text retains common exact dimension checks" {
  let actual = compile(
    @query.parse_query(
      "SELECT id, VECTOR_INNER_PRODUCT(left_vector, VECTOR_CONCAT(right_vector,right_vector)) AS value FROM vectors ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    vector_scalar_context(),
    construction_limits(),
  ).unwrap()
  guard @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    )
    is Rejected(diagnostic) else {
    fail("dimension 2 cannot score against dimension 4")
  }
  guard @check.diagnostic_cause(diagnostic)
    is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
    raise @check.diagnostic_cause(diagnostic)
  }
  assert_true(
    issue.kind is Operation(Expression(TypeMismatch("equal vector dimensions"))),
  )
}
