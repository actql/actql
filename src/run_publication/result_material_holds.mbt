///|
/// Durable ownership of one published Result generation. Physical stores
/// persist each returned body with compare-and-swap before acting on it.
pub(all) enum ResultMaterialHoldIssue {
  InvalidMaterialHold
  MaterialHoldConflict
  MaterialHoldLimit
  MaterialHoldEncoding
} derive(Eq, Debug)

///|
struct ResultMaterialHolds {
  binding_cid : String
  material_generation_cid : String
  mut revision : Int
  mut accepting_readers : Bool
  mut consumer_holds : Array[String]
  released_consumers : Array[String]
  mut active_readers : Array[String]
  ended_readers : Array[String]
}

///|
fn material_holds_sorted_unique(values : Array[String]) -> Bool {
  for index = 0; index < values.length(); index = index + 1 {
    if !valid_contract_cid(values[index]) ||
      (
        index > 0 &&
        @canonical.compare_utf16(values[index - 1], values[index]) >= 0
      ) {
      return false
    }
  }
  true
}

///|
fn material_holds_disjoint(
  first : Array[String],
  second : Array[String],
) -> Bool {
  for identity in first {
    if second.contains(identity) {
      return false
    }
  }
  true
}

///|
fn material_holds_valid(value : ResultMaterialHolds) -> Bool {
  valid_contract_cid(value.binding_cid) &&
  valid_contract_cid(value.material_generation_cid) &&
  value.revision >= 0 &&
  value.consumer_holds.length() + value.released_consumers.length() > 0 &&
  material_holds_sorted_unique(value.consumer_holds) &&
  material_holds_sorted_unique(value.released_consumers) &&
  material_holds_sorted_unique(value.active_readers) &&
  material_holds_sorted_unique(value.ended_readers) &&
  material_holds_disjoint(value.consumer_holds, value.released_consumers) &&
  material_holds_disjoint(value.active_readers, value.ended_readers) &&
  (!value.accepting_readers || !value.consumer_holds.is_empty())
}

///|
fn material_holds_emit_array(
  writer : @encode.Writer,
  values : Array[String],
) -> Unit raise {
  @encode.begin_array(writer)
  for value in values {
    @encode.string_value(writer, value)
  }
  @encode.end_array(writer)
}

