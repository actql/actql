///|
/// DATA names are logical producer bindings. Parsing does not acquire, save,
/// materialize or split an execution task.
pub(all) enum DataExpression {
  RelationQuery(Query)
  PropertyGraph(PropertyGraphConstructor)
  NamedGraphCall(SgaCall)
}

///|
pub(all) struct DataDeclaration {
  name : NamePart
  value : DataExpression
  start : Int
  end : Int
}

///|
struct QueryScript {
  source : Tokens
  declarations : Array[DataDeclaration]
  query : Query
  work : Int
}

///|
pub fn data_declaration_count(script : QueryScript) -> Int {
  script.declarations.length()
}

///|
pub fn data_declaration_at(
  script : QueryScript,
  index : Int,
) -> DataDeclaration? {
  script.declarations.get(index)
}

///|
pub fn script_query(script : QueryScript) -> Query {
  script.query
}

///|
pub fn script_document(script : QueryScript) -> @origin.Document {
  script.source.document
}

///|
pub fn script_work(script : QueryScript) -> Int {
  script.work
}

///|
pub fn parse_query_script(
  text : String,
  limits : QueryLimits,
  source_path? : String = "<query>",
) -> Result[QueryScript, Diagnostic] {
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
    let declarations : Array[DataDeclaration] = []
    while parser.has("DATA") {
      parser.node()
      let start = parser.peek().start
      parser.keyword("DATA")
      if declarations.length() >= limits.max_cte_count {
        raise QueryAbort("DATA declaration count limit", start)
      }
      let name_at = parser.peek().start
      let name = parser.name()
      if declarations.any(declaration => same_cte_name(declaration.name, name)) {
        raise QueryAbort("Duplicate DATA name", name_at)
      }
      parser.symbol(61)
      let value = if parser.has("PROPERTY") {
        DataExpression::PropertyGraph(parser.property_graph())
      } else if sga_call_head(parser.peek()) {
        DataExpression::NamedGraphCall(parser.sga_call())
      } else {
        // Use the same query-expression parser and original token stream.
        // A retained declaration is not an externally exported Result.
        DataExpression::RelationQuery(parser.query(cte_body=true))
      }
      let end = parser.peek().end
      parser.symbol(59)
      declarations.push({ name, value, start, end, })
    }
    let query = parser.query()
    parser.end()
    Ok({ source, declarations, query, work: parser.work, })
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
