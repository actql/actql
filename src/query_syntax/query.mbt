///|
pub(all) struct QueryLimits {
  lexical : LexicalLimits
  expression : ExpressionLimits
  max_syntax_nodes : Int
  max_cte_count : Int
  max_work : Int
}

///|
pub(all) struct Projection {
  expression : Expression?
  name : NamePart?
  star : String?
}

///|
pub(all) struct SortTerm {
  expression : Expression
  direction : String
  nulls : String
}

///|
pub(all) enum QueryOperation {
  Where(Expression)
  Select(Array[Projection], Bool)
  Order(Array[SortTerm])
  Limit(Int, Int)
}

///|
struct Query {
  source : Tokens
  relation : Array[NamePart]
  source_alias : NamePart?
  operations : Array[QueryOperation]
  work : Int
}

///|
pub fn relation(query : Query) -> Array[NamePart] {
  query.relation.copy()
}

///|
pub fn relation_alias(query : Query) -> NamePart? {
  query.source_alias
}

///|
pub fn query_source(query : Query) -> Tokens {
  query.source
}

///|
pub fn query_document(query : Query) -> @origin.Document {
  query.source.document
}

///|
pub fn operation_count(query : Query) -> Int {
  query.operations.length()
}

///|
pub fn operation_at(query : Query, index : Int) -> QueryOperation? {
  if index < 0 || index >= query.operations.length() {
    return None
  }
  match query.operations[index] {
    Where(e) => Some(Where(e))
    Select(xs, distinct) => Some(Select(xs.copy(), distinct))
    Order(xs) => Some(Order(xs.copy()))
    Limit(count, offset) => Some(Limit(count, offset))
  }
}

///|
pub fn query_work(query : Query) -> Int {
  query.work
}

///|
priv suberror QueryAbort {
  QueryAbort(String, Int)
  QueryExpression(Diagnostic)
}

///|
priv struct QueryParser {
  source : Tokens
  limits : QueryLimits
  mut index : Int
  mut work : Int
  mut expression_nodes : Int
  mut syntax_nodes : Int
}

///|
fn QueryParser::peek(self : QueryParser) -> Token {
  self.source.tokens[self.index]
}

///|
fn QueryParser::advance(self : QueryParser) -> Token raise QueryAbort {
  self.spend(1)
  let token = self.peek()
  if token.value == End {
    raise QueryAbort("Expected query token", token.start)
  }
  self.index += 1
  token
}

///|
fn QueryParser::spend(
  self : QueryParser,
  amount : Int,
) -> Unit raise QueryAbort {
  if amount < 0 || amount > self.limits.max_work - self.work {
    raise QueryAbort("Query work limit", self.peek().start)
  }
  self.work += amount
}

///|
fn QueryParser::node(self : QueryParser) -> Unit raise QueryAbort {
  if self.syntax_nodes >= self.limits.max_syntax_nodes {
    raise QueryAbort("Query syntax node limit", self.peek().start)
  }
  self.syntax_nodes += 1
}

///|
fn QueryParser::has(self : QueryParser, expected : String) -> Bool {
  keyword(self.peek(), expected)
}

///|
fn QueryParser::keyword(
  self : QueryParser,
  expected : String,
) -> Unit raise QueryAbort {
  let token = self.advance()
  if !keyword(token, expected) {
    raise QueryAbort("Expected " + expected, token.start)
  }
}

///|
fn QueryParser::name(self : QueryParser) -> NamePart raise QueryAbort {
  let token = self.advance()
  match token.value {
    Word(value) => { value, quoted: false, }
    QuotedName(value) => { value, quoted: true, }
    _ => raise QueryAbort("Expected identifier", token.start)
  }
}

///|
fn QueryParser::path(self : QueryParser) -> Array[NamePart] raise QueryAbort {
  let parts = [self.name()]
  while self.peek().value == Symbol(46) {
    ignore(self.advance())
    parts.push(self.name())
  }
  parts
}

///|
fn QueryParser::expression(self : QueryParser) -> Expression raise QueryAbort {
  let remaining = self.limits.max_work - self.work
  let expression_limits = {
    ..self.limits.expression,
    max_nodes: self.limits.expression.max_nodes - self.expression_nodes,
    max_work: self.limits.expression.max_work.min(remaining),
  }
  match parse_fragment(self.source, self.index, expression_limits) {
    Ok((expression, next)) => {
      self.spend(expression.work)
      self.expression_nodes += expression.nodes.length()
      self.index = next
      expression
    }
    Err(error) => raise QueryExpression(error)
  }
}

///|
fn QueryParser::source_name(
  self : QueryParser,
) -> (Array[NamePart], NamePart?) raise QueryAbort {
  let relation = self.path()
  let source_alias = if self.has("AS") {
    self.keyword("AS")
    Some(self.name())
  } else {
    None
  }
  (relation, source_alias)
}

