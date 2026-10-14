///|
fn nearest_short_program(tail : String) -> Result[@program.Program, Issue] {
  with_carrier_program(
    "WITH q AS (FROM queries |> ASSERT UNIQUE BY (request_id)), c AS (FROM candidates |> ASSERT UNIQUE BY (item_id)) FROM q |> NEAREST c USING embedding K 2 AS hit" + tail,
    nearest_context(),
  )
}

///|
test "short NEAREST uses the same Common proven keys and cosine as explicit roles" {
  let short = nearest_short_program("").unwrap()
  let body = semantic(short)
  assert_true(body.contains("\"metric\":\"cosine\""))
  assert_true(body.contains("\"id\":\"request_id\""))
  assert_true(body.contains("\"id\":\"item_id\""))
  assert_true(body.contains("\"fields\":[\"request_id\",\"embedding\",\"note\",\"hit\"]"))
  let program = with_demand_program(Ok(short))
  match @check.check_parsed(program, check_environment(veca=true), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("original Values inputs")
  }
}

///|
test "short NEAREST does not invent an ID from a field name or foreign proof" {
  for text in [
    "FROM queries |> NEAREST candidates USING embedding K 1 AS hit",
    "WITH q AS (FROM queries |> ASSERT UNIQUE BY (request_id)) FROM q |> NEAREST candidates USING embedding K 1 AS hit",
    "WITH c AS (FROM candidates |> ASSERT UNIQUE BY (item_id)) FROM queries |> NEAREST c USING embedding K 1 AS hit",
  ] {
    assert_true(with_carrier_program(text, nearest_context()) is Err(UnsupportedNearest))
  }
}

///|
test "nearest query-only default differs from explicit two-scope wildcard" {
  assert_true(nearest_short_program(" |> SELECT note, hit.score AS score") is Ok(_))
  assert_true(nearest_short_program(" |> SELECT c.label") is Err(_))
  let wildcard = with_carrier_program(
    "WITH q AS (FROM queries |> ASSERT UNIQUE BY (request_id)), c AS (FROM candidates |> ASSERT UNIQUE BY (item_id)) FROM q |> NEAREST c USING embedding K 2 KEEP (*) AS hit",
    nearest_context(),
  )
  assert_true(wildcard is Err(DuplicateOutput))
  let collision = with_carrier_program(
    "FROM queries |> SELECT request_id AS hit, embedding |> NEAREST candidates AS c QUERY KEY (hit) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding K 1 AS hit",
    nearest_context(),
  )
  assert_true(collision is Err(DuplicateOutput))
}

///|
test "short nearest defaults equal explicit cosine and query-only KEEP" {
  let prefix = "WITH q AS (FROM queries |> ASSERT UNIQUE BY (request_id)), c AS (FROM candidates |> ASSERT UNIQUE BY (item_id)) FROM q |> NEAREST c AS c "
  let explicit = with_carrier_program(prefix + "QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC cosine K 2 KEEP (q.*) AS hit", nearest_context()).unwrap()
  assert_eq(semantic(nearest_short_program("").unwrap()), semantic(explicit))
}

///|
test "short nearest projects original candidate body without flattening or refetch" {
  let actual = with_carrier_program(
    "WITH q AS (FROM queries |> ASSERT UNIQUE BY (request_id)), c AS (FROM candidates |> ASSERT UNIQUE BY (item_id) |> SELECT item_id, embedding, label AS body) FROM q |> NEAREST c USING embedding K 2 AS hit |> SELECT hit.body AS body, hit.rank AS rank",
    nearest_context(),
  )
  let program = with_demand_program(actual)
  let body = semantic(program)
  assert_eq(body.split("\"values\":{").length(), 3)
  assert_true(body.contains("\"cardinality\":\"many_to_one\""))
  match @check.check_parsed(program, check_environment(veca=true), None, check_limits()) {
    Checked(checked) => {
      let pipeline = @check.unit_pipeline(checked, 0).unwrap()
      let target = @pipeline.lookup(pipeline, "aql_final_rows").unwrap()
      let rows = @pipeline.carrier_at(pipeline, target).unwrap()
      guard rows is @carrier.Relation(records) else { fail("rows") }
      assert_eq(@carrier.fields(records).map(field => @schema.reference_name(field.name)), ["body", "rank"])
      assert_true(@contract.type_equal(@carrier.field_at(records, 0).unwrap().contract.unwrap(), @contract.primitive(@contract.StringType, nullable=false), 10000))
    }
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("original retained Values")
  }
}
