///|
/// Positive bounds for one exact unique Text-key query. No capacity or I/O
/// authority is issued by these synchronous request/response projections.
pub(all) struct RecordLookupLimits {
  max_key_bytes : Int
  max_columns : Int
  max_comparison_work : Int
  max_request_bytes : Int
  max_request_nodes : Int
  max_request_depth : Int
}

///|
pub(all) enum RecordLookupIssue {
  InvalidLimits
  BudgetExceeded
  InvalidKey
  InvalidSelection
  Form(FormFieldIssue)
  Page(RecordPageIssue)
  UnexpectedStatus
  IncompleteResponse
  ForeignRecord
  ForeignRequest
  ChangedObservation
} derive(Eq, Debug)

///|
/// The original Catalog and exact query stay together. In particular this
/// cannot be constructed from a missing-record scalar, a 404 or equal JSON.
pub struct RecordLookupRequest {
  priv catalog : FormFieldCatalog
  priv key : String
  priv value : String
  priv names : Array[String]
  priv max_comparison_work : Int
  priv document : @encode.EncodedDocument
}

///|
/// DATA observed under one original request. Even an empty complete response
/// is not global absence, a conditional-create grant, current authority or an
/// Effect outcome. The physical Site must bind and authorize the actual call.
pub struct RecordLookupObservation {
  priv request : RecordLookupRequest
  priv page : OriginalRecordPage
}

///|
fn record_lookup_limits_valid(limits : RecordLookupLimits) -> Bool {
  limits.max_key_bytes > 0 &&
  limits.max_columns > 0 &&
  limits.max_columns <= 998 &&
  limits.max_comparison_work > 0 &&
  limits.max_request_bytes > 0 &&
  limits.max_request_nodes > 0 &&
  limits.max_request_depth > 0
}

///|
/// A field token is never interpolated as query syntax. Original non-ASCII
/// field codes remain unchanged; ASCII punctuation/operators and whitespace
/// are not valid saved field-code tokens. No normalization or alias is made.
fn record_lookup_field_token(code : String) -> Bool {
  if code.is_empty() || (code[0] >= '0' && code[0] <= '9') {
    return false
  }
  for unit in code {
    if unit <= ' ' || unit == '\u007f' || unit == '\u0085' ||
      unit == '\u00a0' || unit == '\u1680' ||
      (unit >= '\u2000' && unit <= '\u200a') ||
      unit == '\u2028' || unit == '\u2029' || unit == '\u202f' ||
      unit == '\u205f' || unit == '\u3000' {
      return false
    }
    if unit < '\u0080' &&
      !(unit >= 'a' && unit <= 'z') &&
      !(unit >= 'A' && unit <= 'Z') &&
      !(unit >= '0' && unit <= '9') &&
      unit != '_' {
      return false
    }
  }
  true
}