///|
pub fn result_material_holds_wire(
  value : ResultMaterialHolds,
) -> Result[String, ResultMaterialHoldIssue] {
  if !material_holds_valid(value) ||
    value.consumer_holds.length() + value.released_consumers.length() > 1024 ||
    value.active_readers.length() + value.ended_readers.length() > 1024 {
    return Err(MaterialHoldLimit)
  }
  let writer = @encode.writer(200000, 5000, 4) catch {
    _ => return Err(MaterialHoldEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "accepting_readers")
    @encode.bool_value(writer, value.accepting_readers)
    @encode.key(writer, "active_readers")
    material_holds_emit_array(writer, value.active_readers)
    @encode.key(writer, "binding_cid")
    @encode.string_value(writer, value.binding_cid)
    @encode.key(writer, "consumer_holds")
    material_holds_emit_array(writer, value.consumer_holds)
    @encode.key(writer, "ended_readers")
    material_holds_emit_array(writer, value.ended_readers)
    @encode.key(writer, "material_generation_cid")
    @encode.string_value(writer, value.material_generation_cid)
    @encode.key(writer, "released_consumers")
    material_holds_emit_array(writer, value.released_consumers)
    @encode.key(writer, "revision")
    @encode.number_value(writer, value.revision.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-result-material-holds/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(MaterialHoldEncoding)
  }
}

///|
fn material_holds_read_array(value : @json.CanonicalValue?) -> Array[String]? {
  guard value is Some(@json.Array(items)) else { return None }
  let result : Array[String] = []
  for item in @json.array_values(items) {
    guard item is @json.String(identity) else { return None }
    result.push(identity)
  }
  Some(result)
}

///|
pub fn admit_result_material_holds(
  wire : String,
) -> Result[ResultMaterialHolds, ResultMaterialHoldIssue] {
  let body = match parse_contract_wire(wire, 200000, 5000, 4) {
    Ok(value) => value
    Err(_) => return Err(InvalidMaterialHold)
  }
  guard @json.object_fields(body) is Some(fields) &&
    fields.length() == 9 &&
    optional_string(@json.object_field(body, "version")) ==
    Some("actql-result-material-holds/0.1") &&
    @json.object_field(body, "accepting_readers") is Some(@json.Bool(accepting)) &&
    optional_string(@json.object_field(body, "binding_cid")) is Some(binding) &&
    optional_string(@json.object_field(body, "material_generation_cid"))
    is Some(material) &&
    delivery_optional_count(@json.object_field(body, "revision"))
    is Some(revision64) &&
    revision64 >= 0L &&
    revision64 <= 2147483647L &&
    material_holds_read_array(@json.object_field(body, "consumer_holds"))
    is Some(consumers) &&
    material_holds_read_array(@json.object_field(body, "released_consumers"))
    is Some(released) &&
    material_holds_read_array(@json.object_field(body, "active_readers"))
    is Some(readers) &&
    material_holds_read_array(@json.object_field(body, "ended_readers"))
    is Some(ended) else {
    return Err(InvalidMaterialHold)
  }
  let value = {
    binding_cid: binding,
    material_generation_cid: material,
    revision: revision64.to_int(),
    accepting_readers: accepting,
    consumer_holds: consumers,
    released_consumers: released,
    active_readers: readers,
    ended_readers: ended,
  }
  if !material_holds_valid(value) ||
    result_material_holds_wire(value) != Ok(wire) {
    return Err(InvalidMaterialHold)
  }
  Ok(value)
}

///|
pub fn begin_result_material_holds(
  binding_cid : String,
  material_generation_cid : String,
) -> Result[ResultMaterialHolds, ResultMaterialHoldIssue] {
  let value = {
    binding_cid,
    material_generation_cid,
    revision: 0,
    accepting_readers: true,
    consumer_holds: [binding_cid],
    released_consumers: [],
    active_readers: [],
    ended_readers: [],
  }
  if material_holds_valid(value) {
    Ok(value)
  } else {
    Err(InvalidMaterialHold)
  }
}

///|
pub fn result_material_holds_revision(value : ResultMaterialHolds) -> Int {
  value.revision
}

///|
pub fn result_material_holds_binding(value : ResultMaterialHolds) -> String {
  value.binding_cid
}

///|
pub fn result_material_holds_generation(value : ResultMaterialHolds) -> String {
  value.material_generation_cid
}

///|
pub fn result_material_holds_reclaimable(value : ResultMaterialHolds) -> Bool {
  !value.accepting_readers &&
  value.consumer_holds.is_empty() &&
  value.active_readers.is_empty()
}

///|
pub fn prepare_result_material_holds_step(
  value : ResultMaterialHolds,
  operation : String,
  identity : String,
) -> Result[ResultMaterialHolds, ResultMaterialHoldIssue] {
  if !material_holds_valid(value) ||
    (operation != "stop_readers" && !valid_contract_cid(identity)) {
    return Err(InvalidMaterialHold)
  }
  let next = {
    ..value,
    consumer_holds: value.consumer_holds.copy(),
    released_consumers: value.released_consumers.copy(),
    active_readers: value.active_readers.copy(),
    ended_readers: value.ended_readers.copy(),
  }
  let mut changed = false
  match operation {
    "add_consumer" => {
      if !next.accepting_readers || next.released_consumers.contains(identity) {
        return Err(MaterialHoldConflict)
      }
      if !next.consumer_holds.contains(identity) {
        next.consumer_holds.push(identity)
        next.consumer_holds.sort_by(@canonical.compare_utf16)
        changed = true
      }
    }
    "release_consumer" => {
      if !next.consumer_holds.contains(identity) {
        if next.released_consumers.contains(identity) {
          return Ok(value)
        }
        return Err(MaterialHoldConflict)
      }
      next.consumer_holds = next.consumer_holds.filter(item => item != identity)
      next.released_consumers.push(identity)
      next.released_consumers.sort_by(@canonical.compare_utf16)
      if next.consumer_holds.is_empty() {
        next.accepting_readers = false
      }
      changed = true
    }
    "begin_reader" => {
      if !next.accepting_readers || next.ended_readers.contains(identity) {
        return Err(MaterialHoldConflict)
      }
      if !next.active_readers.contains(identity) {
        next.active_readers.push(identity)
        next.active_readers.sort_by(@canonical.compare_utf16)
        changed = true
      }
    }
    "end_reader" => {
      if !next.active_readers.contains(identity) {
        if next.ended_readers.contains(identity) {
          return Ok(value)
        }
        return Err(MaterialHoldConflict)
      }
      next.active_readers = next.active_readers.filter(item => item != identity)
      next.ended_readers.push(identity)
      next.ended_readers.sort_by(@canonical.compare_utf16)
      changed = true
    }
    "stop_readers" =>
      if next.accepting_readers {
        next.accepting_readers = false
        changed = true
      }
    _ => return Err(InvalidMaterialHold)
  }
  if !changed {
    return Ok(value)
  }
  next.revision = next.revision + 1
  if next.revision <= value.revision ||
    !material_holds_valid(next) ||
    result_material_holds_wire(next) is Err(_) {
    return Err(MaterialHoldLimit)
  }
  Ok(next)
}
