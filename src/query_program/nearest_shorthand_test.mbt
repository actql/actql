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