///|
fn QueryParser::projections(
  self : QueryParser,
) -> Array[Projection] raise QueryAbort {
  let values : Array[Projection] = []
  while true {
    self.node()
    let projection = if self.peek().value == Symbol(42) {
      ignore(self.advance())
      { expression: None, name: None, star: Some("*"), }
    } else {
      let expression = self.expression()
      let name = if self.has("AS") {
        self.keyword("AS")
        Some(self.name())
      } else {
        None
      }
      { expression: Some(expression), name, star: None, }
    }
    values.push(projection)
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  values
}

///|
fn QueryParser::order(self : QueryParser) -> Array[SortTerm] raise QueryAbort {
  let terms : Array[SortTerm] = []
  while true {
    self.node()
    let expression = self.expression()
    let direction = if self.has("DESC") {
      self.keyword("DESC")
      "desc"
    } else if self.has("ASC") {
      self.keyword("ASC")
      "asc"
    } else {
      "asc"
    }
    let nulls = if self.has("NULLS") {
      self.keyword("NULLS")
      if self.has("FIRST") {
        self.keyword("FIRST")
        "first"
      } else {
        self.keyword("LAST")
        "last"
      }
    } else if direction == "asc" {
      "first"
    } else {
      "last"
    }
    terms.push({ expression, direction, nulls, })
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  terms
}

///|
fn QueryParser::small_limit(
  self : QueryParser,
  zero_allowed : Bool,
) -> Int raise QueryAbort {
  let token = self.advance()
  let text = match token.value {
    Numeric(text) => text
    _ =>
      raise QueryAbort("LIMIT and OFFSET require integer literals", token.start)
  }
  let mut result = 0
  for unit in text {
    self.spend(1)
    let digit = unit.to_int() - 48
    if digit < 0 || digit > 9 || result > (2147483646 - digit) / 10 {
      raise QueryAbort("LIMIT or OFFSET out of range", token.start)
    }
    result = result * 10 + digit
  }
  if !zero_allowed && result == 0 {
    raise QueryAbort("LIMIT zero is not supported", token.start)
  }
  result
}

///|
fn QueryParser::limit(self : QueryParser) -> QueryOperation raise QueryAbort {
  self.keyword("LIMIT")
  let count = self.small_limit(false)
  let offset = if self.has("OFFSET") {
    self.keyword("OFFSET")
    self.small_limit(true)
  } else {
    0
  }
  Limit(count, offset)
}

///|
fn QueryParser::end(self : QueryParser) -> Unit raise QueryAbort {
  if self.peek().value == Symbol(59) {
    ignore(self.advance())
  }
  if self.peek().value != End {
    raise QueryAbort("Expected end of one query", self.peek().start)
  }
}

///|
fn QueryParser::sql(self : QueryParser) -> Query raise QueryAbort {
  self.keyword("SELECT")
  let distinct = self.has("DISTINCT")
  if distinct {
    self.keyword("DISTINCT")
  }
  let projections = self.projections()
  self.keyword("FROM")
  let (relation, source_alias) = self.source_name()
  let operations : Array[QueryOperation] = []
  if self.has("WHERE") {
    self.keyword("WHERE")
    self.node()
    operations.push(Where(self.expression()))
  }
  operations.push(Select(projections, distinct))
  if self.has("ORDER") {
    self.keyword("ORDER")
    self.keyword("BY")
    operations.push(Order(self.order()))
  }
  if self.has("LIMIT") {
    self.node()
    operations.push(self.limit())
  }
  self.end()
  { source: self.source, relation, source_alias, operations, work: self.work, }
}

///|
fn QueryParser::pipe(self : QueryParser) -> Query raise QueryAbort {
  self.keyword("FROM")
  let (relation, source_alias) = self.source_name()
  let operations : Array[QueryOperation] = []
  while self.peek().value == Pipe {
    ignore(self.advance())
    self.node()
    if self.has("WHERE") {
      self.keyword("WHERE")
      operations.push(Where(self.expression()))
    } else if self.has("SELECT") {
      self.keyword("SELECT")
      let distinct = self.has("DISTINCT")
      if distinct {
        self.keyword("DISTINCT")
      }
      operations.push(Select(self.projections(), distinct))
    } else if self.has("ORDER") {
      self.keyword("ORDER")
      self.keyword("BY")
      operations.push(Order(self.order()))
    } else if self.has("LIMIT") {
      operations.push(self.limit())
    } else {
      raise QueryAbort("Unknown Pipe operation", self.peek().start)
    }
  }
  self.end()
  { source: self.source, relation, source_alias, operations, work: self.work, }
}

///|
pub fn parse_query(
  text : String,
  limits : QueryLimits,
  source_path? : String = "<query>",
) -> Result[Query, Diagnostic] {
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
  }
  try {
    let query = if parser.has("SELECT") { parser.sql() } else { parser.pipe() }
    Ok(query)
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
