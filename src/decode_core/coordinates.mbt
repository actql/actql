///|
/// Local arena coordinate only. It is not a path, persistent ID or authority.
/// Returns None for a cursor from a different owned tree.
pub fn tree_index(root : Cursor, cursor : Cursor) -> Int? {
  if physical_equal(root.tree, cursor.tree) {
    Some(cursor.index)
  } else {
    None
  }
}
