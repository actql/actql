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
  PrecedingParameter(String)
  FollowingParameter(String)
} derive(Eq, Debug)

///|
pub(all) struct AnalyticFrame {
  start : FrameBoundary
  end : FrameBoundary
} derive(Eq, Debug)

///|
pub(all) struct AnalyticWindow {
  partition_by : Array[Expression]
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
pub(all) enum GroupingScope {
  SqlSelect
  PipeAggregate
} derive(Eq)

///|
/// An authored operation integer. Bound values belong to the common checker;
/// the parser retains the parameter name without evaluating or defaulting it.
pub(all) enum QueryInteger {
  Integer(Int64)
  BoundParameter(String)
} derive(Eq, Debug)

///|
pub(all) enum QueryOperation {
  GraphCall(SgaCall)
  UnnestSource(Expression, NamePart, NamePart?)
  AssertUnique(Array[Array[NamePart]])
  Infer(InferClause)
  Nearest(NearestClause)
  RetainResult(NamePart)
  Where(Expression)
  Extend(Array[Projection])
  Set(Array[(NamePart, Expression)])
  Drop(Array[NamePart])
  Rename(Array[(NamePart, NamePart)])
  Alias(NamePart)
  Group(Array[Expression], Array[Projection], GroupingScope)
  Having(Expression)
  Analytic(Array[Projection])
  Select(Array[Projection], Bool)
  Order(Array[SortTerm])
  Limit(QueryInteger, QueryInteger)
}

///|
pub(all) struct KeepItem {
  path : Array[NamePart]
  wildcard : Bool
  name : NamePart?
}

///|
pub(all) struct UpdateEffectClause {
  name : NamePart
  target : String
  mapping : NamePart
  result : NamePart
  id : NamePart
  set : Array[(NamePart, Expression)]
}

///|
pub(all) struct InferClause {
  contract : NamePart
  keys : Array[Array[NamePart]]
  inputs : Array[(NamePart, Expression)]
  keep : Array[KeepItem]
  name : NamePart
}

///|
pub(all) struct NearestClause {
  relation : Array[NamePart]
  candidate_alias : NamePart
  query_keys : Array[Array[NamePart]]
  query_vector : Expression
  candidate_keys : Array[Array[NamePart]]
  candidate_vector : Expression
  metric : String
  k : Int64
  keep : Array[KeepItem]
  name : NamePart
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
  max_output_rows : Int64?
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
  effect : UpdateEffectClause?
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
        keyword(first, "FROM") ||
        keyword(first, "DATA") ||
        first.value == Symbol(40),
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
      if first.value != Symbol(40) {
        return Ok(keyword(first, "SELECT") || keyword(first, "WITH"))
      }
      // Inspect admitted tokens, not source substrings: parentheses and
      // comments do not change whether the head is SQL or FROM-headed Pipe.
      let tokens = match tokenize(text, limits, source_path~) {
        Ok(tokens) => tokens
        Err(issue) => return Err(issue)
      }
      let mut index = 0
      while token_at(tokens, index).unwrap().value == Symbol(40) {
        index += 1
      }
      let head = token_at(tokens, index).unwrap()
      Ok(keyword(head, "SELECT") || keyword(head, "WITH"))
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
    UnnestSource(expression, element, offset) =>
      Some(UnnestSource(expression, element, offset))
    GraphCall(call) => Some(GraphCall(copy_sga_call(call)))
    AssertUnique(keys) => Some(AssertUnique(keys.map(path => path.copy())))
    Nearest(clause) =>
      Some(
        Nearest({
          ..clause,
          relation: clause.relation.copy(),
          query_keys: clause.query_keys.map(path => path.copy()),
          candidate_keys: clause.candidate_keys.map(path => path.copy()),
          keep: clause.keep.map(item => { ..item, path: item.path.copy(), }),
        }),
      )
    Infer(clause) =>
      Some(
        Infer({
          ..clause,
          keys: clause.keys.map(path => path.copy()),
          inputs: clause.inputs.copy(),
          keep: clause.keep.map(item => { ..item, path: item.path.copy(), }),
        }),
      )
    Where(e) => Some(Where(e))
    Extend(xs) => Some(Extend(xs.copy()))
    Set(xs) => Some(Set(xs.copy()))
    Drop(xs) => Some(Drop(xs.copy()))
    Rename(xs) => Some(Rename(xs.copy()))
    Alias(name) => Some(Alias(name))
    RetainResult(name) => Some(RetainResult(name))
    Group(keys, projections, scope) =>
      Some(Group(keys.copy(), projections.copy(), scope))
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
  cte_scopes : Array[Array[(NamePart, NamePart)]]
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
/// Relation names retain exact quoted spelling, separately from field aliases.
pub fn same_relation_name(left : NamePart, right : NamePart) -> Bool {
  if left.quoted || right.quoted {
    left.value == right.value
  } else {
    ascii_upper(left.value) == ascii_upper(right.value)
  }
}

///|
// A CTE is a query-local alias, not a published Source View path. Backticks
// quote its syntax without changing case-insensitive alias resolution.
fn same_cte_name(left : NamePart, right : NamePart) -> Bool {
  ascii_upper(left.value) == ascii_upper(right.value)
}

///|
fn QueryParser::resolve_cte(
  self : QueryParser,
  relation : Array[NamePart],
) -> Array[NamePart] raise QueryAbort {
  if relation.length() != 1 {
    return relation
  }
  let mut scope = self.cte_scopes.length() - 1
  while scope >= 0 {
    let bindings = self.cte_scopes[scope]
    let mut index = bindings.length() - 1
    while index >= 0 {
      self.spend(1)
      let (authored, producer) = bindings[index]
      if same_cte_name(relation[0], authored) {
        return [producer]
      }
      index -= 1
    }
    scope -= 1
  }
  relation
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
  let resolved = self.resolve_cte(relation)
  let explicit_alias = self.optional_source_alias()
  let source_alias = if explicit_alias is None &&
    resolved[0].value != relation[0].value {
    Some(relation[0])
  } else {
    explicit_alias
  }
  (resolved, source_alias)
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
      "ORDER", "LIMIT", "UNION", "INTERSECT", "EXCEPT", "ON", "USING", "MAX_OUTPUT_ROWS",
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
  let bound = self.bind_query(self.parenthesized())
  let source_alias = match self.optional_source_alias() {
    Some(value) => value
    None => raise QueryAbort("Subquery requires an alias", self.peek().start)
  }
  (bound.relation, Some(source_alias), bound.ctes)
}

///|
fn QueryParser::bind_query(
  self : QueryParser,
  inner : Query,
) -> Query raise QueryAbort {
  self.node()
  let generated = self.fresh_producer("aql_query_source_")
  let ctes = inner.ctes + [{ name: generated, query: { ..inner, ctes: [], }, }]
  if ctes.length() > self.limits.max_cte_count {
    raise QueryAbort("CTE count limit", self.peek().start)
  }
  {
    source: self.source,
    ctes,
    relation: [generated],
    source_alias: None,
    graph: None,
    joins: [],
    operations: [],
    sets: [],
    final_operations: [],
    effect: None,
    work: self.work,
  }
}

///|
fn QueryParser::fresh_producer(
  self : QueryParser,
  prefix : String,
) -> NamePart raise QueryAbort {
  let mut serial = self.synthetic_sources
  let mut generated_name = prefix + serial.to_string()
  while true {
    self.spend(self.source.tokens.length())
    if !self.source.tokens.any(token => {
        match token.value {
          Word(value) | QuotedName(value) =>
            ascii_upper(value) == ascii_upper(generated_name)
          _ => false
        }
      }) {
      break
    }
    serial += 1
    generated_name = prefix + serial.to_string()
  }
  self.synthetic_sources = serial + 1
  { value: generated_name, quoted: false, }
}

///|
fn QueryParser::parenthesized(self : QueryParser) -> Query raise QueryAbort {
  if self.source_depth >= 32 {
    raise QueryAbort("Subquery depth limit", self.peek().start)
  }
  self.node()
  self.source_depth += 1
  if self.advance().value != Symbol(40) {
    raise QueryAbort("Expected query opening parenthesis", self.peek().start)
  }
  let inner = self.query(cte_body=true)
  self.source_depth -= 1
  if self.advance().value != Symbol(41) {
    raise QueryAbort("Expected query closing parenthesis", self.peek().start)
  }
  inner
}

///|
fn QueryParser::sql_operand(self : QueryParser) -> Query raise QueryAbort {
  if self.peek().value == Symbol(40) {
    self.bind_query(self.parenthesized())
  } else {
    self.sql_term()
  }
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
        max_output_rows: self.join_bound(),
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
        max_output_rows: self.join_bound(),
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
      max_output_rows: self.join_bound(),
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
  if self.peek().value is Parameter(name) {
    ignore(self.advance())
    if self.has("PRECEDING") {
      self.keyword("PRECEDING")
      return PrecedingParameter(name)
    }
    self.keyword("FOLLOWING")
    return FollowingParameter(name)
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
  let partition_by : Array[Expression] = []
  if self.has("PARTITION") {
    self.keyword("PARTITION")
    self.keyword("BY")
    while true {
      let start = self.peek().start
      self.node()
      let path = self.path()
      // Keep the existing path grammar, but retain its original expression
      // owner and span so ordinary prefix/property lowering can consume it.
      partition_by.push({
        source: self.source,
        nodes: [
          {
            kind: Reference(path),
            start,
            end: self.source.tokens[self.index - 1].end,
          },
        ],
        root: 0,
        work: 1,
      })
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
  let count = self.limit_integer(false)
  let offset = if self.has("OFFSET") {
    self.keyword("OFFSET")
    self.limit_integer(true)
  } else {
    Integer(0L)
  }
  Limit(count, offset)
}

///|
fn QueryParser::limit_integer(
  self : QueryParser,
  zero_allowed : Bool,
) -> QueryInteger raise QueryAbort {
  if self.peek().value is Parameter(name) {
    ignore(self.advance())
    BoundParameter(name)
  } else {
    Integer(self.safe_integer(zero_allowed))
  }
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
// Explicit UNNEST consumes an array value, not an installed Relation alias.
// Element and offset names remain authored columns in the resulting scope.
fn QueryParser::unnest_source(
  self : QueryParser,
) -> QueryOperation raise QueryAbort {
  self.keyword("UNNEST")
  self.symbol(40)
  let expression = self.expression()
  self.symbol(41)
  if self.has("AS") {
    self.keyword("AS")
  }
  if self.has("WITH") || self.peek().value == Pipe || self.peek().value == End {
    raise QueryAbort(
      "UNNEST requires an explicit element alias in this profile",
      self.peek().start,
    )
  }
  let element = self.name()
  let offset = if self.has("WITH") {
    self.keyword("WITH")
    self.keyword("OFFSET")
    let name = if self.has("AS") {
      self.keyword("AS")
      self.name()
    } else if self.peek().value is QuotedName(_) {
      self.name()
    } else if self.optional_source_alias() is Some(name) {
      name
    } else {
      { value: "offset", quoted: false, }
    }
    Some(name)
  } else {
    None
  }
  self.node()
  UnnestSource(expression, element, offset)
}

///|
fn QueryParser::sql_term(self : QueryParser) -> Query raise QueryAbort {
  self.keyword("SELECT")
  let distinct = self.has("DISTINCT")
  if distinct {
    self.keyword("DISTINCT")
  }
  let projections = self.projections()
  let operations : Array[QueryOperation] = []
  let (relation, source_alias, ctes) = if self.has("FROM") {
    self.keyword("FROM")
    if self.has("UNNEST") {
      operations.push(self.unnest_source())
      ([], None, [])
    } else {
      self.query_source()
    }
  } else {
    ([], None, [])
  }
  let joins : Array[JoinPart] = []
  while !relation.is_empty() && self.starts_join() {
    let (part, join_ctes) = self.join_part()
    joins.push(part)
    for cte in join_ctes {
      ctes.push(cte)
    }
  }

  if self.has("WHERE") {
    self.keyword("WHERE")
    self.node()
    operations.push(Where(self.expression()))
  }
  let grouped = self.has("GROUP") ||
    projections.any(projection => projection.aggregate is Some(_))
  if self.has("GROUP") {
    operations.push(Group(self.group_keys(), projections, SqlSelect))
  } else if grouped {
    operations.push(Group([], projections, SqlSelect))
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
    effect: None,
    work: self.work,
  }
}

///|
fn QueryParser::query(
  self : QueryParser,
  cte_body? : Bool = false,
) -> Query raise QueryAbort {
  let ctes : Array[CtePart] = []
  let scope : Array[(NamePart, NamePart)] = []
  let nested_scope = !self.cte_scopes.is_empty()
  self.cte_scopes.push(scope)
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
      if scope.any(binding => same_cte_name(binding.0, name)) {
        raise QueryAbort("Duplicate CTE name", self.peek().start)
      }
      self.keyword("AS")
      let body = self.parenthesized()
      for nested in body.ctes {
        if ctes.length() >= self.limits.max_cte_count {
          raise QueryAbort("CTE count limit", self.peek().start)
        }
        ctes.push(nested)
      }
      if ctes.length() >= self.limits.max_cte_count {
        raise QueryAbort("CTE count limit", self.peek().start)
      }
      // Bind only after the body: non-recursive declarations can see earlier
      // CTEs, including outer scopes, but cannot acquire a recursive binding.
      // Nested names get private producer identities before flattening. Range
      // aliases keep the authored spelling, so qualification is unchanged.
      let producer = if nested_scope {
        self.fresh_producer("aql_cte_scope_")
      } else {
        name
      }
      scope.push((name, producer))
      ctes.push({ name: producer, query: { ..body, ctes: [], }, })
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
  }
  let term = if self.has("FROM") { self.pipe(cte_body~) } else { self.sql() }
  let term = if self.peek().value == Pipe {
    self.pipe_tail(term, cte_body~)
  } else {
    term
  }
  let all_ctes = ctes + term.ctes
  if all_ctes.length() > self.limits.max_cte_count {
    raise QueryAbort("CTE count limit", self.peek().start)
  }
  ignore(self.cte_scopes.pop())
  { ..term, ctes: all_ctes, work: self.work, }
}

///|
fn QueryParser::sql(self : QueryParser) -> Query raise QueryAbort {
  let term = self.sql_operand()
  let ctes = term.ctes.copy()
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
    let right = self.sql_operand()
    for cte in right.ctes {
      ctes.push(cte)
    }
    sets.push({ kind, duplicates, by_name, right: { ..right, ctes: [], }, })
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
  if sets.is_empty() {
    { ..term, operations: term.operations + tail, work: self.work, }
  } else {
    { ..term, ctes, sets, final_operations: tail, work: self.work, }
  }
}

///|
fn QueryParser::pipe(
  self : QueryParser,
  cte_body? : Bool = false,
) -> Query raise QueryAbort {
  self.keyword("FROM")
  let mut graph : GraphQuery? = None
  let operations : Array[QueryOperation] = []
  let (relation, source_alias, ctes) = if self.has("GRAPH") {
    if cte_body {
      raise QueryAbort("Graph CTE body is unsupported", self.peek().start)
    }
    self.keyword("GRAPH")
    let relation = self.path()
    let label_field = self.graph_labels()
    graph = Some({ label_field, pattern: None, })
    (relation, None, [])
  } else if self.has("UNNEST") {
    operations.push(self.unnest_source())
    ([], None, [])
  } else {
    self.query_source()
  }
  self.pipe_tail(
    {
      source: self.source,
      ctes,
      relation,
      source_alias,
      graph,
      joins: [],
      operations,
      sets: [],
      final_operations: [],
      effect: None,
      work: self.work,
    },
    cte_body~,
  )
}

///|
// Standard SELECT and FROM-starting Pipe use the same scope and operators.
fn QueryParser::pipe_tail(
  self : QueryParser,
  input : Query,
  cte_body? : Bool = false,
) -> Query raise QueryAbort {
  let relation = input.relation
  let source_alias = input.source_alias
  let ctes = input.ctes.copy()
  let mut graph = input.graph
  let joins = input.joins.copy()
  let operations = input.operations.copy()
  let sets = input.sets.copy()
  let final_operations = input.final_operations.copy()
  let mut effect = input.effect
  while self.peek().value == Pipe {
    if effect is Some(_) {
      raise QueryAbort("EFFECT must be terminal", self.peek().start)
    }
    // Once a set is complete, a following relational operator consumes its
    // output scope. Bind that producer instead of pushing the operator into
    // the left operand or repeating either operand's computation.
    let next = token_at(self.source, self.index + 1).unwrap()
    if !sets.is_empty() &&
      (
        (
          !final_operations.is_empty() &&
          (
            keyword(next, "UNION") ||
            keyword(next, "INTERSECT") ||
            keyword(next, "EXCEPT")
          )
        ) ||
        !(keyword(next, "ORDER") ||
        keyword(next, "LIMIT") ||
        keyword(next, "UNION") ||
        keyword(next, "INTERSECT") ||
        keyword(next, "EXCEPT"))
      ) {
      let producer : Query = {
        source: self.source,
        ctes,
        relation,
        source_alias,
        graph,
        joins,
        operations,
        sets,
        final_operations,
        effect: None,
        work: self.work,
      }
      return self.pipe_tail(self.bind_query(producer), cte_body~)
    }
    ignore(self.advance())
    self.node()
    if sga_call_head(self.peek()) {
      if graph is Some(current) && current.pattern is Some(_) {
        raise QueryAbort(
          "SGA call requires a Graph input before MATCH",
          self.peek().start,
        )
      }
      operations.push(GraphCall(self.sga_call()))
    } else if self.has("MATCH") {
      match graph {
        Some(current) if current.pattern is None => {
          let pattern = self.graph_match()
          // Syntax preserves a label. Its owner is resolved by lowering:
          // property graphs carry label membership themselves; the legacy
          // property-mapping profile requires its explicit annotation.
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
      if self.source_depth >= 32 {
        raise QueryAbort("Subquery depth limit", self.peek().start)
      }
      self.source_depth += 1
      let parsed = self.query(cte_body=true)
      self.source_depth -= 1
      let right = if !parsed.sets.is_empty() {
        self.bind_query(parsed)
      } else {
        parsed
      }
      for cte in right.ctes {
        ctes.push(cte)
      }
      if self.advance().value != Symbol(41) {
        raise QueryAbort(
          "Expected Pipe set closing parenthesis",
          self.peek().start,
        )
      }
      sets.push({ kind, duplicates, by_name, right: { ..right, ctes: [], }, })
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
      operations.push(Group(keys, aggregates, PipeAggregate))
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
    } else if self.has("RESULT") {
      self.keyword("RESULT")
      operations.push(RetainResult(self.name()))
    } else if self.has("ASSERT") {
      self.keyword("ASSERT")
      self.keyword("UNIQUE")
      self.keyword("BY")
      self.symbol(40)
      let keys = [self.path()]
      while self.peek().value == Symbol(44) {
        ignore(self.advance())
        keys.push(self.path())
      }
      self.symbol(41)
      operations.push(AssertUnique(keys))
    } else if self.has("EFFECT") {
      if cte_body {
        raise QueryAbort(
          "EFFECT is not allowed in a declaration body",
          self.peek().start,
        )
      }
      effect = Some(self.update_effect_clause())
    } else if self.has("INFER") {
      if cte_body {
        raise QueryAbort(
          "INFER is not allowed in a CTE body",
          self.peek().start,
        )
      }
      operations.push(Infer(self.infer_clause()))
    } else if self.has("NEAREST") {
      operations.push(Nearest(self.nearest_clause()))
    } else if self.has("KEEP") {
      raise QueryAbort(
        "KEEP requires an INFER or NEAREST operator",
        self.peek().start,
      )
    } else {
      raise QueryAbort("Unknown Pipe operation", self.peek().start)
    }
  }
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
    effect,
    work: self.work,
  }
}

///|
fn QueryParser::symbol(
  self : QueryParser,
  expected : Int,
) -> Unit raise QueryAbort {
  let token = self.advance()
  if token.value != Symbol(expected) {
    raise QueryAbort("Expected operator clause delimiter", token.start)
  }
}

///|
fn QueryParser::infer_clause(
  self : QueryParser,
) -> InferClause raise QueryAbort {
  self.keyword("INFER")
  let contract = self.name()
  self.keyword("ITEM")
  self.keyword("KEY")
  self.symbol(40)
  let keys : Array[Array[NamePart]] = []
  while true {
    self.node()
    keys.push(self.path())
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  self.symbol(41)
  self.keyword("INPUT")
  self.symbol(40)
  let inputs : Array[(NamePart, Expression)] = []
  if self.peek().value != Symbol(41) {
    while true {
      self.node()
      let name = self.name()
      self.symbol(61)
      inputs.push((name, self.expression()))
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
  }
  self.symbol(41)
  let keep = self.keep_clause()
  self.keyword("AS")
  { contract, keys, inputs, keep, name: self.name(), }
}

///|
fn QueryParser::keep_clause(
  self : QueryParser,
) -> Array[KeepItem] raise QueryAbort {
  let keep : Array[KeepItem] = []
  if self.has("KEEP") {
    self.keyword("KEEP")
    self.symbol(40)
    while true {
      self.node()
      let path : Array[NamePart] = []
      let mut wildcard = false
      if self.peek().value == Symbol(42) {
        ignore(self.advance())
        wildcard = true
      } else {
        path.push(self.name())
        while self.peek().value == Symbol(46) {
          ignore(self.advance())
          if self.peek().value == Symbol(42) {
            ignore(self.advance())
            wildcard = true
            break
          }
          path.push(self.name())
        }
      }
      let name = if self.has("AS") && !wildcard {
        self.keyword("AS")
        Some(self.name())
      } else {
        None
      }
      keep.push({ path, wildcard, name, })
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
    self.symbol(41)
  }
  keep
}

///|
fn QueryParser::nearest_keys(
  self : QueryParser,
) -> Array[Array[NamePart]] raise QueryAbort {
  self.keyword("KEY")
  self.symbol(40)
  let keys : Array[Array[NamePart]] = []
  while true {
    self.node()
    keys.push(self.path())
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  self.symbol(41)
  keys
}

///|
fn QueryParser::nearest_clause(
  self : QueryParser,
) -> NearestClause raise QueryAbort {
  self.keyword("NEAREST")
  let relation = self.resolve_cte(self.path())
  self.keyword("AS")
  let candidate_alias = self.name()
  self.keyword("QUERY")
  let query_keys = self.nearest_keys()
  self.keyword("VECTOR")
  let query_vector = self.expression()
  self.keyword("CANDIDATE")
  let candidate_keys = self.nearest_keys()
  self.keyword("VECTOR")
  let candidate_vector = self.expression()
  self.keyword("METRIC")
  let metric_start = self.peek().start
  let metric = self.name()
  if metric.quoted ||
    !["COSINE", "DOT", "L2"].contains(ascii_upper(metric.value)) {
    raise QueryAbort("NEAREST metric must be cosine, dot or l2", metric_start)
  }
  self.keyword("K")
  let k = self.safe_integer(false)
  let keep = self.keep_clause()
  self.keyword("AS")
  {
    relation,
    candidate_alias,
    query_keys,
    query_vector,
    candidate_keys,
    candidate_vector,
    metric: metric.value.to_lower(),
    k,
    keep,
    name: self.name(),
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
    cte_scopes: [],
  }
  try {
    let query = parser.query()
    parser.end()
    Ok({ ..query, work: parser.work, })
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
pub fn terminal_effect(query : Query) -> UpdateEffectClause? {
  query.effect.map(clause => { ..clause, set: clause.set.copy(), })
}

///|
// Preserve the parsed source and expression origins when a checked Model
// producer is retained before an Effect continuation. This is AST slicing,
// not reparsing text or constructing another execution language.
pub fn effect_result_continuation(
  query : Query,
  input : NamePart,
) -> (Query, Query)? {
  if query.effect is None ||
    !query.sets.is_empty() ||
    !query.final_operations.is_empty() {
    return None
  }
  let mut has_infer = false
  for index in 0..<query.operations.length() {
    match query.operations[index] {
      Infer(_) => has_infer = true
      RetainResult(_) if has_infer && index + 1 < query.operations.length() => {
        let prefix = {
          ..query,
          operations: Array::makei(index + 1, i => query.operations[i]),
          effect: None,
        }
        let tail = {
          ..query,
          relation: [input],
          source_alias: None,
          graph: None,
          joins: [],
          ctes: [],
          operations: Array::makei(query.operations.length() - index - 1, i => {
            query.operations[index + 1 + i]
          }),
        }
        return Some((prefix, tail))
      }
      _ => ()
    }
  }
  None
}

///|
fn QueryParser::join_bound(self : QueryParser) -> Int64? raise QueryAbort {
  if self.has("MAX_OUTPUT_ROWS") {
    self.keyword("MAX_OUTPUT_ROWS")
    Some(self.safe_integer(false))
  } else {
    None
  }
}

///|
fn QueryParser::update_effect_clause(
  self : QueryParser,
) -> UpdateEffectClause raise QueryAbort {
  self.keyword("EFFECT")
  let name = self.name()
  self.keyword("UPDATE")
  self.keyword("TARGET")
  let target = self.expression()
  let target = match
    expression_node(target, expression_root(target)).unwrap().kind {
    StringLiteral(value) => value
    _ =>
      raise QueryAbort(
        "Effect TARGET requires a string literal",
        self.peek().start,
      )
  }
  self.keyword("MAPPING")
  let mapping = self.name()
  self.keyword("FROM")
  self.keyword("RESULT")
  let result = self.name()
  self.keyword("ID")
  let id = self.name()
  self.keyword("SET")
  self.symbol(40)
  let assignments : Array[(NamePart, Expression)] = []
  while true {
    self.node()
    let field = self.name()
    self.symbol(61)
    assignments.push((field, self.expression()))
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  self.symbol(41)
  { name, target, mapping, result, id, set: assignments, }
}
