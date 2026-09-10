///|
priv enum Emission {
  Value(Contract)
  FieldMap(Fields)
  Key(String)
  TextValue(String)
  NumberValue(Double)
  BoolValue(Bool)
  End
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
  let work : Array[Emission] = [Value(contract)]
  while !work.is_empty() {
    match work.pop().unwrap() {
      Key(name) => @encode.key(writer, name)
      TextValue(value) => @encode.string_value(writer, value)
      NumberValue(value) => @encode.number_value(writer, value)
      BoolValue(value) => @encode.bool_value(writer, value)
      End => @encode.end_object(writer)
      FieldMap(fields) => {
        @encode.begin_object(writer)
        work.push(End)
        for i = fields.values.length() - 1; i >= 0; i = i - 1 {
          let field = fields.values[i]
          work.push(Value(field.contract))
          work.push(Key(field.name))
        }
      }
      Value(value) => {
        @encode.begin_object(writer)
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
        work.push(End)
        for i = members.length() - 1; i >= 0; i = i - 1 {
          work.push(members[i].1)
          work.push(Key(members[i].0))
        }
      }
    }
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
