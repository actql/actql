///|
/// Arguments retain their syntactic role until ordinary Program lowering.
/// A producer name is never inferred from the content of a string literal.
pub(all) enum SgaArgument {
  Producer(NamePart)
  TextValue(String)
  NumberValue(String)
  BooleanValue(Bool)
  NullValue
  ParameterValue(String)
  ObjectValue(Array[(String, SgaArgument)])
  ListValue(Array[SgaArgument])
} derive(Eq, Debug)

///|
pub(all) struct SgaCall {
  operation : String
  arguments : Array[(String, SgaArgument)]
  start : Int
  end : Int
} derive(Eq, Debug)

///|
// These are the adopted ActQL logical operation names, not GQL functions or
// provider procedures. No backend, acquisition or materialization is chosen.
fn sga_operation(name : String) -> Bool {
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
fn sga_call_head(token : Token) -> Bool {
  match token.value {
    Word(name) => sga_operation(ascii_upper(name).to_lower())
    _ => false
  }
}

///|
fn copy_sga_argument(argument : SgaArgument) -> SgaArgument {
  match argument {
    ObjectValue(fields) =>
      ObjectValue(fields.map(field => (field.0, copy_sga_argument(field.1))))
    ListValue(items) => ListValue(items.map(copy_sga_argument))
    other => other
  }
}

///|
fn copy_sga_call(call : SgaCall) -> SgaCall {
  {
    ..call,
    arguments: call.arguments.map(field => (field.0, copy_sga_argument(field.1))),
  }
}

///|
/// Consume a lowered Graph prefix exactly once. Relational compilation cannot
/// silently ignore a Graph call; the caller must first emit every prefix step.
pub fn after_graph_calls(query : Query) -> Query {
  let mut count = 0
  while count < query.operations.length() &&
        query.operations[count] is GraphCall(_) {
    count += 1
  }
  { ..query, operations: query.operations[count:].to_owned(), }
}

///|
// A role comes from the existing logical operation contract. For example,
// reach.start.from is a Relation producer, while reach.start is an ID value.
fn sga_producer_argument(operation : String, path : Array[String]) -> Bool {
  match operation {
    "reach" | "traverse" => path == ["start", "from"]
    "shortest_path" => path == ["source", "from"] || path == ["target", "from"]
    "subgraph" => path == ["nodes", "from"]
    "graphs_equal"
    | "graph_diff"
    | "graft_graph"
    | "union_graphs"
    | "subtract_graphs"
    | "apply_graph_delta"
    | "mean_graphs" => path == ["with"]
    _ => false
  }
}

///|
fn sga_selector_object(operation : String, path : Array[String]) -> Bool {
  match operation {
    "reach" | "traverse" => path == ["start"]
    "shortest_path" => path == ["source"] || path == ["target"]
    "subgraph" => path == ["nodes"]
    _ => false
  }
}

///|
fn QueryParser::sga_argument(
  self : QueryParser,
  operation : String,
  path : Array[String],
  depth : Int,
) -> SgaArgument raise QueryAbort {
  // Keep recursion bounded independently of the caller's configurable budget.
  // Work and syntax nodes are charged to the containing query parser.
  if depth > self.limits.expression.max_depth || depth > 32 {
    raise QueryAbort("SGA argument depth limit", self.peek().start)
  }
  self.node()
  let token = self.peek()
  if token.value == Symbol(91) {
    self.symbol(91)
    let items : Array[SgaArgument] = []
    while self.peek().value != Symbol(93) {
      items.push(self.sga_argument(operation, path, depth + 1))
      if self.peek().value != Symbol(44) {
        break
      }
      self.symbol(44)
      if self.peek().value == Symbol(93) {
        raise QueryAbort("Expected SGA list member", self.peek().start)
      }
    }
    self.symbol(93)
    return ListValue(items)
  }
  if sga_producer_argument(operation, path) {
    // Bare and backtick names are references. A quoted STRING is a value,
    // and cannot select an existing producer, including inside explicit lists.
    return Producer(self.name())
  }
  if token.value == Symbol(123) {
    self.symbol(123)
    let fields = self.sga_arguments(operation, path, depth + 1, 125)
    self.symbol(125)
    return ObjectValue(fields)
  }
  match self.advance().value {
    Text(value) => {
      let output = StringBuilder()
      output.write_string(value)
      // Keep the existing GoogleSQL lexical rule for adjacent String chunks.
      // Each decoded chunk retains its value; this is not NFC/LF conversion.
      while self.peek().value is Text(chunk) {
        ignore(self.advance())
        output.write_string(chunk)
      }
      TextValue(output.to_string())
    }
    Numeric(value) => NumberValue(value)
    Parameter(name) => ParameterValue(name)
    Word(name) if ascii_upper(name) == "TRUE" => BooleanValue(true)
    Word(name) if ascii_upper(name) == "FALSE" => BooleanValue(false)
    Word(name) if ascii_upper(name) == "NULL" => NullValue
    Symbol(45) => {
      let number = self.advance()
      match number.value {
        Numeric(value) => NumberValue("-" + value)
        _ => raise QueryAbort("Expected SGA numeric value", number.start)
      }
    }
    _ =>
      raise QueryAbort("Expected SGA value or producer reference", token.start)
  }
}

///|
fn QueryParser::sga_arguments(
  self : QueryParser,
  operation : String,
  path : Array[String],
  depth : Int,
  closing : Int,
) -> Array[(String, SgaArgument)] raise QueryAbort {
  let fields : Array[(String, SgaArgument)] = []
  while self.peek().value != Symbol(closing) {
    self.node()
    let at = self.peek().start
    let name = self.name()
    // Fold operation/selector vocabulary only. Object-valued data (for
    // example a predicate's literal object) retains its authored field names.
    // Folding every nested String key would change a value before admission.
    let key = if path.is_empty() || sga_selector_object(operation, path) {
      ascii_upper(name.value).to_lower()
    } else {
      name.value
    }
    self.spend(fields.length())
    if fields.any(field => field.0 == key) {
      raise QueryAbort("Duplicate SGA argument", at)
    }
    self.symbol(58)
    let value = self.sga_argument(operation, path + [key], depth)
    fields.push((key, value))
    if self.peek().value != Symbol(44) {
      break
    }
    self.symbol(44)
    if self.peek().value == Symbol(closing) {
      raise QueryAbort("Expected SGA named argument", self.peek().start)
    }
  }
  fields
}

///|
fn QueryParser::sga_call(self : QueryParser) -> SgaCall raise QueryAbort {
  self.node()
  let token = self.advance()
  let operation = match token.value {
    Word(name) => ascii_upper(name).to_lower()
    _ => raise QueryAbort("Expected SGA operation name", token.start)
  }
  if !sga_operation(operation) {
    raise QueryAbort("Unknown SGA operation", token.start)
  }
  self.symbol(40)
  let arguments = self.sga_arguments(operation, [], 1, 41)
  let end = self.peek().end
  self.symbol(41)
  { operation, arguments, start: token.start, end, }
}

///|
/// Parse one adopted named call using the same bounded token and query parser.
/// This syntax entry does not admit a Program or authorize/execute a provider.
/// Public script lowering and common consumer support are separate obligations.
pub fn parse_sga_call(
  text : String,
  limits : QueryLimits,
  source_path? : String = "<query>",
) -> Result[SgaCall, Diagnostic] {
  if [limits.max_syntax_nodes, limits.max_work, limits.expression.max_depth].any(n => {
        n < 0 || n == 2147483647
      },
    ) {
    return Err({ issue: InvalidLimits, span: None, })
  }
  let source = match tokenize(text, limits.lexical, source_path~) {
    Ok(source) => source
    Err(error) => return Err(error)
  }
  let parser : QueryParser = {
    source,
    limits,
    index: 0,
    work: 0,
    expression_nodes: 0,
    syntax_nodes: 0,
    source_depth: 0,
    synthetic_sources: 0,
    cte_scopes: [],
  }
  try {
    let call = parser.sga_call()
    if parser.peek().value != End {
      raise QueryAbort("Expected end of SGA call", parser.peek().start)
    }
    Ok(call)
  } catch {
    QueryExpression(error) => Err(error)
    QueryAbort(message, at) =>
      Err({
        issue: Syntax(message),
        span: Some(
          @origin.span(@origin.range(source.document, at, at).unwrap()),
        ),
      })
  }
}
