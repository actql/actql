///|
// One query-expression owner for every public SQL/Pipe producer binding.
// This wrapper neither adds declarations nor reparses the original source.
struct QueryScript {
  query : Query
}

///|
pub fn script_query(script : QueryScript) -> Query {
  script.query
}

///|
pub fn script_document(script : QueryScript) -> @origin.Document {
  query_document(script.query)
}

///|
pub fn script_work(script : QueryScript) -> Int {
  query_work(script.query)
}

///|
pub fn parse_query_script(
  text : String,
  limits : QueryLimits,
  source_path? : String = "<query>",
) -> Result[QueryScript, Diagnostic] {
  parse_query(text, limits, source_path~).map(single_query_script)
}

///|
pub fn single_query_script(query : Query) -> QueryScript {
  { query, }
}

///|
pub fn terminal_command_effect_count(query : Query) -> Int {
  query.commands.length()
}

///|
pub fn terminal_command_effect_at(
  query : Query,
  index : Int,
) -> CommandEffectClause? {
  query.commands
  .get(index)
  .map(clause => { ..clause, input: clause.input.copy(), })
}

///|
pub(all) struct CommandEffectClause {
  name : NamePart
  result : NamePart
  result_alias : NamePart
  target : Expression
  contract : NamePart
  input : Array[(NamePart, Expression)]
  start : Int
  end : Int
}

///|
pub fn command_effect_count(script : QueryScript) -> Int {
  terminal_command_effect_count(script_query(script))
}

///|
pub fn command_effect_at(
  script : QueryScript,
  index : Int,
) -> CommandEffectClause? {
  terminal_command_effect_at(script_query(script), index)
}

///|
fn QueryParser::command_effect_clause(
  self : QueryParser,
) -> CommandEffectClause raise QueryAbort {
  self.node()
  let start = self.peek().start
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
      if input.any(entry => same_binding_name(entry.0, field)) {
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
  let end = self.peek().end
  self.symbol(41)
  { name, result, result_alias, target, contract, input, start, end, }
}
