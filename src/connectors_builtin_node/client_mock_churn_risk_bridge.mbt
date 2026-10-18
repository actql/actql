///|
// Existing Common Mapping constructor over the same original declaration.
// No copied SourceView, CREATE relabelling, current permission or Host identity.
#export_name("clientProgramMockChurnRiskUpdateMapping")
pub fn client_program_mock_churn_risk_update_mapping(
  declaration : @client_row_source_host.RowDeclaration,
) -> Result[String, @client_row_source_host.RowMappingIssue] {
  @client_row_source_host.prepare_churn_risk_mock_update_mapping(declaration, {
    max_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
    max_views: 1,
    max_fields: 5,
  }).map(mapping => mapping.body)
}

///|
#export_name("clientProgramMockChurnRiskAcceptChargedDocument")
pub fn client_program_mock_churn_risk_accept_charged_document(
  run : @client_row_source_host.RowRun,
  charge : @client_row_source_host.RowPageCharge,
  acquisition : @client_row_source_host.RowAcquisition,
  salesforce : @client_row_source_host.RowDeclaration,
  snowflake : @client_row_source_host.RowDeclaration,
  bytes : Bytes,
  max_work : Int,
) -> Result[Int, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.accept_charged_mock_churn_risk_document(
    run, charge, acquisition, salesforce, snowflake, bytes, max_work,
  )
}
