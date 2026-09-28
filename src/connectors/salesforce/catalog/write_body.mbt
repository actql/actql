///|
pub(all) struct WriteBodyLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum WriteBodyIssue {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  UnexpectedField(String)
  MissingField(String)
  NullNotAllowed(String)
  InvalidValue(String)
  /// A written `date` or `datetime` is outside Salesforce's documented range.
  ValueOutOfRange(String)
  /// A written `datetime` has a nonzero millisecond part; this revision
  /// writes whole seconds only.
  SubsecondTimestamp(String)
} derive(Eq, Debug)

///|
/// One bounded scalar row body. This is not an Effect admission or permission
/// to send a mutation; current authority and preview guards remain separate.
pub struct WriteBody {
  projection : WriteProjection
  json : String
}

///|
pub fn write_body_json(body : WriteBody) -> String {
  body.json
}

///|
pub fn write_body_projection(body : WriteBody) -> WriteProjection {
  body.projection
}

///|
/// Emit one field value. A written value (`observed` false) is an approved
/// ActQL value sent as it is; an observed value is the provider's current
/// value, in its own spelling, read into the same ActQL representation.
fn emit_write_cell(
  output : @encode.Writer,
  cursor : @decode.Cursor,
  field : FieldMetadata,
  observed? : Bool = false,
) -> Result[Unit, WriteBodyIssue] {
  if @decode.is_null(cursor) {
    if !field.nullable {
      return Err(NullNotAllowed(field.name))
    }
    @encode.null_value(output) catch {
      _ => return Err(BudgetExceeded)
    }
    return Ok(())
  }
  match field.native_type {
    "id"
    | "reference"
    | "string"
    | "textarea"
    | "email"
    | "phone"
    | "url"
    | "picklist"
    | "combobox" => {
      guard @decode.text(cursor) is Ok(value) else {
        return Err(InvalidValue(field.name))
      }
      @encode.string_value(output, value) catch {
        _ => return Err(BudgetExceeded)
      }
    }
    "boolean" => {
      guard @decode.boolean(cursor) is Ok(value) else {
        return Err(InvalidValue(field.name))
      }
      @encode.bool_value(output, value) catch {
        _ => return Err(BudgetExceeded)
      }
    }
    "int" => {
      guard @decode.int32(cursor) is Ok(value) else {
        return Err(InvalidValue(field.name))
      }
      @encode.number_value(output, value.to_double()) catch {
        _ => return Err(BudgetExceeded)
      }
    }
    "double" => {
      guard @decode.finite_number(cursor) is Ok(value) else {
        return Err(InvalidValue(field.name))
      }
      @encode.number_value(output, value) catch {
        _ => return Err(BudgetExceeded)
      }
    }
    "date" | "datetime" => {
      guard @decode.text(cursor) is Ok(text) else {
        return Err(InvalidValue(field.name))
      }
      let value = if !observed {
        if temporal_write_issue(field.native_type, text, field.name)
          is Some(issue) {
          return Err(issue)
        }
        text
      } else if field.native_type == "date" {
        guard actql_date(text) else { return Err(InvalidValue(field.name)) }
        text
      } else {
        guard salesforce_datetime_utc(text) is Some(utc) else {
          return Err(InvalidValue(field.name))
        }
        utc
      }
      @encode.string_value(output, value) catch {
        _ => return Err(BudgetExceeded)
      }
    }
    _ => return Err(InvalidValue(field.name))
  }
  Ok(())
}

///|
/// The selected field set is exact: omission requires a different projection,
/// while an included JSON null is an explicit request to clear that field.
pub fn prepare_write_body(
  projection : WriteProjection,
  bytes : Bytes,
  limits : WriteBodyLimits,
) -> Result[WriteBody, WriteBodyIssue] {
  prepare_write_body_omitting(projection, bytes, limits, [])
}

///|
/// As `prepare_write_body`, except that a field named in `omittable` may be
/// absent from this row: its Mapping omits it when the source value is null.
/// Any other absent field is still `MissingField`.
pub fn prepare_write_body_omitting(
  projection : WriteProjection,
  bytes : Bytes,
  limits : WriteBodyLimits,
  omittable : Array[String],
) -> Result[WriteBody, WriteBodyIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 1 || limits.max_depth < 1 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidBody
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        if issue.kind is @decode.BudgetExceeded {
          BudgetExceeded
        } else {
          InvalidBody
        },
      )
  }
  guard @decode.open_object(root) is Ok(object) &&
    @decode.object_field_names(root) is Ok(names) else {
    return Err(InvalidBody)
  }
  for name in names {
    if !projection.field_names.contains(name) {
      return Err(UnexpectedField(name))
    }
  }
  let ordered = projection.fields.copy()
  ordered.sort_by((left, right) => {
    @canonical.compare_utf16(left.name, right.name)
  })
  let output = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  @encode.begin_object(output) catch {
    _ => return Err(BudgetExceeded)
  }
  for field in ordered {
    guard @decode.lookup(object, field.name) is Some(cursor) else {
      if omittable.contains(field.name) {
        continue
      }
      return Err(MissingField(field.name))
    }
    @encode.key(output, field.name) catch {
      _ => return Err(BudgetExceeded)
    }
    match emit_write_cell(output, cursor, field) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  @encode.end_object(output) catch {
    _ => return Err(BudgetExceeded)
  }
  let json = @encode.finish(output) catch { _ => return Err(BudgetExceeded) }
  Ok({ projection, json, })
}

///|
/// The written value a row body refused before sending, as canonical JSON:
/// the Resource, the field, the declared ActQL type and why (`range`,
/// `precision`, `format` or `null`). The value itself is never part of it.
/// Other failures are not value refusals.
pub fn write_body_value_refusal_json(
  issue : WriteBodyIssue,
  projection : WriteProjection,
) -> String? {
  let (field, kind) = match issue {
    ValueOutOfRange(field) => (field, "range")
    SubsecondTimestamp(field) => (field, "precision")
    InvalidValue(field) => (field, "format")
    NullNotAllowed(field) => (field, "null")
    _ => return None
  }
  guard projection.fields.search_by(value => value.name == field) is Some(index) &&
    write_value_type(projection.fields[index].native_type)
    is Some(expected_type) else {
    return None
  }
  Some(
    object([
      ("expected_type", expected_type.to_json()),
      ("field", field.to_json()),
      ("kind", kind.to_json()),
      ("resource", projection.resource.to_json()),
    ]).stringify(),
  )
}
