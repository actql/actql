///|
/// Actual quantities in one immutable admitted subtree. This is borrowed
/// Source/index metadata, not a repeated parser, semantic verdict or grant.
/// UTF16 quantities include original field names and scalar Text only.
pub(all) struct SubtreeConstructionGeometry {
  nodes : Int
  arrays : Int
  array_items : Int
  objects : Int
  fields : Int
  texts : Int
  max_object_fields : Int
  max_key_utf16 : Int
  max_text_utf16 : Int
  total_utf16 : Int64
  work : Int64
} derive(Eq, Debug)

///|
/// Read the SAME contiguous admitted preorder span. No child Cursor, Map,
/// subtree array, String or normalized copy is constructed in the walk. The
/// only output is this fixed scalar DATA record. The caller funds its frame
/// before entry; original input/backing remains with the admitted tree owner.
pub fn observe_subtree_construction_geometry(
  root : Cursor,
) -> SubtreeConstructionGeometry {
  let (nodes, spine_work) = observe_subtree_size(root)
  let mut arrays = 0
  let mut items = 0
  let mut objects = 0
  let mut fields = 0
  let mut texts = 0
  let mut max_fields = 0
  let mut max_key = 0
  let mut max_text = 0
  let mut utf16 = 0L
  let mut work = spine_work
  for index in root.index..<(root.index + nodes) {
    work += 1L
    match root.tree[index].value {
      ArrayValue(children) => {
        arrays += 1
        items += children.length()
      }
      ObjectValue(children) => {
        objects += 1
        fields += children.length()
        max_fields = Int::max(max_fields, children.length())
        for child in children {
          work += 1L
          let size = child.key.length()
          max_key = Int::max(max_key, size)
          utf16 += size.to_int64()
        }
      }
      Text(value) => {
        texts += 1
        max_text = Int::max(max_text, value.length())
        utf16 += value.length().to_int64()
      }
      _ => ()
    }
  }
  {
    nodes,
    arrays,
    array_items: items,
    objects,
    fields,
    texts,
    max_object_fields: max_fields,
    max_key_utf16: max_key,
    max_text_utf16: max_text,
    total_utf16: utf16,
    work,
  }
}
