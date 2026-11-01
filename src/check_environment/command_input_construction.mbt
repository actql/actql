///|
// The original presence reader and metadata observer use the same field names.
let command_input_required_fields_key : String = "required_fields"

///|
let command_input_fields_key : String = "fields"

///|
priv struct CommandInputConstruction {
  presence_form : Bool
  fields : Int
  required : Int
  work : Int64
}

///|
fn observe_command_input_construction(
  root : @decode.Cursor,
) -> CommandInputConstruction {
  let mut presence_form = false
  let mut fields = 0
  let mut required = 0
  let mut work = 1L
  if @decode.object_length(root) is Some(count) {
    for i in 0..<count {
      let (name, child) = @decode.field_at(root, i).unwrap()
      work += 2L
      if name == command_input_fields_key {
        fields = @decode.object_length(child).unwrap_or(0)
        work += 1L
      }
      if name == command_input_required_fields_key {
        presence_form = true
        required = @decode.array_length(child).unwrap_or(0)
        work += 1L
      }
    }
  }
  { presence_form, fields, required, work, }
}

///|
fn command_input_retained_construction(
  v : CommandInputConstruction,
) -> @shape.CollectionConstructionExtent {
  if !v.presence_form {
    return { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
  }
  let f = v.fields.to_int64()
  // Every retained required name must be distinct and declared. Invalid names
  // refuse before insertion, so this is a structural bound, not a new cap.
  let r = Int::min(v.required, v.fields).to_int64()
  @shape.collection_construction_extent({
    records: 2L + f,
    record_references: 5L + 2L * f,
    record_words: 3L,
    reference_arrays: 1L,
    reference_items: f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 2L,
    map_entries: f + r,
  }).unwrap()
}

///|
fn command_input_working_construction(
  v : CommandInputConstruction,
) -> @shape.CollectionConstructionExtent {
  if !v.presence_form {
    return { record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }
  }
  let f = v.fields.to_int64()
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  // Original meter1H2W, root views2H3R, outer Contract/Shape2H2R1W,
  // shared field and three lookup sites, scalar3H3W, typed-return3H3R2W.
  // Declarations retain their own tuples/array beside the child's typed values.
  // Original checked Field assembly reuses the SAME NFC/sort/seen-Map scratch
  // bounded by the ValueContract owner for this same original subtree.
  @shape.collection_construction_extent({
    records: 11L + field.record_headers + 3L * child.record_headers + f,
    record_references: 8L +
    field.reference_slots +
    3L * child.reference_slots +
    2L * f,
    record_words: 8L + field.scalar_words + 3L * child.scalar_words,
    reference_arrays: 4L,
    reference_items: f + 6L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: 3L,
  }).unwrap()
}
