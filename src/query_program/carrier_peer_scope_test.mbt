///|
fn carrier_peer_program(text : String) -> @program.Program raise {
  with_demand_program(with_carrier_program(text, nearest_context()))
}

///|
test "Vectors to Relation retains a visible candidate peer for NEAREST" {
  let prefix = "WITH v AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), candidate_rows AS (SELECT item_id, embedding, label FROM candidates) "
  let suffix = " |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 KEEP (c.label) AS hit"
  let actual = carrier_peer_program(prefix + "FROM v |> vectors()" + suffix)
  let explicit = carrier_peer_program(
    prefix.replace(old="candidate_rows AS", new="rows AS (FROM v |> vectors()), candidate_rows AS") + "FROM rows" + suffix,
  )
  for program in [actual, explicit] {
    assert_eq(semantic(program).split("\"values\":{").length(), 3)
    assert_eq(semantic(program).split("\"nearest\":{").length(), 2)
    assert_true(semantic(program).contains("\"cardinality\":\"many_to_one\""))
    match @check.check_parsed(program, check_environment(veca=true), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("the declared typed vector controls have no provider")
    }
  }
}
