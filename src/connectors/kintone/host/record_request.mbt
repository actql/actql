///|
fn record_request_id(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for unit in value {
    if unit < '0' || unit > '9' {
      return false
    }
  }
  true
}

///|
/// Closed presence projection for private JS forwarding. It creates no
/// provider cursor, original identity, permission or completion evidence.
pub fn record_request_cursor(
  fields : Array[String],
) -> Result[String?, RecordReadIssue] {
  if fields.length() > 1 {
    return Err(InvalidRequest)
  }
  if fields.is_empty() {
    return Ok(None)
  }
  if !record_request_id(fields[0]) {
    return Err(InvalidRequest)
  }
  Ok(Some(fields[0]))
}

///|
/// Compare the provider's numeric seek ordering without converting, rewriting
/// or replacing either original API ID used in a request or ResourceRef.
fn record_id_after(value : String, prior : String) -> Bool {
  let mut left = 0
  let mut right = 0
  while left < value.length() && value[left] == '0' {
    left += 1
  }
  while right < prior.length() && prior[right] == '0' {
    right += 1
  }
  let length = value.length() - left
  let previous = prior.length() - right
  if length != previous {
    return length > previous
  }
  for index in 0..<length {
    if value[left + index] != prior[right + index] {
      return value[left + index] > prior[right + index]
    }
  }
  false
}

///|
/// Fixed JSON parameters for the documented POST + GET method-override form.
/// The physical caller pins the endpoint/header and obtains its own read use.
pub fn record_form_request_body(
  prepared : PreparedRecordRead,
  max_bytes : Int,
) -> Result[String, RecordReadIssue] {
  record_form_body(prepared.original.catalog.app_id, max_bytes)
}

///|
fn record_form_body(
  app : String,
  max_bytes : Int,
) -> Result[String, RecordReadIssue] {
  if max_bytes <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, 4, 2) catch {
    issue => return Err(RequestEncoding(issue))
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "app")
    @encode.string_value(writer, app)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => {
      @encode.cancel_writer(writer)
      Err(RequestEncoding(issue))
    }
  }
}

///|
/// Selection comes from the same original acquisition, not a caller-supplied
/// query. Unpushed predicates/order remain in the existing Common pipeline.
/// Kintone's JSON request supports at most 1000 selected field codes; the
/// original response and request byte reservations remain caller obligations.
pub fn record_page_request_body(
  prepared : PreparedRecordRead,
  cursor : String?,
  per_page : Int,
  max_bytes : Int,
) -> Result[String, RecordReadIssue] {
  record_page_body(
    prepared.original.catalog.app_id,
    prepared.names,
    cursor,
    per_page,
    max_bytes,
  )
}

///|
fn record_page_body(
  app : String,
  names : Array[String],
  cursor : String?,
  per_page : Int,
  max_bytes : Int,
) -> Result[String, RecordReadIssue] {
  if max_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if per_page <= 0 || per_page > 500 || names.length() > 998 {
    return Err(InvalidRequest)
  }
  let prefix = match cursor {
    None => ""
    Some(value) => {
      if value.length() > max_bytes || !record_request_id(value) {
        return Err(InvalidRequest)
      }
      "$id > " + value + " "
    }
  }
  let query = prefix + "order by $id asc limit " + per_page.to_string()
  let writer = @encode.writer(max_bytes, names.length() + 12, 3) catch {
    issue => return Err(RequestEncoding(issue))
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "app")
    @encode.string_value(writer, app)
    @encode.key(writer, "fields")
    @encode.begin_array(writer)
    @encode.string_value(writer, "$id")
    @encode.string_value(writer, "$revision")
    for field in names {
      @encode.string_value(writer, field)
    }
    @encode.end_array(writer)
    @encode.key(writer, "query")
    @encode.string_value(writer, query)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => {
      @encode.cancel_writer(writer)
      Err(RequestEncoding(issue))
    }
  }
}

///|
/// A short original page ends this seek traversal. totalCount, a timeout or a
/// transport return alone never does. No cursor grants another request use.
pub fn record_page_next_cursor(
  read : RecordRead,
  prior : String?,
  per_page : Int,
) -> Result[String?, RecordReadIssue] {
  if per_page <= 0 || per_page > 500 {
    return Err(InvalidRequest)
  }
  if prior is Some(value) && !record_request_id(value) {
    return Err(InvalidRequest)
  }
  let ids = match record_read_page_ids(read) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if ids.length() > per_page {
    return refuse_record_read(read, InvalidPageOrder)
  }
  let mut cursor = prior
  for id in ids {
    if !record_request_id(id) {
      return refuse_record_read(read, InvalidPageOrder)
    }
    if cursor is Some(previous) && !record_id_after(id, previous) {
      return refuse_record_read(read, InvalidPageOrder)
    }
    cursor = Some(id)
  }
  if ids.length() < per_page {
    Ok(None)
  } else {
    Ok(cursor)
  }
}
