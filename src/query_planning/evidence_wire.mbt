///|
/// Shared canonical record codec. Serialization is not issuance authority.
priv enum QueryRecordRole {
  SourceValidation
  Filter
  Select
}

///|
priv struct QueryActualAccess {
  scope_cid : String
  provider_scope_cid : String?
  received_rows : Int
  received_fields : Array[String]
  received_bytes : Int
}

///|
priv struct QueryOutputIdentity {
  contract_cid : String
  rows_cid : String
  row_count : Int
}

///|
priv struct QueryRecordPayload {
  requirement_cid : String
  snapshot : (String, String)?
  scan_scope_cid : String
  access : QueryActualAccess
  output : QueryOutputIdentity
}

///|
fn emit_query_optional_cid(
  value : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match value {
    None => @encode.null_value(writer)
    Some(cid) => @encode.string_value(writer, cid)
  }
}

///|
fn emit_query_access(
  access : QueryActualAccess,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "provider_scope_cid")
  emit_query_optional_cid(access.provider_scope_cid, writer)
  @encode.key(writer, "received_bytes")
  @encode.number_value(writer, access.received_bytes.to_double())
  @encode.key(writer, "received_fields")
  @encode.begin_array(writer)
  for field in access.received_fields {
    @encode.string_value(writer, field)
  }
  @encode.end_array(writer)
  @encode.key(writer, "received_rows")
  @encode.number_value(writer, access.received_rows.to_double())
  @encode.key(writer, "scope_cid")
  @encode.string_value(writer, access.scope_cid)
  @encode.end_object(writer)
}

///|
fn emit_query_output(
  output : QueryOutputIdentity,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "contract_cid")
  @encode.string_value(writer, output.contract_cid)
  @encode.key(writer, "row_count")
  @encode.number_value(writer, output.row_count.to_double())
  @encode.key(writer, "rows_cid")
  @encode.string_value(writer, output.rows_cid)
  @encode.end_object(writer)
}

///|
fn emit_query_snapshot(
  snapshot : (String, String)?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match snapshot {
    None => @encode.null_value(writer)
    Some((contract, token)) => {
      @encode.begin_object(writer)
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, contract)
      @encode.key(writer, "token_cid")
      @encode.string_value(writer, token)
      @encode.end_object(writer)
    }
  }
}

///|
fn emit_query_record(
  payload : QueryRecordPayload,
  issuer : String,
  attempt : String,
  role : QueryRecordRole,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "actual_access")
  emit_query_access(payload.access, writer)
  @encode.key(writer, "attempt")
  @encode.string_value(writer, attempt)
  @encode.key(writer, "issuer")
  @encode.string_value(writer, issuer)
  @encode.key(writer, "output")
  emit_query_output(payload.output, writer)
  @encode.key(writer, "requirement_cid")
  @encode.string_value(writer, payload.requirement_cid)
  @encode.key(writer, "role")
  @encode.string_value(
    writer,
    match role {
      SourceValidation => "source_validation"
      Filter => "filter"
      Select => "select"
    },
  )
  @encode.key(writer, "scan_scope_cid")
  @encode.string_value(writer, payload.scan_scope_cid)
  @encode.key(writer, "snapshot")
  emit_query_snapshot(payload.snapshot, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-process-evidence/0.1")
  @encode.end_object(writer)
}
