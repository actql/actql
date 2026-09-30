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
  aggregate : AggregateCall?
  analytic : AnalyticCall?
  name : NamePart?
  star : String?
}

///|
pub(all) struct AggregateCall {
  function_name : String
  argument : Expression?
  distinct : Bool
  order_by : Array[SortTerm]
  delimiter : String?
}

///|
pub(all) enum FrameBoundary {
  UnboundedPreceding
  CurrentRow
  UnboundedFollowing
  Preceding(Int64)
  Following(Int64)
} derive(Eq, Debug)

///|
pub(all) struct AnalyticFrame {
  start : FrameBoundary
  end : FrameBoundary
} derive(Eq, Debug)

///|
pub(all) struct AnalyticWindow {
  partition_by : Array[Array[NamePart]]
  order_by : Array[SortTerm]
  frame : AnalyticFrame?
}

///|
pub(all) struct AnalyticCall {
  expression : Expression?
  aggregate : AggregateCall?
  window : AnalyticWindow
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
  Extend(Array[Projection])
  Set(Array[(NamePart, Expression)])
  Drop(Array[NamePart])
  Rename(Array[(NamePart, NamePart)])
  Alias(NamePart)
  Group(Array[Expression], Array[Projection])
  Having(Expression)
  Analytic(Array[Projection])
  Select(Array[Projection], Bool)
  Order(Array[SortTerm])
  Limit(Int64, Int64)
}

///|
pub(all) struct SetPart {
  kind : String
  duplicates : String
  by_name : Bool
  right : Query
}

///|
pub(all) struct JoinPart {
  kind : String
  relation : Array[NamePart]
  source_alias : NamePart?
  on : Expression?
  using_columns : Array[NamePart]
  pre_join_filter : Expression?
}

///|
pub(all) struct CtePart {
  name : NamePart
  query : Query
}

///|
struct Query {
  source : Tokens
  ctes : Array[CtePart]
  relation : Array[NamePart]
  source_alias : NamePart?
  graph : GraphQuery?
  joins : Array[JoinPart]
  operations : Array[QueryOperation]
  sets : Array[SetPart]
  final_operations : Array[QueryOperation]
  work : Int
}

///|
pub fn cte_count(query : Query) -> Int {
  query.ctes.length()
}

///|
pub fn cte_at(query : Query, index : Int) -> CtePart? {
  query.ctes.get(index)
}

///|
pub fn set_part_count(query : Query) -> Int {
  query.sets.length()
}

///|
pub fn join_part_count(query : Query) -> Int {
  query.joins.length()
}

///|
pub fn join_part_at(query : Query, index : Int) -> JoinPart? {
  query.joins.get(index)
}

///|
pub fn set_part_at(query : Query, index : Int) -> SetPart? {
  query.sets.get(index)
}

///|
pub fn final_operation_count(query : Query) -> Int {
  query.final_operations.length()
}

