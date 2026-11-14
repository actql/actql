///|
// Actual phased Request parser/checker/compiler and its SAME Prepared owner.
// This component supplies a nominal Ledger, not physical Native backing,
// Account/Run admission, old state or a cleanup ACK.
test "ordinary direct forty UNION branches retain original normalization through same Request" {
  let statements : Array[String] = []
  for index in 0..<40 {
    statements.push("SELECT \{index} AS n")
  }
  let sql = statements.join(" UNION ALL ")
  let (environment, publication) = request_query_publication_fixture()
  let (parent, input) = native_driver_parent(sql)
  let captured = request_native_test_value(
    "{\"format\":\"sql\",\"text\":\"" + sql + "\"}",
  )
  let prepared = prepare_request_default_source_computation_check(
    parent,
    input,
    captured,
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
    // Exact installed Native submitted Source result convention.
    public_primary=false,
  )
  match prepared {
    Err(CheckOutcome(@checked.Rejected(diagnostic))) =>
      match @checked.diagnostic_cause(diagnostic) {
        Units(ProofConversion(cause)) => raise cause
        Units(cause) => raise cause
        cause => raise cause
      }
    Err(issue) => {
      let original : Error = issue
      fail(@debug.to_string(original))
    }
    Ok(_) => ()
  }
  assert_eq(
    finish_request_checked_computation(parent, input, environment, publication).unwrap(),
    Pure,
  )
  let original = parent.compiled_program.unwrap()
  let result = @publication_host.issue_prepared_client_local_normalization(
    original,
  )
  let cause = match result {
    Ok(_) => "issued"
    Err(CommonInventory(BudgetExceeded)) => "common-inventory-budget"
    Err(CommonInventory(InvalidLimits)) => "common-inventory-limits"
    Err(CommonInventory(CompletionObserved)) => "common-completion"
    Err(CommonInventory(ForeignOriginal)) => "common-foreign-original"
    Err(CommonInventory(UnsupportedRequirement)) => "common-unsupported"
    Err(Evidence(_)) => "evidence-encoding"
    Err(_) => "other-typed-issue"
  }
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(cause, "issued")
}
