///|
fn nearest_carrier_role_program(text : String) -> @program.Program raise {
  with_demand_program(with_carrier_program(text, nearest_context()))
}

///|
test "typed NEAREST keeps the four Relation and Vectors operand combinations" {
  let prefix = "WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) "
  for
    (query, candidate, roles, vector_builds) in [
      (
        "queries", "candidates", "QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
        2,
      ),
      ("queries", "cv", "QUERY KEY (request_id) VECTOR embedding ", 2),
      ("qv", "candidates", "CANDIDATE KEY (c.item_id) VECTOR c.embedding ", 2),
      ("qv", "cv", "", 2),
    ] {
    println("NEAREST_CARRIER_PAIR " + query + "/" + candidate)
    let actual = nearest_carrier_role_program(
      prefix +
      "FROM " +
      query +
      " |> NEAREST " +
      candidate +
      " AS c " +
      roles +
      "METRIC dot K 2 KEEP (c.label) AS hit",
    )
    assert_eq(
      semantic(actual).split("\"to_vectors\":{").length(),
      vector_builds + 1,
    )
    assert_eq(semantic(actual).split("\"nearest\":{").length(), 2)
    assert_true(semantic(actual).contains("\"cardinality\":\"many_to_one\""))
    match
      @check.check_parsed(
        actual,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("both inputs come from the original typed Values controls")
    }
  }
}

///|
test "Vectors NEAREST permits exact role restatement and a normal output tail" {
  let prefix = "WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) "
  for
    roles in [
      "", "QUERY KEY (qv.request_id) VECTOR qv.embedding ", "CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
      "QUERY KEY (request_id) VECTOR ((embedding)) CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
    ] {
    let actual = nearest_carrier_role_program(
      prefix +
      "FROM qv |> NEAREST cv AS c " +
      roles +
      "METRIC dot K 2 KEEP (c.label) AS hit |> SELECT label, hit.score AS score |> ORDER BY score DESC",
    )
    match
      @check.check_parsed(
        actual,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("all typed inputs are closed")
    }
  }
  for
    roles in [
      "QUERY KEY (note) VECTOR embedding ", "QUERY KEY (request_id) VECTOR note ",
      "CANDIDATE KEY (c.label) VECTOR c.embedding ", "CANDIDATE KEY (c.item_id) VECTOR c.label ",
    ] {
    assert_true(
      with_carrier_program(
        prefix + "FROM qv |> NEAREST cv AS c " + roles + "METRIC dot K 1 AS hit",
        nearest_context(),
      )
      is Err(InvalidQuery),
    )
  }
  assert_true(
    with_carrier_program(
      prefix + "FROM qv AS q |> NEAREST cv AS c METRIC dot K 1 AS hit",
      nearest_context(),
    )
    is Err(RangeAliasRequiresRelation),
  )
  assert_true(
    with_carrier_program(
      prefix +
      "FROM qv |> NEAREST cv AS c METRIC dot K 1 AS hit |> SELECT qv.hit",
      nearest_context(),
    )
    is Err(_),
  )
}

///|
test "Relation roles cannot be omitted or inferred from candidate names" {
  for
    text in [
      "WITH c AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM queries |> NEAREST c AS corpus METRIC dot K 1 AS hit",
      "WITH q AS (FROM queries |> to_vectors(id: request_id, vector: embedding)) FROM q |> NEAREST candidates AS c METRIC dot K 1 AS hit",
    ] {
    assert_true(
      with_carrier_program(text, nearest_context()) is Err(InvalidQuery),
    )
  }
}

///|
test "normalized Vectors and repeated operand occurrences keep original roles" {
  let actual = nearest_carrier_role_program(
    "WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)) FROM qv |> normalize_vectors() |> NEAREST qv AS c METRIC dot K 1 AS hit",
  )
  assert_eq(semantic(actual).split("\"values\":{").length(), 2)
  assert_eq(semantic(actual).split("\"to_vectors\":{").length(), 2)
  assert_eq(semantic(actual).split("\"normalize_vectors\":true").length(), 2)
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("both occurrences use the same original input")
  }
}
