///|
/// An owned view of the initial exact-count profile, not executable evidence.
/// Keep checked field identities; no argument roots are fabricated for fields.
struct PreparedCountGroup {
  checked : @relation.CheckedOperation
  keys : Array[@schema.FieldName]
  counts : Array[PreparedCount]
  name_bytes : Int
}

///|
pub struct PreparedCount {
  name : String
  field : @schema.FieldName?
  distinct : Bool?
}

///|
pub(all) enum CountGroupIssue {
  NotGroup
  UnsupportedAggregate(Int)
  InvalidLimits
  PreparationLimit
} derive(Eq, Debug)

///|
pub fn prepare_count_group(
  checked : @relation.CheckedOperation,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedCountGroup, CountGroupIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard @relation.group(checked) is Some(group) else { return Err(NotGroup) }
  // The shared checked accessor preserves repeated grouping occurrences.
  // Schema width does not bound their count. Check the actual occurrences
  // before constructing further arrays or processing names.
  let count = @relation.aggregate_count(group)
  if count > max_entries {
    return Err(PreparationLimit)
  }
  let checked_keys = @relation.group_keys(group)
  if checked_keys.length() > max_entries - count {
    return Err(PreparationLimit)
  }
  let mut remaining = max_name_bytes
  let spend_name = fn(name : String) -> Bool {
    if name.length() > remaining {
      return false
    }
    let bytes = @utf8.encode(name).length()
    if bytes > remaining {
      return false
    }
    remaining -= bytes
    true
  }
  let keys = []
  for key in checked_keys {
    if !spend_name(@schema.reference_name(key.field)) {
      return Err(PreparationLimit)
    }
    keys.push(key.field)
  }
  let counts = []
  for i in 0..<count {
    let aggregate = @relation.aggregate_at(group, i).unwrap()
    if @relation.aggregate_function(aggregate) != @relation.Count ||
      @relation.aggregate_filter(aggregate) is Some(_) ||
      @relation.aggregate_distinct(aggregate) == Some(true) {
      return Err(UnsupportedAggregate(i))
    }
    let field = match @relation.aggregate_argument(aggregate) {
      Rows => None
      Field(key) => Some(key.field)
      Expression(_) => return Err(UnsupportedAggregate(i))
    }
    let name = @relation.aggregate_name(aggregate)
    if !spend_name(name) {
      return Err(PreparationLimit)
    }
    if field is Some(field) && !spend_name(@schema.reference_name(field)) {
      return Err(PreparationLimit)
    }
    counts.push({
      name,
      field,
      distinct: @relation.aggregate_distinct(aggregate),
    })
  }
  Ok({ checked, keys, counts, name_bytes: max_name_bytes - remaining, })
}

///|
pub fn count_group_checked(
  group : PreparedCountGroup,
) -> @relation.CheckedOperation {
  group.checked
}

///|
pub fn count_group_key_count(group : PreparedCountGroup) -> Int {
  group.keys.length()
}

///|
pub fn count_group_key_at(
  group : PreparedCountGroup,
  index : Int,
) -> @schema.FieldName? {
  group.keys.get(index)
}

///|
pub fn count_group_aggregate_count(group : PreparedCountGroup) -> Int {
  group.counts.length()
}

///|
pub fn count_group_aggregate_at(
  group : PreparedCountGroup,
  index : Int,
) -> PreparedCount? {
  group.counts.get(index)
}

///|
fn emit_count_group_params(
  group : PreparedCountGroup,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "aggs")
  @encode.begin_object(out)
  for count in group.counts {
    @encode.key(out, count.name)
    @encode.begin_object(out)
    if count.distinct is Some(value) {
      @encode.key(out, "distinct")
      @encode.bool_value(out, value)
    }
    if count.field is Some(field) {
      @encode.key(out, "field")
      @encode.string_value(out, @schema.reference_name(field))
    }
    @encode.key(out, "fn")
    @encode.string_value(out, "count")
    @encode.end_object(out)
  }
  @encode.end_object(out)
  @encode.key(out, "by")
  @encode.begin_array(out)
  for field in group.keys {
    @encode.string_value(out, @schema.reference_name(field))
  }
  @encode.end_array(out)
  @encode.end_object(out)
}
