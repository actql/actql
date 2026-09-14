///|
/// Bounded view of the existing checked inner-join contract. No cardinality
/// assumption, input evidence or physical ordering is invented by preparation.
struct PreparedInnerJoin {
  checked : @join.CheckedJoin
  keys : Array[(@schema.FieldName, @schema.FieldName)]
  projection : Array[InnerJoinField]
  name_bytes : Int
}

///|
pub struct InnerJoinField {
  output : @schema.FieldName
  input : @schema.FieldName
}

///|
pub(all) enum InnerJoinIssue {
  InvalidLimits
  UnsupportedKind
  PreparationLimit
  InvalidCheckedShape
  InvalidGuard
} derive(Eq, Debug)

///|
pub fn prepare_inner_join(
  checked : @join.CheckedJoin,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedInnerJoin, InnerJoinIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  if @join.kind(checked) != @join.Inner {
    return Err(UnsupportedKind)
  }
  let key_count = @join.key_count(checked)
  let schema = @join.output_schema(checked)
  let width = @schema.field_count(schema)
  if key_count > max_entries || width > max_entries - key_count {
    return Err(PreparationLimit)
  }
  let mut remaining = max_name_bytes
  let spend = fn(field : @schema.FieldName) -> Bool {
    let name = @schema.reference_name(field)
    if name.length() > remaining {
      return false
    }
    let size = @utf8.encode(name).length()
    if size > remaining {
      return false
    }
    remaining -= size
    true
  }
  let keys = []
  for index in 0..<key_count {
    let pair = @join.key_at(checked, index).unwrap()
    if !spend(pair.left) || !spend(pair.right) {
      return Err(PreparationLimit)
    }
    keys.push((pair.left, pair.right))
  }
  // The checked projection's width was bounded before requesting its copy.
  // Omitted projection retains both qualified namespaces; aliases stay distinct.
  let authored = @join.projection(checked)
  let projection = []
  for index in 0..<width {
    let output = @schema.field_at(schema, index).unwrap().name
    let input = match authored {
      None => output
      Some(fields) => {
        guard fields.get(index) is Some(field) && field.output == output else {
          return Err(InvalidCheckedShape)
        }
        field.input
      }
    }
    if !spend(output) || !spend(input) {
      return Err(PreparationLimit)
    }
    projection.push({ output, input, })
  }
  Ok({ checked, keys, projection, name_bytes: max_name_bytes - remaining, })
}

///|
pub fn inner_join_checked(join : PreparedInnerJoin) -> @join.CheckedJoin {
  join.checked
}

///|
pub fn inner_join_key_count(join : PreparedInnerJoin) -> Int {
  join.keys.length()
}

///|
pub fn inner_join_key_at(
  join : PreparedInnerJoin,
  index : Int,
) -> (@schema.FieldName, @schema.FieldName)? {
  join.keys.get(index)
}

///|
pub fn inner_join_field_count(join : PreparedInnerJoin) -> Int {
  join.projection.length()
}

///|
pub fn inner_join_field_at(
  join : PreparedInnerJoin,
  index : Int,
) -> InnerJoinField? {
  join.projection.get(index)
}
