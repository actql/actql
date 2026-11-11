// Same-runtime installed Snowflake response plumbing. These wrappers expose
// the original Core types; no opaque value crosses another runtime or wire.

///|
#export_name("clientProgramSnowflakeResponseLimits")
pub fn client_program_snowflake_response_limits(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_columns : Int,
  max_name_units : Int,
  max_handle_units : Int,
  max_partitions : Int,
  max_rows : Int,
  max_total_rows : Int64,
) -> @snowflake_response.ResponseLimits {
  {
    max_bytes,
    max_nodes,
    max_depth,
    max_columns,
    max_name_units,
    max_handle_units,
    max_partitions,
    max_rows,
    max_total_rows,
  }
}

///|
#export_name("clientProgramSnowflakeDescriptionLimits")
pub fn client_program_snowflake_description_limits(
  max_columns : Int,
  max_name_bytes : Int,
  max_schema_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @snowflake_description.DescriptionLimits {
  { max_columns, max_name_bytes, max_schema_bytes, max_nodes, max_depth, }
}

///|
#export_name("clientProgramSnowflakeDeclarationLimits")
pub fn client_program_snowflake_declaration_limits(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_views : Int,
  max_fields : Int,
) -> @client_row_source_host.RowDeclarationLimits {
  { max_bytes, max_nodes, max_depth, max_views, max_fields, }
}

///|
#export_name("clientProgramSnowflakeDescribeTable")
pub fn client_program_snowflake_describe_table(
  database : String,
  schema : String,
  table : String,
  bodies : Array[Bytes],
  response_limits : @snowflake_response.ResponseLimits,
  description_limits : @snowflake_description.DescriptionLimits,
) -> Result[@snowflake_description.TableDescription, @snowflake_read.ReadIssue] {
  if bodies.is_empty() {
    return Err(Response(InvalidResponse))
  }
  let target = match
    @snowflake_description.table_target(
      database,
      schema,
      table,
      description_limits.max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Description(issue))
  }
  let original = match
    @snowflake_response.project_result_set(bodies[0], response_limits) {
    Ok(value) => value
    Err(issue) => return Err(Response(issue))
  }
  let partitions = []
  for index in 1..<bodies.length() {
    let page = match
      @snowflake_response.project_partition(
        bodies[index],
        original,
        index,
        response_limits,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Response(issue))
    }
    partitions.push(page)
  }
  @snowflake_description.project_table_description(
    target, original, partitions, description_limits,
  ).map_err(issue => @snowflake_read.Description(issue))
}

///|
#export_name("clientProgramSnowflakeGenerateReadDeclaration")
pub fn client_program_snowflake_generate_read_declaration(
  description : @snowflake_description.TableDescription,
  resource : String,
  connector : String,
  revision : String,
  description_limits : @snowflake_description.DescriptionLimits,
  declaration_limits : @client_row_source_host.RowDeclarationLimits,
) -> Result[@client_row_source_host.RowDeclaration, @snowflake_read.ReadIssue] {
  let fields = []
  for index in 0..<@snowflake_description.description_column_count(description) {
    fields.push(
      @snowflake_description.description_column_name(description, index).unwrap(),
    )
  }
  let projection = match
    @snowflake_description.prepare_read_projection(
      description, fields, description_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Description(issue))
  }
  @snowflake_description.generate_read_declaration(
    projection, resource, connector, revision, declaration_limits,
  ).map_err(issue => @snowflake_read.Host(issue))
}

///|
#export_name("clientProgramSnowflakePrepareRead")
pub fn client_program_snowflake_prepare_read(
  description : @snowflake_description.TableDescription,
  declaration : @client_row_source_host.RowDeclaration,
  requirement : @planning.QueryRequirement,
  query_contract : String,
  evidence_contract : String,
  description_limits : @snowflake_description.DescriptionLimits,
  declaration_limits : @client_row_source_host.RowDeclarationLimits,
) -> Result[@snowflake_read.PreparedRead, @snowflake_read.ReadIssue] {
  @snowflake_read.prepare_declared_read(
    description, declaration, requirement, query_contract, evidence_contract, description_limits,
    declaration_limits,
  )
}

///|
#export_name("clientProgramSnowflakeReadAcquisition")
pub fn client_program_snowflake_read_acquisition(
  read : @snowflake_read.PreparedRead,
) -> @client_row_source_host.RowAcquisition {
  @snowflake_read.prepared_read_acquisition(read)
}

///|
#export_name("clientProgramSnowflakeBorrowRead")
pub fn client_program_snowflake_borrow_read(
  prepared : @snowflake_read.PreparedRead,
  run : @client_row_source_host.RowRun,
  limits : @snowflake_response.ResponseLimits,
  max_contract_pairs : Int,
) -> Result[@snowflake_read.Read, @snowflake_read.ReadIssue] {
  @snowflake_read.borrow_accounted_read(
    prepared, run, limits, max_contract_pairs,
  )
}

///|
#export_name("clientProgramSnowflakePrepareStatement")
pub fn client_program_snowflake_prepare_statement(
  read : @snowflake_read.Read,
  request_id : String,
  warehouse : String,
  role : String,
  timeout_seconds : Int,
  max_requests : Int,
  max_request_bytes : Int,
) -> Result[@snowflake_read.StatementRead, @snowflake_read.StatementIssue] {
  @snowflake_read.prepare_statement_read(
    read, request_id, warehouse, role, timeout_seconds, max_requests, max_request_bytes,
  )
}

///|
#export_name("clientProgramSnowflakeNextRequest")
pub fn client_program_snowflake_next_request(
  value : @snowflake_read.StatementRead,
) -> Result[@snowflake_read.StatementRequest?, @snowflake_read.StatementIssue] {
  @snowflake_read.next_statement_request(value)
}

