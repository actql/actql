///|
/// DATA names are logical producer bindings. Parsing does not acquire, save,
/// materialize or split an execution task.
pub(all) enum DataExpression {
  RelationQuery(Query)
  Graph(GraphConstructor)
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
  commands : Array[CommandEffectClause]
  work : Int
}

///|
pub(all) struct CommandEffectClause {
  name : NamePart
  result : NamePart
  result_alias : NamePart
  target : Expression
  contract : NamePart
  input : Array[(NamePart, Expression)]
}

///|
pub fn command_effect_count(script : QueryScript) -> Int {
  script.commands.length()
}

///|
pub fn command_effect_at(
  script : QueryScript,
  index : Int,
) -> CommandEffectClause? {
  script.commands
  .get(index)
  .map(clause => { ..clause, input: clause.input.copy(), })
}

///|
fn QueryParser::command_effect_clause(
  self : QueryParser,
) -> CommandEffectClause raise QueryAbort {
  self.node()
  self.keyword("EFFECT")
  let name = self.name()
  self.keyword("COMMAND")
  self.keyword("FROM")
  self.keyword("RESULT")
  let result = self.name()
  self.keyword("AS")
  let result_alias = self.name()
  self.keyword("TARGET")
  let target = self.expression()
  self.keyword("CONTRACT")
  let contract = self.name()
  self.keyword("INPUT")
  self.symbol(40)
  let input : Array[(NamePart, Expression)] = []
  if self.peek().value != Symbol(41) {
    while true {
      self.node()
      let field = self.name()
      if input.any(entry => same_cte_name(entry.0, field)) {
        raise QueryAbort("Duplicate COMMAND input field", self.peek().start)
      }
      self.symbol(61)
      input.push((field, self.expression()))
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
  }
  self.symbol(41)
  { name, result, result_alias, target, contract, input, }
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
        DataExpression::Graph(parser.graph())
      } else if sga_call_head(parser.peek()) {
        DataExpression::NamedGraphCall(parser.sga_call())
      } else {
        // Use the same query-expression parser and original token stream.
        // A retained declaration is not an externally exported Result.
        DataExpression::RelationQuery(
          parser.query(cte_body=true, graph_data_body=true),
        )
      }
      let end = parser.peek().end
      parser.symbol(59)
      declarations.push({ name, value, start, end, })
    }
    let query = parser.query()
    let commands : Array[CommandEffectClause] = []
    if parser.peek().value == Symbol(59) {
      ignore(parser.advance())
      while parser.has("EFFECT") {
        if query.effect is Some(_) || query.table_effect is Some(_) {
          raise QueryAbort(
            "Conflicting terminal Effect declarations",
            parser.peek().start,
          )
        }
        let at = parser.peek().start
        let clause = parser.command_effect_clause()
        if commands.any(previous => same_cte_name(previous.name, clause.name)) {
          raise QueryAbort("Duplicate Effect name", at)
        }
        commands.push(clause)
        parser.symbol(59)
      }
      if parser.peek().value == Symbol(59) {
        raise QueryAbort("Expected end of one query", parser.peek().start)
      }
    }
    parser.end()
    Ok({ source, declarations, query, commands, work: parser.work, })
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

///|
// Preserve the original parsed query and source owner, without reparsing text.
pub fn single_query_script(query : Query) -> QueryScript {
  {
    source: query.source,
    declarations: [],
    query,
    commands: [],
    work: query.work,
  }
}
