///|
/// Temporary annotated builder; annotations are not semantic value fields.
pub(all) struct Node[T] {
  value : Value[T]
  span : @source.Span
  annotation : T
}

///|
pub(all) struct Field[T] {
  key : String
  key_span : @source.Span
  value : Node[T]
}

///|
pub(all) enum Value[T] {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[Node[T]])
  Object(Array[Field[T]])
}

///|
struct Map[T] {
  root : @decode.Cursor
  annotations : Array[T]
  peak_frames : Int
}

///|
pub fn[T] node_count(map : Map[T]) -> Int {
  map.annotations.length()
}

///|
pub fn[T] peak_frames(map : Map[T]) -> Int {
  map.peak_frames
}

///|
pub fn[T] annotation(map : Map[T], cursor : @decode.Cursor) -> T? {
  match @decode.tree_index(map.root, cursor) {
    Some(i) if i >= 0 && i < map.annotations.length() =>
      Some(map.annotations[i])
    _ => None
  }
}

///|
priv enum Work[T] {
  Visit(Node[T], Int)
  Finish(Node[T], Int)
}

///|
/// Own the semantic tree and index its sidecar in the same preorder. Annotation
/// values must themselves be immutable handles; no structural paths are stored.
pub fn[T] admit(
  root : Node[T],
  limits : @decode.Limits,
) -> Result[(@decode.Cursor, Map[T]), @decode.Issue] {
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_string_bytes < 0 ||
    limits.max_total_string_bytes < 0 {
    return Err({ kind: InvalidLimits, path: [], span: root.span, })
  }
  let work = [Visit(root, 0)]
  let values : Array[@source.Node] = []
  let annotations : Array[T] = []
  let mut scheduled = 1
  let mut peak_frames = 1
  while work.pop() is Some(task) {
    match task {
      Visit(n, depth) => {
        scheduled -= 1
        if annotations.length() >= limits.max_nodes || depth > limits.max_depth {
          return Err({ kind: BudgetExceeded, path: [], span: n.span, })
        }
        annotations.push(n.annotation)
        let children = match n.value {
          Array(xs) => xs
          Object(fs) => fs.map(f => f.value)
          _ => []
        }
        if children.length() >
          limits.max_nodes - annotations.length() - scheduled {
          return Err({ kind: BudgetExceeded, path: [], span: n.span, })
        }
        scheduled += children.length()
        work.push(Finish(n, children.length()))
        for i = children.length() - 1; i >= 0; i = i - 1 {
          work.push(Visit(children[i], depth + 1))
        }
      }
      Finish(n, count) => {
        let children : Array[@source.Node] = []
        for _ in 0..<count {
          children.push(values.pop().unwrap())
        }
        let child = i => children[count - 1 - i]
        let value = match n.value {
          Null => @source.Null
          Bool(b) => @source.Bool(b)
          Number(v) => @source.Number(v)
          String(s) => @source.String(s)
          Array(_) => @source.Array(Array::makei(count, child))
          Object(fs) =>
            @source.Object(
              Array::makei(count, i => {
                key: fs[i].key,
                key_span: fs[i].key_span,
                value: child(i),
              }),
            )
        }
        values.push({ value, span: n.span, })
      }
    }
    peak_frames = peak_frames.max(work.length())
  }
  match @decode.admit(values[0], limits) {
    Err(e) => Err(e)
    Ok(root) => Ok((root, { root, annotations, peak_frames, }))
  }
}
