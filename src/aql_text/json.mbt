///|
priv enum JsonWork {
  Visit(@source.Node)
  Finish(@source.Node, Int)
}

///|
priv struct JsonBody {
  node : @source.Node
  start : Int
  end : Int
  generated : Map[Int, Bool]
  nodes : Int
}

///|
// Scan one strict JSON island without applying outer-language trivia rules.
// The existing JSON parser owns syntax, duplicate keys, numbers and Unicode.
fn Parser::read_json(
  self : Parser,
  object_required? : Bool = true,
  argument_value? : Bool = false,
) -> JsonBody raise {
  if self.lookahead != None {
    raise Abort(Expected("JSON body"), self.scanner.byte_offset)
  }
  self.scanner.trivia()
  self.scanner.budget.charge(Tokens, 1, self.scanner.byte_offset)
  let start = self.scanner.byte_offset
  let start_offset = self.scanner.offset
  let stack : Array[Int] = []
  let mut quoted = false
  let mut escaped = false
  let mut begun = false
  while self.scanner.peek() is Some(n) {
    if quoted {
      ignore(self.scanner.advance())
      if escaped {
        escaped = false
      } else if n == 0x5c {
        escaped = true
      } else if n == 0x22 {
        quoted = false
        if stack.is_empty() {
          break
        }
      }
      continue
    }
    if n == 0x22 {
      quoted = true
    } else if n == 0x7b || n == 0x5b {
      if stack.length() >= self.limits.construction.source.max_depth {
        raise Abort(Json(@source.DepthLimit), self.scanner.byte_offset)
      }
      self.scanner.budget.charge(
        SyntaxDepth,
        self.syntax_depth + stack.length() + 1,
        self.scanner.byte_offset,
      )
      stack.push(if n == 0x7b { 0x7d } else { 0x5d })
    } else if n == 0x7d || n == 0x5d {
      if argument_value && stack.is_empty() {
        break
      }
      if stack.pop() != Some(n) {
        raise Abort(Json(@source.UnexpectedToken), self.scanner.byte_offset)
      }
      ignore(self.scanner.advance())
      if stack.is_empty() {
        break
      }
      continue
    } else if stack.is_empty() &&
      (
        n == 0x3b ||
        n == 0x7c ||
        (argument_value && (n == 0x2c || n == 0x29 || n == 0x5d || n == 0x7d)) ||
        (n == 0x2f && self.scanner.peek(ahead=1) == Some(0x2a)) ||
        (n == 0x2d && self.scanner.peek(ahead=1) == Some(0x2d)) ||
        n == 0x20 ||
        n == 0x09 ||
        n == 0x0a ||
        n == 0x0d
      ) {
      break
    }
    begun = true
    ignore(self.scanner.advance())
  }
  if !begun || quoted || !stack.is_empty() {
    raise Abort(Json(@source.UnexpectedEnd), self.scanner.byte_offset)
  }
  let text = self.scanner.text[start_offset:self.scanner.offset].to_owned()
  self.scanner.budget.charge(
    LoweringWork,
    self.scanner.byte_offset - start,
    start,
  )
  let parsed = match
    @source.parse_json_measured(text, {
      ..self.limits.construction.source,
      max_nodes: self.remaining_json_nodes.min(
        self.scanner.budget.left(SyntaxNodes),
      ),
    }) {
    Ok(p) => p
    Err(e) => {
      let offset = match e.location {
        Source(s) => s.start_byte
        ByteOffset(n) => n
        _ => 0
      }
      raise Abort(Json(e.issue), start + offset)
    }
  }
  if object_required && !(parsed.node.value is Object(_)) {
    raise Abort(Expected("JSON object"), start)
  }
  self.scanner.budget.charge(SyntaxNodes, parsed.usage.nodes, start)
  self.remaining_json_nodes -= parsed.usage.nodes
  {
    node: parsed.node,
    start,
    end: self.scanner.byte_offset,
    generated: Map([]),
    nodes: parsed.usage.nodes,
  }
}

///|
fn Parser::json_body(
  self : Parser,
  object_required? : Bool = true,
) -> @builder.Node raise {
  self.lower_json(self.read_json(object_required~))
}

///|
fn Parser::lower_json(self : Parser, body : JsonBody) -> @builder.Node raise {
  let start = body.start
  let work = [Visit(body.node)]
  let values : Array[@builder.Node] = []
  while work.pop() is Some(task) {
    match task {
      Visit(node) => {
        self.scanner.budget.charge(
          LoweringWork,
          1,
          start + node.span.start_byte,
        )
        if node.value is String(value) {
          let bytes = match
            @scalar.admit_utf8_length(
              value,
              self.scanner.budget.left(LiteralBytes),
            ) {
            Ok(n) => n
            Err(_) =>
              raise LimitAbort(LiteralBytes, start + node.span.start_byte)
          }
          self.scanner.budget.charge(
            LiteralBytes,
            bytes,
            start + node.span.start_byte,
          )
        }
        let count = match node.value {
          Array(xs) => xs.length()
          Object(fs) => fs.length()
          _ => 0
        }
        work.push(Finish(node, count))
        match node.value {
          Array(xs) =>
            for i = count - 1; i >= 0; i = i - 1 {
              work.push(Visit(xs[i]))
            }
          Object(fs) =>
            for i = count - 1; i >= 0; i = i - 1 {
              work.push(Visit(fs[i].value))
            }
          _ => ()
        }
      }
      Finish(node, count) => {
        let children : Array[@builder.Node] = []
        for _ in 0..<count {
          children.push(values.pop().unwrap())
        }
        let value : @builder.Value = match node.value {
          Null => Null
          Bool(b) => Bool(b)
          Number(n) => Number(n)
          String(s) => String(s)
          Array(_) => Array(Array::makei(count, i => children[count - 1 - i]))
          Object(fs) => {
            let fields : Array[@builder.Field] = []
            for i, f in fs {
              self.scanner.budget.charge(
                LoweringWork,
                1,
                start + f.key_span.start_byte,
              )
              let bytes = match
                @scalar.admit_utf8_length(
                  f.key,
                  self.scanner.budget.left(LiteralBytes),
                ) {
                Ok(n) => n
                Err(_) =>
                  raise LimitAbort(LiteralBytes, start + f.key_span.start_byte)
              }
              self.scanner.budget.charge(
                LiteralBytes,
                bytes,
                start + f.key_span.start_byte,
              )
              fields.push({
                key: f.key,
                origin: self.origin(
                  start + f.key_span.start_byte,
                  start + f.key_span.end_byte,
                  generated=false,
                ),
                value: children[count - 1 - i],
              })
            }
            Object(fields)
          }
        }
        let origin = self.origin(
          start + node.span.start_byte,
          start + node.span.end_byte,
          generated=body.generated.contains(node.span.start_byte),
        )
        match @builder.add(self.builder, value, origin) {
          Ok(n) => values.push(n)
          Err(e) => raise Abort(Construction(e), start + node.span.start_byte)
        }
      }
    }
  }
  values[0]
}
