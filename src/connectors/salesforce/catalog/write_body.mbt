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
  /// A written or observed decimal has a nonzero digit beyond its scale.
  ValueBeyondScale(String)
} derive(Eq, Debug)

///|
/// One bounded scalar row body. This is not an Effect admission or permission
/// to send a mutation; current authority and preview guards remain separate.
/// `json` is the provider request body; `value_json` is the same row as ActQL
/// values, the meaning a Preview states. They differ only in how a decimal
/// is spelled: a JSON number to the provider, fixed-scale text in ActQL.
pub struct WriteBody {
  projection : WriteProjection
  json : String
  value_json : String
}

///|
pub fn write_body_json(body : WriteBody) -> String {
  body.json
}

///|
/// The row as ActQL values: what a Preview approves and what a recovered
/// request is rebuilt from.
pub fn write_body_value_json(body : WriteBody) -> String {
  body.value_json
}

///|
pub fn write_body_projection(body : WriteBody) -> WriteProjection {
  body.projection
}

///|
/// Write one value to each writer.
fn emit_each(
  writers : Array[@encode.Writer],
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Result[Unit, WriteBodyIssue] {
  for writer in writers {
    emit(writer) catch {
      _ => return Err(BudgetExceeded)
    }
  }
  Ok(())
}

///|
/// Emit one field value. A written value is an approved ActQL value: it is
/// sent to `output` in the provider's spelling and, when `value_output` is
/// given, kept there as the same ActQL value. An observed value
/// (`observed_source`, the bytes it was parsed from) is the provider's
/// current value in its own spelling, read into `output` as an ActQL value.
fn emit_write_cell(
  output : @encode.Writer,
  cursor : @decode.Cursor,
  field : FieldMetadata,
  observed_source? : Bytes? = None,
  value_output? : @encode.Writer? = None,
) -> Result[Unit, WriteBodyIssue] {
  let writers = match value_output {
    Some(value) => [output, value]
    None => [output]
  }
  if @decode.is_null(cursor) {
    if !field.nullable {
      return Err(NullNotAllowed(field.name))
    }
    return emit_each(writers, writer => @encode.null_value(writer))
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
      emit_each(writers, writer => @encode.string_value(writer, value))
    }
    "boolean" => {
      guard @decode.boolean(cursor) is Ok(value) else {
        return Err(InvalidValue(field.name))
      }
      emit_each(writers, writer => @encode.bool_value(writer, value))
    }
    "int" => {
      guard @decode.int32(cursor) is Ok(value) else {
        return Err(InvalidValue(field.name))
      }
      emit_each(writers, writer => {
        @encode.number_value(writer, value.to_double())
      })
    }
    "double" => {
      guard double_decimal(field) is Some((precision, scale)) else {
        return Err(InvalidValue(field.name))
      }
      match observed_source {
        Some(source) => {
          // The value the provider's number text denotes, as the declared
          // decimal. `finite_number` only checks that it is a JSON number.
          guard @decode.finite_number(cursor) is Ok(_) &&
            source_lexeme(source, cursor) is Some(lexeme) else {
            return Err(InvalidValue(field.name))
          }
          match json_number_decimal(lexeme, precision, scale) {
            Ok(text) =>
              emit_each([output], writer => @encode.string_value(writer, text))
            Err(DecimalFormat) => Err(InvalidValue(field.name))
            Err(DecimalRange) => Err(ValueOutOfRange(field.name))
            Err(DecimalScale) => Err(ValueBeyondScale(field.name))
          }
        }
        None => {
          // An approved ActQL decimal, sent as the same number text.
          guard @decode.text(cursor) is Ok(text) else {
            return Err(InvalidValue(field.name))
          }
          if decimal_write_issue(text, precision, scale, field.name)
            is Some(issue) {
            return Err(issue)
          }
          match
            emit_each([output], writer => {
              @encode.decimal_number_value(writer, text)
            }) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
          match value_output {
            Some(value) =>
              emit_each([value], writer => @encode.string_value(writer, text))
            None => Ok(())
          }
        }
      }
    }
    "date" | "datetime" => {
      guard @decode.text(cursor) is Ok(text) else {
        return Err(InvalidValue(field.name))
      }
      let value = if observed_source is None {
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
      emit_each(writers, writer => @encode.string_value(writer, value))
    }
    _ => Err(InvalidValue(field.name))
  }
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
  let (output, values) = (
    @encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth),
    @encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth),
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  match emit_each([output, values], writer => @encode.begin_object(writer)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for field in ordered {
    guard @decode.lookup(object, field.name) is Some(cursor) else {
      if omittable.contains(field.name) {
        continue
      }
      return Err(MissingField(field.name))
    }
    match
      emit_each([output, values], writer => @encode.key(writer, field.name)) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match emit_write_cell(output, cursor, field, value_output=Some(values)) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match emit_each([output, values], writer => @encode.end_object(writer)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (json, value_json) = (@encode.finish(output), @encode.finish(values)) catch {
    _ => return Err(BudgetExceeded)
  }
  Ok({ projection, json, value_json, })
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
    ValueBeyondScale(field) => (field, "scale")
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
