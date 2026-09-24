///|
/// Both providers use the common issuance/capture owner, while their issuer
/// lifetimes and exact transport observations remain independent.
test "broad evidence custody keeps provider issuers independent" {
  let salesforce = salesforce_issued_fixture()
  let duckdb = broad_issuer_fixture()
  let salesforce_attempt = salesforce_issued_read(salesforce)
  let duckdb_attempt = broad_issued_attempt(duckdb)
  let salesforce_identity = @salesforce_query.salesforce_broad_attempt_identity(
    salesforce_attempt,
  )
  let duckdb_identity = @duckdb_query.duckdb_broad_attempt_identity(
    duckdb_attempt,
  ).unwrap()
  assert_true(salesforce_identity.0 != duckdb_identity.0)

  broad_issued_run(duckdb, duckdb_attempt)
  let duckdb_records = @duckdb_query.issue_duckdb_broad_records(
    duckdb_attempt,
    query_material_limits(),
  ).unwrap()
  let duckdb_observation = @duckdb_query.capture_duckdb_broad_query(
    duckdb.issuer,
    duckdb_attempt,
    duckdb_records,
    query_capture_limits(),
  ).unwrap()
  salesforce.settled.push(salesforce_attempt)
  let salesforce_observation = @salesforce_query.complete_salesforce_broad_capture(
    salesforce.issuer,
    salesforce_attempt,
    salesforce_completion_limits(),
  ).unwrap()
  assert_true(
    @salesforce_query.salesforce_broad_observation_cid(salesforce_observation) !=
    @duckdb_query.duckdb_broad_observation_cid(duckdb_observation),
  )
  assert_true(
    @salesforce_query.complete_salesforce_broad_capture(
      salesforce.issuer,
      salesforce_attempt,
      salesforce_completion_limits(),
    )
    is Err(_),
  )
  assert_true(
    @duckdb_query.capture_duckdb_broad_query(
      duckdb.issuer,
      duckdb_attempt,
      duckdb_records,
      query_capture_limits(),
    )
    is Err(AlreadyCaptured),
  )

  @salesforce_query.close_salesforce_broad_issuer(salesforce.issuer)
  assert_true(
    @salesforce_query.salesforce_broad_captured_source(
      salesforce.issuer,
      salesforce_attempt,
      salesforce_observation,
    )
    is Err(Unavailable),
  )
  assert_true(
    @duckdb_query.verify_duckdb_broad_records(
      duckdb.issuer,
      duckdb_attempt,
      duckdb_records,
    )
    is Ok(_),
  )
  @duckdb_query.close_duckdb_query_issuer(duckdb.issuer)
  assert_true(
    @duckdb_query.verify_duckdb_broad_records(
      duckdb.issuer,
      duckdb_attempt,
      duckdb_records,
    )
    is Err(IssuerClosed),
  )
}
