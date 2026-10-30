///|
/// Protocol DATA under one original Form, not an insertion grant or an
/// absence observation. Omitted fields remain omitted, including defaults.
pub struct RecordCreateRequest {
  priv mut self : RecordCreateRequest?
  priv catalog : FormFieldCatalog
  priv records : Array[RecordWriteValues]
  priv document : String
}

///|
/// Each original target remains paired with its own checked write values.
/// Required revisions are never omitted or replaced by an unchecked -1.
pub struct RecordUpdateRequest {
  priv mut self : RecordUpdateRequest?
  priv records : Array[(OriginalRecordTarget, RecordWriteValues)]
  priv document : @encode.EncodedDocument
}

///|
fn check_record_create_values(
  catalog : FormFieldCatalog,
  records : Array[RecordWriteValues],
  limits : RecordMutationLimits,
) -> Result[Unit, RecordMutationIssue] {
  if !mutation_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if records.is_empty() {
    return Err(InvalidRequest)
  }
  if records.length() > limits.max_records ||
    catalog.app_id.length() > limits.max_identity_bytes {
    return Err(BudgetExceeded)
  }
  for record in records {
    if !physical_equal(record.catalog, catalog) {
      return Err(ForeignCatalog)
    }
  }
  Ok(())
}

///|
// One original serialization for emission and exact saved-body comparison.
fn emit_record_create_body(
  writer : @encode.Writer,
  catalog : FormFieldCatalog,
  records : Array[RecordWriteValues],
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_ordered_object(writer)
  @encode.ordered_key(writer, "app")
  @encode.string_value(writer, catalog.app_id)
  @encode.ordered_key(writer, "records")
  @encode.begin_array(writer)
  for record in records {
    @encode.emit_document(writer, record.document)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
}

///|
pub fn prepare_record_create_request(
  catalog : FormFieldCatalog,
  records : Array[RecordWriteValues],
  limits : RecordMutationLimits,
) -> Result[RecordCreateRequest, RecordMutationIssue] {
  match check_record_create_values(catalog, records, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let document = try {
    emit_record_create_body(writer, catalog, records)
    @encode.finish_document(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  let result : RecordCreateRequest = {
    self: None,
    catalog,
    records: records.copy(),
    document: @encode.document_text(document),
  }
  result.self = Some(result)
  Ok(result)
}

///|
/// Restore protocol DATA only after the same serializer matches the complete
/// saved body. No emitted request, tag, CID, approval or dispatch is issued.
/// The caller still authenticates its saved row and original Mapping/Form.
pub fn restore_record_create_request(
  catalog : FormFieldCatalog,
  records : Array[RecordWriteValues],
  original_body : String,
  limits : RecordMutationLimits,
) -> Result[RecordCreateRequest, RecordMutationIssue] {
  match check_record_create_values(catalog, records, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard @scalar.admit_utf8_length(original_body, limits.max_output_bytes)
    is Ok(_) else {
    return Err(BudgetExceeded)
  }
  let writer = @encode.comparing_writer(
    original_body,
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let equal = try {
    emit_record_create_body(writer, catalog, records)
    @encode.finish_comparison_usage(writer).0
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  if !equal {
    return Err(InvalidRequest)
  }
  let result : RecordCreateRequest = {
    self: None,
    catalog,
    records: records.copy(),
    document: original_body,
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_create_request_body(request : RecordCreateRequest) -> String {
  request.document
}

///|
pub fn record_create_request_values(
  request : RecordCreateRequest,
) -> Array[RecordWriteValues] {
  request.records.copy()
}

///|
pub fn prepare_record_update_request(
  records : Array[(OriginalRecordTarget, RecordWriteValues)],
  limits : RecordMutationLimits,
) -> Result[RecordUpdateRequest, RecordMutationIssue] {
  if !mutation_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if records.is_empty() {
    return Err(InvalidRequest)
  }
  if records.length() > limits.max_records {
    return Err(BudgetExceeded)
  }
  let catalog = records[0].0.page.catalog
  let mut identity = limits.max_identity_bytes
  let mut work = limits.max_comparison_work
  for index, (target, values) in records {
    if !physical_equal(target.page.catalog, catalog) ||
      !physical_equal(values.catalog, catalog) {
      return Err(ForeignCatalog)
    }
    for
      value in [
        target.page.app_id,
        target.record.record_id,
        target.record.revision,
      ] {
      if value.length() > identity {
        return Err(BudgetExceeded)
      }
      identity -= value.length()
    }
    for prior in 0..<index {
      let left = records[prior].0.record.record_id
      let right = target.record.record_id
      for value in [left, right] {
        if value.length() > work {
          return Err(BudgetExceeded)
        }
        work -= value.length()
      }
      if same_numeric_record_id(left, right) {
        return Err(DuplicateTarget)
      }
    }
  }
  let writer = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let document = try {
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "app")
    @encode.string_value(writer, catalog.app_id)
    @encode.ordered_key(writer, "records")
    @encode.begin_array(writer)
    for (target, values) in records {
      @encode.begin_ordered_object(writer)
      @encode.ordered_key(writer, "id")
      @encode.string_value(writer, target.record.record_id)
      @encode.ordered_key(writer, "record")
      @encode.emit_document(writer, values.document)
      @encode.ordered_key(writer, "revision")
      @encode.string_value(writer, target.record.revision)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.ordered_key(writer, "upsert")
    @encode.bool_value(writer, false)
    @encode.end_object(writer)
    @encode.finish_document(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  let result : RecordUpdateRequest = {
    self: None,
    records: records.copy(),
    document,
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_update_request_body(request : RecordUpdateRequest) -> String {
  @encode.document_text(request.document)
}

///|
pub fn record_update_request_values(
  request : RecordUpdateRequest,
) -> Array[(OriginalRecordTarget, RecordWriteValues)] {
  request.records.copy()
}

///|
/// Complete response DATA for the original request, not commit/current/cleanup
/// authority. The physical caller must bind the received bytes to its claim.
pub struct RecordCreateAcknowledgement {
  priv mut self : RecordCreateAcknowledgement?
  priv request : RecordCreateRequest
  priv records : Array[(String, String)]
  response_sha256 : String
}

///|
pub struct RecordUpdateAcknowledgement {
  priv mut self : RecordUpdateAcknowledgement?
  priv request : RecordUpdateRequest
  priv records : Array[(String, String)]
  response_sha256 : String
}

///|
fn write_response_cursor(
  status : Int,
  bytes : Bytes,
  limits : RecordMutationLimits,
) -> Result[@decode.Cursor, RecordMutationIssue] {
  if !mutation_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if status != 200 {
    return Err(UnexpectedStatus)
  }
  if bytes.length() > limits.max_output_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_output_bytes,
      max_nodes: limits.max_output_nodes,
      max_depth: limits.max_output_depth,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  match
    @decode.admit(parsed, {
      max_nodes: limits.max_output_nodes,
      max_depth: limits.max_output_depth,
      max_string_bytes: limits.max_identity_bytes,
      max_total_string_bytes: limits.max_output_bytes,
    }) {
    Ok(value) => Ok(value)
    Err(error) =>
      Err(
        match error.kind {
          BudgetExceeded => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
}

///|
/// Every identity is an exact bounded digit string. Comparison is used only
/// for duplicate refusal; no ID or revision is converted through Number.
fn write_response_identities(
  records : Array[(String, String)],
  limits : RecordMutationLimits,
) -> Result[Int, RecordMutationIssue] {
  let mut identity = limits.max_identity_bytes
  let mut work = limits.max_comparison_work
  for index, (id, revision) in records {
    for value in [id, revision] {
      if value.length() > identity {
        return Err(BudgetExceeded)
      }
      identity -= value.length()
      if !form_digits(value) {
        return Err(InvalidResponse)
      }
    }
    for prior in 0..<index {
      let left = records[prior].0
      for value in [left, id] {
        if value.length() > work {
          return Err(BudgetExceeded)
        }
        work -= value.length()
      }
      if same_numeric_record_id(left, id) {
        return Err(UncorrelatedResult)
      }
    }
  }
  Ok(work)
}

///|
pub fn project_record_create_acknowledgement(
  request : RecordCreateRequest,
  status : Int,
  bytes : Bytes,
  limits : RecordMutationLimits,
) -> Result[RecordCreateAcknowledgement, RecordMutationIssue] {
  let root = match write_response_cursor(status, bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.closed_object(root, ["ids", "revisions"]) is Ok(object) &&
    @decode.lookup(object, "ids") is Some(ids) &&
    @decode.lookup(object, "revisions") is Some(revisions) &&
    @decode.array_length(ids) == Some(request.records.length()) &&
    @decode.array_length(revisions) == Some(request.records.length()) else {
    return Err(UncorrelatedResult)
  }
  if request.records.length() > limits.max_records {
    return Err(BudgetExceeded)
  }
  let records = []
  for index in 0..<request.records.length() {
    guard @decode.element_at(ids, index) is Some(id) &&
      @decode.text(id) is Ok(id) &&
      @decode.element_at(revisions, index) is Some(revision) &&
      @decode.text(revision) is Ok(revision) else {
      return Err(InvalidResponse)
    }
    records.push((id, revision))
  }
  match write_response_identities(records, limits) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result : RecordCreateAcknowledgement = {
    self: None,
    request,
    records,
    response_sha256: @sha.hex(bytes),
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn project_record_update_acknowledgement(
  request : RecordUpdateRequest,
  status : Int,
  bytes : Bytes,
  limits : RecordMutationLimits,
) -> Result[RecordUpdateAcknowledgement, RecordMutationIssue] {
  let root = match write_response_cursor(status, bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.closed_object(root, ["records"]) is Ok(object) &&
    @decode.lookup(object, "records") is Some(entries) &&
    @decode.array_length(entries) == Some(request.records.length()) else {
    return Err(UncorrelatedResult)
  }
  if request.records.length() > limits.max_records {
    return Err(BudgetExceeded)
  }
  let records = []
  for index in 0..<request.records.length() {
    guard @decode.element_at(entries, index) is Some(entry) &&
      @decode.closed_object(entry, ["id", "revision"]) is Ok(object) &&
      form_text(object, "id") is Some(id) &&
      form_text(object, "revision") is Some(revision) else {
      return Err(InvalidResponse)
    }
    records.push((id, revision))
  }
  let mut work = match write_response_identities(records, limits) {
    Err(issue) => return Err(issue)
    Ok(remaining) => remaining
  }
  // Correlate by exact original ID, without assuming response order or
  // accepting a missing original because another ID has the same spelling.
  for (target, _) in request.records {
    let mut found = false
    for (id, _) in records {
      for value in [target.record.record_id, id] {
        if value.length() > work {
          return Err(BudgetExceeded)
        }
        work -= value.length()
      }
      if id == target.record.record_id {
        found = true
        break
      }
    }
    if !found {
      return Err(UncorrelatedResult)
    }
  }
  let result : RecordUpdateAcknowledgement = {
    self: None,
    request,
    records,
    response_sha256: @sha.hex(bytes),
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_create_acknowledgement_request(
  response : RecordCreateAcknowledgement,
) -> RecordCreateRequest {
  response.request
}

///|
pub fn record_create_acknowledgement_records(
  response : RecordCreateAcknowledgement,
) -> Array[(String, String)] {
  response.records.copy()
}

///|
pub fn record_update_acknowledgement_request(
  response : RecordUpdateAcknowledgement,
) -> RecordUpdateRequest {
  response.request
}

///|
pub fn record_update_acknowledgement_records(
  response : RecordUpdateAcknowledgement,
) -> Array[(String, String)] {
  response.records.copy()
}

///|
pub fn record_create_request_app_id(request : RecordCreateRequest) -> String {
  request.catalog.app_id
}

///|
pub fn record_create_request_count(request : RecordCreateRequest) -> Int {
  request.records.length()
}

///|
pub fn record_update_request_app_id(request : RecordUpdateRequest) -> String {
  request.records[0].0.page.app_id
}

///|
pub fn record_update_request_count(request : RecordUpdateRequest) -> Int {
  request.records.length()
}

///|
/// Same original Form/revision DATA only. Actual current authority and the
/// physical response's request binding remain with the existing Site.
pub fn recheck_record_create_form(
  request : RecordCreateRequest,
  bytes : Bytes,
  limits : FormFieldLimits,
) -> Result[Unit, RecordMutationIssue] {
  recheck_original_record_form(request.catalog, bytes, limits)
}

///|
/// Reuse the existing original-target observation without issuing a delete
/// claim. The same target objects, not their JSON IDs, remain retained.
pub fn record_update_request_observation(
  request : RecordUpdateRequest,
  limits : RecordMutationLimits,
) -> Result[RecordDeleteRequest, RecordMutationIssue] {
  prepare_record_delete_request(request.records.map(record => record.0), limits)
}

///|
/// Constructor correspondence only, not physical dispatch or response custody.
pub fn record_create_request_is_original(value : RecordCreateRequest) -> Bool {
  value.self is Some(original) && physical_equal(original, value)
}

///|
pub fn record_create_acknowledgement_is_original(
  value : RecordCreateAcknowledgement,
) -> Bool {
  value.self is Some(original) && physical_equal(original, value)
}

///|
/// Original request DATA, not authority or an acknowledged provider action.
pub fn record_update_request_is_original(value : RecordUpdateRequest) -> Bool {
  value.self is Some(original) && physical_equal(original, value)
}

///|
/// Same decoded response object, not a copy with equal private request fields.
pub fn record_update_acknowledgement_is_original(
  value : RecordUpdateAcknowledgement,
) -> Bool {
  value.self is Some(original) && physical_equal(original, value)
}
