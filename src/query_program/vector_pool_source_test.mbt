///|
fn vector_pool_control(
  reduction : String,
  relation : Bool,
  cohort? : Bool = false,
) -> @program.Program {
  // Authored independently of source compilation. A dynamic assertion supplies
  // Relation member-key evidence; Vectors retains its intrinsic identity role.
  let input = if cohort { "grouped" } else { "candidates" }
  let prefix = if relation {
    "{\"from\":\"" + input + "\",\"assert_rows\":{\"unique_by\":[\"item_id\"]},\"as\":\"members\"}"
  } else {
    "{\"from\":\"" + input + "\",\"to_vectors\":{\"id\":\"item_id\",\"vector\":\"embedding\"},\"as\":\"members\"}"
  }
  let grouping = if cohort { "cohort" } else { "label" }
  let body = "{\"by\":[\"" +
    grouping +
    "\"],\"method\":\"" +
    reduction +
    "\",\"output_id\":\"pooled_id\"" +
    (if relation { ",\"vector\":\"embedding\"" } else { "" }) +
    "}"
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.vector_pool\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    "{\"values\":{\"schema\":{\"item_id\":{\"type\":\"string\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"item_id\":\"b\",\"embedding\":[0,1],\"label\":\"second\"},{\"item_id\":\"a\",\"embedding\":[1,0],\"label\":\"first\"}]},\"as\":\"candidates\"}," +
    (if cohort {
      "{\"from\":\"candidates\",\"derive\":{\"cohort\":{\"literal\":1}}},{\"select\":[\"item_id\",\"embedding\",\"cohort\"],\"as\":\"grouped\"},"
    } else {
      ""
    }) +
    prefix +
    ",{\"from\":\"members\",\"pool_vectors\":" +
    body +
    ",\"as\":\"pooled\"},{\"from\":\"pooled\",\"vectors\":true},{\"sort\":[{\"field\":\"" +
    grouping +
    "\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"" +
    grouping +
    "\",\"pooled_id\",\"embedding\",\"member_count\"],\"as\":\"answer\"}],\"results\":{\"rows\":{\"from\":\"answer\",\"fields\":[\"" +
    grouping +
    "\",\"pooled_id\",\"embedding\",\"member_count\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn vector_pool_checked(program : @program.Program) -> Unit raise {
  match
    @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed vector control")
  }
}

///|
test "P2 independent pooling Programs use existing Relation and Vectors common owners" {
  for relation in [false, true] {
    for reduction in ["sum", "mean", "max"] {
      vector_pool_checked(vector_pool_control(reduction, relation))
    }
  }
}

///|
test "P2 pooling source retains argument roles and output columns across both Carriers" {
  for relation in [false, true] {
    for reduction in ["sum", "mean", "max"] {
      let prefix = if relation {
        "FROM candidates |> ASSERT UNIQUE BY (item_id)"
      } else {
        "FROM candidates |> to_vectors(id: item_id, vector: embedding)"
      }
      let text = "WITH members AS (" +
        prefix +
        "), pooled AS (FROM members |> pool_vectors(by: [LABEL], method: '" +
        reduction +
        "', output_id: pooled_id" +
        (if relation { ", vector: EMBEDDING" } else { "" }) +
        ")), rows AS (FROM pooled |> vectors()) SELECT label, pooled_id, embedding, member_count FROM rows ORDER BY label"
      let actual = with_carrier_program(text, nearest_context()).unwrap()
      let expected = vector_pool_control(reduction, relation)
      assert_eq(
        with_carrier_argument(actual, "pool_vectors"),
        with_carrier_argument(expected, "pool_vectors"),
      )
      assert_eq(with_carrier_argument(actual, "vectors"), "true")
      vector_pool_checked(actual)
    }
  }
}

///|
fn vector_pool_issue(text : String) -> @pipeline.IssueKind raise {
  match with_carrier_program(text, nearest_context()) {
    Err(BindingPreparation(LocalProgram(Pipeline(0, diagnostic)))) =>
      diagnostic.kind
    Err(_) => fail("Unexpected refusal boundary")
    Ok(_) => fail("Invalid pool must not be admitted")
  }
}

///|
test "P2 pooling keeps common member key role and collision refusals" {
  assert_eq(
    vector_pool_issue(
      "FROM candidates |> pool_vectors(vector: embedding, by: [label], method: 'sum') |> vectors() |> SELECT label",
    ),
    MissingKeyEvidence,
  )
  let prefix = "WITH members AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM members |> "
  let tail = " |> vectors() |> SELECT label"
  let cases : Array[(String, @pipeline.IssueKind)] = [
    (
      "pool_vectors(by: [label, LABEL], method: 'sum')",
      Vector(DuplicatePoolField(Unqualified("label"))),
    ),
    ("pool_vectors(by: [], method: 'sum')", Vector(InvalidBody)),
    ("pool_vectors(by: [label], method: 'SUM')", Vector(InvalidBody)),
    (
      "pool_vectors(by: [label], method: 'sum', output_id: embedding)",
      Vector(OutputCollision("embedding")),
    ),
    (
      "pool_vectors(by: [label], method: 'sum', vector: label)",
      Vector(InvalidRole(InvalidRole(Unqualified("label")))),
    ),
  ]
  for (call, expected) in cases {
    assert_eq(vector_pool_issue(prefix + call + tail), expected)
  }
  assert_true(
    with_carrier_program(
      prefix + "pool_vectors(by: [missing], method: 'sum')" + tail,
      nearest_context(),
    )
    is Err(UnknownColumn),
  )
  for
    call in [
      "pool_vectors(by: [label])", "pool_vectors(by: [label], method: 'sum', id: 'override')",
    ] {
    assert_true(
      with_carrier_program(prefix + call + tail, nearest_context())
      is Err(InvalidQuery),
    )
  }
}

///|
test "P2 prepared two-member public pool sources retain derived grouping and empty schema" {
  for relation in [false, true] {
    for empty in [false, true] {
      let prefix = "FROM candidates" +
        (if empty { " |> WHERE FALSE" } else { "" }) +
        " |> SELECT item_id, embedding, 1 AS cohort |> " +
        (if relation {
          "ASSERT UNIQUE BY (item_id)"
        } else {
          "to_vectors(id: item_id, vector: embedding)"
        })
      let text = "WITH members AS (" +
        prefix +
        "), pooled AS (FROM members |> pool_vectors(by: [COHORT], method: \"mean\", output_id: pooled_id" +
        (if relation { ", vector: EMBEDDING" } else { "" }) +
        ")), rows AS (FROM pooled |> vectors()) SELECT cohort, pooled_id, embedding, member_count FROM rows ORDER BY cohort"
      let actual = match with_carrier_program(text, nearest_context()) {
        Ok(program) => program
        Err(UnsupportedGraph) => fail("Carrier call follows Relation projection")
        Err(UnknownColumn) => fail("Unknown derived group column")
        Err(UnsupportedProjection) => fail("Unsupported derived group projection")
        Err(BindingPreparation(LocalProgram(Pipeline(index, diagnostic)))) =>
          fail(index.to_string() + ": " + @debug.to_string(diagnostic.kind))
        Err(_) => fail("Other pool preparation failure")
      }
      let expected = vector_pool_control("mean", relation, cohort=true)
      vector_pool_checked(expected)
      vector_pool_checked(actual)
      assert_eq(
        with_carrier_argument(actual, "pool_vectors"),
        with_carrier_argument(expected, "pool_vectors"),
      )
    }
  }
}