///|
#export_name("clientProgramSnowflakeRequestMaterial")
pub fn client_program_snowflake_request_material(
  request : @snowflake_read.StatementRequest,
) -> (String, String, String?, Int) {
  (
    @snowflake_read.statement_request_method(request),
    @snowflake_read.statement_request_path(request),
    @snowflake_read.statement_request_body(request),
    @snowflake_read.statement_request_sequence(request),
  )
}

///|
#export_name("clientProgramSnowflakeAttemptRequest")
pub fn client_program_snowflake_attempt_request(
  value : @snowflake_read.StatementRead,
  request : @snowflake_read.StatementRequest,
) -> Result[Unit, @snowflake_read.StatementIssue] {
  @snowflake_read.attempt_statement_request(value, request)
}

///|
#export_name("clientProgramSnowflakeChargeResponse")
pub fn client_program_snowflake_charge_response(
  value : @snowflake_read.StatementRead,
  request : @snowflake_read.StatementRequest,
  status : Int,
  body : Bytes,
) -> Result[@snowflake_read.StatementResponse, @snowflake_read.StatementIssue] {
  @snowflake_read.charge_statement_response(value, request, status, body)
}

///|
#export_name("clientProgramSnowflakeAcceptResponse")
pub fn client_program_snowflake_accept_response(
  value : @snowflake_read.StatementRead,
  response : @snowflake_read.StatementResponse,
  body : Bytes,
) -> Result[Unit, @snowflake_read.StatementIssue] {
  @snowflake_read.accept_charged_statement_response(value, response, body)
}

///|
#export_name("clientProgramSnowflakeRejectResponse")
pub fn client_program_snowflake_reject_response(
  value : @snowflake_read.StatementRead,
  response : @snowflake_read.StatementResponse,
) -> Result[Unit, @snowflake_read.StatementIssue] {
  @snowflake_read.reject_statement_response(value, response)
}

///|
#export_name("clientProgramSnowflakeResponseUnknown")
pub fn client_program_snowflake_response_unknown(
  value : @snowflake_read.StatementRead,
  request : @snowflake_read.StatementRequest,
) -> Result[Unit, @snowflake_read.StatementIssue] {
  @snowflake_read.mark_statement_response_unknown(value, request)
}

///|
#export_name("clientProgramSnowflakeStatementComplete")
pub fn client_program_snowflake_statement_complete(
  value : @snowflake_read.StatementRead,
) -> Bool {
  @snowflake_read.statement_read_complete(value)
}

///|
#export_name("clientProgramSnowflakeStatementOriginal")
pub fn client_program_snowflake_statement_original(
  value : @snowflake_read.StatementRead,
) -> (String, String?) {
  (
    @snowflake_read.statement_read_request_id(value),
    @snowflake_read.statement_read_handle(value),
  )
}

///|
#export_name("clientProgramSnowflakeReadUsage")
pub fn client_program_snowflake_read_usage(
  value : @snowflake_read.Read,
) -> (Int, Int64) {
  @snowflake_read.result_read_usage(value)
}

///|
#export_name("clientProgramSnowflakeInterruptRead")
pub fn client_program_snowflake_interrupt_read(
  value : @snowflake_read.Read,
) -> Unit {
  @snowflake_read.interrupt_result_read(value)
}

///|
#export_name("clientProgramSnowflakeRetireReadBorrow")
pub fn client_program_snowflake_retire_read_borrow(
  value : @snowflake_read.Read,
) -> Result[Unit, @snowflake_read.ReadIssue] {
  @snowflake_read.retire_borrowed_read(value)
}

///|
#export_name("clientProgramSnowflakeBindReadTransport")
pub fn client_program_snowflake_bind_read_transport(
  value : @snowflake_read.Read,
  observe_stop : () -> Bool,
) -> Result[Unit, @snowflake_read.ReadIssue] {
  @snowflake_read.bind_borrowed_read_transport(value, observe_stop)
}

///|
/// Unit means the original refusal was recorded, never response acceptance.
#export_name("clientProgramSnowflakeRecordDecoderRefusal")
pub fn client_program_snowflake_record_decoder_refusal(
  value : @snowflake_read.StatementRead,
  response : @snowflake_read.StatementResponse,
) -> Result[Unit, @snowflake_read.StatementIssue] {
  match @snowflake_read.reject_statement_response(value, response) {
    Err(InvalidResponse) => Ok(())
    other => other
  }
}

///|
/// Unit records the original loss; it grants no successful completion or ACK.
#export_name("clientProgramSnowflakeRecordResponseLoss")
pub fn client_program_snowflake_record_response_loss(
  value : @snowflake_read.StatementRead,
  request : @snowflake_read.StatementRequest,
) -> Result[Unit, @snowflake_read.StatementIssue] {
  match @snowflake_read.mark_statement_response_unknown(value, request) {
    Err(TransportUnknown) => Ok(())
    other => other
  }
}

///|
#export_name("clientProgramSnowflakeReadDeclarationConstructionCapacity")
pub fn client_program_snowflake_read_declaration_construction_capacity(
  body_lengths : Array[Int],
  encoded_units : Int,
  target_units : Int,
  resource_units : Int,
  connector_units : Int,
  revision_units : Int,
  response : @snowflake_response.ResponseLimits,
  description : @snowflake_description.DescriptionLimits,
  declaration : @client_row_source_host.RowDeclarationLimits,
) -> @execution.ExecutionCapacity? {
  @snowflake_description.read_declaration_construction_capacity(
    body_lengths, encoded_units, target_units, resource_units, connector_units, revision_units,
    response, description, declaration,
  )
}
