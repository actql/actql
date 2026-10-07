///|
priv enum Emission {
  Value(Contract)
  FieldMap(Fields)
  FieldsAt(Fields, Int)
  Members(Array[(String, Emission)], Int)
  Key(String)
  TextValue(String)
  NumberValue(Double)
  BoolValue(Bool)
  End
}

///|
/// Exclusive emission of one checked contract into the caller's writer.
/// Object children are borrowed one at a time; names and text use the existing
/// bounded writer cursors. Cancellation invalidates the incomplete document.
struct CheckedEmission {
  writer : @encode.Writer
  mut pending : Array[Emission]
  max_frames : Int
  mut key : @encode.OrderedKeyEmitCursor?
  mut text : @encode.StringEmitCursor?
  mut done : Bool
  mut closed : Bool
}

///|
pub fn start_checked_emission(
  contract : Contract,
  writer : @encode.Writer,
  max_frames : Int,
) -> CheckedEmission raise @encode.EncodeFailure {
  if max_frames < 1 {
    raise @encode.OutputLimit
  }
  {
    writer,
    pending: [Value(contract)],
    max_frames,
    key: None,
    text: None,
    done: false,
    closed: false,
  }
}

///|
pub fn cancel_checked_emission(value : CheckedEmission) -> Unit {
  if !value.closed {
    value.closed = true
    value.pending = []
    if value.key is Some(cursor) {
      @encode.cancel_ordered_key(cursor)
    }
    if value.text is Some(cursor) {
      @encode.cancel_string_value(cursor)
    }
    value.key = None
    value.text = None
    if !value.done {
      @encode.cancel_writer(value.writer)
    }
  }
}

///|
fn push_emission(
  value : CheckedEmission,
  frame : Emission,
) -> Unit raise @encode.EncodeFailure {
  if value.pending.length() >= value.max_frames {
    raise @encode.OutputLimit
  }
  value.pending.push(frame)
}

///|
fn type_name(shape : Shape) -> String {
  match shape {
    Text(_) => "string"
    Number => "number"
    Boolean => "boolean"
    Timestamp => "timestamp"
    Date => "date"
    Json => "json"
    Decimal(..) => "decimal"
    Array(_, ..) => "array"
    Object(_) => "object"
    Vector(..) => "vector"
    ResourceRef(..) => "resource_ref"
    ArtifactRef(..) => "artifact_ref"
  }
}

///|
fn optional_number(
  members : Array[(String, Emission)],
  key : String,
  value : Int64?,
) -> Unit {
  if value is Some(n) {
    members.push((key, NumberValue(n.to_double())))
  }
}

///|
/// Emits the complete checked contract in canonical key order, including fixed fields.
/// Budgets and the choice of text/measurement/hash sink belong to the supplied Writer.
pub fn emit_checked(
  contract : Contract,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let cursor = start_checked_emission(contract, writer, 2147483647)
  while !advance_checked_emission(cursor) {
    ()
  }
}

///|
/// One structural transition or at most 64 UTF-16 units per call. Poll count
/// does not change the supplied writer's byte, node or depth consumption.
pub fn advance_checked_emission(
  cursor : CheckedEmission,
) -> Bool raise @encode.EncodeFailure {
  if cursor.closed || cursor.done {
    raise @encode.ClosedWriter
  }
  errdefer cancel_checked_emission(cursor)
  if cursor.key is Some(key) {
    if @encode.advance_ordered_key(key) {
      cursor.key = None
    }
  } else if cursor.text is Some(text) {
    if @encode.advance_string_value(text) {
      cursor.text = None
    }
  } else if cursor.pending.pop() is Some(frame) {
    let writer = cursor.writer
    match frame {
      Key(name) => cursor.key = Some(@encode.start_ordered_key(writer, name))
      TextValue(value) =>
        cursor.text = Some(@encode.start_string_value(writer, value))
      NumberValue(value) => @encode.number_value(writer, value)
      BoolValue(value) => @encode.bool_value(writer, value)
      End => @encode.end_object(writer)
      FieldMap(fields) => {
        @encode.begin_ordered_object(writer)
        push_emission(cursor, End)
        if !fields.values.is_empty() {
          push_emission(cursor, FieldsAt(fields, 0))
        }
      }
      FieldsAt(fields, index) => {
        if index + 1 < fields.values.length() {
          push_emission(cursor, FieldsAt(fields, index + 1))
        }
        let field = fields.values[index]
        push_emission(cursor, Value(field.contract))
        push_emission(cursor, Key(field.name))
      }
      Members(members, index) => {
        if index + 1 < members.length() {
          push_emission(cursor, Members(members, index + 1))
        }
        push_emission(cursor, members[index].1)
        push_emission(cursor, Key(members[index].0))
      }
      Value(value) => {
        @encode.begin_ordered_object(writer)
        let members : Array[(String, Emission)] = [
          ("nullable", BoolValue(value.nullable)),
          ("type", TextValue(type_name(value.shape))),
        ]
        match value.shape {
          Text(bounds) => {
            optional_number(members, "min_length", bounds.min_length)
            optional_number(members, "max_codepoints", bounds.max_codepoints)
            optional_number(members, "max_utf8_bytes", bounds.max_utf8_bytes)
          }
          Decimal(precision~, scale~) => {
            members.push(("precision", NumberValue(precision.to_double())))
            members.push(("scale", NumberValue(scale.to_double())))
          }
          Array(items, max_items~) => {
            members.push(("items", Value(items)))
            optional_number(members, "max_items", max_items)
          }
          Object(fields) => {
            members.push(("additional_properties", BoolValue(false)))
            members.push(("fields", FieldMap(fields)))
          }
          Vector(dimensions~) => {
            members.push(("dimensions", NumberValue(dimensions)))
            members.push(("element_type", TextValue("f32")))
          }
          ResourceRef(resource_kind~) =>
            members.push(("resource_kind", TextValue(resource_kind)))
          ArtifactRef(media_type~) =>
            if media_type is Some(media) {
              members.push(("media_type", TextValue(media)))
            }
          _ => ()
        }
        members.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
        // At most five fixed vocabulary members; never the object's fields.
        push_emission(cursor, End)
        push_emission(cursor, Members(members, 0))
      }
    }
  }
  if cursor.pending.is_empty() && cursor.key is None && cursor.text is None {
    cursor.done = true
    true
  } else {
    false
  }
}

///|
pub fn stringify_checked(
  contract : Contract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth)
  emit_checked(contract, writer)
  @encode.finish(writer)
}
