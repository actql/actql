///|
/// Pure request/response bounds. These allocate no Effect or numerical grant.
pub(all) struct RecordMutationLimits {
  max_records : Int
  max_identity_bytes : Int
  max_comparison_work : Int
  max_output_bytes : Int
  max_output_nodes : Int
  max_output_depth : Int
}

///|
pub(all) enum RecordMutationIssue {
  InvalidLimits
  BudgetExceeded
  InvalidIndex
  ForeignCatalog
  MissingTarget
  ChangedRevision
  DuplicateTarget
  InvalidRequest
  UnexpectedStatus
  InvalidResponse
} derive(Eq, Debug)

///|
/// Original read DATA only. The complete page and its original Form remain
/// retained; API ID/revision cannot be replaced by a Record Number or a
/// separately decoded equal object. Authority and Preview belong elsewhere.
pub struct OriginalRecordTarget {
  priv page : OriginalRecordPage
  priv record : OriginalRecord
}

///|
pub fn prepare_original_record_target(
  page : OriginalRecordPage,
  index : Int,
  max_identity_bytes : Int,
) -> Result[OriginalRecordTarget, RecordMutationIssue] {
  if max_identity_bytes <= 0 {
    return Err(InvalidLimits)
  }
  guard page.records.get(index) is Some(record) else {
    return Err(InvalidIndex)
  }
  let mut remaining = max_identity_bytes
  for value in [page.app_id, record.record_id, record.revision] {
    if value.length() > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= value.length()
    if !form_digits(value) {
      return Err(InvalidRequest)
    }
  }
  Ok({ page, record, })
}

///|
pub fn original_record_target_page(
  target : OriginalRecordTarget,
) -> OriginalRecordPage {
  target.page
}

///|
pub fn original_record_target_id(target : OriginalRecordTarget) -> String {
  target.record.record_id
}

///|
pub fn original_record_target_revision(target : OriginalRecordTarget) -> String {
  target.record.revision
}

///|
/// Revision correspondence only, not full Preview/current authorization. A
/// fresh response must be decoded against the same original Catalog. No
/// revision is synthesized from time, a newer row or an equal foreign Form.
pub fn match_original_record_target_revision(
  target : OriginalRecordTarget,
  observed : OriginalRecordPage,
  max_comparison_work : Int,
) -> Result[Unit, RecordMutationIssue] {
  if max_comparison_work <= 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(target.page.catalog, observed.catalog) {
    return Err(ForeignCatalog)
  }
  let mut remaining = max_comparison_work
  for record in observed.records {
    for value in [target.record.record_id, record.record_id] {
      if value.length() > remaining {
        return Err(BudgetExceeded)
      }
      remaining -= value.length()
    }
    if record.record_id == target.record.record_id {
      for value in [target.record.revision, record.revision] {
        if value.length() > remaining {
          return Err(BudgetExceeded)
        }
        remaining -= value.length()
      }
      return if record.revision == target.record.revision {
        Ok(())
      } else {
        Err(ChangedRevision)
      }
    }
  }
  Err(MissingTarget)
}

///|
/// A protocol candidate under one original App/Form, never a dispatch claim.
/// Ordered IDs and required revisions retain their exact original strings.
pub struct RecordDeleteRequest {
  priv targets : Array[OriginalRecordTarget]
  priv document : @encode.EncodedDocument
}

///|
fn mutation_limits_valid(limits : RecordMutationLimits) -> Bool {
  limits.max_records > 0 &&
  limits.max_records <= 100 &&
  limits.max_identity_bytes > 0 &&
  limits.max_comparison_work > 0 &&
  limits.max_output_bytes > 0 &&
  limits.max_output_nodes > 0 &&
  limits.max_output_depth > 0
}

///|
/// Duplicate detection only: no normalized spelling becomes a target ID.
fn same_numeric_record_id(left : String, right : String) -> Bool {
  let mut first = 0
  let mut second = 0
  while first + 1 < left.length() && left[first] == '0' {
    first += 1
  }
  while second + 1 < right.length() && right[second] == '0' {
    second += 1
  }
  if left.length() - first != right.length() - second {
    return false
  }
  while first < left.length() {
    if left[first] != right[second] {
      return false
    }
    first += 1
    second += 1
  }
  true
}

///|
pub fn prepare_record_delete_request(
  targets : Array[OriginalRecordTarget],
  limits : RecordMutationLimits,
) -> Result[RecordDeleteRequest, RecordMutationIssue] {
  if !mutation_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if targets.is_empty() {
    return Err(InvalidRequest)
  }
  if targets.length() > limits.max_records {
    return Err(BudgetExceeded)
  }
  let first = targets[0]
  let mut identity = limits.max_identity_bytes
  let mut work = limits.max_comparison_work
  for index, target in targets {
    if !physical_equal(first.page.catalog, target.page.catalog) {
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
      let left = targets[prior].record.record_id
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
  try {
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "app")
    @encode.string_value(writer, first.page.app_id)
    @encode.ordered_key(writer, "ids")
    @encode.begin_array(writer)
    for target in targets {
      @encode.string_value(writer, target.record.record_id)
    }
    @encode.end_array(writer)
    @encode.ordered_key(writer, "revisions")
    @encode.begin_array(writer)
    for target in targets {
      @encode.string_value(writer, target.record.revision)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok({ targets: targets.copy(), document: @encode.finish_document(writer), })
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn record_delete_request_body(request : RecordDeleteRequest) -> String {
  @encode.document_text(request.document)
}

///|
pub fn record_delete_request_targets(
  request : RecordDeleteRequest,
) -> Array[OriginalRecordTarget] {
  request.targets.copy()
}

///|
/// An HTTP response observation for this original request. This is neither
/// an Effect commit nor cleanup ACK; lost replies have no constructor here.
pub struct RecordDeleteAcknowledgement {
  priv request : RecordDeleteRequest
  response_sha256 : String
}

///|
pub fn record_delete_acknowledgement_request(
  response : RecordDeleteAcknowledgement,
) -> RecordDeleteRequest {
  response.request
}

///|
pub fn project_record_delete_acknowledgement(
  request : RecordDeleteRequest,
  status : Int,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RecordDeleteAcknowledgement, RecordMutationIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  if status != 200 {
    return Err(UnexpectedStatus)
  }
  if bytes.length() > max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
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
  let root = match
    @decode.admit(parsed, {
      max_nodes,
      max_depth,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }) {
    Ok(value) => value
    Err(error) =>
      return Err(
        match error.kind {
          BudgetExceeded => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  guard @decode.open_object(root) is Ok(_) &&
    @decode.object_length(root) == Some(0) else {
    return Err(InvalidResponse)
  }
  Ok({ request, response_sha256: @sha.hex(bytes), })
}
