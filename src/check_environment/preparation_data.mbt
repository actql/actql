///|
pub(all) struct EnvironmentPreparationData {
  members : Int64
  max_fields : Int64
  max_name_utf16 : Int64
  inspection_work : Int64
}

///|
/// Original admitted schema-bearing member sizes, never a schema verdict.
/// Unrelated Model prompts and the outer member list do not become a row width.
/// No parsing, hashing, member identity or schema admission is repeated.
pub fn preparation_data_geometry(
  original : WireEnvironment,
) -> EnvironmentPreparationData {
  let mut fields = 0L
  let mut name = 0L
  let mut work = 1L
  for section in [SchemaSnapshots, SourceViews, MappingContracts] {
    for i in 0..<member_count(original, section) {
      let item = original.sections[position(section)][i]
      let geometry = @decode.observe_subtree_construction_geometry(item.cursor)
      work += geometry.work + 1L
      fields = Int64::max(
        fields,
        Int64::max(
          geometry.max_object_fields.to_int64(),
          geometry.array_items.to_int64(),
        ),
      )
      name = Int64::max(
        name,
        Int64::max(
          geometry.max_key_utf16.to_int64(),
          geometry.max_text_utf16.to_int64(),
        ),
      )
    }
  }
  {
    members: original.members.to_int64(),
    max_fields: fields,
    max_name_utf16: name,
    inspection_work: work,
  }
}
