///|
/// Pure graph-value construction is an ActQL extension. The table mapping
/// vocabulary follows the selected GoogleSQL SQL/PGQ profile. These names
/// describe logical producers and element definitions, never a storage target.
pub(all) enum GraphPropertySelection {
  AllColumns
  AllColumnsExcept(Array[NamePart])
  NoProperties
  Columns(Array[(NamePart, NamePart)])
} derive(Eq, Debug)

///|
pub(all) struct GraphLabel {
  name : NamePart
  properties : GraphPropertySelection
} derive(Eq, Debug)

///|
pub(all) struct GraphNodeDefinition {
  producer : Array[NamePart]
  name : NamePart
  key : Array[NamePart]
  labels : Array[GraphLabel]
} derive(Eq, Debug)

///|
pub(all) struct GraphEndpointReference {
  key : Array[NamePart]
  definition : NamePart
  referenced_key : Array[NamePart]?
} derive(Eq, Debug)

///|
pub(all) struct GraphEdgeDefinition {
  producer : Array[NamePart]
  name : NamePart
  key : Array[NamePart]
  source : GraphEndpointReference
  destination : GraphEndpointReference
  labels : Array[GraphLabel]
} derive(Eq, Debug)

///|
pub(all) struct GraphConstructor {
  nodes : Array[GraphNodeDefinition]
  edges : Array[GraphEdgeDefinition]
  start : Int
  end : Int
} derive(Eq, Debug)

///|
fn QueryParser::property_columns(
  self : QueryParser,
) -> Array[NamePart] raise QueryAbort {
  self.symbol(40)
  let fields = [self.name()]
  self.node()
  while self.peek().value == Symbol(44) {
    ignore(self.advance())
    self.node()
    fields.push(self.name())
  }
  self.symbol(41)
  fields
}

///|
fn QueryParser::property_selection(
  self : QueryParser,
) -> GraphPropertySelection raise QueryAbort {
  if self.has("NO") {
    self.keyword("NO")
    self.keyword("PROPERTIES")
    return NoProperties
  }
  if !self.has("PROPERTIES") {
    return AllColumns
  }
  self.keyword("PROPERTIES")
  if self.has("ARE") {
    self.keyword("ARE")
  }
  if self.has("ALL") {
    self.keyword("ALL")
    self.keyword("COLUMNS")
    if self.has("EXCEPT") {
      self.keyword("EXCEPT")
      return AllColumnsExcept(self.property_columns())
    }
    return AllColumns
  }
  self.symbol(40)
  let fields : Array[(NamePart, NamePart)] = []
  while true {
    self.node()
    let field = self.name()
    let output = if self.has("AS") {
      self.keyword("AS")
      self.name()
    } else {
      field
    }
    fields.push((field, output))
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  // The initial profile projects columns; it does not reinterpret a computed
  // expression as an identifier or silently discard its remaining tokens.
  self.symbol(41)
  Columns(fields)
}

///|
fn QueryParser::property_labels(
  self : QueryParser,
  definition : NamePart,
) -> Array[GraphLabel] raise QueryAbort {
  let labels : Array[GraphLabel] = []
  while self.has("LABEL") || self.has("DEFAULT") {
    self.node()
    let name = if self.has("DEFAULT") {
      self.keyword("DEFAULT")
      self.keyword("LABEL")
      definition
    } else {
      self.keyword("LABEL")
      self.name()
    }
    labels.push({ name, properties: self.property_selection(), })
  }
  if labels.is_empty() {
    self.node()
    labels.push({ name: definition, properties: self.property_selection(), })
  }
  labels
}

///|
fn QueryParser::graph_element_name(
  self : QueryParser,
) -> (Array[NamePart], NamePart) raise QueryAbort {
  self.node()
  let producer = self.path()
  let name = if self.has("AS") {
    self.keyword("AS")
    self.name()
  } else {
    producer.last().unwrap()
  }
  (producer, name)
}

///|
fn QueryParser::property_endpoint(
  self : QueryParser,
  role : String,
) -> GraphEndpointReference raise QueryAbort {
  self.node()
  self.keyword(role)
  self.keyword("KEY")
  let key = self.property_columns()
  self.keyword("REFERENCES")
  let definition = self.name()
  let referenced_key = if self.peek().value == Symbol(40) {
    Some(self.property_columns())
  } else {
    None
  }
  { key, definition, referenced_key, }
}

///|
fn QueryParser::graph(self : QueryParser) -> GraphConstructor raise QueryAbort {
  self.node()
  let start = self.peek().start
  self.keyword("PROPERTY")
  self.keyword("GRAPH")
  self.symbol(40)
  self.keyword("NODE")
  self.keyword("TABLES")
  self.symbol(40)
  let nodes : Array[GraphNodeDefinition] = []
  while true {
    let (producer, name) = self.graph_element_name()
    // A Relation producer does not carry an automatically designated DB
    // primary key. The selected initial profile requires an explicit KEY.
    self.keyword("KEY")
    let key = self.property_columns()
    let labels = self.property_labels(name)
    nodes.push({ producer, name, key, labels, })
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  self.symbol(41)
  let edges : Array[GraphEdgeDefinition] = []
  if self.has("EDGE") {
    self.keyword("EDGE")
    self.keyword("TABLES")
    self.symbol(40)
    while true {
      let (producer, name) = self.graph_element_name()
      self.keyword("KEY")
      let key = self.property_columns()
      let source = self.property_endpoint("SOURCE")
      let destination = self.property_endpoint("DESTINATION")
      let labels = self.property_labels(name)
      edges.push({ producer, name, key, source, destination, labels, })
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
    self.symbol(41)
  }
  let end = self.peek().end
  self.symbol(41)
  { nodes, edges, start, end, }
}

///|
/// Parse the pure constructor using the existing bounded query lexer/parser.
/// This operation does not resolve producers, admit a Graph or issue a domain.
pub fn parse_graph(
  text : String,
  limits : QueryLimits,
  source_path? : String = "<graph>",
) -> Result[GraphConstructor, Diagnostic] {
  if [limits.max_syntax_nodes, limits.max_cte_count, limits.max_work].any(n => {
      n < 0 || n == 2147483647
    }) {
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
    let graph = parser.graph()
    parser.end()
    Ok(graph)
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
