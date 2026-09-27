///|
priv struct NativeOp {
  name : String
  token : Token
  body : JsonBody
}

///|
priv struct NativeData {
  name : String
  token : Token
  input : (String, Token)?
  operations : Array[NativeOp]
}

///|
priv enum StepDraft {
  Explicit(JsonBody)
  Data(NativeData)
}

///|
fn generator_operation(name : String) -> Bool {
  name == "values" ||
  name == "graph" ||
  name == "mean_graphs" ||
  name == "calendar_series" ||
  name == "time_series"
}

///|
fn Parser::read_data(self : Parser) -> NativeData raise {
  let (name, token) = self.name()
  ignore(self.symbol(0x3d))
  let mut input = None
  if self.token().value is Word(word) && ascii_keyword(word, "FROM") {
    ignore(self.take())
    input = Some(self.name())
    if self.token().value == Symbol(0x3b) {
      ignore(self.take())
      return { name, token, input, operations: [], }
    }
    let pipe = self.take()
    if pipe.value != Pipe {
      raise Abort(Expected("|> OP"), pipe.start)
    }
  }
  let operations : Array[NativeOp] = []
  while true {
    self.scanner.budget.charge(SyntaxNodes, 1, self.scanner.byte_offset)
    ignore(self.keyword("OP"))
    let op = self.take()
    let operation = match op.value {
      Word(name) if native_operation(name) => name
      _ => raise Abort(Expected("registered native operation"), op.start)
    }
    if operations.is_empty() && input == None && !generator_operation(operation) {
      raise Abort(Expected("generator OP or explicit FROM"), op.start)
    }
    let body = self.read_json(object_required=false)
    let generator = if operation == "graph" {
      raw_field(body.node, "nodes") is Some(_) ||
      raw_field(body.node, "edges") is Some(_)
    } else {
      generator_operation(operation)
    }
    if operations.is_empty() && input == None && !generator {
      raise Abort(Expected("generator with explicit sources"), op.start)
    }
    if (!operations.is_empty() || input != None) && generator {
      raise Abort(Expected("generator only at DATA start"), op.start)
    }
    operations.push({ name: operation, token: op, body, })
    let delimiter = self.take()
    if delimiter.value == Symbol(0x3b) {
      break
    }
    if delimiter.value != Pipe {
      raise Abort(Expected("; or |> OP"), delimiter.start)
    }
  }
  { name, token, input, operations, }
}

