///|
// Graph names select an existing Graph value. The label field is a local
// query annotation, never a Graph identity or entity-type declaration.
pub(all) struct GraphQuery {
  label_field : String?
  pattern : GraphPattern?
}

///|
pub(all) enum GraphPathMode {
  Walk
  Trail
  Acyclic
} derive(Eq, Debug)

///|
pub(all) enum GraphConstraint {
  Predicate(Expression)
  Properties(Array[(NamePart, Expression)])
}

///|
pub(all) struct GraphNodePattern {
  variable : NamePart?
  label : NamePart?
  constraint : GraphConstraint?
  start : Int
  end : Int
}

///|
pub(all) struct GraphEdgePattern {
  variable : NamePart?
  label : NamePart?
  constraint : GraphConstraint?
  direction : String
  quantified : Bool
  min_hops : Int64
  max_hops : Int64
  start : Int
  end : Int
}

///|
pub(all) struct GraphPattern {
  path_name : NamePart?
  mode : GraphPathMode
  nodes : Array[GraphNodePattern]
  edges : Array[GraphEdgePattern]
  start : Int
  end : Int
}

///|
fn QueryParser::graph_symbol(
  self : QueryParser,
  value : Int,
) -> Unit raise QueryAbort {
  let token = self.advance()
  if token.value != Symbol(value) {
    raise QueryAbort("Expected graph delimiter", token.start)
  }
}

///|
fn QueryParser::graph_text(self : QueryParser) -> String raise QueryAbort {
  let token = self.advance()
  match token.value {
    Text(value) if token.annotation_compatible => value
    _ => raise QueryAbort("Expected Graph LABELS string", token.start)
  }
}

///|
fn QueryParser::graph_labels(self : QueryParser) -> String? raise QueryAbort {
  if !self.has("LABELS") {
    return None
  }
  self.keyword("LABELS")
  self.node()
  self.graph_symbol(123)
  if self.graph_text() != "node" {
    raise QueryAbort("GRAPH_NODE_LABEL_MAPPING_REQUIRED", self.peek().start)
  }
  self.graph_symbol(58)
  self.graph_symbol(123)
  if self.graph_text() != "field" {
    raise QueryAbort("GRAPH_NODE_LABEL_MAPPING_REQUIRED", self.peek().start)
  }
  self.graph_symbol(58)
  let field = self.graph_text()
  if field == "" {
    raise QueryAbort("GRAPH_NODE_LABEL_MAPPING_REQUIRED", self.peek().start)
  }
  self.graph_symbol(125)
  self.graph_symbol(125)
  Some(field)
}

///|
fn QueryParser::graph_constraint(
  self : QueryParser,
) -> GraphConstraint? raise QueryAbort {
  if self.has("WHERE") {
    self.keyword("WHERE")
    return Some(Predicate(self.expression()))
  }
  if self.peek().value != Symbol(123) {
    return None
  }
  self.graph_symbol(123)
  let fields : Array[(NamePart, Expression)] = []
  while true {
    self.node()
    let field = self.name()
    self.graph_symbol(58)
    fields.push((field, self.expression()))
    if self.peek().value != Symbol(44) {
      break
    }
    self.graph_symbol(44)
  }
  self.graph_symbol(125)
  Some(Properties(fields))
}

///|
fn QueryParser::graph_node(
  self : QueryParser,
) -> GraphNodePattern raise QueryAbort {
  self.node()
  let start = self.peek().start
  self.graph_symbol(40)
  let variable = if self.has("WHERE") {
    None
  } else {
    match self.peek().value {
      Word(_) | QuotedName(_) => Some(self.name())
      _ => None
    }
  }
  let label = if self.peek().value == Symbol(58) {
    self.graph_symbol(58)
    Some(self.name())
  } else {
    None
  }
  let constraint = self.graph_constraint()
  let end = self.peek().end
  self.graph_symbol(41)
  { variable, label, constraint, start, end, }
}

