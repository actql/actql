///|
// Canonical material only. Exact authority and successful retained measurements
// are checked by the issuer, not inferred from any of these strings/documents.
fn native_output_identity(
  measurement : DuckDBNativeMeasurement,
) -> @planning.QueryOutputIdentity {
  let (cid, _, _, rows) = @duckdb.native_receipt_digest(
    measurement.receipts,
    @duckdb.NativeResult,
  )
  {
    contract_cid: @planning.query_requirement_contracts(
      measurement.attempt.preparation.requirement,
    ).1,
    rows_cid: cid,
    row_count: rows,
  }
}

///|
fn emit_native_accesses(
  cids : Array[String],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "native_result_cid")
  @encode.string_value(writer, cids[1])
  @encode.key(writer, "validation_scan_cid")
  @encode.string_value(writer, cids[0])
  @encode.end_object(writer)
}

///|
fn emit_native_receipt(
  authority : DuckDBNativeAuthority,
  measurement : DuckDBNativeMeasurement,
  scope : String,
  role : @duckdb.NativeReceiptRole,
  fields : Array[String],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let (cid, bytes, _, rows) = @duckdb.native_receipt_digest(
    measurement.receipts,
    role,
  )
  @encode.begin_object(writer)
  @encode.key(writer, "attempt")
  @encode.string_value(writer, authority.number)
  @encode.key(writer, "issuer")
  @encode.string_value(writer, authority.issuer.name)
  @encode.key(writer, "read_view")
  @encode.string_value(writer, authority.read_view)
  @encode.key(writer, "received_bytes")
  @encode.number_value(writer, bytes.to_double())
  @encode.key(writer, "received_fields")
  @encode.begin_array(writer)
  for field in fields {
    @encode.string_value(writer, field)
  }
  @encode.end_array(writer)
  @encode.key(writer, "received_rows")
  @encode.number_value(writer, rows.to_double())
  @encode.key(writer, "received_rows_cid")
  @encode.string_value(writer, cid)
  @encode.key(writer, "requirement_cid")
  @encode.string_value(
    writer,
    @planning.query_requirement_cid(authority.issuer.requirement),
  )
  @encode.key(writer, "role")
  @encode.string_value(
    writer,
    match role {
      ValidationScan => "validation_scan"
      NativeResult => "native_result"
    },
  )
  @encode.key(writer, "scan_scope_cid")
  @encode.string_value(writer, scope)
  @encode.key(writer, "snapshot")
  @planning.emit_query_snapshot(None, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-receipt/0.1")
  @encode.end_object(writer)
}

///|
fn emit_native_record(
  authority : DuckDBNativeAuthority,
  measurement : DuckDBNativeMeasurement,
  scope : String,
  receipts : Array[String],
  role : @planning.QueryRecordRole,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "accesses")
  emit_native_accesses(receipts, writer)
  @encode.key(writer, "attempt")
  @encode.string_value(writer, authority.number)
  @encode.key(writer, "issuer")
  @encode.string_value(writer, authority.issuer.name)
  @encode.key(writer, "output")
  @planning.emit_query_output(native_output_identity(measurement), writer)
  @encode.key(writer, "read_view")
  @encode.string_value(writer, authority.read_view)
  @encode.key(writer, "requirement_cid")
  @encode.string_value(
    writer,
    @planning.query_requirement_cid(authority.issuer.requirement),
  )
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
  @encode.string_value(writer, scope)
  @encode.key(writer, "snapshot")
  @planning.emit_query_snapshot(None, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-two-receipt-evidence/0.1")
  @encode.end_object(writer)
}

///|
fn build_native_records(
  authority : DuckDBNativeAuthority,
  measurement : DuckDBNativeMeasurement,
  limits : @planning.QueryMaterialLimits,
) -> Result[DuckDBNativeRecords, DuckDBEvidenceIssue] {
  guard @planning.query_artifact_budget(
      limits.max_work,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(budget) else {
    return Err(InvalidLimits)
  }
  try {
    let requirement = authority.issuer.requirement
    let scope = @planning.query_scan_scope(requirement, budget)
    let receipt_documents = []
    let receipt_cids = []
    let mut remaining_fields = limits.max_fields
    for role in [@duckdb.ValidationScan, @duckdb.NativeResult] {
      let count = @duckdb.native_receipt_field_count(measurement.receipts, role)
      if count > remaining_fields {
        return Err(FieldLimit)
      }
      remaining_fields -= count
      if !@planning.query_artifact_spend_work(budget, count) {
        return Err(WorkLimit)
      }
      let fields = []
      for i in 0..<count {
        guard @duckdb.native_receipt_field(measurement.receipts, role, i)
          is Some(field) else {
          return Err(InvalidRetainedLayout)
        }
        if !@planning.query_artifact_spend_work(budget, field.length()) {
          return Err(WorkLimit)
        }
        fields.push(field)
      }
      let (document, cid) = @planning.query_record_document(budget, writer => {
        emit_native_receipt(authority, measurement, scope, role, fields, writer)
      })
      receipt_documents.push(document)
      receipt_cids.push(cid)
    }
    let documents = []
    let cids = []
    for role in [@planning.SourceValidation, @planning.Filter, @planning.Select] {
      let (document, cid) = @planning.query_record_document(budget, writer => {
        emit_native_record(
          authority, measurement, scope, receipt_cids, role, writer,
        )
      })
      documents.push(document)
      cids.push(cid)
    }
    Ok({
      authority,
      measurement,
      scope,
      receipt_documents,
      receipt_cids,
      documents,
      cids,
      bytes: limits.max_bytes - @planning.query_artifact_remaining(budget).1,
      nodes: limits.max_nodes - @planning.query_artifact_remaining(budget).2,
    })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
fn emit_native_observation(
  records : DuckDBNativeRecords,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let requirement = records.authority.issuer.requirement
  @encode.begin_object(writer)
  @encode.key(writer, "accesses")
  emit_native_accesses(records.receipt_cids, writer)
  @encode.key(writer, "coverage")
  @encode.begin_object(writer)
  @encode.key(writer, "complete")
  @encode.bool_value(writer, true)
  @encode.key(writer, "filter_evidence_cid")
  @encode.string_value(writer, records.cids[1])
  @encode.key(writer, "scope_cid")
  @encode.string_value(writer, records.scope)
  @encode.key(writer, "select_evidence_cid")
  @encode.string_value(writer, records.cids[2])
  @encode.key(writer, "source_validation_evidence_cid")
  @encode.string_value(writer, records.cids[0])
  @encode.end_object(writer)
  @encode.key(writer, "evidence_contract_cid")
  @encode.string_value(
    writer,
    @planning.query_two_receipt_contract_cid(records.authority.issuer._contract),
  )
  @encode.key(writer, "execution")
  @encode.begin_object(writer)
  @encode.key(writer, "attempt")
  @encode.string_value(writer, records.authority.number)
  @encode.key(writer, "issuer")
  @encode.string_value(writer, records.authority.issuer.name)
  @encode.key(writer, "read_view")
  @encode.string_value(writer, records.authority.read_view)
  @encode.end_object(writer)
  @encode.key(writer, "output")
  @planning.emit_query_output(
    native_output_identity(records.measurement),
    writer,
  )
  @encode.key(writer, "owner")
  @encode.begin_object(writer)
  @encode.key(writer, "input")
  @encode.string_value(writer, @planning.query_requirement_site(requirement).1)
  @encode.key(writer, "program_source_cid")
  @encode.string_value(
    writer,
    @context.program_identity_definition_cid(
      @planning.query_requirement_program(requirement),
    ),
  )
  @encode.key(writer, "stage")
  @encode.string_value(writer, @planning.query_requirement_site(requirement).0)
  @encode.end_object(writer)
  @encode.key(writer, "parameter_values_cid")
  @encode.string_value(
    writer,
    @planning.query_material_cids(
      @planning.query_requirement_material(requirement),
    ).2,
  )
  @encode.key(writer, "requirement_cid")
  @encode.string_value(writer, @planning.query_requirement_cid(requirement))
  @encode.key(writer, "resolved_request_cid")
  @encode.string_value(
    writer,
    @planning.query_material_cids(
      @planning.query_requirement_material(requirement),
    ).0,
  )
  @encode.key(writer, "retention")
  @encode.string_value(writer, "process")
  @encode.key(writer, "snapshot")
  @planning.emit_query_snapshot(None, writer)
  @encode.key(writer, "source_contract_cid")
  @encode.string_value(
    writer,
    @planning.query_requirement_source(requirement).1,
  )
  @encode.key(writer, "source_ref")
  @encode.string_value(
    writer,
    @planning.query_requirement_source(requirement).0,
  )
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-two-receipt-observation/0.1")
  @encode.end_object(writer)
}
