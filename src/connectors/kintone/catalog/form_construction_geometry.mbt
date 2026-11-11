///|
/// Scalar geometry of the SAME observed catalog. No path vector, metadata
/// clone, parser, contract or replacement observation is constructed.
pub(all) struct FormConstructionGeometry {
  fields : Int
  path_slots : Int64
  max_path_depth : Int
} derive(Eq, Debug)

///|
pub fn form_construction_geometry(
  original : FormFieldCatalog,
) -> FormConstructionGeometry? {
  let mut path_slots = 0L
  let mut max_path_depth = 0
  for field in original.fields {
    let depth = field.path.length()
    if path_slots > 9223372036854775807L - depth.to_int64() {
      return None
    }
    path_slots += depth.to_int64()
    max_path_depth = Int::max(max_path_depth, depth)
  }
  Some({ fields: original.fields.length(), path_slots, max_path_depth, })
}

///|
/// Scalar shape of the original selected trees, including descendants of an
/// empty SUBTABLE. Names and metadata are borrowed, not reconstructed.
pub(all) struct SelectedFormConstructionGeometry {
  fields : Int
  tables : Int
  max_children : Int
  max_code_units : Int
  code_units : Int64
} derive(Eq, Debug)

///|
pub fn selected_form_construction_geometry(
  original : FormFieldCatalog,
  names : Array[String],
) -> SelectedFormConstructionGeometry? {
  let mut fields = 0
  let mut tables = 0
  let mut max_children = 0
  let mut max_code_units = 2
  let mut code_units = 0L
  for field in original.fields {
    if field.path.is_empty() {
      return None
    }
    let mut selected = false
    for name in names {
      if name == field.path[0] {
        selected = true
        break
      }
    }
    if !selected {
      continue
    }
    fields += 1
    let size = field.code.length()
    if code_units > 9223372036854775807L - size.to_int64() {
      return None
    }
    code_units += size.to_int64()
    max_code_units = Int::max(max_code_units, size)
    if field.native_type == "SUBTABLE" {
      tables += 1
      let mut children = 0
      for child in original.fields {
        if child.path.length() == field.path.length() + 1 {
          let mut same = true
          for index in 0..<field.path.length() {
            if child.path[index] != field.path[index] {
              same = false
              break
            }
          }
          if same {
            children += 1
          }
        }
      }
      max_children = Int::max(max_children, children)
    }
  }
  Some({ fields, tables, max_children, max_code_units, code_units, })
}
