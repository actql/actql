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

///|
// DATA validation and byte-preserving UPDATE preparation over the same
// original declarations. Physical file/current/claim duties stay with Host.
#export_name("clientProgramMockChurnRiskAdmitTargetDocument")
pub fn client_program_mock_churn_risk_admit_target_document(
  salesforce : @client_row_source_host.RowDeclaration,
  snowflake : @client_row_source_host.RowDeclaration,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_work : Int,
) -> Result[
  @client_row_source_host.MockTargetDocument,
  @client_row_source_host.RowSourceIssue,
] {
  @client_row_source_host.admit_mock_churn_risk_target_document(
    salesforce,
    snowflake,
    bytes,
    { max_bytes, max_nodes, max_depth, max_rows, },
    max_work,
  )
}

///|
#export_name("clientProgramMockChurnRiskObserveTarget")
pub fn client_program_mock_churn_risk_observe_target(
  document : @client_row_source_host.MockTargetDocument,
  declaration : @client_row_source_host.RowDeclaration,
  identity : String,
) -> Result[
  @client_row_source_host.MockTargetRow,
  @client_row_source_host.RowSourceIssue,
] {
  @client_row_source_host.observe_mock_churn_risk_target(
    document, declaration, identity,
  )
}

///|
#export_name("clientProgramMockChurnRiskTargetBefore")
pub fn client_program_mock_churn_risk_target_before(
  row : @client_row_source_host.MockTargetRow,
) -> String? {
  @client_row_source_host.mock_churn_risk_target_before(row)
}

///|
#export_name("clientProgramMockChurnRiskTargetVersion")
pub fn client_program_mock_churn_risk_target_version(
  row : @client_row_source_host.MockTargetRow,
) -> String? {
  @client_row_source_host.mock_churn_risk_target_version(row)
}

///|
#export_name("clientProgramMockChurnRiskPrepareTargetUpdate")
pub fn client_program_mock_churn_risk_prepare_target_update(
  document : @client_row_source_host.MockTargetDocument,
  row : @client_row_source_host.MockTargetRow,
  expected_version : String,
  value_wire : String,
  max_work : Int,
) -> Result[Bytes, @client_row_source_host.RowSourceIssue] {
  @client_row_source_host.prepare_mock_churn_risk_target_update(
    document, row, expected_version, value_wire, max_work,
  )
}
