///|
fn check_staged_values_join_oracle(program : @program.Program) -> Unit raise {
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    _ => fail("the retained staged Values JOIN control must remain closed")
  }
}

///|
// Change only binding-coordinate members in these explicit fixture tails.
// Expression field/member names and data values are not private bindings.
fn shared_values_chain_tail_oracle(tail : String) -> String {
  tail
  .replace_all(
    old="\"from\":\"aql_chain_join_2\"",
    new="\"from\":\"aql_chain_join_4\"",
  )
  .replace_all(
    old="\"as\":\"aql_chain_result_3\"",
    new="\"as\":\"aql_chain_result_5\"",
  )
}

///|
// Four original role names now occupy the shared binding inventory after
// two range reservations and two installed Values seeds. Other roles still
// consume their own slot even when this particular query does not emit them.
fn shared_values_specialized_tail_oracle(tail : String) -> String {
  tail
  .replace_all(
    old="\"from\":\"aql_join_taken\"",
    new="\"from\":\"aql_join_taken_12\"",
  )
  .replace_all(
    old="\"as\":\"aql_join_result\"",
    new="\"as\":\"aql_join_result_14\"",
  )
}
