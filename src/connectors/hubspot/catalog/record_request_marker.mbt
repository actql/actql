///|
/// Private physical metadata for the original request, not an idempotency
/// key, a business selector or proof that the request was sent/applied.
pub struct RecordRequestMarker {
  priv catalog : PropertyCatalog
  property : String
  request_id : String
}

///|
/// The caller supplies the request identifier already associated with its
/// original Effect items. This function validates DATA; it issues no identity,
/// journal entry, grant or request and does not create the provider property.
pub fn prepare_record_request_marker(
  catalog : PropertyCatalog,
  property : String,
  request_id : String,
  limits : WriteBodyLimits,
) -> Result[RecordRequestMarker, RecordRequestIssue] {
  if !write_body_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if request_id.is_empty() || property == "id" {
    return Err(InvalidMarker)
  }
  match require_property_write(catalog, property) {
    Ok(_) => ()
    Err(issue) => return Err(Property(issue))
  }
  guard property_named(catalog, property) is Some(metadata) else {
    return Err(InvalidMarker)
  }
  // A marker must persist the exact original identifier. Numeric, option,
  // checkbox and other provider conversions cannot supply that fact.
  if metadata.native_type != "string" {
    return Err(InvalidMarker)
  }
  let writer = @encode.writer(
    limits.max_input_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let wire = try {
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, property)
    @encode.string_value(writer, request_id)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  match prepare_write_body(catalog, [property], @utf8.encode(wire), limits) {
    Ok(_) => Ok({ catalog, property, request_id, })
    Err(issue) => Err(Value(issue))
  }
}

///|
pub fn record_batch_request_marker(
  request : RecordBatchRequest,
) -> RecordRequestMarker? {
  request.marker
}

///|
/// Re-read only the complete original Encoder-produced string properties.
/// The business values stay in their original WriteBody; no rounded JSON
/// number, replacement WriteBody or extra logical field is introduced.
fn emit_marked_record_properties(
  writer : @encode.Writer,
  body : WriteBody,
  marker : RecordRequestMarker,
  limits : RecordRequestLimits,
) -> Unit raise @encode.EncodeFailure {
  let parsed = match
    @source.parse_json_bytes(
      @utf8.encode(@encode.document_text(body.properties_document)),
      {
        max_input_bytes: limits.max_body_bytes,
        max_nodes: limits.max_body_nodes,
        max_depth: limits.max_body_depth,
      },
    ) {
    Ok(value) => value
    Err(_) => raise @encode.OutputLimit
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: limits.max_body_nodes,
      max_depth: limits.max_body_depth,
      max_string_bytes: limits.max_body_bytes,
      max_total_string_bytes: limits.max_body_bytes,
    }) {
    Ok(value) => value
    Err(_) => raise @encode.OutputLimit
  }
  guard @decode.open_object(cursor) is Ok(object) else {
    raise @encode.InvalidStructure
  }
  if @decode.object_length(cursor) != Some(body.names.length()) {
    raise @encode.InvalidStructure
  }
  let names = body.names.copy()
  names.push(marker.property)
  names.sort_by(@canonical.compare_utf16)
  @encode.begin_ordered_object(writer)
  for name in names {
    @encode.ordered_key(writer, name)
    if name == marker.property {
      @encode.string_value(writer, marker.request_id)
    } else {
      guard @decode.lookup(object, name) is Some(value) else {
        raise @encode.InvalidStructure
      }
      guard @decode.text(value) is Ok(text) else {
        raise @encode.InvalidStructure
      }
      @encode.string_value(writer, text)
    }
  }
  @encode.end_object(writer)
}
