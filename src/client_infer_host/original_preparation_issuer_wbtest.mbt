///|
test "original preparation issuer rejects foreign plan before consuming its ticket" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let occurrence = @publication_host.prepared_client_infer_execution_occurrence(
    prepared, 2,
  ).unwrap()
  let foreign = call_identity_plan(fixture_prepared())
  let before = @resources.ledger_usage(ledger)
  assert_true(
    enter_original_model_preparation(
      occurrence, compiled, definition, foreign, consumer, 7L, 5L, 100L, 5L,
    )
    is Err(OriginalCapacity(@publication_host.ForeignInput)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  enter_original_model_preparation(
    occurrence, compiled, definition, plan, consumer, 7L, 5L, 100L, 5L,
  ).unwrap()
  assert_true(
    enter_original_model_preparation(
      occurrence, compiled, definition, plan, consumer, 7L, 5L, 100L, 5L,
    )
    is Err(
      OriginalCapacity(
        @publication_host.Read(
          @publication_host.Resource(@resources.SpentClaim)
        )
      )
    ),
  )
  original_preparation_test_release(ledger, read)
}
