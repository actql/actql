///|
priv enum Work {
  Visit(@source.Node, Int)
  Finish(@source.Node, Int)
}

///|
/// Import editable source data. Its supplied measurements are deliberately not
/// accepted as proof: every occurrence, key and span goes through the builder.
pub fn import_parsed(
  builder : Builder,
  parsed : @source.ParsedSource,
) -> Result[Node, Issue] {
  if builder.closed {
    return Err(Closed)
  }
  let work = [Visit(parsed.node, 0)]
  let values : Array[Node] = []
  let node_limit = builder.limits.source.max_nodes.min(
    builder.limits.tree.max_nodes,
  )
  let available = node_limit - builder.allocated_nodes
  let depth_limit = builder.limits.source.max_depth.min(
    builder.limits.tree.max_depth,
  )
  let mut visited = 0
  let mut scheduled = 1
  while work.pop() is Some(task) {
    match task {
      Visit(node, parent_depth) => {
        scheduled -= 1
        if visited >= available {
          builder.closed = true
          return Err(NodeLimit)
        }
        visited += 1
        let count = match node.value {
          Array(xs) => xs.length()
          Object(fs) => fs.length()
          _ => 0
        }
        let container = match node.value {
          Array(_) | Object(_) => true
          _ => false
        }
        if container && parent_depth >= depth_limit {
          builder.closed = true
          return Err(DepthLimit)
        }
        if count > available - visited - scheduled {
          builder.closed = true
          return Err(NodeLimit)
        }
        scheduled += count
        let depth = parent_depth + (if container { 1 } else { 0 })
        work.push(Finish(node, count))
        match node.value {
          Array(xs) =>
            for i = count - 1; i >= 0; i = i - 1 {
              work.push(Visit(xs[i], depth))
            }
          Object(fs) =>
            for i = count - 1; i >= 0; i = i - 1 {
              work.push(Visit(fs[i].value, depth))
            }
          _ => ()
        }
      }
      Finish(node, count) => {
        let origin = match @origin.validate_span(builder.document, node.span) {
          Ok(origin) => origin
          Err(_) => {
            builder.closed = true
            return Err(InvalidSpan)
          }
        }
        let children : Array[Node] = []
        for _ in 0..<count {
          children.push(values.pop().unwrap())
        }
        let value : Value = match node.value {
          Null => Null
          Bool(b) => Bool(b)
          Number(n) => Number(n)
          String(s) => String(s)
          Array(_) => Array(Array::makei(count, i => children[count - 1 - i]))
          Object(fs) => {
            let fields : Array[Field] = []
            for i, f in fs {
              let key_origin = match
                @origin.validate_span(builder.document, f.key_span) {
                Ok(o) => o
                Err(_) => {
                  builder.closed = true
                  return Err(InvalidSpan)
                }
              }
              fields.push({
                key: f.key,
                origin: key_origin,
                value: children[count - 1 - i],
              })
            }
            Object(fields)
          }
        }
        match add(builder, value, origin) {
          Ok(built) => values.push(built)
          Err(e) => return Err(e)
        }
      }
    }
  }
  Ok(values[0])
}