///|
pub fn prepare_record_text_key_lookup(
  catalog : FormFieldCatalog,
  key : String,
  value : String,
  names : Array[String],
  limits : RecordLookupLimits,
) -> Result[RecordLookupRequest, RecordLookupIssue] {
  if !record_lookup_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if value.length() > limits.max_key_bytes ||
    key.length() > limits.max_comparison_work ||
    names.length() > limits.max_columns {
    return Err(BudgetExceeded)
  }
  let metadata = match require_form_unique_key(catalog, key) {
    Ok(value) => value
    Err(issue) => return Err(Form(issue))
  }
  // Number's historical storage domain is not replaced by Text or Double.
  // A missing Text key also cannot enforce uniqueness for a later insertion.
  if metadata.native_type != "SINGLE_LINE_TEXT" ||
    value.is_empty() ||
    !record_lookup_field_token(key) {
    return Err(InvalidKey)
  }
  for unit in value {
    if unit < ' ' || unit == '\u007f' {
      return Err(InvalidKey)
    }
  }
  if @utf8.encode(value).length() > limits.max_key_bytes {
    return Err(BudgetExceeded)
  }
  let selected = []
  let seen : Map[String, Bool] = Map([])
  let mut remaining = limits.max_comparison_work - key.length()
  for name in names {
    if name.length() > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= name.length()
    if seen.contains(name) ||
      form_field_named(catalog, [name]) is None {
      return Err(InvalidSelection)
    }
    seen[name] = true
    selected.push(name)
  }
  if !seen.contains(key) {
    if selected.length() >= limits.max_columns {
      return Err(BudgetExceeded)
    }
    selected.push(key)
  }
  // Provider query escaping and JSON escaping are separate layers. Only the
  // exact original value is matched; no guessed case/Unicode normalization.
  let literal = value.replace_all(old="\\", new="\\\\").replace_all(
    old="\"",
    new="\\\"",
  )
  let query = key + " = \"" + literal + "\" limit 2"
  let writer = @encode.writer(
    limits.max_request_bytes,
    limits.max_request_nodes,
    limits.max_request_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "app")
    @encode.string_value(writer, catalog.app_id)
    @encode.key(writer, "fields")
    @encode.begin_array(writer)
    @encode.string_value(writer, "$id")
    @encode.string_value(writer, "$revision")
    for name in selected {
      @encode.string_value(writer, name)
    }
    @encode.end_array(writer)
    @encode.key(writer, "query")
    @encode.string_value(writer, query)
    @encode.key(writer, "totalCount")
    @encode.bool_value(writer, true)
    @encode.end_object(writer)
    Ok({
      catalog,
      key,
      value,
      names: selected,
      max_comparison_work: limits.max_comparison_work,
      document: @encode.finish_document(writer),
    })
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
pub fn record_lookup_request_body(request : RecordLookupRequest) -> String {
  @encode.document_text(request.document)
}

///|
pub fn record_lookup_request_uses_catalog(
  request : RecordLookupRequest,
  catalog : FormFieldCatalog,
) -> Bool {
  physical_equal(request.catalog, catalog)
}

///|
/// Require the explicitly requested total count, not short-page heuristics.
/// Leading zeroes in count DATA do not rewrite any original target identity.
fn record_lookup_count_is(text : String, count : Int) -> Bool {
  if text.is_empty() {
    return false
  }
  for index in 0..<(text.length() - 1) {
    if text[index] != '0' {
      return false
    }
  }
  text[text.length() - 1] == (if count == 0 { '0' } else { '1' })
}

///|
pub fn project_record_key_lookup(
  request : RecordLookupRequest,
  status : Int,
  bytes : Bytes,
  limits : RecordPageLimits,
) -> Result[RecordLookupObservation, RecordLookupIssue] {
  if status != 200 {
    return Err(UnexpectedStatus)
  }
  let page = match
    project_record_page(bytes, request.catalog, request.names, limits) {
    Ok(value) => value
    Err(issue) => return Err(Page(issue))
  }
  let count = page.records.length()
  guard count <= 1 && page.total_count is Some(total) &&
    record_lookup_count_is(total, count) else {
    return Err(IncompleteResponse)
  }
  if count == 1 {
    let mut remaining = request.max_comparison_work
    let mut found = false
    for field in page.records[0].fields {
      if field.metadata.code.length() > remaining {
        return Err(BudgetExceeded)
      }
      remaining -= field.metadata.code.length()
      if field.metadata.code == request.key {
        guard @decode.text(field.value) is Ok(value) else {
          return Err(ForeignRecord)
        }
        if value.length() > remaining || request.value.length() >
          remaining - value.length() {
          return Err(BudgetExceeded)
        }
        if value != request.value {
          return Err(ForeignRecord)
        }
        found = true
        break
      }
    }
    if !found {
      return Err(ForeignRecord)
    }
  }
  Ok({ request, page, })
}

///|
pub fn record_key_lookup_page(
  observation : RecordLookupObservation,
) -> OriginalRecordPage {
  observation.page
}

///|
pub fn record_key_lookup_uses_request(
  observation : RecordLookupObservation,
  request : RecordLookupRequest,
) -> Bool {
  physical_equal(observation.request, request)
}

///|
/// Correspondence DATA only; an empty visible result is not global absence
/// or immunity to a concurrent create. Physical conditional writes, authority
/// and all retained request/response responsibilities remain with the Site.
pub fn match_record_key_lookup(
  original : RecordLookupObservation,
  observed : RecordLookupObservation,
) -> Result[Unit, RecordLookupIssue] {
  if !physical_equal(original.request, observed.request) {
    return Err(ForeignRequest)
  }
  if original.page.records.length() != observed.page.records.length() {
    return Err(ChangedObservation)
  }
  if original.page.records.length() == 1 &&
    (original.page.records[0].record_id != observed.page.records[0].record_id ||
    original.page.records[0].revision != observed.page.records[0].revision) {
    return Err(ChangedObservation)
  }
  Ok(())
}
