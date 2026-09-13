///|
// Canonical material only. Exact authority and successful retained measurements
// are checked by the issuer, not inferred from any of these strings/documents.
fn native_output_identity(
  measurement : DuckDBNativeMeasurement,
) -> QueryOutputIdentity {
  let (cid, _, _, rows) = @duckdb.native_receipt_digest(
    measurement.receipts,
    @duckdb.NativeResult,
  )
  {
    contract_cid: measurement.attempt.preparation.requirement.output_contract_cid,
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
  @encode.string_value(writer, authority.issuer.requirement.cid)
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
  emit_query_snapshot(None, writer)
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
  role : QueryRecordRole,
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
  emit_query_output(native_output_identity(measurement), writer)
  @encode.key(writer, "read_view")
  @encode.string_value(writer, authority.read_view)
  @encode.key(writer, "requirement_cid")
  @encode.string_value(writer, authority.issuer.requirement.cid)
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
  emit_query_snapshot(None, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-two-receipt-evidence/0.1")
  @encode.end_object(writer)
}

///|
fn build_native_records(
  authority : DuckDBNativeAuthority,
  measurement : DuckDBNativeMeasurement,
  limits : QueryMaterialLimits,
) -> Result[DuckDBNativeRecords, DuckDBEvidenceIssue] {
  let budget : QueryMaterialBudget = {
    work: limits.max_work,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  try {
    let requirement = authority.issuer.requirement
    let scope = query_scan_scope(requirement, budget)
    let receipt_documents = []
    let receipt_cids = []
    let mut remaining_fields = limits.max_fields
    for role in [@duckdb.ValidationScan, @duckdb.NativeResult] {
      let count = @duckdb.native_receipt_field_count(measurement.receipts, role)
      if count > remaining_fields {
        return Err(FieldLimit)
      }
      remaining_fields -= count
      if count > budget.work {
        return Err(WorkLimit)
      }
      budget.work -= count
      let fields = []
      for i in 0..<count {
        guard @duckdb.native_receipt_field(measurement.receipts, role, i)
          is Some(field) else {
          return Err(InvalidRetainedLayout)
        }
        if field.length() > budget.work {
          return Err(WorkLimit)
        }
        budget.work -= field.length()
        fields.push(field)
      }
      let (document, cid) = query_record_document(budget, writer => {
        emit_native_receipt(authority, measurement, scope, role, fields, writer)
      })
      receipt_documents.push(document)
      receipt_cids.push(cid)
    }
    let documents = []
    let cids = []
    for role in [SourceValidation, Filter, Select] {
      let (document, cid) = query_record_document(budget, writer => {
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
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
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
  @encode.string_value(writer, query_two_receipt_cid)
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
  emit_query_output(native_output_identity(records.measurement), writer)
  @encode.key(writer, "owner")
  @encode.begin_object(writer)
  @encode.key(writer, "input")
  @encode.string_value(writer, requirement.input)
  @encode.key(writer, "program_source_cid")
  @encode.string_value(
    writer,
    @context.program_identity_definition_cid(requirement.program),
  )
  @encode.key(writer, "stage")
  @encode.string_value(writer, requirement.stage)
  @encode.end_object(writer)
  @encode.key(writer, "parameter_values_cid")
  @encode.string_value(writer, requirement.material.parameter_values_cid)
  @encode.key(writer, "requirement_cid")
  @encode.string_value(writer, requirement.cid)
  @encode.key(writer, "resolved_request_cid")
  @encode.string_value(writer, requirement.material.request_cid)
  @encode.key(writer, "retention")
  @encode.string_value(writer, "process")
  @encode.key(writer, "snapshot")
  emit_query_snapshot(None, writer)
  @encode.key(writer, "source_contract_cid")
  @encode.string_value(writer, requirement.source_contract_cid)
  @encode.key(writer, "source_ref")
  @encode.string_value(writer, requirement.source_ref)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-two-receipt-observation/0.1")
  @encode.end_object(writer)
}