///|
fn QueryParser::graph_edge(
  self : QueryParser,
  mode : GraphPathMode,
) -> GraphEdgePattern raise QueryAbort {
  self.node()
  let start = self.peek().start
  let incoming = self.peek().value == Operator("<")
  if incoming {
    ignore(self.advance())
  }
  self.graph_symbol(45)
  self.graph_symbol(91)
  let variable = if self.has("WHERE") {
    None
  } else {
    match self.peek().value {
      Word(_) | QuotedName(_) => Some(self.name())
      _ => None
    }
  }
  let label = if self.peek().value == Symbol(58) {
    self.graph_symbol(58)
    Some(self.name())
  } else {
    None
  }
  let constraint = self.graph_constraint()
  self.graph_symbol(93)
  self.graph_symbol(45)
  if !incoming {
    let token = self.advance()
    if token.value != Operator(">") {
      raise QueryAbort(
        "GRAPH_PATTERN_UNSUPPORTED_SHAPE: directed edge required",
        token.start,
      )
    }
  }
  let mut min_hops = 1L
  let mut max_hops = 1L
  let quantified = self.peek().value == Symbol(123)
  if quantified {
    self.graph_symbol(123)
    min_hops = self.safe_integer(true)
    self.graph_symbol(44)
    if self.peek().value == Symbol(125) {
      raise QueryAbort(
        "GRAPH_PATTERN_UNSUPPORTED_SHAPE: open quantifier",
        self.peek().start,
      )
    }
    max_hops = self.safe_integer(true)
    self.graph_symbol(125)
    if mode != Acyclic ||
      variable is Some(_) ||
      constraint is Some(_) ||
      min_hops > max_hops ||
      max_hops == 0L {
      raise QueryAbort(
        "GRAPH_PATTERN_UNSUPPORTED_SHAPE: bounded ACYCLIC edge required", start,
      )
    }
  } else if self.peek().value == Symbol(43) || self.peek().value == Symbol(42) {
    raise QueryAbort(
      "GRAPH_PATTERN_UNSUPPORTED_SHAPE: open quantifier",
      self.peek().start,
    )
  }
  {
    variable,
    label,
    constraint,
    direction: if incoming {
      "in"
    } else {
      "out"
    },
    quantified,
    min_hops,
    max_hops,
    start,
    end: self.peek().start,
  }
}

///|
fn QueryParser::graph_match(
  self : QueryParser,
) -> GraphPattern raise QueryAbort {
  let start = self.peek().start
  self.keyword("MATCH")
  let named_path = match self.peek().value {
    Word(_) | QuotedName(_) =>
      self.source.tokens[self.index + 1].value == Symbol(61)
    _ => false
  }
  let path_name = if named_path {
    let name = self.name()
    self.graph_symbol(61)
    Some(name)
  } else {
    None
  }
  let mode = if self.has("WALK") {
    self.keyword("WALK")
    Walk
  } else if self.has("TRAIL") {
    self.keyword("TRAIL")
    Trail
  } else if self.has("ACYCLIC") {
    self.keyword("ACYCLIC")
    Acyclic
  } else {
    // The selected GoogleSQL path profile uses WALK when no mode is authored.
    // Keep the same bounded shape checks and common traversal owner.
    Walk
  }
  let nodes = [self.graph_node()]
  let edges : Array[GraphEdgePattern] = []
  while self.peek().value == Symbol(45) || self.peek().value == Operator("<") {
    edges.push(self.graph_edge(mode))
    nodes.push(self.graph_node())
  }
  if edges.any(edge => edge.quantified) && edges.length() != 1 {
    raise QueryAbort(
      "GRAPH_PATTERN_UNSUPPORTED_SHAPE: quantified path must be homogeneous",
      self.peek().start,
    )
  }
  { path_name, mode, nodes, edges, start, end: self.peek().start, }
}
