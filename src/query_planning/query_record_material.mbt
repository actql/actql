///|
// Canonical material construction only, never issuance or read-view authority.
priv enum QueryRecordBuildIssue {
  InvalidRetainedLayout
  FieldLimit
  WorkLimit
  Encoding(@encode.EncodeFailure)
}

///|
fn query_record_document(
  budget : QueryMaterialBudget,
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> (@encode.EncodedDocument, String) raise @encode.EncodeFailure {
  let writer = @encode.writer(budget.bytes / 2, budget.nodes / 2, budget.depth)
  emit(writer)
  let document = @encode.finish_document(writer)
  let before = budget.nodes
  let cid = material_hash(budget, writer => {
    @encode.emit_document(writer, document)
  })
  budget.bytes -= @encode.document_bytes(document)
  budget.nodes -= before - budget.nodes
  (document, cid)
}

///|
fn query_record_payload(
  requirement : QueryRequirement,
  received : @execution.RowWireIdentity,
  output : @execution.RowWireIdentity,
  schema : @schema.Schema,
  limits : QueryMaterialLimits,
  budget : QueryMaterialBudget,
) -> Result[QueryRecordPayload, QueryRecordBuildIssue] {
  let count = @schema.field_count(schema)
  if count > limits.max_fields {
    return Err(FieldLimit)
  }
  if count > budget.work {
    return Err(WorkLimit)
  }
  budget.work -= count
  let fields : Array[String] = []
  for i in 0..<count {
    let name = @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    if name.length() > budget.work {
      return Err(WorkLimit)
    }
    budget.work -= name.length()
    if i > 0 {
      let previous = fields[i - 1]
      if previous.length() > budget.work {
        return Err(WorkLimit)
      }
      budget.work -= previous.length()
      if @canonical.compare_utf16(previous, name) >= 0 {
        return Err(InvalidRetainedLayout)
      }
    }
    fields.push(name)
  }
  try {
    let access = material_hash(budget, writer => {
      @encode.begin_object(writer)
      @encode.key(writer, "received_fields")
      @encode.begin_array(writer)
      for field in fields {
        @encode.string_value(writer, field)
      }
      @encode.end_array(writer)
      @encode.key(writer, "received_rows_cid")
      @encode.string_value(writer, @execution.row_wire_cid(received))
      @encode.key(writer, "requirement_cid")
      @encode.string_value(writer, requirement.cid)
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-query-access-scope/0.1")
      @encode.end_object(writer)
    })
    let scope = query_scan_scope(requirement, budget)
    Ok({
      requirement_cid: requirement.cid,
      snapshot: None,
      scan_scope_cid: scope,
      access: {
        scope_cid: access,
        provider_scope_cid: None,
        received_rows: @execution.row_wire_usage(received).2,
        received_fields: fields,
        received_bytes: @execution.row_wire_usage(received).0,
      },
      output: {
        contract_cid: requirement.output_contract_cid,
        rows_cid: @execution.row_wire_cid(output),
        row_count: @execution.row_wire_usage(output).2,
      },
    })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
fn query_scan_scope(
  requirement : QueryRequirement,
  budget : QueryMaterialBudget,
) -> String raise @encode.EncodeFailure {
  material_hash(budget, writer => {
    @encode.begin_object(writer)
    @encode.key(writer, "resolved_request_cid")
    @encode.string_value(writer, requirement.material.request_cid)
    @encode.key(writer, "source_contract_cid")
    @encode.string_value(writer, requirement.source_contract_cid)
    @encode.key(writer, "source_ref")
    @encode.string_value(writer, requirement.source_ref)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-query-scan-scope/0.1")
    @encode.end_object(writer)
  })
}
