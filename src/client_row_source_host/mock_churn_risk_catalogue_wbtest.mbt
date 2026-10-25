///|
test "portable Mock catalogue keeps original declarations and exact alias membership" {
  let catalogue = prepare_mock_churn_risk_catalogue(mock_update_limits()).unwrap()
  assert_eq(mock_churn_risk_source_count(catalogue), 2)
  assert_eq(mock_churn_risk_query_alias_count(catalogue), 2)
  assert_eq(mock_churn_risk_update_alias_count(catalogue), 1)
  let salesforce = mock_churn_risk_source_at(catalogue, 0).unwrap()
  let snowflake = mock_churn_risk_source_at(catalogue, 1).unwrap()
  assert_eq(salesforce.0, "salesforce")
  assert_eq(snowflake.0, "snowflake")
  // Independent retained declarations predate the portable factory.
  assert_eq(salesforce.1.catalog, mock_update_declaration().catalog)
  assert_eq(snowflake.1.catalog, mock_document_warehouse().catalog)
  let query = mock_churn_risk_query_alias_at(catalogue, 0).unwrap()
  assert_eq(query.0, "salesforce.accounts")
  assert_eq(physical_equal(query.1, salesforce.1), true)
  let query = mock_churn_risk_query_alias_at(catalogue, 1).unwrap()
  assert_eq(query.0, "snowflake.usage_30d")
  assert_eq(physical_equal(query.1, snowflake.1), true)
  let update = mock_churn_risk_update_alias_at(catalogue, 0).unwrap()
  assert_eq(update.0, "salesforce.Account")
  assert_eq(physical_equal(update.1, salesforce.1), true)
  assert_eq(mock_churn_risk_source_at(catalogue, -1) is None, true)
  assert_eq(mock_churn_risk_query_alias_at(catalogue, 2) is None, true)
  assert_eq(mock_churn_risk_update_alias_at(catalogue, 1) is None, true)
}

///|
test "portable Mock catalogue does not reuse another factory original" {
  let first = prepare_mock_churn_risk_catalogue(mock_update_limits()).unwrap()
  let second = prepare_mock_churn_risk_catalogue(mock_update_limits()).unwrap()
  assert_eq(
    physical_equal(
      mock_churn_risk_source_at(first, 0).unwrap().1,
      mock_churn_risk_source_at(second, 0).unwrap().1,
    ),
    false,
  )
  let original = mock_churn_risk_update_alias_at(first, 0).unwrap().1
  let actual = prepare_churn_risk_mock_update_mapping(
    original,
    mock_update_limits(),
  ).unwrap()
  let retained = prepare_churn_risk_mock_update_mapping(
    mock_update_declaration(),
    mock_update_limits(),
  ).unwrap()
  assert_eq(actual.body, retained.body)
}

///|
test "portable Mock catalogue preserves declaration refusal under original limits" {
  let small = mock_update_limits()
  assert_eq(
    prepare_mock_churn_risk_catalogue({ ..small, max_bytes: 1, }) is Err(_),
    true,
  )
  assert_eq(
    prepare_mock_churn_risk_catalogue({ ..small, max_nodes: 1, }) is Err(_),
    true,
  )
  assert_eq(
    prepare_mock_churn_risk_catalogue({ ..small, max_fields: 1, }) is Err(_),
    true,
  )
}
