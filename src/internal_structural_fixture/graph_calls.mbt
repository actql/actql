///|
// Named SGA calls are another spelling of the existing closed STEP operations.
// Argument roles come from their operation contracts, never string contents.
fn named_graph_operation(name : String) -> Bool {
  match name {
    "reach"
    | "traverse"
    | "shortest_path"
    | "components"
    | "degree"
    | "graph_bounds"
    | "match_nodes"
    | "match_edges"
    | "normalize_graph"
    | "subgraph"
    | "graft_graph"
    | "union_graphs"
    | "subtract_graphs"
    | "graphs_equal"
    | "graph_diff"
    | "apply_graph_delta"
    | "mean_graphs"
    | "node_rows"
    | "edge_rows" => true
    _ => false
  }
}

///|
fn named_reference_position(operation : String, path : Array[String]) -> Bool {
  for reference in native_reference_paths(operation) {
    if reference.length() == path.length() {
      let mut equal = true
      for i in 0..<path.length() {
        if reference[i] != path[i] {
          equal = false
          break
        }
      }
      if equal {
        return true
      }
    }
  }
  false
}

///|
fn Parser::named_key(self : Parser) -> (String, Token) raise {
  let token = self.take()
  self.scanner.budget.charge(Symbols, 1, token.start)
  let spelling = match token.value {
    Word(name) | QuotedName(name) | Text(name) => name
    _ => raise Abort(Expected("named argument"), token.start)
  }
  let key = match @canonical.normalize_nfc_lf(spelling) {
    Ok(value) => value
    Err(_) => raise Abort(Expected("Unicode argument name"), token.start)
  }
  (key, token)
}

///|
fn named_span(start : Int, end : Int) -> @source.Span {
  {
    start_byte: start,
    end_byte: end,
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 1,
    source_path: "",
  }
}

///|
fn Parser::named_node(
  self : Parser,
  value : @source.Value,
  start : Int,
  end : Int,
  depth : Int,
) -> @source.Node raise {
  self.scanner.budget.charge(SyntaxNodes, 1, start)
  self.scanner.budget.charge(SyntaxDepth, self.syntax_depth + depth, start)
  self.scanner.budget.charge(LoweringWork, 1, start)
  if self.remaining_json_nodes == 0 {
    raise LimitAbort(SyntaxNodes, start)
  }
  self.remaining_json_nodes -= 1
  { value, span: named_span(start, end), }
}

///|
// JSON islands use offsets relative to their own start. The named-call tree
// first uses absolute offsets and is shifted once to the containing body.
fn offset_named_node(
  node : @source.Node,
  delta : Int,
  budget : Budget,
) -> @source.Node raise LimitAbort {
  budget.charge(LoweringWork, 1, node.span.start_byte + delta)
  let span = {
    ..node.span,
    start_byte: node.span.start_byte + delta,
    end_byte: node.span.end_byte + delta,
  }
  let value = match node.value {
    @source.Array(items) =>
      @source.Array(items.map(item => offset_named_node(item, delta, budget)))
    @source.Object(fields) =>
      @source.Object(
        fields.map(field => {
          ..field,
          key_span: {
            ..field.key_span,
            start_byte: field.key_span.start_byte + delta,
            end_byte: field.key_span.end_byte + delta,
          },
          value: offset_named_node(field.value, delta, budget),
        }),
      )
    other => other
  }
  { value, span, }
}

///|
fn Parser::named_value(
  self : Parser,
  operation : String,
  path : Array[String],
  depth : Int,
) -> (@source.Node, Int) raise {
  self.scanner.trivia()
  let start = self.scanner.byte_offset
  if depth > self.limits.construction.source.max_depth {
    raise Abort(Json(@source.DepthLimit), start)
  }
  let reference = named_reference_position(operation, path)
  if self.scanner.peek() == Some(0x7b) {
    ignore(self.symbol(0x7b))
    let fields : Array[@source.Field] = []
    let seen : Map[String, Bool] = Map([])
    let mut nodes = 1
    self.scanner.trivia()
    while self.scanner.peek() != Some(0x7d) {
      let (key, token) = self.named_key()
      if seen.contains(key) {
        raise Abort(Expected("unique named argument"), token.start)
      }
      seen[key] = true
      ignore(self.symbol(0x3a))
      let (value, count) = self.named_value(operation, path + [key], depth + 1)
      nodes += count
      fields.push({ key, key_span: named_span(token.start, token.end), value, })
      if self.token().value != Symbol(0x2c) {
        break
      }
      ignore(self.take())
      self.scanner.trivia()
      if self.scanner.peek() == Some(0x7d) {
        raise Abort(
          Expected("named argument after comma"),
          self.scanner.byte_offset,
        )
      }
    }
    let end = self.symbol(0x7d).end
    (self.named_node(@source.Object(fields), start, end, depth), nodes)
  } else if self.scanner.peek() == Some(0x5b) {
    ignore(self.symbol(0x5b))
    let items : Array[@source.Node] = []
    let mut nodes = 1
    self.scanner.trivia()
    while self.scanner.peek() != Some(0x5d) {
      let (value, count) = self.named_value(operation, path, depth + 1)
      nodes += count
      items.push(value)
      if self.token().value != Symbol(0x2c) {
        break
      }
      ignore(self.take())
      self.scanner.trivia()
      if self.scanner.peek() == Some(0x5d) {
        raise Abort(
          Expected("list member after comma"),
          self.scanner.byte_offset,
        )
      }
    }
    let end = self.symbol(0x5d).end
    (self.named_node(@source.Array(items), start, end, depth), nodes)
  } else if reference {
    let (name, token) = self.name()
    (self.named_node(@source.String(name), token.start, token.end, depth), 1)
  } else {
    let body = self.read_json(object_required=false, argument_value=true)
    (offset_named_node(body.node, body.start, self.scanner.budget), body.nodes)
  }
}

///|
fn Parser::read_named_graph_arguments(
  self : Parser,
  operation : String,
) -> JsonBody raise {
  let open = self.symbol(0x28)
  let fields : Array[@source.Field] = []
  let seen : Map[String, Bool] = Map([])
  let mut nodes = 1
  self.scanner.trivia()
  while self.scanner.peek() != Some(0x29) {
    let (key, token) = self.named_key()
    if seen.contains(key) {
      raise Abort(Expected("unique named argument"), token.start)
    }
    seen[key] = true
    ignore(self.symbol(0x3a))
    let (value, count) = self.named_value(operation, [key], 1)
    nodes += count
    fields.push({ key, key_span: named_span(token.start, token.end), value, })
    if self.token().value != Symbol(0x2c) {
      break
    }
    ignore(self.take())
    self.scanner.trivia()
    if self.scanner.peek() == Some(0x29) {
      raise Abort(
        Expected("named argument after comma"),
        self.scanner.byte_offset,
      )
    }
  }
  let close = self.symbol(0x29)
  let body = if fields.is_empty() &&
    (
      operation == "node_rows" ||
      operation == "edge_rows" ||
      operation == "normalize_graph"
    ) {
    self.named_node(@source.Bool(true), open.start, close.end, 1)
  } else {
    self.named_node(@source.Object(fields), open.start, close.end, 1)
  }
  {
    node: offset_named_node(body, -open.start, self.scanner.budget),
    start: open.start,
    end: close.end,
    generated: Map([]),
    nodes,
  }
}