///|
fn raw_field(node : @source.Node, key : String) -> @source.Node? {
  match node.value {
    Object(fields) => {
      for f in fields {
        if f.key == key {
          return Some(f.value)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn raw_text(node : @source.Node?) -> String? {
  match node {
    Some({ value: String(s), .. }) => Some(s)
    _ => None
  }
}

///|
fn reserve_text(node : @source.Node, reserved : Map[String, Bool]) -> Unit {
  match node.value {
    String(s) => reserved[s] = true
    Array(xs) =>
      for x in xs {
        if x.value is String(s) {
          reserved[s] = true
        }
      }
    _ => ()
  }
}

///|
// These are producer-reference positions, not arbitrary strings inside operator
// payloads. Literal data, metadata and expression field names are never aliases.
fn native_reference_paths(operation : String) -> Array[Array[String]] {
  match operation {
    "graph" => [["nodes", "from"], ["edges", "from"]]
    "shortest_path" => [["source", "from"], ["target", "from"]]
    "subgraph" => [["nodes", "from"]]
    "traverse" => [["start", "from"]]
    "nearest" | "text_rank" => [["queries"]]
    "join"
    | "append"
    | "nest"
    | "except"
    | "intersect"
    | "cross_join"
    | "interval_join"
    | "asof_join"
    | "graphs_equal"
    | "graph_diff"
    | "graft_graph"
    | "union_graphs"
    | "subtract_graphs"
    | "apply_graph_delta"
    | "merge_rankings"
    | "mean_graphs" => [["with"]]
    _ => []
  }
}

///|
fn at_path(node : @source.Node, path : Array[String]) -> @source.Node? {
  let mut at = Some(node)
  for key in path {
    at = match at {
      Some(n) => raw_field(n, key)
      None => None
    }
  }
  at
}

///|
fn body_reference_paths(
  node : @source.Node,
  operation : String?,
) -> Array[Array[String]] {
  match operation {
    Some(op) => native_reference_paths(op)
    None => {
      let paths = [["from"]]
      if node.value is Object(fields) {
        for f in fields {
          if native_operation(f.key) {
            for path in native_reference_paths(f.key) {
              paths.push([f.key] + path)
            }
          }
        }
      }
      paths
    }
  }
}

///|
fn reserve_references(
  body : JsonBody,
  op : String?,
  reserved : Map[String, Bool],
  budget : Budget,
) -> Unit raise LimitAbort {
  budget.charge(LoweringWork, body.nodes, body.start)
  for path in body_reference_paths(body.node, op) {
    budget.charge(LoweringWork, body.nodes, body.start)
    budget.charge(LoweringWork, body.nodes, body.start)
    if at_path(body.node, path) is Some(n) {
      reserve_text(n, reserved)
    }
  }
}

///|
fn rewrite_target(
  node : @source.Node,
  aliases : Map[String, String],
  changed : Map[Int, Bool],
) -> @source.Node {
  match node.value {
    String(s) =>
      match aliases.get(s) {
        Some(target) if target != s => {
          changed[node.span.start_byte] = true
          { ..node, value: String(target), }
        }
        _ => node
      }
    Array(xs) =>
      {
        ..node,
        value: Array(
          xs.map(n => {
            match n.value {
              String(s) =>
                match aliases.get(s) {
                  Some(target) if target != s => {
                    changed[n.span.start_byte] = true
                    { ..n, value: String(target), }
                  }
                  _ => n
                }
              _ => n
            }
          }),
        ),
      }
    _ => node
  }
}

///|
fn rewrite_path(
  node : @source.Node,
  path : Array[String],
  index : Int,
  aliases : Map[String, String],
  changed : Map[Int, Bool],
) -> @source.Node {
  if index == path.length() {
    return rewrite_target(node, aliases, changed)
  }
  match node.value {
    Object(fields) =>
      {
        ..node,
        value: Object(
          fields.map(f => {
            if f.key == path[index] {
              {
                ..f,
                value: rewrite_path(f.value, path, index + 1, aliases, changed),
              }
            } else {
              f
            }
          }),
        ),
      }
    _ => node
  }
}

///|
fn resolve_body(
  body : JsonBody,
  op : String?,
  aliases : Map[String, String],
  budget : Budget,
) -> JsonBody raise LimitAbort {
  budget.charge(LoweringWork, body.nodes, body.start)
  let changed : Map[Int, Bool] = Map([])
  let mut node = body.node
  for path in body_reference_paths(node, op) {
    for _ in 0..<4 {
      budget.charge(LoweringWork, body.nodes, body.start)
    }
    node = rewrite_path(node, path, 0, aliases, changed)
  }
  { ..body, node, generated: changed, }
}

///|
fn Parser::lower_steps(
  self : Parser,
  drafts : Array[StepDraft],
  aliases : Map[String, String],
  reserved : Map[String, Bool],
) -> Array[@builder.Node] raise {
  let steps : Array[@builder.Node] = []
  let mut helper_index = 0
  for draft in drafts {
    match draft {
      Explicit(body) => {
        self.scanner.budget.charge(GeneratedSteps, 1, body.start)
        steps.push(
          self.lower_json(
            resolve_body(body, None, aliases, self.scanner.budget),
          ),
        )
        if raw_text(raw_field(body.node, "as")) is Some(name) {
          if aliases.contains(name) {
            raise Abort(Expected("unique producer name"), body.start)
          }
          aliases[name] = name
        }
      }
      Data(data) => {
        if aliases.contains(data.name) {
          raise Abort(Expected("unique DATA name"), data.token.start)
        }
        let from = match data.input {
          Some((name, token)) =>
            match aliases.get(name) {
              Some(target) => Some((target, token))
              None =>
                raise Abort(
                  Expected("previously declared producer"),
                  token.start,
                )
            }
          None => None
        }
        if data.operations.is_empty() {
          aliases[data.name] = from.unwrap().0
          continue
        }
        for i, op in data.operations {
          self.scanner.budget.charge(GeneratedSteps, 1, op.token.start)
          let fields = [
            self.field(
              op.name,
              self.lower_json(
                resolve_body(
                  op.body,
                  Some(op.name),
                  aliases,
                  self.scanner.budget,
                ),
              ),
              op.token,
            ),
          ]
          if i == 0 && from is Some((name, token)) {
            fields.push(
              self.field(
                "from",
                self.node(String(name), token.start, token.end),
                token,
              ),
            )
          }
          if i == data.operations.length() - 1 {
            fields.push(
              self.field(
                "as",
                self.node(String(data.name), data.token.start, data.token.end),
                data.token,
              ),
            )
          } else if generator_operation(op.name) {
            let mut helper = "__aql_native_" + helper_index.to_string()
            while reserved.contains(helper) {
              self.scanner.budget.charge(LoweringWork, 1, op.token.start)
              helper_index += 1
              helper = "__aql_native_" + helper_index.to_string()
            }
            helper_index += 1
            self.scanner.budget.charge(Symbols, 1, op.token.start)
            reserved[helper] = true
            fields.push(
              self.field(
                "as",
                self.node(String(helper), op.token.start, op.token.end),
                op.token,
              ),
            )
          }
          steps.push(self.node(Object(fields), data.token.start, op.body.end))
        }
        aliases[data.name] = data.name
      }
    }
  }
  steps
}
