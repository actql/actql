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
/// Select an explicit SQL or query-text source and parse its original tokens.
/// None is the existing wrong-form route, not a structural-text fallback.
pub fn parse_selected_query_script(
  text : String,
  limits : QueryLimits,
  sql_only : Bool,
  source_path? : String = "<query>",
) -> Result[QueryScript?, Diagnostic] {
  parse_selected_query_script_owned(text, limits, sql_only, source_path)
}

///|
/// Observe only the original lexer/parser's declared work counters, including
/// a refused grammar/lexical prefix. Input-document admission precedes those
/// counters; failure there is explicitly incomplete, never a zero-work proof.
/// This performs one original parse and introduces no alternate syntax route.
pub fn observe_selected_query_script(
  text : String,
  limits : QueryLimits,
  sql_only : Bool,
  source_path? : String = "<query>",
) -> (Result[QueryScript?, Diagnostic], Int64, Bool) {
  let spent = Ref(0L)
  let lexical = Ref(false)
  let parser = Ref(false)
  let result = parse_selected_query_script_owned(
    text,
    limits,
    sql_only,
    source_path,
    observe_lexical=Some(value => {
      spent.val += value.to_int64()
      lexical.val = true
    }),
    observe_parser=Some(value => {
      spent.val += value.to_int64()
      parser.val = true
    }),
  )
  let complete = lexical.val && (parser.val || result is Ok(None))
  (result, spent.val, complete)
}

///|
fn parse_selected_query_script_owned(
  text : String,
  limits : QueryLimits,
  sql_only : Bool,
  source_path : String,
  read_document? : (String, Int, String) -> Result[
    @origin.Document,
    @origin.Issue,
  ] = (text, max_bytes, path) => {
    @origin.document(text, max_bytes, source_path=path)
  },
  observe_lexical? : ((Int) -> Unit)? = None,
  observe_parser? : ((Int) -> Unit)? = None,
) -> Result[QueryScript?, Diagnostic] {
  if [limits.max_syntax_nodes, limits.max_cte_count, limits.max_work].any(n => {
      n < 0 || n == 2147483647
    }) {
    return Err({ issue: InvalidLimits, span: None, })
  }
  let source = match
    scan_tokens(
      text,
      limits.lexical,
      source_path,
      false,
      query_route=Some(sql_only),
      read_document~,
      observe_work=observe_lexical,
    ) {
    Ok(source) => source
    Err(issue) => return Err(issue)
  }
  let first = source.tokens[0]
  if !query_head(first) {
    return Ok(None)
  }
  if sql_only {
    let mut index = 0
    while source.tokens[index].value == Symbol(40) {
      index += 1
    }
    let head = source.tokens[index]
    if !(sql_head(head) && (index == 0 || !keyword(head, "CREATE"))) {
      return Ok(None)
    }
  }
  parse_query_tokens(source, limits, observe_work=observe_parser).map(query => {
    Some(single_query_script(query))
  })
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
