///|
/// Original Parameter type constructors only, excluding arbitrary default/meta
/// data. This quantity DATA does not interpret a ParameterType or accept syntax.
/// The caller separately funds full declaration preflight and actual defaults.
pub(all) struct ParameterReadConstructionGeometry {
  types : Int
  arrays : Int
  objects : Int
  fields : Int
  enumerants : Int
  enumeration_arrays : Int
  max_view_fields : Int
  max_identifier_units : Int
  work : Int64
} derive(Eq, Debug)

///|
priv struct ParameterQuantityWork {
  mut used : Int64
  mut max_fields : Int
  mut max_name : Int
}

///|
// Direct original indexed fields; no ObjectView, parser, field copy, Unicode
// normalization or type admission. Unknown/malformed syntax is left to the
// unchanged reader, including its first typed refusal and original limits.
fn parameter_quantity_child(
  source : @decode.Cursor,
  field : String,
  meter : ParameterQuantityWork,
) -> @decode.Cursor? {
  meter.used += 1L
  if @decode.object_length(source) is Some(count) {
    meter.max_fields = Int::max(meter.max_fields, count)
    for i in 0..<count {
      meter.used += 2L
      let (name, value) = @decode.field_at(source, i).unwrap()
      meter.max_name = Int::max(meter.max_name, name.length())
      if name == field {
        return Some(value)
      }
    }
  }
  None
}

///|
/// Must be reserved before entry. One bounded original-Cursor stack selects
/// only declared items/fields type positions; default/meta descendants do not
/// become typed Contract/ParameterRule constructors. All backing stays borrowed.
pub fn observe_parameter_read_construction_geometry(
  root : @decode.Cursor,
) -> ParameterReadConstructionGeometry {
  let meter : ParameterQuantityWork = { used: 0L, max_fields: 0, max_name: 0, }
  let pending : Array[@decode.Cursor] = [root]
  let mut types = 0
  let mut arrays = 0
  let mut objects = 0
  let mut fields = 0
  let mut enumerants = 0
  let mut enumeration_arrays = 0
  while pending.pop() is Some(current) {
    meter.used += 1L
    types += 1
    // The original initial open_object is built before closed-body refusal,
    // so its complete direct field count belongs to this scratch frame.
    let type_source = parameter_quantity_child(
      current, read_contract_type_field, meter,
    )
    let mut kind = ""
    if type_source is Some(value) && @decode.is_text(value) {
      kind = @decode.text(value).unwrap()
      meter.max_name = Int::max(meter.max_name, kind.length())
    }
    if kind == "array" {
      arrays += 1
      if parameter_quantity_child(current, parameter_items_field, meter)
        is Some(child) {
        pending.push(child)
      }
    } else if kind == "object" {
      objects += 1
      if parameter_quantity_child(current, parameter_fields_field, meter)
        is Some(children) &&
        @decode.object_length(children) is Some(count) {
        fields += count
        meter.max_fields = Int::max(meter.max_fields, count)
        for i in 0..<count {
          meter.used += 2L
          let (name, child) = @decode.field_at(children, i).unwrap()
          meter.max_name = Int::max(meter.max_name, name.length())
          pending.push(child)
        }
      }
    } else if kind == "string" {
      if parameter_quantity_child(current, "enum", meter) is Some(values) {
        if @decode.array_length(values) is Some(count) {
          enumeration_arrays += 1
          enumerants += count
        }
      }
      if parameter_quantity_child(current, "format", meter) is Some(value) &&
        @decode.is_text(value) {
        meter.max_name = Int::max(
          meter.max_name,
          @decode.text(value).unwrap().length(),
        )
      }
    }
  }
  {
    types,
    arrays,
    objects,
    fields,
    enumerants,
    enumeration_arrays,
    max_view_fields: meter.max_fields,
    max_identifier_units: meter.max_name,
    work: meter.used,
  }
}
