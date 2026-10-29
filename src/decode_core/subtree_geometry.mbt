///|
/// Measurements of this exact original subtree, not the whole admitted arena.
/// Selected field-name text values and all field names are inspected only for
/// UTF-16 length. No parse, Unicode scan, normalization or semantic admission.
pub(all) struct SubtreeGeometry {
  nodes : Int
  objects : Int
  arrays : Int
  fields : Int
  max_fields : Int
  max_array_items : Int
  max_selected_text_units : Int
  outer_depth : Int
  work : Int64
} derive(Eq, Debug)

///|
/// Every original index constructor appends preorder nodes, visiting one child
/// before its next sibling. Therefore the first later parent below root.index
/// closes this contiguous subtree, including raw JSON and flat scalar columns.
/// Constant storage: one returned9-word record, no Cursor/container copies.
/// Work counts actual node/field/ancestor/name-selection metadata visits; it
/// is not a character-comparison, validation-call or CPU instruction count.
pub fn observe_subtree_geometry(
  root : Cursor,
  selected_text_fields : Array[String],
) -> SubtreeGeometry {
  let mut work = 0L
  let mut outer_depth = 0
  let mut parent = root.tree[root.index].parent
  while parent >= 0 {
    outer_depth += 1
    work += 1L
    parent = root.tree[parent].parent
  }
  let mut nodes = 0
  let mut objects = 0
  let mut arrays = 0
  let mut fields = 0
  let mut max_fields = 0
  let mut max_array_items = 0
  let mut max_selected_text_units = 0
  for index = root.index; index < root.tree.length(); index = index + 1 {
    let node = root.tree[index]
    if index != root.index && node.parent < root.index {
      break
    }
    nodes += 1
    work += 1L
    match node.value {
      ObjectValue(values) => {
        objects += 1
        fields += values.length()
        max_fields = Int::max(max_fields, values.length())
        for field in values {
          work += 1L
          max_selected_text_units = Int::max(
            max_selected_text_units,
            field.key.length(),
          )
        }
      }
      ArrayValue(values) => {
        arrays += 1
        max_array_items = Int::max(max_array_items, values.length())
      }
      Text(value) =>
        if node.edge is Field(name, _) {
          for selected in selected_text_fields {
            work += 1L
            if selected == name {
              max_selected_text_units = Int::max(
                max_selected_text_units,
                value.length(),
              )
              break
            }
          }
        }
      _ => ()
    }
  }
  {
    nodes,
    objects,
    arrays,
    fields,
    max_fields,
    max_array_items,
    max_selected_text_units,
    outer_depth,
    work,
  }
}