///|
pub fn final_operation_at(query : Query, index : Int) -> QueryOperation? {
  query.final_operations.get(index)
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
pub fn graph_query(query : Query) -> GraphQuery? {
  query.graph
}

///|
pub fn query_source(query : Query) -> Tokens {
  query.source
}

///|
/// Classify the first admitted token before choosing a query-only AQL form.
/// A malformed query never falls back to a structural Program or YAML.
pub fn starts_query(
  text : String,
  limits : LexicalLimits,
  source_path? : String = "<query>",
) -> Result[Bool, Diagnostic] {
  match scan_tokens(text, limits, source_path, true) {
    Err(issue) => Err(issue)
    Ok(tokens) => {
      let first = token_at(tokens, 0).unwrap()
      Ok(
        keyword(first, "SELECT") ||
        keyword(first, "WITH") ||
        keyword(first, "FROM"),
      )
    }
  }
}

///|
/// SQL is selected explicitly. A Pipe source must retain the AQL-text
/// spelling, even though both lower through the same query representation.
pub fn starts_sql(
  text : String,
  limits : LexicalLimits,
  source_path? : String = "<query>",
) -> Result[Bool, Diagnostic] {
  match scan_tokens(text, limits, source_path, true) {
    Err(issue) => Err(issue)
    Ok(tokens) => {
      let first = token_at(tokens, 0).unwrap()
      Ok(keyword(first, "SELECT") || keyword(first, "WITH"))
    }
  }
}

///|
/// Parse a published relation alias with the same quoted-name lexer as a
/// query. Installation must still bind the result to one Source View and
/// reject collisions before making the snapshot visible.
pub fn parse_relation_path(
  text : String,
  limits : LexicalLimits,
  source_path? : String = "<alias>",
) -> Result[Array[NamePart], Diagnostic] {
  let tokens = match tokenize(text, limits, source_path~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let parts : Array[NamePart] = []
  let mut expect_name = true
  for index in 0..<token_count(tokens) {
    let token = token_at(tokens, index).unwrap()
    if token.value == End {
      if !expect_name && !parts.is_empty() {
        return Ok(parts)
      }
      return Err({
        issue: Syntax("Expected relation name"),
        span: token_origin(tokens, index).map(@origin.span),
      })
    }
    if expect_name {
      if parts.length() >= 16 {
        return Err({
          issue: Syntax("Relation path limit"),
          span: token_origin(tokens, index).map(@origin.span),
        })
      }
      match token.value {
        Word(value) => parts.push({ value, quoted: false, })
        QuotedName(value) => parts.push({ value, quoted: true, })
        _ =>
          return Err({
            issue: Syntax("Expected relation name"),
            span: token_origin(tokens, index).map(@origin.span),
          })
      }
      expect_name = false
    } else if token.value == Symbol(46) {
      expect_name = true
    } else {
      return Err({
        issue: Syntax("Expected relation separator"),
        span: token_origin(tokens, index).map(@origin.span),
      })
    }
  }
  Err({ issue: Syntax("Expected relation name"), span: None, })
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
    Extend(xs) => Some(Extend(xs.copy()))
    Set(xs) => Some(Set(xs.copy()))
    Drop(xs) => Some(Drop(xs.copy()))
    Rename(xs) => Some(Rename(xs.copy()))
    Alias(name) => Some(Alias(name))
    Group(keys, projections) => Some(Group(keys.copy(), projections.copy()))
    Having(e) => Some(Having(e))
    Analytic(projections) => Some(Analytic(projections.copy()))
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
  mut source_depth : Int
  mut synthetic_sources : Int
}

///|
fn ascii_upper(value : String) -> String {
  let out = StringBuilder()
  for char in value {
    let code = char.to_int()
    out.write_char(
      (if code >= 97 && code <= 122 { code - 32 } else { code }).unsafe_to_char(),
    )
  }
  out.to_string()
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
  (relation, self.optional_source_alias())
}

///|
fn QueryParser::optional_source_alias(
  self : QueryParser,
) -> NamePart? raise QueryAbort {
  if self.has("AS") {
    self.keyword("AS")
    Some(self.name())
  } else if self.peek().value is Word(value) &&
    ![
      "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "WHERE", "GROUP", "HAVING",
      "ORDER", "LIMIT", "UNION", "INTERSECT", "EXCEPT", "ON", "USING",
    ].contains(value.to_upper()) {
    Some(self.name())
  } else {
    None
  }
}

///|
fn QueryParser::query_source(
  self : QueryParser,
) -> (Array[NamePart], NamePart?, Array[CtePart]) raise QueryAbort {
  if self.peek().value != Symbol(40) {
    let (relation, source_alias) = self.source_name()
    return (relation, source_alias, [])
  }
  self.node()
  if self.source_depth >= 32 {
    raise QueryAbort("Subquery depth limit", self.peek().start)
  }
  let mut serial = self.synthetic_sources
  let mut generated_name = "aql_query_source_" + serial.to_string()
  while self.source.tokens.any(token => {
          match token.value {
            Word(value) | QuotedName(value) =>
              ascii_upper(value) == ascii_upper(generated_name)
            _ => false
          }
        }) {
    self.spend(self.source.tokens.length())
    serial += 1
    generated_name = "aql_query_source_" + serial.to_string()
  }
  self.synthetic_sources = serial + 1
  self.source_depth += 1
  ignore(self.advance())
  let term = self.sql_term()
  let tail : Array[QueryOperation] = []
  if self.has("ORDER") {
    self.keyword("ORDER")
    self.keyword("BY")
    tail.push(Order(self.order()))
  }
  if self.has("LIMIT") {
    tail.push(self.limit())
  }
  let inner = { ..term, operations: term.operations + tail, }
  self.source_depth -= 1
  if self.advance().value != Symbol(41) {
    raise QueryAbort("Expected subquery closing parenthesis", self.peek().start)
  }
  let source_alias = match self.optional_source_alias() {
    Some(value) => value
    None => raise QueryAbort("Subquery requires an alias", self.peek().start)
  }
  let generated : NamePart = { value: generated_name, quoted: false, }
  let ctes = inner.ctes + [{ name: generated, query: { ..inner, ctes: [], }, }]
  if ctes.length() > self.limits.max_cte_count {
    raise QueryAbort("CTE count limit", self.peek().start)
  }
  ([generated], Some(source_alias), ctes)
}

///|
fn QueryParser::join_part(
  self : QueryParser,
) -> (JoinPart, Array[CtePart]) raise QueryAbort {
  self.node()
  let kind = if self.has("INNER") {
    self.keyword("INNER")
    "inner"
  } else if self.has("LEFT") {
    self.keyword("LEFT")
    if self.has("OUTER") {
      self.keyword("OUTER")
    }
    "left"
  } else if self.has("FULL") {
    self.keyword("FULL")
    if self.has("OUTER") {
      self.keyword("OUTER")
    }
    "full"
  } else if self.has("CROSS") {
    self.keyword("CROSS")
    "cross"
  } else {
    "inner"
  }
  self.keyword("JOIN")
  let (relation, source_alias, ctes) = self.query_source()
  if kind == "cross" {
    return (
      {
        kind,
        relation,
        source_alias,
        on: None,
        using_columns: [],
        pre_join_filter: None,
      },
      ctes,
    )
  }
  if self.has("ON") {
    self.keyword("ON")
    self.node()
    return (
      {
        kind,
        relation,
        source_alias,
        on: Some(self.expression()),
        using_columns: [],
        pre_join_filter: None,
      },
      ctes,
    )
  }
  self.keyword("USING")
  if self.advance().value != Symbol(40) {
    raise QueryAbort("Expected USING opening parenthesis", self.peek().start)
  }
  let using_columns : Array[NamePart] = []
  while true {
    self.node()
    using_columns.push(self.name())
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  if self.advance().value != Symbol(41) {
    raise QueryAbort("Expected USING closing parenthesis", self.peek().start)
  }
  (
    {
      kind,
      relation,
      source_alias,
      on: None,
      using_columns,
      pre_join_filter: None,
    },
    ctes,
  )
}

///|
fn QueryParser::starts_join(self : QueryParser) -> Bool {
  self.has("JOIN") ||
  self.has("INNER") ||
  self.has("LEFT") ||
  self.has("FULL") ||
  self.has("CROSS")
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
      {
        expression: None,
        aggregate: None,
        analytic: None,
        name: None,
        star: Some("*"),
      }
    } else {
      let aggregate = if self.aggregate_head() {
        Some(self.aggregate())
      } else {
        None
      }
      let expression = if aggregate is Some(_) {
        None
      } else {
        Some(self.expression())
      }
      let analytic = if self.has("OVER") {
        Some({ expression, aggregate, window: self.over(), })
      } else {
        None
      }
      let name = if self.has("AS") {
        self.keyword("AS")
        Some(self.name())
      } else {
        None
      }
      if (aggregate is Some(_) || analytic is Some(_)) && name is None {
        raise QueryAbort("Function output requires AS name", self.peek().start)
      }
      {
        expression: if analytic is Some(_) {
          None
        } else {
          expression
        },
        aggregate: if analytic is Some(_) {
          None
        } else {
          aggregate
        },
        analytic,
        name,
        star: None,
      }
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
fn QueryParser::frame_boundary(
  self : QueryParser,
) -> FrameBoundary raise QueryAbort {
  if self.has("UNBOUNDED") {
    self.keyword("UNBOUNDED")
    if self.has("PRECEDING") {
      self.keyword("PRECEDING")
      return UnboundedPreceding
    }
    self.keyword("FOLLOWING")
    return UnboundedFollowing
  }
  if self.has("CURRENT") {
    self.keyword("CURRENT")
    self.keyword("ROW")
    return CurrentRow
  }
  let distance = self.safe_integer(false)
  if self.has("PRECEDING") {
    self.keyword("PRECEDING")
    Preceding(distance)
  } else {
    self.keyword("FOLLOWING")
    Following(distance)
  }
}

///|
fn QueryParser::over(self : QueryParser) -> AnalyticWindow raise QueryAbort {
  self.keyword("OVER")
  if self.advance().value != Symbol(40) {
    raise QueryAbort("Expected OVER opening parenthesis", self.peek().start)
  }
  let partition_by : Array[Array[NamePart]] = []
  if self.has("PARTITION") {
    self.keyword("PARTITION")
    self.keyword("BY")
    while true {
      self.node()
      partition_by.push(self.path())
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
  }
  self.keyword("ORDER")
  self.keyword("BY")
  let order_by = self.order()
  let frame = if self.has("ROWS") {
    self.keyword("ROWS")
    self.keyword("BETWEEN")
    let start = self.frame_boundary()
    self.keyword("AND")
    let end = self.frame_boundary()
    Some({ start, end, })
  } else {
    None
  }
  if self.advance().value != Symbol(41) {
    raise QueryAbort("Expected OVER closing parenthesis", self.peek().start)
  }
  { partition_by, order_by, frame, }
}

///|
fn QueryParser::aggregate_head(self : QueryParser) -> Bool {
  match self.peek().value {
    Word(name) =>
      [
        "COUNT", "COUNTIF", "SUM", "AVG", "MIN", "MAX", "ARRAY_AGG", "STRING_AGG",
      ].contains(upper_ascii(name)) &&
      self.source.tokens.get(self.index + 1).map(token => token.value) ==
      Some(Symbol(40))
    _ => false
  }
}

///|
fn QueryParser::aggregate(self : QueryParser) -> AggregateCall raise QueryAbort {
  let token = self.advance()
  let function_name = match token.value {
    Word(name) => upper_ascii(name)
    _ => raise QueryAbort("Expected aggregate function", token.start)
  }
  if self.advance().value != Symbol(40) {
    raise QueryAbort("Expected aggregate opening parenthesis", token.start)
  }
  let distinct = self.has("DISTINCT")
  if distinct {
    self.keyword("DISTINCT")
  }
  let argument = if self.peek().value == Symbol(42) {
    ignore(self.advance())
    if function_name != "COUNT" || distinct {
      raise QueryAbort("Invalid aggregate star", token.start)
    }
    None
  } else {
    Some(self.expression())
  }
  let delimiter = if function_name == "STRING_AGG" {
    if self.advance().value != Symbol(44) {
      raise QueryAbort("STRING_AGG requires a delimiter", token.start)
    }
    match self.advance().value {
      Text(value) => Some(value)
      _ => raise QueryAbort("STRING_AGG delimiter must be literal", token.start)
    }
  } else {
    None
  }
  if function_name == "ARRAY_AGG" {
    self.keyword("IGNORE")
    self.keyword("NULLS")
  }
  let order_by = if function_name == "ARRAY_AGG" ||
    function_name == "STRING_AGG" {
    self.keyword("ORDER")
    self.keyword("BY")
    self.order()
  } else {
    []
  }
  if self.advance().value != Symbol(41) {
    raise QueryAbort("Expected aggregate closing parenthesis", token.start)
  }
  if argument is None && function_name != "COUNT" {
    raise QueryAbort("Aggregate argument required", token.start)
  }
  if distinct && ["COUNTIF", "MIN", "MAX"].contains(function_name) {
    raise QueryAbort("DISTINCT is not valid for this aggregate", token.start)
  }
  { function_name, argument, distinct, order_by, delimiter, }
}

///|
fn QueryParser::group_keys(
  self : QueryParser,
) -> Array[Expression] raise QueryAbort {
  self.keyword("GROUP")
  self.keyword("BY")
  if self.peek().value == Symbol(40) &&
    self.source.tokens.get(self.index + 1).map(token => token.value) ==
    Some(Symbol(41)) {
    ignore(self.advance())
    ignore(self.advance())
    return []
  }
  let keys : Array[Expression] = []
  while true {
    self.node()
    keys.push(self.expression())
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  keys
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
fn QueryParser::safe_integer(
  self : QueryParser,
  zero_allowed : Bool,
) -> Int64 raise QueryAbort {
  let token = self.advance()
  let text = match token.value {
    Numeric(text) => text
    _ => raise QueryAbort("Expected safe integer literal", token.start)
  }
  let mut result = 0L
  for unit in text {
    self.spend(1)
    let digit = unit.to_int() - 48
    if digit < 0 ||
      digit > 9 ||
      result > (9007199254740991L - digit.to_int64()) / 10L {
      raise QueryAbort("Integer literal exceeds safe range", token.start)
    }
    result = result * 10L + digit.to_int64()
  }
  if !zero_allowed && result == 0L {
    raise QueryAbort("Expected positive integer literal", token.start)
  }
  result
}

///|
fn QueryParser::limit(self : QueryParser) -> QueryOperation raise QueryAbort {
  self.keyword("LIMIT")
  let count = self.safe_integer(false)
  let offset = if self.has("OFFSET") {
    self.keyword("OFFSET")
    self.safe_integer(true)
  } else {
    0L
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
fn QueryParser::sql_term(self : QueryParser) -> Query raise QueryAbort {
  self.keyword("SELECT")
  let distinct = self.has("DISTINCT")
  if distinct {
    self.keyword("DISTINCT")
  }
  let projections = self.projections()
  self.keyword("FROM")
  let (relation, source_alias, ctes) = self.query_source()
  let joins : Array[JoinPart] = []
  while self.starts_join() {
    let (part, join_ctes) = self.join_part()
    joins.push(part)
    for cte in join_ctes {
      ctes.push(cte)
    }
  }
  let operations : Array[QueryOperation] = []
  if self.has("WHERE") {
    self.keyword("WHERE")
    self.node()
    operations.push(Where(self.expression()))
  }
  let grouped = self.has("GROUP") ||
    projections.any(projection => projection.aggregate is Some(_))
  if self.has("GROUP") {
    operations.push(Group(self.group_keys(), projections))
  } else if grouped {
    operations.push(Group([], projections))
  }
  if self.has("HAVING") {
    if !grouped {
      raise QueryAbort("HAVING requires grouping", self.peek().start)
    }
    self.keyword("HAVING")
    operations.push(Having(self.expression()))
  }
  if projections.any(projection => projection.analytic is Some(_)) {
    operations.push(Analytic(projections))
  }
  operations.push(Select(projections, distinct))
  {
    source: self.source,
    ctes,
    relation,
    source_alias,
    graph: None,
    joins,
    operations,
    sets: [],
    final_operations: [],
    work: self.work,
  }
}

///|
fn QueryParser::sql(self : QueryParser) -> Query raise QueryAbort {
  let ctes : Array[CtePart] = []
  if self.has("WITH") {
    self.keyword("WITH")
    if self.has("RECURSIVE") {
      raise QueryAbort("Recursive CTE is unsupported", self.peek().start)
    }
    while true {
      self.node()
      if ctes.length() >= self.limits.max_cte_count {
        raise QueryAbort("CTE count limit", self.peek().start)
      }
      let name = self.name()
      if ctes.any(part => part.name.value == name.value) {
        raise QueryAbort("Duplicate CTE name", self.peek().start)
      }
      self.keyword("AS")
      if self.advance().value != Symbol(40) {
        raise QueryAbort("Expected CTE opening parenthesis", self.peek().start)
      }
      let body = self.sql_term()
      if self.advance().value != Symbol(41) {
        raise QueryAbort("Expected CTE closing parenthesis", self.peek().start)
      }
      for nested in body.ctes {
        if ctes.length() >= self.limits.max_cte_count {
          raise QueryAbort("CTE count limit", self.peek().start)
        }
        ctes.push(nested)
      }
      if ctes.length() >= self.limits.max_cte_count {
        raise QueryAbort("CTE count limit", self.peek().start)
      }
      ctes.push({ name, query: { ..body, ctes: [], }, })
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
  }
  let term = self.sql_term()
  let sets : Array[SetPart] = []
  let mut set_spelling : (String, String, Bool)? = None
  while self.has("UNION") || self.has("INTERSECT") || self.has("EXCEPT") {
    self.node()
    let kind = if self.has("UNION") {
      self.keyword("UNION")
      "union"
    } else if self.has("INTERSECT") {
      self.keyword("INTERSECT")
      "intersect"
    } else {
      self.keyword("EXCEPT")
      "except"
    }
    let duplicates = if self.has("ALL") {
      self.keyword("ALL")
      if kind != "union" {
        raise QueryAbort("Set operator requires DISTINCT", self.peek().start)
      }
      "all"
    } else {
      self.keyword("DISTINCT")
      "distinct"
    }
    let by_name = if self.has("BY") {
      self.keyword("BY")
      self.keyword("NAME")
      true
    } else {
      false
    }
    match set_spelling {
      Some((old_kind, old_duplicates, old_by_name)) =>
        if old_kind != kind ||
          old_duplicates != duplicates ||
          old_by_name != by_name {
          raise QueryAbort(
            "Mixed set operators require parentheses",
            self.peek().start,
          )
        }
      None => set_spelling = Some((kind, duplicates, by_name))
    }
    sets.push({ kind, duplicates, by_name, right: self.sql_term(), })
  }
  let tail : Array[QueryOperation] = []
  if self.has("ORDER") {
    self.keyword("ORDER")
    self.keyword("BY")
    tail.push(Order(self.order()))
  }
  if self.has("LIMIT") {
    self.node()
    tail.push(self.limit())
  }
  self.end()
  let all_ctes = ctes + term.ctes
  if all_ctes.length() > self.limits.max_cte_count {
    raise QueryAbort("CTE count limit", self.peek().start)
  }
  if sets.is_empty() {
    {
      ..term,
      ctes: all_ctes,
      operations: term.operations + tail,
      work: self.work,
    }
  } else {
    { ..term, ctes: all_ctes, sets, final_operations: tail, work: self.work, }
  }
}

///|
fn QueryParser::pipe(self : QueryParser) -> Query raise QueryAbort {
  self.keyword("FROM")
  let mut graph : GraphQuery? = None
  let (relation, source_alias, ctes) = if self.has("GRAPH") {
    self.keyword("GRAPH")
    let relation = self.path()
    let label_field = self.graph_labels()
    graph = Some({ label_field, pattern: None, })
    (relation, None, [])
  } else {
    self.query_source()
  }
  let joins : Array[JoinPart] = []
  let operations : Array[QueryOperation] = []
  let sets : Array[SetPart] = []
  let final_operations : Array[QueryOperation] = []
  while self.peek().value == Pipe {
    ignore(self.advance())
    self.node()
    if self.has("MATCH") {
      match graph {
        Some(current) if current.pattern is None => {
          let pattern = self.graph_match()
          if current.label_field is None &&
            pattern.nodes.any(node => node.label is Some(_)) {
            raise QueryAbort("GRAPH_NODE_LABEL_MAPPING_REQUIRED", pattern.start)
          }
          graph = Some({ ..current, pattern: Some(pattern), })
        }
        Some(_) =>
          raise QueryAbort(
            "GRAPH_PATTERN_UNSUPPORTED_SHAPE: a second MATCH needs a separate Graph input",
            self.peek().start,
          )
        None =>
          raise QueryAbort(
            "GRAPH_PATTERN_GRAPH_SOURCE_REQUIRED",
            self.peek().start,
          )
      }
    } else if self.has("UNION") || self.has("INTERSECT") || self.has("EXCEPT") {
      if !final_operations.is_empty() {
        raise QueryAbort(
          "Set input cannot follow final ordering",
          self.peek().start,
        )
      }
      let kind = if self.has("UNION") {
        self.keyword("UNION")
        "union"
      } else if self.has("INTERSECT") {
        self.keyword("INTERSECT")
        "intersect"
      } else {
        self.keyword("EXCEPT")
        "except"
      }
      let duplicates = if self.has("ALL") {
        self.keyword("ALL")
        if kind != "union" {
          raise QueryAbort("Set operator requires DISTINCT", self.peek().start)
        }
        "all"
      } else {
        self.keyword("DISTINCT")
        "distinct"
      }
      let by_name = if self.has("BY") {
        self.keyword("BY")
        self.keyword("NAME")
        true
      } else {
        false
      }
      if self.advance().value != Symbol(40) {
        raise QueryAbort(
          "Pipe set input must be parenthesized",
          self.peek().start,
        )
      }
      let right = self.sql_term()
      if self.advance().value != Symbol(41) {
        raise QueryAbort(
          "Expected Pipe set closing parenthesis",
          self.peek().start,
        )
      }
      sets.push({ kind, duplicates, by_name, right, })
    } else if !sets.is_empty() && !(self.has("ORDER") || self.has("LIMIT")) {
      raise QueryAbort(
        "Unsupported operation after Pipe set",
        self.peek().start,
      )
    } else if self.starts_join() {
      if !sets.is_empty() ||
        (!joins.is_empty() && !operations.is_empty()) ||
        operations.length() > 1 {
        raise QueryAbort(
          "Pipe JOIN prefix must be one WHERE",
          self.peek().start,
        )
      }
      let pre_join_filter = if operations.length() == 1 {
        match operations[0] {
          Where(expression) => Some(expression)
          _ =>
            raise QueryAbort(
              "Pipe JOIN prefix must be one WHERE",
              self.peek().start,
            )
        }
      } else {
        None
      }
      if pre_join_filter is Some(_) {
        operations.clear()
      }
      let (part, join_ctes) = self.join_part()
      joins.push({ ..part, pre_join_filter, })
      for cte in join_ctes {
        ctes.push(cte)
      }
    } else if self.has("WHERE") {
      self.keyword("WHERE")
      operations.push(Where(self.expression()))
    } else if self.has("EXTEND") {
      self.keyword("EXTEND")
      let values = self.projections()
      if values.any(p => p.name is None || p.expression is None) {
        raise QueryAbort(
          "EXTEND requires named scalar expressions",
          self.peek().start,
        )
      }
      operations.push(Extend(values))
    } else if self.has("SET") {
      self.keyword("SET")
      let values : Array[(NamePart, Expression)] = []
      while true {
        self.node()
        let name = self.name()
        if self.advance().value != Symbol(61) {
          raise QueryAbort("SET requires an equals sign", self.peek().start)
        }
        values.push((name, self.expression()))
        if self.peek().value != Symbol(44) {
          break
        }
        ignore(self.advance())
      }
      operations.push(Set(values))
    } else if self.has("DROP") {
      self.keyword("DROP")
      let values : Array[NamePart] = []
      while true {
        self.node()
        values.push(self.name())
        if self.peek().value != Symbol(44) {
          break
        }
        ignore(self.advance())
      }
      operations.push(Drop(values))
    } else if self.has("RENAME") {
      self.keyword("RENAME")
      let values : Array[(NamePart, NamePart)] = []
      while true {
        self.node()
        let from = self.name()
        self.keyword("AS")
        values.push((from, self.name()))
        if self.peek().value != Symbol(44) {
          break
        }
        ignore(self.advance())
      }
      operations.push(Rename(values))
    } else if self.has("AS") {
      self.keyword("AS")
      operations.push(Alias(self.name()))
    } else if self.has("AGGREGATE") {
      self.keyword("AGGREGATE")
      let aggregates = self.projections()
      if aggregates.any(projection => projection.aggregate is None) {
        raise QueryAbort("AGGREGATE requires named calls", self.peek().start)
      }
      let keys = if self.has("GROUP") { self.group_keys() } else { [] }
      operations.push(Group(keys, aggregates))
    } else if self.has("SELECT") {
      self.keyword("SELECT")
      let distinct = self.has("DISTINCT")
      if distinct {
        self.keyword("DISTINCT")
      }
      let projections = self.projections()
      if projections.any(projection => projection.analytic is Some(_)) {
        operations.push(Analytic(projections))
      }
      operations.push(Select(projections, distinct))
    } else if self.has("ORDER") {
      self.keyword("ORDER")
      self.keyword("BY")
      let operation = Order(self.order())
      if sets.is_empty() {
        operations.push(operation)
      } else {
        final_operations.push(operation)
      }
    } else if self.has("LIMIT") {
      let operation = self.limit()
      if sets.is_empty() {
        operations.push(operation)
      } else {
        final_operations.push(operation)
      }
    } else if self.has("INFER") || self.has("NEAREST") || self.has("KEEP") {
      raise QueryAbort(
        "INFER/NEAREST KEEP is adopted but not implemented in the query frontend",
        self.peek().start,
      )
    } else {
      raise QueryAbort("Unknown Pipe operation", self.peek().start)
    }
  }
  self.end()
  if graph is Some(current) && current.pattern is None {
    raise QueryAbort("GRAPH_PATTERN_MATCH_REQUIRED", self.peek().start)
  }
  if ctes.length() > self.limits.max_cte_count {
    raise QueryAbort("CTE count limit", self.peek().start)
  }
  {
    source: self.source,
    ctes,
    relation,
    source_alias,
    graph,
    joins,
    operations,
    sets,
    final_operations,
    work: self.work,
  }
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
    source_depth: 0,
    synthetic_sources: 0,
  }
  try {
    let query = if parser.has("SELECT") || parser.has("WITH") {
      parser.sql()
    } else {
      parser.pipe()
    }
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
