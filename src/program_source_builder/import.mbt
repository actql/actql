///|
priv enum Work {
  Visit(@source.Node, Int)
  Finish(@source.Node, Int)
}

///|
priv enum CursorWork {
  CursorVisit(@wire.Cursor, Int)
  CursorFinish(@wire.Cursor, Int)
}

///|
// Copy an already admitted contract fragment into a new source owner. A
// generated origin makes the provenance boundary explicit; the fragment's
// original location remains with its own cursor, not the query source.
pub fn import_cursor(
  builder : Builder,
  cursor : @wire.Cursor,
  generated_origin : @origin.Origin,
) -> Result[Node, Issue] {
  if builder.closed {
    return Err(Closed)
  }
  if !@origin.belongs_to(builder.document, generated_origin) {
    return Err(ForeignOrigin)
  }
  let work : Array[CursorWork] = [CursorVisit(cursor, 0)]
  let values : Array[Node] = []
  let mut visited = 0
  let mut scheduled = 1
  let available = builder.limits.source.max_nodes.min(
      builder.limits.tree.max_nodes,
    ) -
    builder.allocated_nodes
  let depth_limit = builder.limits.source.max_depth.min(
    builder.limits.tree.max_depth,
  )
  while work.pop() is Some(task) {
    match task {
      CursorVisit(current, parent_depth) => {
        scheduled -= 1
        if visited >= available {
          builder.closed = true
          return Err(NodeLimit)
        }
        visited += 1
        let count = match @wire.view(current) {
          ArrayValue(xs) => xs.length()
          ObjectValue(_) => @wire.object_length(current).unwrap()
          _ => 0
        }
        let container = @wire.array_length(current) is Some(_) ||
          @wire.object_length(current) is Some(_)
        if container && parent_depth >= depth_limit {
          builder.closed = true
          return Err(DepthLimit)
        }
        let depth = parent_depth + (if container { 1 } else { 0 })
        if count > available - visited - scheduled {
          builder.closed = true
          return Err(NodeLimit)
        }
        scheduled += count
        work.push(CursorFinish(current, count))
        for i = count - 1; i >= 0; i = i - 1 {
          let child = match @wire.view(current) {
            ArrayValue(xs) => xs[i]
            ObjectValue(_) => @wire.field_at(current, i).unwrap().1
            _ => panic()
          }
          work.push(CursorVisit(child, depth))
        }
      }
      CursorFinish(current, count) => {
        let children : Array[Node] = []
        for _ in 0..<count {
          children.push(values.pop().unwrap())
        }
        let value : Value = match @wire.view(current) {
          NullValue => Null
          BoolValue(value) => Bool(value)
          NumberValue(value) => Number(value)
          TextValue(value) => String(value)
          ArrayValue(_) =>
            Array(Array::makei(count, i => children[count - 1 - i]))
          ObjectValue(_) => {
            let fields : Array[Field] = []
            for i in 0..<count {
              fields.push({
                key: @wire.field_at(current, i).unwrap().0,
                origin: generated_origin,
                value: children[count - 1 - i],
              })
            }
            Object(fields)
          }
        }
        match add(builder, value, generated_origin) {
          Ok(node) => values.push(node)
          Err(error) => return Err(error)
        }
      }
    }
  }
  Ok(values[0])
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
