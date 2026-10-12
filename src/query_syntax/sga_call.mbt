///|
/// Arguments retain their syntactic role until ordinary Program lowering.
/// A producer name is never inferred from the content of a string literal.
pub(all) enum SgaArgument {
  Producer(NamePart)
  FieldReference(Array[NamePart])
  OutputName(NamePart)
  TextValue(String)
  NumberValue(String)
  BooleanValue(Bool)
  NullValue
  ParameterValue(String)
  ObjectValue(Array[(String, SgaArgument)])
  FieldMapValue(Array[(Array[NamePart], SgaArgument)])
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
    "to_vectors"
    | "normalize_vectors"
    | "score_vectors"
    | "pool_vectors"
    | "vectors"
    | "to_events"
    | "row_window"
    | "window_events"
    | "watermark_events"
    | "watermark_rows"
    | "lag"
    | "dedupe_events"
    | "session"
    | "events"
    | "reach"
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
// Currently connected source lowerings with Relation output. False does not
// assert a Graph output: other logical operations can remain unsupported.
// The common checker owns Carrier validity and the operation's output schema.
pub fn has_sga_relation_lowering(operation : String) -> Bool {
  match operation {
    "node_rows"
    | "edge_rows"
    | "degree"
    | "graph_bounds"
    | "components"
    | "graphs_equal"
    | "graph_diff"
    | "match_nodes"
    | "match_edges"
    | "traverse"
    | "reach"
    | "shortest_path" => true
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
fn carrier_call_head(token : Token) -> Bool {
  match token.value {
    Word(name) =>
      [
        "to_vectors", "normalize_vectors", "score_vectors", "pool_vectors", "vectors",
        "to_events", "row_window", "window_events", "watermark_events", "session",
        "events", "dedupe_events", "watermark_rows", "lag",
      ].contains(ascii_upper(name).to_lower())
    _ => false
  }
}

///|
fn copy_sga_argument(argument : SgaArgument) -> SgaArgument {
  match argument {
    FieldReference(path) => FieldReference(path.copy())
    ObjectValue(fields) =>
      ObjectValue(fields.map(field => (field.0, copy_sga_argument(field.1))))
    FieldMapValue(fields) =>
      FieldMapValue(
        fields.map(field => (field.0.copy(), copy_sga_argument(field.1))),
      )
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
    "reach" => path == ["start"]
    "traverse" => path == ["start"] || path == ["hops"]
    "shortest_path" => path == ["source"] || path == ["target"]
    "subgraph" => path == ["nodes"]
    "union_graphs" | "subtract_graphs" => path == ["merge"]
    "match_nodes" | "match_edges" => path == ["bindings"]
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
  if sga_field_argument(operation, path) {
    let field = self.path()
    if field.length() == 2 && sga_operand_field_argument(operation, path) {
      let operand = self.resolve_producer([field[0]])
      return FieldReference([operand[0], field[1]])
    }
    return FieldReference(field)
  }
  if sga_output_argument(operation, path) {
    return OutputName(self.sga_output_name())
  }
  if sga_producer_argument(operation, path) {
    // Bare and backtick names are references. A quoted STRING is a value,
    // and cannot select an existing producer, including inside explicit lists.
    return Producer(self.resolve_producer([self.name()])[0])
  }
  if token.value == Symbol(123) &&
    ["dedupe_events", "lag"].contains(operation) &&
    path == ["order_by"] {
    return self.sga_order_argument(operation, depth + 1)
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
    Parameter(name) => ParameterValue(self.source.identifier(name))
    Word(name) if ascii_upper(name) == "TRUE" => BooleanValue(true)
    Word(name) if ascii_upper(name) == "FALSE" => BooleanValue(false)
    Word(name) if ascii_upper(name) == "NULL" => NullValue
    Symbol(43 | 45 as sign) => {
      let number = self.advance()
      match number.value {
        Numeric(value) =>
          NumberValue((if sign == 45 { "-" } else { "+" }) + value)
        _ => raise QueryAbort("Expected SGA numeric value", number.start)
      }
    }
    _ =>
      raise QueryAbort("Expected SGA value or producer reference", token.start)
  }
}

///|
// The common OrderKey reader distinguishes a one-field shorthand from the
// closed field/dir/nulls form. Preserve shorthand names as typed references,
// including quotation and receivers, until ordinary Carrier name resolution.
fn QueryParser::sga_order_argument(
  self : QueryParser,
  operation : String,
  depth : Int,
) -> SgaArgument raise QueryAbort {
  if depth > self.limits.expression.max_depth || depth > 32 {
    raise QueryAbort("SGA argument depth limit", self.peek().start)
  }
  self.symbol(123)
  let fields : Array[(Array[NamePart], SgaArgument)] = []
  while self.peek().value != Symbol(125) {
    self.node()
    let at = self.peek().start
    let key = self.path()
    self.spend(fields.length())
    if fields.any(field => field.0 == key) {
      raise QueryAbort("Duplicate SGA argument", at)
    }
    self.symbol(58)
    let value = if key.length() == 1 &&
      ascii_upper(key[0].value) == "FIELD" &&
      (self.peek().value is Word(_) || self.peek().value is QuotedName(_)) {
      self.node()
      FieldReference(self.path())
    } else {
      self.sga_argument(operation, ["literal"], depth)
    }
    fields.push((key, value))
    if self.peek().value != Symbol(44) {
      break
    }
    self.symbol(44)
    if self.peek().value == Symbol(125) {
      raise QueryAbort("Expected SGA named argument", self.peek().start)
    }
  }
  self.symbol(125)
  if fields.length() == 1 {
    return FieldMapValue(fields)
  }
  let named : Array[(String, SgaArgument)] = []
  for (key, value) in fields {
    guard key.length() == 1 else {
      raise QueryAbort("Expected OrderKey argument name", self.peek().start)
    }
    let key = ascii_upper(key[0].value).to_lower()
    self.spend(named.length())
    if named.any(field => field.0 == key) {
      raise QueryAbort("Duplicate SGA argument", self.peek().start)
    }
    if key == "field" && !(value is FieldReference(_)) {
      raise QueryAbort("Expected OrderKey field reference", self.peek().start)
    }
    named.push((key, value))
  }
  ObjectValue(named)
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
    // Fold typed argument vocabulary only. Object-valued data (for
    // example a predicate's literal object) retains its authored field names.
    // Folding every nested String key would change a value before admission.
    let key = if path.is_empty() ||
      sga_selector_object(operation, path) ||
      sga_expression_position(operation, path) {
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
    binding_scopes: [],
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
