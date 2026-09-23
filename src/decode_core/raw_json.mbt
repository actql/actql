///|
/// Active-ancestry continuations for physical JSON. Callers bound raw input
/// bytes before parsing; admission still owns node, depth, text,
/// Unicode and duplicate-key checks before exposing an immutable cursor.
priv enum RawJsonWork {
  RawVisit(Json, Int, Edge, Int)
  RawArrayNext(Array[Json], Int, Int, Int)
  RawObjectNext(Array[(String, Json)], Int, Int, Int, @shape.KeyAdmission)
}

///|
/// Admit parsed physical JSON without first allocating a source-value tree.
/// Every node carries the supplied physical frame span, as it did through the
/// previous raw-JSON-to-source conversion. Authoring normalization is omitted.
pub fn admit_raw_json(
  root : Json,
  span : @span.Span,
  limits : Limits,
) -> Result[Cursor, Issue] {
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_string_bytes < 0 ||
    limits.max_total_string_bytes < 0 {
    return Err({ kind: InvalidLimits, path: [], span, })
  }
  let tree : Array[OwnedNode] = []
  let work : Array[RawJsonWork] = [RawVisit(root, -1, Root, 0)]
  let mut remaining_text = limits.max_total_string_bytes
  let mut deepest = 0
  let mut largest_string = 0
  while work.length() > 0 {
    let task = work.pop().unwrap()
    match task {
      RawVisit(value, parent, edge, parent_depth) => {
        if tree.length() >= limits.max_nodes {
          return Err(at(tree, parent, edge, span, BudgetExceeded))
        }
        let is_container = match value {
          Array(_) | Object(_) => true
          _ => false
        }
        if is_container && parent_depth >= limits.max_depth {
          return Err(at(tree, parent, edge, span, BudgetExceeded))
        }
        let depth = parent_depth + (if is_container { 1 } else { 0 })
        deepest = Int::max(deepest, depth)
        let remaining_nodes = limits.max_nodes - tree.length() - 1
        let owned : OwnedValue = match value {
          Null => Null
          True => Bool(true)
          False => Bool(false)
          Number(number, ..) => Number(number)
          String(text) => {
            match text_charge(text, limits, remaining_text) {
              Ok(size) => {
                remaining_text -= size
                largest_string = Int::max(largest_string, size)
              }
              Err(kind) => return Err(at(tree, parent, edge, span, kind))
            }
            Text(text)
          }
          Array(items) => {
            if items.length() > remaining_nodes {
              return Err(at(tree, parent, edge, span, BudgetExceeded))
            }
            ArrayValue([])
          }
          Object(fields) => {
            if fields.length() > remaining_nodes {
              return Err(at(tree, parent, edge, span, BudgetExceeded))
            }
            ObjectValue([])
          }
        }
        let index = tree.length()
        tree.push({ value: owned, span, parent, edge, })
        if parent >= 0 {
          match (tree[parent].value, edge) {
            (ArrayValue(items), Element(_)) => items.push(index)
            (ObjectValue(fields), Field(key, key_span)) =>
              fields.push({ key, span: key_span, index, })
            _ => abort("invalid raw JSON admission continuation")
          }
        }
        match value {
          Array(items) => work.push(RawArrayNext(items, index, 0, depth))
          Object(fields) =>
            work.push(
              RawObjectNext(
                fields.to_array(),
                index,
                0,
                depth,
                @shape.key_admission(),
              ),
            )
          _ => ()
        }
      }
      RawArrayNext(items, parent, next, depth) =>
        if next < items.length() {
          work.push(RawArrayNext(items, parent, next + 1, depth))
          work.push(RawVisit(items[next], parent, Element(next), depth))
        }
      RawObjectNext(fields, parent, next, depth, seen) =>
        if next < fields.length() {
          let (key, value) = fields[next]
          let edge = Field(key, span)
          match text_charge(key, limits, remaining_text) {
            Ok(size) => {
              remaining_text -= size
              largest_string = Int::max(largest_string, size)
            }
            Err(kind) => return Err(at(tree, parent, edge, span, kind))
          }
          if !@shape.admit_key(seen, key) {
            return Err(at(tree, parent, edge, span, DuplicateField))
          }
          work.push(RawObjectNext(fields, parent, next + 1, depth, seen))
          work.push(RawVisit(value, parent, edge, depth))
        }
    }
  }
  Ok({
    tree,
    index: 0,
    usage: {
      nodes: tree.length(),
      depth: deepest,
      largest_string_bytes: largest_string,
      total_string_bytes: limits.max_total_string_bytes - remaining_text,
    },
  })
}
