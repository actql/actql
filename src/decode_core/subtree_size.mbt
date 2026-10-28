///|
/// Exact original preorder extent without walking every sibling or creating
/// child Cursors. Admission appends each complete child before its next sibling;
/// the rightmost descendant therefore closes this contiguous subtree.
/// Work counts the actual last-child-spine metadata visits, not validation or
/// CPU. No external count hint, reconstructed tree or semantic verdict enters.
pub fn observe_subtree_size(root : Cursor) -> (Int, Int64) {
  let mut last = root.index
  let mut work = 0L
  let mut descend = true
  while descend {
    work += 1L
    match root.tree[last].value {
      ArrayValue(items) if !items.is_empty() => last = items[items.length() - 1]
      ObjectValue(fields) if !fields.is_empty() =>
        last = fields[fields.length() - 1].index
      _ => descend = false
    }
  }
  (last - root.index + 1, work)
}
