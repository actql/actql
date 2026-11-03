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
  except_columns : Array[NamePart]
  replacements : Array[StarReplacement]
}

///|
pub(all) struct StarReplacement {
  name : NamePart
  expression : Expression?
  aggregate : AggregateCall?
  analytic : AnalyticCall?
}

///|
pub(all) struct AggregateCall {
  function_name : String
  argument : Expression?
  filter : Expression?
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
  reference : (NamePart, Int)?
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
  SqlSelectAll
  PipeAggregate(Array[NamePart?], Array[NamePart])
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
  Unpivot(UnpivotClause)
  AssertUnique(Array[Array[NamePart]])
  Infer(InferClause)
  Serialize(SerializeClause)
  Nearest(NearestClause)
  RetainResult(NamePart)
  Where(Expression)
  Extend(Array[Projection])
  Set(Array[(NamePart, Expression)])
  Drop(Array[NamePart])
  Rename(Array[(NamePart, NamePart)])
  Alias(NamePart)
  Pivot(PivotClause)
  Group(Array[Expression], Array[Projection], GroupingScope)
  Having(Expression, Array[(NamePart, AggregateCall)])
  Qualify(Expression, Array[(NamePart, AggregateCall)])
  Analytic(Array[Projection])
  // Private window outputs are operands of SELECT expressions, not input aliases.
  AnalyticExpressions(Array[Projection], Array[NamePart])
  // ORDER windows either consume SELECT aliases or the current projected rows.
  OrderAnalytic(Array[Projection], Bool)
  Select(Array[Projection], Bool)
  Distinct
  Order(Array[SortTerm])
  Limit(QueryInteger, QueryInteger)
}

///|
pub(all) struct UnpivotClause {
  column_sets : Array[Array[NamePart]]
  row_labels : Array[UnpivotRowLabel?]
  value_columns : Array[NamePart]
  name_column : NamePart
  include_nulls : Bool
}

///|
pub(all) enum UnpivotRowLabel {
  TextLabel(String)
  IntegerLabel(String)
} derive(Eq, Debug)

///|
pub(all) struct KeepItem {
  path : Array[NamePart]
  wildcard : Bool
  name : NamePart?
}

///|
pub(all) struct PivotClause {
  function_name : String
  count_star : Bool
  argument : Array[NamePart]
  argument_expression : Expression?
  column : Array[NamePart]
  prefix : NamePart?
  values : Array[(String, NamePart?)]
}

///|
pub(all) enum UpdateEffectTarget {
  ConcreteTarget(String)
  LogicalTarget(Array[NamePart])
}

///|
// These are the existing canonical keyed record operations. The historical
// clause name retains its API lineage; it does not widen an installed grant.
pub(all) enum KeyedEffectKind {
  Update
  Upsert
  Delete
} derive(Eq, Debug)

///|
pub(all) struct UpdateEffectClause {
  kind : KeyedEffectKind
  name : NamePart?
  target : UpdateEffectTarget
  mapping : NamePart?
  result : NamePart?
  id : NamePart
  id_expression : Expression?
  set : Array[(NamePart, Expression)]
}

///|
/// Table writes consume the completed Relation once. A missing name denotes
/// an anonymous operation whose identity is fixed by ordinary Program lowering.
pub(all) struct TableEffectClause {
  name : NamePart?
  target : Array[NamePart]
  allow_replace : Bool
}

///|
pub(all) struct InferClause {
  contract : NamePart
  keys : Array[Array[NamePart]]?
  inputs : Array[(NamePart, Expression)]
  keep : Array[KeepItem]
  name : NamePart
  // Diagnostic custody only; never part of the lowered Program identity.
  origin : @origin.Origin?
}

///|
// Authored STORE is resolved against the installed write Mapping. It is not
// the canonical relation-store opcode or an inferred upload Command.
pub(all) struct StoreEffectClause {
  name : NamePart?
  target : Array[NamePart]
  set : Array[(NamePart, Expression)]
  start : Int
  end : Int
}

///|
pub(all) struct NearestRolePair {
  keys : Array[Array[NamePart]]
  vector : Expression
}

///|
pub(all) struct NearestClause {
  relation : Array[NamePart]
  candidate_alias : NamePart
  candidate_alias_explicit : Bool
  query_vector : Expression?
  query_roles : NearestRolePair?
  candidate_roles : NearestRolePair?
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
  inner_by_name : Bool
  sql_chain : Bool
  by_name_columns : Array[NamePart]?
  right : Query
}

///|
pub(all) struct JoinPart {
  kind : String
  relation : Array[NamePart]
  source_alias : NamePart?
  file_listing : FileListSelector?
  on : Expression?
  using_columns : Array[NamePart]
  pre_join_filter : Expression?
  max_output_rows : Int64?
}

///|
pub(all) enum QueryBindingOrigin {
  // Authored name and original UTF-8 byte range, before physical scope binding.
  AuthoredWith(NamePart, Int, Int)
  RelationalContinuation
} derive(Eq, Debug)

///|
pub(all) struct QueryBinding {
  name : NamePart
  query : Query
  origin : QueryBindingOrigin
  // Applies only to a relational continuation, never an authored WITH body.
  carry_ranges : Bool
}

///|
struct Query {
  source : Tokens
  primary : ProducerPrimary?
  implicit_source_alias : Bool
  // Parser-owned operand roles; generated names do not establish either role.
  positional_output : Bool
  bound_source : NamePart?
  bindings : Array[QueryBinding]
  relation : Array[NamePart]
  source_alias : NamePart?
  file_listing : FileListSelector?
  graph : GraphQuery?
  joins : Array[JoinPart]
  operations : Array[QueryOperation]
  sets : Array[SetPart]
  final_operations : Array[QueryOperation]
  effect : UpdateEffectClause?
  table_effect : TableEffectClause?
  store_effect : StoreEffectClause?
  insert_effect : InsertEffectClause?
  short_command_effect : ShortCommandEffectClause?
  commands : Array[CommandEffectClause]
  work : Int
}

///|
/// A single unqualified reference in this retained parsed Query, not a Source
/// grant or a semantic verdict. Nested expressions, CTEs, subqueries, unknown
/// shapes and producer primaries remain dependent. No names/values are read.
pub fn is_standalone_reference_projection(query : Query) -> Bool {
  guard standalone_projection_expression(query) is Some(expression) &&
    expression.nodes.length() == 1 &&
    expression.root == 0 else {
    return false
  }
  match expression.nodes[0].kind {
    Reference(parts) => parts.length() == 1
    _ => false
  }
}

///|
/// Shape evidence from the same parser-owned scalar AST, not a checked value
/// or execution grant. No relation, producer, CTE, command or column reference
/// may contribute to this projection. Caller parameters remain caller DATA.
pub fn is_source_free_scalar_projection(query : Query) -> Bool {
  guard standalone_projection_expression(query) is Some(expression) else {
    return false
  }
  for node in expression.nodes {
    match node.kind {
      Reference(_) => return false
      Null
      | Boolean(_)
      | Number(_)
      | StringLiteral(_)
      | JsonLiteral(_)
      | ParameterReference(_)
      | Property(_, _)
      | ArrayOffset(_, _, _)
      | Unary(_, _)
      | Binary(_, _, _)
      | Call(_, _)
      | ArrayConstructor(_, _)
      | StructConstructor(_)
      | Parenthesized(_)
      | Predicate(_, _)
      | SearchedCase(_, _)
      | Cast(_, _)
      | Interval(_, _) => ()
    }
  }
  true
}

///|
fn standalone_projection_expression(query : Query) -> Expression? {
  if query.primary is Some(_) ||
    query.bound_source is Some(_) ||
    !query.relation.is_empty() ||
    query.source_alias is Some(_) ||
    !query.bindings.is_empty() ||
    query.file_listing is Some(_) ||
    query.graph is Some(_) ||
    !query.joins.is_empty() ||
    !query.sets.is_empty() ||
    !query.final_operations.is_empty() ||
    query.effect is Some(_) ||
    query.table_effect is Some(_) ||
    query.store_effect is Some(_) ||
    query.insert_effect is Some(_) ||
    query.short_command_effect is Some(_) ||
    !query.commands.is_empty() ||
    query.operations.length() != 1 {
    return None
  }
  match query.operations[0] {
    Select(projections, _) => {
      guard projections.length() == 1 else { return None }
      let projection = projections[0]
      guard projection.expression is Some(expression) &&
        projection.aggregate is None &&
        projection.analytic is None &&
        projection.star is None &&
        projection.except_columns.is_empty() &&
        projection.replacements.is_empty() else {
        return None
      }
      Some(expression)
    }
    _ => None
  }
}

///|
pub fn query_binding_count(query : Query) -> Int {
  query.bindings.length()
}

///|
pub fn query_binding_at(query : Query, index : Int) -> QueryBinding? {
  query.bindings.get(index)
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
  query.sets
  .get(index)
  .map(part => {
    ..part,
    by_name_columns: part.by_name_columns.map(columns => columns.copy()),
  })
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
// This parser/lowerer-owned source is not an authored relation or range name.
pub fn bound_source(query : Query) -> NamePart? {
  query.bound_source
}

///|
pub fn positional_output(query : Query) -> Bool {
  query.positional_output
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
      Ok(query_head(first))
    }
  }
}

///|
fn query_head(first : Token) -> Bool {
  sql_head(first) ||
  keyword(first, "FROM") ||
  keyword(first, "TIME_SERIES") ||
  keyword(first, "CALENDAR_SERIES") ||
  first.value == Symbol(40)
}

///|
fn sql_head(first : Token) -> Bool {
  keyword(first, "SELECT") || keyword(first, "WITH") || keyword(first, "CREATE")
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
        return Ok(sql_head(first))
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
        QuotedName(value) =>
          parts.push({ value: tokens.identifier(value), quoted: true, })
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
    Unpivot(clause) =>
      Some(
        Unpivot({
          ..clause,
          column_sets: clause.column_sets.map(columns => columns.copy()),
          row_labels: clause.row_labels.copy(),
          value_columns: clause.value_columns.copy(),
        }),
      )
    GraphCall(call) => Some(GraphCall(copy_sga_call(call)))
    AssertUnique(keys) => Some(AssertUnique(keys.map(path => path.copy())))
    Nearest(clause) =>
      Some(
        Nearest({
          ..clause,
          relation: clause.relation.copy(),
          query_roles: clause.query_roles.map(roles => {
            ..roles,
            keys: roles.keys.map(path => path.copy()),
          }),
          candidate_roles: clause.candidate_roles.map(roles => {
            ..roles,
            keys: roles.keys.map(path => path.copy()),
          }),
          keep: clause.keep.map(item => { ..item, path: item.path.copy(), }),
        }),
      )
    Infer(clause) =>
      Some(
        Infer({
          ..clause,
          keys: clause.keys.map(keys => keys.map(path => path.copy())),
          inputs: clause.inputs.copy(),
          keep: clause.keep.map(item => { ..item, path: item.path.copy(), }),
        }),
      )
    Serialize(clause) =>
      Some(
        Serialize({
          ..clause,
          order_by: clause.order_by.copy(),
          options: clause.options.copy(),
        }),
      )
    Where(e) => Some(Where(e))
    Extend(xs) => Some(Extend(copy_projections(xs)))
    Set(xs) => Some(Set(xs.copy()))
    Drop(xs) => Some(Drop(xs.copy()))
    Rename(xs) => Some(Rename(xs.copy()))
    Alias(name) => Some(Alias(name))
    Pivot(clause) =>
      Some(
        Pivot({
          ..clause,
          argument: clause.argument.copy(),
          column: clause.column.copy(),
          values: clause.values.copy(),
        }),
      )
    RetainResult(name) => Some(RetainResult(name))
    Group(keys, projections, scope) =>
      Some(
        Group(
          keys.copy(),
          copy_projections(projections),
          match scope {
            SqlSelect => SqlSelect
            SqlSelectAll => SqlSelectAll
            PipeAggregate(names, embedded) =>
              PipeAggregate(names.copy(), embedded.copy())
          },
        ),
      )
    Having(e, calls) =>
      Some(
        Having(
          e,
          calls.map(pair => {
            (pair.0, { ..pair.1, order_by: pair.1.order_by.copy(), })
          }),
        ),
      )
    Analytic(projections) => Some(Analytic(copy_projections(projections)))
    AnalyticExpressions(projections, names) =>
      Some(AnalyticExpressions(copy_projections(projections), names.copy()))
    OrderAnalytic(projections, selected_scope) =>
      Some(OrderAnalytic(copy_projections(projections), selected_scope))
    Qualify(e, calls) =>
      Some(
        Qualify(
          e,
          calls.map(pair => {
            (pair.0, { ..pair.1, order_by: pair.1.order_by.copy(), })
          }),
        ),
      )
    Select(xs, distinct) => Some(Select(copy_projections(xs), distinct))
    Distinct => Some(Distinct)
    Order(xs) => Some(Order(xs.copy()))
    Limit(count, offset) => Some(Limit(count, offset))
  }
}

///|
fn copy_aggregate_call(call : AggregateCall) -> AggregateCall {
  { ..call, order_by: call.order_by.copy(), }
}

///|
fn copy_analytic_call(call : AnalyticCall) -> AnalyticCall {
  {
    ..call,
    aggregate: call.aggregate.map(copy_aggregate_call),
    window: {
      ..call.window,
      partition_by: call.window.partition_by.copy(),
      order_by: call.window.order_by.copy(),
    },
  }
}

///|
fn copy_projections(projections : Array[Projection]) -> Array[Projection] {
  projections.map(projection => {
    ..projection,
    aggregate: projection.aggregate.map(copy_aggregate_call),
    analytic: projection.analytic.map(copy_analytic_call),
    except_columns: projection.except_columns.copy(),
    replacements: projection.replacements.map(replacement => {
      ..replacement,
      aggregate: replacement.aggregate.map(copy_aggregate_call),
      analytic: replacement.analytic.map(copy_analytic_call),
    }),
  })
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
  binding_scopes : Array[Array[(NamePart, NamePart)]]
}

///|
priv struct PipeAggregateOrder {
  position : Int
  direction : String
  nulls : String
  start : Int
  end : Int
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
fn same_binding_name(left : NamePart, right : NamePart) -> Bool {
  ascii_upper(left.value) == ascii_upper(right.value)
}

///|
fn QueryParser::resolve_producer(
  self : QueryParser,
  relation : Array[NamePart],
) -> Array[NamePart] raise QueryAbort {
  if relation.length() != 1 {
    return relation
  }
  let mut scope = self.binding_scopes.length() - 1
  while scope >= 0 {
    let bindings = self.binding_scopes[scope]
    let mut index = bindings.length() - 1
    while index >= 0 {
      self.spend(1)
      let (authored, producer) = bindings[index]
      if same_binding_name(relation[0], authored) {
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
    QuotedName(value) => { value: self.source.identifier(value), quoted: true, }
    _ => raise QueryAbort("Expected identifier", token.start)
  }
}

///|
fn QueryParser::set_column_list(
  self : QueryParser,
  keyword? : String = "ON",
) -> Array[NamePart]? raise QueryAbort {
  if !self.has(keyword) {
    return None
  }
  self.keyword(keyword)
  let modifier = if keyword == "BY" { "CORRESPONDING BY" } else { "BY NAME ON" }
  if self.advance().value != Symbol(40) {
    raise QueryAbort(
      "Expected " + modifier + " opening parenthesis",
      self.peek().start,
    )
  }
  let columns : Array[NamePart] = []
  while true {
    self.node()
    columns.push(self.name())
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  if self.advance().value != Symbol(41) {
    raise QueryAbort(
      "Expected " + modifier + " closing parenthesis",
      self.peek().start,
    )
  }
  Some(columns)
}

///|
fn QueryParser::set_name_matching(
  self : QueryParser,
  inner_prefix : Bool,
) -> (Bool, Bool, Array[NamePart]?) raise QueryAbort {
  if self.has("STRICT") {
    if inner_prefix {
      raise QueryAbort(
        "INNER set cannot use STRICT CORRESPONDING",
        self.peek().start,
      )
    }
    self.keyword("STRICT")
    self.keyword("CORRESPONDING")
    return (true, false, self.set_column_list(keyword="BY"))
  }
  if self.has("CORRESPONDING") {
    self.keyword("CORRESPONDING")
    return (true, true, self.set_column_list(keyword="BY"))
  }
  if self.has("BY") {
    self.keyword("BY")
    self.keyword("NAME")
    return (true, inner_prefix, self.set_column_list())
  }
  if inner_prefix {
    raise QueryAbort(
      "INNER set requires BY NAME or CORRESPONDING",
      self.peek().start,
    )
  }
  (false, false, None)
}

///|
fn same_set_column_list(
  left : Array[NamePart]?,
  right : Array[NamePart]?,
) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(left), Some(right)) =>
      left.length() == right.length() &&
      left
      .mapi((index, name) => same_binding_name(name, right[index]))
      .all(value => value)
    _ => false
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
fn QueryParser::expression(
  self : QueryParser,
  stop_before_star? : Bool = false,
) -> Expression raise QueryAbort {
  let remaining = self.limits.max_work - self.work
  let expression_limits = {
    ..self.limits.expression,
    max_nodes: self.limits.expression.max_nodes - self.expression_nodes,
    max_work: self.limits.expression.max_work.min(remaining),
  }
  match
    parse_fragment(
      self.source,
      self.index,
      expression_limits,
      stop_before_star~,
    ) {
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
fn QueryParser::aggregate_expression(
  self : QueryParser,
  prefix : String,
  stop_before_star? : Bool = false,
) -> (Expression, Array[(NamePart, AggregateCall)]) raise QueryAbort {
  let calls : Array[(NamePart, AggregateCall)] = []
  let serial = [self.synthetic_sources]
  let syntax_nodes = [0]
  let limits = {
    ..self.limits.expression,
    max_nodes: self.limits.expression.max_nodes - self.expression_nodes,
    max_work: self.limits.expression.max_work.min(
      self.limits.max_work - self.work,
    ),
  }
  let primary = fn(
    index : Int,
    limits : ExpressionLimits,
  ) -> Result[(NamePart, Int, Int, Int)?, Diagnostic] {
    let parser : QueryParser = {
      source: self.source,
      limits: {
        ..self.limits,
        expression: limits,
        max_work: limits.max_work,
        max_syntax_nodes: self.limits.max_syntax_nodes -
        self.syntax_nodes -
        syntax_nodes[0],
      },
      index,
      work: 0,
      expression_nodes: 0,
      syntax_nodes: 0,
      source_depth: 0,
      synthetic_sources: serial[0],
      binding_scopes: [],
    }
    if !parser.aggregate_head() {
      return Ok(None)
    }
    try {
      let call = parser.aggregate()
      let name = parser.fresh_producer(prefix)
      serial[0] = parser.synthetic_sources
      syntax_nodes[0] += parser.syntax_nodes
      calls.push((name, call))
      Ok(Some((name, parser.index, parser.work, parser.expression_nodes)))
    } catch {
      QueryExpression(error) => Err(error)
      QueryAbort(message, at) =>
        Err({
          issue: Syntax(message),
          span: Some(
            @origin.span(@origin.range(self.source.document, at, at).unwrap()),
          ),
        })
    }
  }
  match
    parse_fragment_resolved(
      self.source,
      self.index,
      limits,
      Some(primary),
      stop_before_star~,
    ) {
    Ok((expression, next, embedded_nodes)) => {
      self.spend(expression.work)
      self.expression_nodes += expression.nodes.length() + embedded_nodes
      self.syntax_nodes += syntax_nodes[0]
      self.index = next
      self.synthetic_sources = serial[0]
      (expression, calls)
    }
    Err(error) => raise QueryExpression(error)
  }
}

///|
fn QueryParser::source_name(
  self : QueryParser,
) -> (Array[NamePart], NamePart?, Bool) raise QueryAbort {
  let relation = self.path()
  let resolved = self.resolve_producer(relation)
  let explicit_alias = self.optional_source_alias()
  let source_alias = if explicit_alias is None &&
    resolved[0].value != relation[0].value {
    Some(relation[0])
  } else {
    explicit_alias
  }
  (resolved, source_alias, explicit_alias is None && source_alias is Some(_))
}

///|
fn QueryParser::optional_source_alias(
  self : QueryParser,
) -> NamePart? raise QueryAbort {
  if self.has("AS") {
    self.keyword("AS")
    Some(self.binding_name())
  } else if self.peek().value is QuotedName(_) {
    Some(self.name())
  } else if self.peek().value is Word(value) &&
    ![
      "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "WHERE", "GROUP", "HAVING",
      "ORDER", "LIMIT", "UNION", "INTERSECT", "EXCEPT", "ON", "USING", "MAX_OUTPUT_ROWS",
      "QUALIFY", "WINDOW", "PIVOT", "UNPIVOT",
    ].contains(value.to_upper()) {
    Some(self.binding_name())
  } else {
    None
  }
}

///|
fn QueryParser::query_source(
  self : QueryParser,
) -> (Array[NamePart], NamePart?, Array[QueryBinding], Bool, FileListSelector?) raise QueryAbort {
  if self.has("LIST_FILES") {
    return self.file_listing_source()
  }
  if self.peek().value != Symbol(40) {
    let (relation, source_alias, implicit_source_alias) = self.source_name()
    let (relation, source_alias, bindings, implicit_source_alias) = self.from_postfix_source(
      relation,
      source_alias,
      [],
      implicit_source_alias~,
    )
    return (relation, source_alias, bindings, implicit_source_alias, None)
  }
  let inner = self.parenthesized()
  let source_alias = self.optional_source_alias()
  if source_alias is Some(result_range) && query_output_carries_ranges(inner) {
    // Apply the existing AS rules to the actual output kind before retaining
    // it. A value-table receiver is a value, not an ordinary whole-row object.
    let bound = self.bind_query(
      { ..inner, operations: inner.operations + [Alias(result_range)], },
      carry_ranges=true,
    )
    let (relation, source_alias, bindings, implicit_source_alias) = self.from_postfix_source(
      bound.relation,
      None,
      bound.bindings,
    )
    return (relation, source_alias, bindings, implicit_source_alias, None)
  }
  // An explicit alias creates one projected range. Without it, preserve the
  // inner query's current names/ranges through the existing continuation scope.
  let carry_ranges = source_alias is None && query_output_carries_ranges(inner)
  let bound = self.bind_query(inner, carry_ranges~)
  let (relation, source_alias, bindings, implicit_source_alias) = self.from_postfix_source(
    bound.relation,
    source_alias,
    bound.bindings,
  )
  (relation, source_alias, bindings, implicit_source_alias, None)
}

///|
fn QueryParser::bind_query(
  self : QueryParser,
  inner : Query,
  carry_ranges? : Bool = false,
) -> Query raise QueryAbort {
  self.node()
  let generated = self.fresh_producer("aql_query_source_")
  let bindings = inner.bindings +
    [
      {
        name: generated,
        query: { ..inner, bindings: [], },
        origin: RelationalContinuation,
        carry_ranges,
      },
    ]
  if bindings.length() > self.limits.max_cte_count {
    raise QueryAbort("CTE count limit", self.peek().start)
  }
  {
    source: self.source,
    primary: None,
    implicit_source_alias: false,
    positional_output: false,
    bound_source: Some(generated),
    bindings,
    relation: [generated],
    source_alias: None,
    file_listing: None,
    graph: None,
    joins: [],
    operations: [],
    sets: [],
    final_operations: [],
    effect: None,
    table_effect: None,
    store_effect: None,
    insert_effect: None,
    short_command_effect: None,
    commands: [],
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
            ascii_upper(
              if token.value is QuotedName(_) {
                self.source.identifier(value)
              } else {
                value
              },
            ) ==
            ascii_upper(generated_name)
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
  let inner = self.query(context=PureQuery)
  self.source_depth -= 1
  if self.advance().value != Symbol(41) {
    raise QueryAbort("Expected query closing parenthesis", self.peek().start)
  }
  inner
}

///|
fn QueryParser::mark_positional_output(
  self : QueryParser,
  query : Query,
) -> Query raise QueryAbort {
  let bindings = query.bindings.copy()
  // Only an internal identity binding exports the same operand values.
  // Authored CTEs and transformed continuations retain their own scopes.
  if query.operations.is_empty() && query.bound_source is Some(bound) {
    for index in 0..<bindings.length() {
      self.spend(1)
      if same_binding_name(bindings[index].name, bound) {
        bindings[index] = {
          ..bindings[index],
          query: self.mark_positional_output(bindings[index].query),
        }
      }
    }
  }
  { ..query, bindings, positional_output: true, }
}

///|
fn QueryParser::sql_operand(
  self : QueryParser,
  positional_output? : Bool = false,
  set_operand? : Bool = false,
) -> Query raise QueryAbort {
  if self.peek().value == Symbol(40) {
    let inner = self.parenthesized()
    let carry_ranges = !set_operand &&
      !self.has("UNION") &&
      !self.has("INTERSECT") &&
      !self.has("EXCEPT") &&
      !self.starts_inner_set() &&
      query_output_carries_ranges(inner)
    self.bind_query(
      if positional_output {
        self.mark_positional_output(inner)
      } else {
        inner
      },
      carry_ranges~,
    )
  } else {
    self.sql_term()
  }
}

///|
fn QueryParser::join_part(
  self : QueryParser,
) -> (JoinPart, Array[QueryBinding]) raise QueryAbort {
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
  } else if self.has("RIGHT") {
    self.keyword("RIGHT")
    if self.has("OUTER") {
      self.keyword("OUTER")
    }
    "right"
  } else if self.has("CROSS") {
    self.keyword("CROSS")
    "cross"
  } else {
    "inner"
  }
  self.keyword("JOIN")
  let (relation, source_alias, bindings, _, file_listing) = self.query_source()
  if kind == "cross" {
    return (
      {
        kind,
        relation,
        source_alias,
        file_listing,
        on: None,
        using_columns: [],
        pre_join_filter: None,
        max_output_rows: self.join_bound(),
      },
      bindings,
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
        file_listing,
        on: Some(self.expression()),
        using_columns: [],
        pre_join_filter: None,
        max_output_rows: self.join_bound(),
      },
      bindings,
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
      file_listing,
      on: None,
      using_columns,
      pre_join_filter: None,
      max_output_rows: self.join_bound(),
    },
    bindings,
  )
}

///|
fn QueryParser::starts_join(self : QueryParser) -> Bool {
  pipe_join_head(self.peek()) && !self.starts_inner_set()
}

///|
fn set_operator_token(token : Token) -> Bool {
  keyword(token, "UNION") ||
  keyword(token, "INTERSECT") ||
  keyword(token, "EXCEPT")
}

///|
fn QueryParser::starts_inner_set(self : QueryParser) -> Bool {
  self.has("INNER") &&
  set_operator_token(token_at(self.source, self.index + 1).unwrap())
}

///|
fn pipe_join_head(token : Token) -> Bool {
  keyword(token, "JOIN") ||
  keyword(token, "INNER") ||
  keyword(token, "LEFT") ||
  keyword(token, "RIGHT") ||
  keyword(token, "FULL") ||
  keyword(token, "CROSS")
}

///|
// An omitted AS still introduces an explicit output alias. Reserve the pinned
// GoogleSQL keyword set here so a clause or unsupported reserved form cannot
// disappear into a column name. Backticks retain the ordinary quoted-name role.
fn QueryParser::optional_output_alias(
  self : QueryParser,
) -> NamePart? raise QueryAbort {
  if self.has("AS") {
    self.keyword("AS")
    return Some(self.binding_name())
  }
  match self.peek().value {
    QuotedName(_) => Some(self.name())
    Word(value) if !query_reserved_word(value) => Some(self.name())
    _ => None
  }
}

///|
// A receiver star and an unqualified star share EXCEPT/REPLACE parsing. The
// expression parser leaves the authored dot-star suffix for this query owner.
fn QueryParser::star_projection(
  self : QueryParser,
  receiver : Expression?,
  embedded : Array[(NamePart, AggregateCall)],
  aggregate_expressions : Bool,
  windows : Array[Projection],
  window_expressions : Bool,
) -> Projection raise QueryAbort {
  ignore(self.advance())
  let except_columns : Array[NamePart] = []
  if self.has("EXCEPT") {
    self.keyword("EXCEPT")
    let open = self.advance()
    if open.value != Symbol(40) {
      raise QueryAbort("Expected EXCEPT opening parenthesis", open.start)
    }
    while true {
      self.node()
      except_columns.push(self.name())
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
    let close = self.advance()
    if close.value != Symbol(41) {
      raise QueryAbort("Expected EXCEPT closing parenthesis", close.start)
    }
  }
  let replacements : Array[StarReplacement] = []
  if self.has("REPLACE") {
    self.keyword("REPLACE")
    self.symbol(40)
    while true {
      self.node()
      let value = self.value_projection(
        embedded,
        aggregate_expressions~,
        windows~,
        window_expressions~,
        require_alias=true,
      )
      replacements.push({
        name: value.name.unwrap(),
        expression: value.expression,
        aggregate: value.aggregate,
        analytic: value.analytic,
      })
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
    self.symbol(41)
  }
  {
    expression: receiver,
    aggregate: None,
    analytic: None,
    name: None,
    star: Some("*"),
    except_columns,
    replacements,
  }
}

///|
fn QueryParser::projections(
  self : QueryParser,
  aggregate_expressions? : Bool = false,
  ordering? : Array[PipeAggregateOrder]? = None,
  windows? : Array[Projection] = [],
  window_expressions? : Bool = false,
) -> (Array[Projection], Array[(NamePart, AggregateCall)]) raise QueryAbort {
  let values : Array[Projection] = []
  let embedded : Array[(NamePart, AggregateCall)] = []
  while true {
    self.node()
    let start = self.peek().start
    let receiver = self.range_star_receiver()
    let projection = if self.peek().value == Symbol(42) {
      self.star_projection(
        receiver, embedded, aggregate_expressions, windows, window_expressions,
      )
    } else {
      let value = self.value_projection(
        embedded,
        aggregate_expressions~,
        windows~,
        window_expressions~,
        stop_before_star=true,
      )
      if self.peek().value == Symbol(46) &&
        self.source.tokens[self.index + 1].value == Symbol(42) {
        guard value.expression is Some(expression) &&
          value.name is None &&
          value.aggregate is None &&
          value.analytic is None else {
          raise QueryAbort(
            "Star receiver requires a scalar expression",
            self.peek().start,
          )
        }
        ignore(self.advance())
        self.star_projection(
          Some(expression),
          embedded,
          aggregate_expressions,
          windows,
          window_expressions,
        )
      } else {
        value
      }
    }
    values.push(projection)
    if ordering is Some(terms) && (self.has("ASC") || self.has("DESC")) {
      let (direction, nulls) = self.order_suffix()
      terms.push({
        position: values.length(),
        direction,
        nulls,
        start,
        end: token_at(self.source, self.index - 1).unwrap().end,
      })
    }
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  (values, embedded)
}

///|
// Scalar, aggregate and analytic replacement values use the same parsed
// projection tree as ordinary SELECT, including its original input scope.
fn QueryParser::value_projection(
  self : QueryParser,
  embedded : Array[(NamePart, AggregateCall)],
  aggregate_expressions? : Bool = false,
  require_alias? : Bool = false,
  windows? : Array[Projection] = [],
  window_expressions? : Bool = false,
  stop_before_star? : Bool = false,
) -> Projection raise QueryAbort {
  let mut embedded_analytic : AnalyticCall? = None
  let (expression, aggregate) = if window_expressions {
    let serial = self.synthetic_sources
    let (expression, extracted, calls) = self.window_expression(
      "aql_select_window_",
      aggregate_prefix=Some("aql_select_aggregate_"),
      stop_before_star~,
    )
    let mut root = expression.root
    while expression.nodes[root].kind is Parenthesized(child) {
      root = child
    }
    if extracted.length() == 1 &&
      expression.nodes[root].kind is Reference(path) &&
      path == [extracted[0].name.unwrap()] {
      if !aggregate_expressions && !calls.is_empty() {
        raise QueryAbort(
          "Pipe SELECT requires scalar or window expressions",
          self.peek().start,
        )
      }
      if calls.is_empty() {
        self.synthetic_sources = serial
      }
      embedded.append(calls)
      embedded_analytic = extracted[0].analytic
      (None, None)
    } else if calls.length() == 1 &&
      extracted.is_empty() &&
      expression.nodes[root].kind is Reference(path) &&
      path == [calls[0].0] {
      self.synthetic_sources = serial
      (None, Some(calls[0].1))
    } else {
      if !aggregate_expressions && !calls.is_empty() {
        raise QueryAbort(
          "Pipe SELECT requires scalar or window expressions",
          self.peek().start,
        )
      }
      windows.append(extracted)
      embedded.append(calls)
      (Some(expression), None)
    }
  } else if aggregate_expressions {
    let serial = self.synthetic_sources
    let (expression, calls) = self.aggregate_expression(
      "aql_select_aggregate_",
      stop_before_star~,
    )
    let mut root = expression.root
    while expression.nodes[root].kind is Parenthesized(child) {
      root = child
    }
    if calls.length() == 1 &&
      expression.nodes[root].kind is Reference(path) &&
      path == [calls[0].0] {
      // A whole aggregate keeps its existing projection and producer IDs.
      // Only calls embedded in a scalar tree need private output slots.
      self.synthetic_sources = serial
      (None, Some(calls[0].1))
    } else {
      if !calls.is_empty() && self.has("OVER") {
        raise QueryAbort("OVER requires one analytic call", self.peek().start)
      }
      embedded.append(calls)
      (Some(expression), None)
    }
  } else if self.aggregate_head() {
    (None, Some(self.aggregate()))
  } else {
    (Some(self.expression(stop_before_star~)), None)
  }
  let analytic = if embedded_analytic is Some(_) {
    embedded_analytic
  } else if self.has("OVER") {
    Some({ expression, aggregate, window: self.over(), })
  } else {
    None
  }
  let name = if require_alias {
    self.keyword("AS")
    Some(self.binding_name())
  } else {
    self.optional_output_alias()
  }
  // Anonymous SELECT values retain no authored alias. Their eventual
  // output support and ordinal alignment belong to Program lowering.
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
    except_columns: [],
    replacements: [],
  }
}

///|
// Keep the star receiver as an ordinary source Reference tree. Quotation and
// location stay attached to its names; no source text is printed or reparsed.
fn QueryParser::range_star_receiver(
  self : QueryParser,
) -> Expression? raise QueryAbort {
  let mut scan = self.index
  while true {
    self.spend(1)
    match self.source.tokens[scan].value {
      Word(value) if ["NULL", "TRUE", "FALSE"].contains(ascii_upper(value)) =>
        return None
      Word(_) | QuotedName(_) => ()
      _ => return None
    }
    if self.source.tokens[scan + 1].value != Symbol(46) {
      return None
    }
    if self.source.tokens[scan + 2].value == Symbol(42) {
      break
    }
    scan += 2
  }
  let start = self.peek().start
  if self.expression_nodes >= self.limits.expression.max_nodes ||
    self.limits.expression.max_depth < 1 {
    raise QueryAbort("Expression node limit", start)
  }
  self.expression_nodes += 1
  let names = []
  let mut end = start
  while true {
    names.push(self.name())
    end = self.source.tokens[self.index - 1].end
    ignore(self.advance()) // The already inspected dot.
    if self.peek().value == Symbol(42) {
      break
    }
  }
  Some({
    source: self.source,
    nodes: [{ kind: Reference(names), start, end, }],
    root: 0,
    work: 1,
  })
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
  // Keep the integer/whole-Parameter role after bounded transparent wrappers.
  // Boundary direction remains authored syntax, including zero distances.
  let distance = self.limit_integer(true)
  let preceding = if self.has("PRECEDING") {
    self.keyword("PRECEDING")
    true
  } else {
    self.keyword("FOLLOWING")
    false
  }
  match (distance, preceding) {
    (Integer(value), true) => Preceding(value)
    (Integer(value), false) => Following(value)
    (BoundParameter(name), true) => PrecedingParameter(name)
    (BoundParameter(name), false) => FollowingParameter(name)
  }
}

///|
fn QueryParser::over(
  self : QueryParser,
  calls? : Array[(NamePart, AggregateCall)]? = None,
  aggregate_prefix? : String = "aql_window_aggregate_",
) -> AnalyticWindow raise QueryAbort {
  self.keyword("OVER")
  self.window_specification(calls~, aggregate_prefix~)
}

///|
fn query_aggregate_function_name(name : String) -> Bool {
  [
    "COUNT", "COUNTIF", "SUM", "AVG", "MIN", "MAX", "ARRAY_AGG", "STRING_AGG", "VAR_POP",
    "VAR_SAMP", "VARIANCE", "STDDEV_POP", "STDDEV_SAMP", "STDDEV",
  ].contains(upper_ascii(name))
}

///|
fn QueryParser::aggregate_head(self : QueryParser) -> Bool {
  match self.peek().value {
    Word(name) | QuotedName(name) =>
      query_aggregate_function_name(
        if self.peek().value is QuotedName(_) {
          self.source.identifier(name)
        } else {
          name
        },
      ) &&
      self.source.tokens.get(self.index + 1).map(token => token.value) ==
      Some(Symbol(40))
    _ => false
  }
}

///|
fn QueryParser::aggregate(
  self : QueryParser,
  calls? : Array[(NamePart, AggregateCall)]? = None,
  aggregate_prefix? : String = "aql_select_aggregate_",
) -> AggregateCall raise QueryAbort {
  let token = self.advance()
  let function_name = match token.value {
    Word(name) => upper_ascii(name)
    QuotedName(name) => upper_ascii(self.source.identifier(name))
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
    Some(
      match calls {
        Some(outputs) => {
          let (expression, embedded) = self.aggregate_expression(
            aggregate_prefix,
          )
          outputs.append(embedded)
          expression
        }
        None => self.expression()
      },
    )
  }
  let delimiter = if function_name == "STRING_AGG" {
    if self.peek().value == Symbol(44) {
      ignore(self.advance())
      guard self.peek().value is Text(_) || self.peek().value == Symbol(40) else {
        raise QueryAbort("STRING_AGG delimiter must be literal", token.start)
      }
      // Literal chunks and their grouping use the ordinary expression parser's
      // decoding, separation, origins and budgets. Computed delimiters remain
      // outside this profile; the common aggregate receives one String value.
      let expression = self.expression()
      let mut root = expression_root(expression)
      while expression_node(expression, root).unwrap().kind
            is Parenthesized(child) {
        root = child
      }
      match expression_node(expression, root).unwrap().kind {
        StringLiteral(value) => Some(value)
        _ =>
          raise QueryAbort("STRING_AGG delimiter must be literal", token.start)
      }
    } else {
      Some(",")
    }
  } else {
    None
  }
  if function_name == "ARRAY_AGG" {
    self.keyword("IGNORE")
    self.keyword("NULLS")
  }
  let filter = if self.has("WHERE") {
    self.keyword("WHERE")
    Some(self.expression())
  } else {
    None
  }
  let order_by = if function_name == "ARRAY_AGG" ||
    function_name == "STRING_AGG" {
    // Window aggregates take their ordering from OVER. Ordinary collection
    // aggregates retain the existing explicit input-order profile.
    if self.peek().value == Symbol(41) &&
      token_at(self.source, self.index + 1)
      .map(token => keyword(token, "OVER"))
      .unwrap_or(false) {
      []
    } else {
      self.keyword("ORDER")
      self.keyword("BY")
      self.order()
    }
  } else {
    []
  }
  if self.advance().value != Symbol(41) {
    raise QueryAbort("Expected aggregate closing parenthesis", token.start)
  }
  if argument is None && function_name != "COUNT" {
    raise QueryAbort("Aggregate argument required", token.start)
  }
  { function_name, argument, filter, distinct, order_by, delimiter, }
}

///|
fn QueryParser::group_keys(
  self : QueryParser,
  names? : Array[NamePart?]? = None,
  ordering? : Array[PipeAggregateOrder]? = None,
) -> Array[Expression] raise QueryAbort {
  self.keyword("GROUP")
  let order_all = ordering is Some(_) && self.has("AND")
  if order_all {
    self.keyword("AND")
    self.keyword("ORDER")
  }
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
    let start = self.peek().start
    keys.push(self.expression())
    if names is Some(names) {
      names.push(self.optional_output_alias())
    }
    if ordering is Some(terms) &&
      (order_all || self.has("ASC") || self.has("DESC") || self.has("NULLS")) {
      let (direction, nulls) = self.order_suffix()
      terms.push({
        position: keys.length(),
        direction,
        nulls,
        start,
        end: token_at(self.source, self.index - 1).unwrap().end,
      })
    }
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  keys
}

///|
fn QueryParser::order_suffix(
  self : QueryParser,
) -> (String, String) raise QueryAbort {
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
  (direction, nulls)
}

///|
// Shorthand sorts use the evaluated AGGREGATE output positions. They never
// expand an input expression after its grouping alias has replaced that name.
fn QueryParser::aggregate_order_term(
  self : QueryParser,
  item : PipeAggregateOrder,
  offset : Int,
) -> SortTerm raise QueryAbort {
  self.node()
  self.spend(1)
  if self.expression_nodes >= self.limits.expression.max_nodes {
    raise QueryAbort("Expression node limit", item.start)
  }
  self.expression_nodes += 1
  {
    expression: {
      source: self.source,
      nodes: [
        {
          kind: Number((item.position + offset).to_string()),
          start: item.start,
          end: item.end,
        },
      ],
      root: 0,
      work: 1,
    },
    direction: item.direction,
    nulls: item.nulls,
  }
}

///|
fn QueryParser::order(
  self : QueryParser,
  calls? : Array[(NamePart, AggregateCall)]? = None,
  windows? : Array[Projection]? = None,
  aggregate_prefix? : String = "aql_order_aggregate_",
) -> Array[SortTerm] raise QueryAbort {
  let terms : Array[SortTerm] = []
  while true {
    self.node()
    let expression = if windows is Some(outputs) {
      let (expression, embedded_windows, embedded_calls) = self.window_expression(
        "aql_order_window_",
        aggregate_prefix=Some("aql_order_aggregate_"),
      )
      for projection in embedded_windows {
        if projection.analytic.unwrap().window.reference is Some((_, at)) {
          raise QueryAbort("Named window is not allowed in ORDER BY", at)
        }
      }
      outputs.append(embedded_windows)
      match calls {
        Some(calls) => calls.append(embedded_calls)
        None if !embedded_calls.is_empty() =>
          raise QueryAbort(
            "Aggregate ORDER BY requires a SELECT query scope",
            self.peek().start,
          )
        _ => ()
      }
      expression
    } else {
      match calls {
        Some(calls) => {
          let (expression, embedded) = self.aggregate_expression(
            aggregate_prefix,
          )
          calls.append(embedded)
          expression
        }
        None => self.expression()
      }
    }
    let (direction, nulls) = self.order_suffix()
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
  self.safe_integer_text(text, token.start, zero_allowed)
}

///|
fn QueryParser::safe_integer_text(
  self : QueryParser,
  text : String,
  start : Int,
  zero_allowed : Bool,
) -> Int64 raise QueryAbort {
  for _ in 0..<text.length() {
    self.spend(1)
  }
  guard exact_integer_literal(text) is Some(result) else {
    raise QueryAbort("Integer literal exceeds safe range", start)
  }
  if !zero_allowed && result == 0L {
    raise QueryAbort("Expected positive integer literal", start)
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
  if self.peek().value == Symbol(40) || self.peek().value == Symbol(43) {
    // Grouping and numeric unary plus preserve an integer or Parameter slot.
    // Use the bounded expression parser, never evaluate constant calls,
    // arithmetic or row references in the Frontend.
    let expression = self.expression()
    let mut root = expression_root(expression)
    while true {
      match expression_node(expression, root).unwrap().kind {
        Parenthesized(child) | Unary("+", child) => root = child
        _ => break
      }
    }
    let node = expression_node(expression, root).unwrap()
    match node.kind {
      Number(text) =>
        Integer(self.safe_integer_text(text, node.start, zero_allowed))
      ParameterReference(name) => BoundParameter(name)
      _ => raise QueryAbort("Expected integer literal or parameter", node.start)
    }
  } else if self.peek().value is Parameter(name) {
    ignore(self.advance())
    BoundParameter(self.source.identifier(name))
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
  let element = self.binding_name()
  let offset = if self.has("WITH") {
    self.keyword("WITH")
    self.keyword("OFFSET")
    let name = if self.has("AS") {
      self.keyword("AS")
      self.binding_name()
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
// Correlation expands the current row; it is not an independent JOIN input.
// Fixed lookahead keeps quoted names out of the operator dispatch.
fn QueryParser::starts_correlated_unnest(
  self : QueryParser,
  lookahead_offset? : Int = 0,
) -> Bool {
  let index = self.index + lookahead_offset
  if index < self.source.tokens.length() &&
    keyword(self.source.tokens[index], "JOIN") {
    index + 1 < self.source.tokens.length() &&
    keyword(self.source.tokens[index + 1], "UNNEST")
  } else {
    index + 2 < self.source.tokens.length() &&
    (
      keyword(self.source.tokens[index], "CROSS") ||
      keyword(self.source.tokens[index], "INNER")
    ) &&
    keyword(self.source.tokens[index + 1], "JOIN") &&
    keyword(self.source.tokens[index + 2], "UNNEST")
  }
}

///|
fn QueryParser::correlated_unnest(
  self : QueryParser,
  operations : Array[QueryOperation],
) -> Unit raise QueryAbort {
  let cross = self.has("CROSS")
  if cross {
    self.keyword("CROSS")
  } else if self.has("INNER") {
    self.keyword("INNER")
  }
  self.keyword("JOIN")
  operations.push(self.unnest_source())
  if !cross && self.has("ON") {
    self.keyword("ON")
    self.node()
    // INNER correlation filters expanded pairs. Keeping the predicate at
    // this point preserves NULL/duplicate rows and the current range scope.
    operations.push(Where(self.expression()))
  }
}

///|
// Read only the initial FROM source and its attached JOINs. SQL owns its later
// clauses; FROM-headed queries pass this same state to the explicit Pipe tail.
fn QueryParser::initial_from(
  self : QueryParser,
  allow_graph_marker? : Bool = false,
) -> (
  Array[NamePart],
  NamePart?,
  Array[QueryBinding],
  Bool,
  FileListSelector?,
  GraphQuery?,
  Array[JoinPart],
  Array[QueryOperation],
) raise QueryAbort {
  self.keyword("FROM")
  let mut graph : GraphQuery? = None
  let operations : Array[QueryOperation] = []
  let (
    initial_relation,
    initial_alias,
    initial_ctes,
    initial_implicit_alias,
    initial_file_listing,
  ) = if allow_graph_marker && self.has("GRAPH") {
    self.keyword("GRAPH")
    let start = self.peek().start
    let relation = self.resolve_producer(self.path())
    let end = self.source.tokens[self.index - 1].end
    if self.has("LABELS") {
      raise QueryAbort("Graph LABELS annotation is retired", self.peek().start)
    }
    // Preserve authored row aliases for Carrier-specific static checking,
    // just as marker-free FROM does. The marker grants no row scope.
    let source_alias = self.optional_source_alias()
    graph = Some({
      pattern: None,
      expectation: Some(
        @origin.range(self.source.document, start, end).unwrap(),
      ),
    })
    (relation, source_alias, [], false, None)
  } else if self.has("UNNEST") {
    operations.push(self.unnest_source())
    ([], None, [], false, None)
  } else {
    self.query_source()
  }
  let mut relation = initial_relation
  let mut source_alias = initial_alias
  let mut implicit_source_alias = initial_implicit_alias
  let mut bindings = initial_ctes
  let mut file_listing = initial_file_listing
  let joins : Array[JoinPart] = []
  while (!relation.is_empty() || !operations.is_empty()) && self.starts_join() {
    if self.starts_correlated_unnest() {
      self.correlated_unnest(operations)
      continue
    }
    if operations.any(operation => operation is UnnestSource(_, _, _)) {
      // Bind the already expanded row, including its immutable ranges, before
      // the next ordinary JOIN. Do not reorder expansion behind the JOIN or
      // publish the private continuation as an authored subquery projection.
      let expanded = self.bind_query(
        {
          source: self.source,
          primary: None,
          implicit_source_alias,
          positional_output: false,
          bound_source: None,
          relation,
          source_alias,
          bindings,
          file_listing,
          graph,
          joins: joins.copy(),
          operations: operations.copy(),
          sets: [],
          final_operations: [],
          effect: None,
          table_effect: None,
          store_effect: None,
          insert_effect: None,
          short_command_effect: None,
          commands: [],
          work: self.work,
        },
        carry_ranges=true,
      )
      relation = expanded.relation
      source_alias = expanded.source_alias
      implicit_source_alias = expanded.implicit_source_alias
      bindings = expanded.bindings
      file_listing = expanded.file_listing
      graph = expanded.graph
      joins.clear()
      operations.clear()
    }
    let (part, join_ctes) = self.join_part()
    joins.push(part)
    for cte in join_ctes {
      bindings.push(cte)
    }
  }

  (
    relation, source_alias, bindings, implicit_source_alias, file_listing, graph,
    joins, operations,
  )
}

///|
fn QueryParser::sql_term(self : QueryParser) -> Query raise QueryAbort {
  self.keyword("SELECT")
  let distinct = self.has("DISTINCT")
  if distinct {
    self.keyword("DISTINCT")
  } else if self.has("ALL") {
    self.keyword("ALL")
  }
  let select_windows : Array[Projection] = []
  let (projections, embedded) = self.projections(
    aggregate_expressions=true,
    windows=select_windows,
    window_expressions=true,
  )
  let group_projections = projections +
    embedded.map(pair => {
      expression: None,
      aggregate: Some(pair.1),
      analytic: None,
      name: Some(pair.0),
      star: None,
      except_columns: [],
      replacements: [],
    })
  let (
    relation,
    source_alias,
    bindings,
    implicit_source_alias,
    file_listing,
    _,
    joins,
    operations,
  ) = if self.has("FROM") {
    self.initial_from()
  } else {
    ([], None, [], false, None, None, [], [])
  }

  if self.has("WHERE") {
    self.keyword("WHERE")
    self.node()
    operations.push(Where(self.expression()))
  }
  let grouped = self.has("GROUP") ||
    projections.any(projection => {
      projection.aggregate is Some(_) ||
      projection.replacements.any(value => value.aggregate is Some(_))
    }) ||
    !embedded.is_empty()
  if self.has("GROUP") {
    if self.source.tokens
      .get(self.index + 2)
      .map(token => keyword(token, "ALL"))
      .unwrap_or(false) {
      self.keyword("GROUP")
      self.keyword("BY")
      self.keyword("ALL")
      operations.push(Group([], group_projections, SqlSelectAll))
    } else {
      operations.push(Group(self.group_keys(), group_projections, SqlSelect))
    }
  } else if grouped {
    operations.push(Group([], group_projections, SqlSelect))
  }
  let mut pending_having : Int? = None
  if self.has("HAVING") {
    self.keyword("HAVING")
    let (predicate, calls) = self.aggregate_expression("aql_having_aggregate_")
    if !grouped {
      if calls.is_empty() {
        // A used WINDOW declaration can introduce aggregation later in SQL.
        pending_having = Some(self.peek().start)
      } else {
        operations.push(Group([], group_projections, SqlSelect))
      }
    }
    operations.push(Having(predicate, calls))
  }
  let selected_windows = !select_windows.is_empty() ||
    projections.any(projection => {
      projection.analytic is Some(_) ||
      projection.replacements.any(value => value.analytic is Some(_))
    })
  let qualifier = if self.has("QUALIFY") {
    self.keyword("QUALIFY")
    self.node()
    let (predicate, windows, calls) = self.qualify_expression()
    if !selected_windows && windows.is_empty() {
      raise QueryAbort("QUALIFY requires a window function", self.peek().start)
    }
    if !calls.is_empty() &&
      !operations.any(operation => operation is Group(_, _, _)) {
      operations.push(Group([], group_projections, SqlSelect))
    }
    Some((predicate, windows, calls))
  } else {
    None
  }
  let declared_aggregates : Array[(NamePart, AggregateCall)] = []
  let window_definitions = if self.has("WINDOW") {
    self.window_definitions(declared_aggregates)
  } else {
    []
  }
  let windows = qualifier.map(value => value.1).unwrap_or([])
  if selected_windows || !windows.is_empty() {
    let all = projections + select_windows + windows
    operations.push(
      if select_windows.is_empty() {
        Analytic(all)
      } else {
        AnalyticExpressions(
          all,
          select_windows.map(projection => projection.name.unwrap()),
        )
      },
    )
  }
  if qualifier is Some((predicate, _, calls)) {
    operations.push(Qualify(predicate, calls))
  }
  operations.push(Select(projections, distinct))
  let resolved = self.resolve_window_operations(operations, window_definitions)
  let window_aggregates = self.used_named_window_aggregates(
    resolved, declared_aggregates,
  )
  let resolved = if window_aggregates.is_empty() {
    resolved
  } else {
    let aggregate_projections = window_aggregates.map(pair => {
      expression: None,
      aggregate: Some(pair.1),
      analytic: None,
      name: Some(pair.0),
      star: None,
      except_columns: [],
      replacements: [],
    })
    let grouped = resolved.any(operation => operation is Group(_, _, _))
    let result : Array[QueryOperation] = []
    let mut inserted = grouped
    for operation in resolved {
      self.spend(1)
      if !inserted &&
        (
          operation is Having(_, _) ||
          operation is Analytic(_) ||
          operation is AnalyticExpressions(_, _) ||
          operation is Qualify(_, _) ||
          operation is Select(_, _)
        ) {
        result.push(
          Group([], group_projections + aggregate_projections, SqlSelect),
        )
        inserted = true
      }
      result.push(
        match operation {
          Group(keys, fields, scope) =>
            Group(keys, fields + aggregate_projections, scope)
          _ => operation
        },
      )
    }
    result
  }
  if pending_having is Some(at) &&
    !resolved.any(operation => operation is Group(_, _, _)) {
    raise QueryAbort("HAVING requires grouping", at)
  }
  {
    source: self.source,
    primary: None,
    implicit_source_alias,
    positional_output: false,
    bound_source: None,
    bindings,
    relation,
    source_alias,
    file_listing,
    graph: None,
    joins,
    operations: resolved,
    sets: [],
    final_operations: [],
    effect: None,
    table_effect: None,
    store_effect: None,
    insert_effect: None,
    short_command_effect: None,
    commands: [],
    work: self.work,
  }
}

///|
fn QueryParser::query(
  self : QueryParser,
  context? : QueryContext = StatementQuery,
) -> Query raise QueryAbort {
  if self.has("CREATE") {
    if context != StatementQuery {
      raise QueryAbort(
        "Table write is not allowed in a declaration body",
        self.peek().start,
      )
    }
    let clause = self.table_create_clause(None)
    self.keyword("AS")
    // Only a whole outer pair is Compute. Other grouped primaries remain Pure
    // and keep their following set, ORDER/LIMIT or Pipe continuation.
    let parentheses = self.ctas_whole_wrapper()
    if parentheses {
      if self.source_depth >= 32 {
        raise QueryAbort("Subquery depth limit", self.peek().start)
      }
      self.node()
      self.source_depth += 1
      self.symbol(40)
    }
    if self.has("CREATE") {
      raise QueryAbort(
        "CTAS input cannot contain another terminal write",
        self.peek().start,
      )
    }
    let body = self.query(context=ComputeQuery)
    if parentheses {
      self.symbol(41)
      self.source_depth -= 1
    }
    if body.effect is Some(_) ||
      body.table_effect is Some(_) ||
      body.store_effect is Some(_) ||
      body.insert_effect is Some(_) ||
      body.short_command_effect is Some(_) {
      raise QueryAbort(
        "CTAS input cannot contain another terminal write",
        self.peek().start,
      )
    }
    return { ..body, table_effect: Some(clause), work: self.work, }
  }
  let bindings : Array[QueryBinding] = []
  let scope : Array[(NamePart, NamePart)] = []
  let nested_scope = !self.binding_scopes.is_empty()
  self.binding_scopes.push(scope)
  if self.has("WITH") {
    self.keyword("WITH")
    if self.has("RECURSIVE") {
      raise QueryAbort("Recursive CTE is unsupported", self.peek().start)
    }
    while true {
      self.node()
      if bindings.length() >= self.limits.max_cte_count {
        raise QueryAbort("CTE count limit", self.peek().start)
      }
      let binding_start = self.peek().start
      let name = self.binding_name()
      if scope.any(binding => same_binding_name(binding.0, name)) {
        raise QueryAbort("Duplicate CTE name", self.peek().start)
      }
      self.keyword("AS")
      let body = self.parenthesized()
      let binding_end = self.source.tokens[self.index - 1].end
      for nested in body.bindings {
        if bindings.length() >= self.limits.max_cte_count {
          raise QueryAbort("CTE count limit", self.peek().start)
        }
        bindings.push(nested)
      }
      if bindings.length() >= self.limits.max_cte_count {
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
      bindings.push({
        name: producer,
        query: { ..body, bindings: [], },
        origin: AuthoredWith(name, binding_start, binding_end),
        carry_ranges: false,
      })
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
  }
  let term = if self.has("FROM") {
    self.pipe(context~)
  } else if self.has("GRAPH") {
    self.producer_query(GraphValue(self.graph()))
  } else if self.has("MEAN_GRAPHS") {
    self.producer_query(GraphGenerator(self.sga_call()))
  } else if self.has("TIME_SERIES") || self.has("CALENDAR_SERIES") {
    self.producer_query(RelationGenerator(self.sga_call()))
  } else {
    self.sql()
  }
  let term = if self.peek().value == Pipe {
    self.pipe_tail(term, context~)
  } else {
    term
  }
  let all_ctes = bindings + term.bindings
  if all_ctes.length() > self.limits.max_cte_count {
    raise QueryAbort("CTE count limit", self.peek().start)
  }
  ignore(self.binding_scopes.pop())
  { ..term, bindings: all_ctes, work: self.work, }
}

///|
fn QueryParser::sql(self : QueryParser) -> Query raise QueryAbort {
  let mut term = self.sql_operand()
  let bindings = term.bindings.copy()
  let sets : Array[SetPart] = []
  let mut set_spelling : (String, String, Bool, Bool, Array[NamePart]?)? = None
  while self.has("UNION") ||
        self.has("INTERSECT") ||
        self.has("EXCEPT") ||
        self.has("INNER") {
    self.node()
    let inner_by_name = if self.has("INNER") {
      self.keyword("INNER")
      true
    } else {
      false
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
    let (by_name, inner_by_name, columns) = self.set_name_matching(
      inner_by_name,
    )
    let mut by_name_columns = columns
    match set_spelling {
      Some((old_kind, old_duplicates, old_by_name, old_inner, old_columns)) => {
        if old_kind != kind ||
          old_duplicates != duplicates ||
          old_by_name != by_name ||
          old_inner != inner_by_name ||
          !same_set_column_list(old_columns, by_name_columns) {
          raise QueryAbort(
            "Mixed set operators require parentheses",
            self.peek().start,
          )
        }
        // One SQL set chain uses its first modifier's display spelling.
        by_name_columns = old_columns
      }
      None =>
        set_spelling = Some(
          (kind, duplicates, by_name, inner_by_name, by_name_columns),
        )
    }
    let right = self.sql_operand(positional_output=!by_name, set_operand=true)
    for cte in right.bindings {
      bindings.push(cte)
    }
    sets.push({
      kind,
      duplicates,
      by_name,
      inner_by_name,
      sql_chain: true,
      by_name_columns,
      right: { ..right, bindings: [], },
    })
  }
  let tail : Array[QueryOperation] = []
  let order_calls : Array[(NamePart, AggregateCall)] = []
  let order_windows : Array[Projection] = []
  let order_start = self.peek().start
  if self.has("ORDER") {
    self.keyword("ORDER")
    self.keyword("BY")
    let terms = self.order(calls=Some(order_calls), windows=Some(order_windows))
    if !order_windows.is_empty() && !sets.is_empty() {
      tail.push(OrderAnalytic(order_windows, false))
    }
    tail.push(Order(terms))
  }
  if self.has("LIMIT") {
    self.node()
    tail.push(self.limit())
  }
  if !order_calls.is_empty() {
    // ORDER belongs to this SELECT, not to an inner producer or a set's
    // already projected output. Keep calls in the existing Group plan.
    if !sets.is_empty() ||
      !term.operations.any(operation => operation is Select(_, _)) {
      raise QueryAbort(
        "Aggregate ORDER BY requires a SELECT query scope", order_start,
      )
    }
    let hidden = order_calls.map(pair => {
      expression: None,
      aggregate: Some(pair.1),
      analytic: None,
      name: Some(pair.0),
      star: None,
      except_columns: [],
      replacements: [],
    })
    let operations : Array[QueryOperation] = []
    let mut grouped = false
    let selected = term.operations.filter_map(operation => {
        match operation {
          Select(projections, _) => Some(projections)
          _ => None
        }
      })[0]
    for operation in term.operations {
      match operation {
        Group(keys, projections, scope) if scope == SqlSelect ||
          scope == SqlSelectAll => {
          operations.push(Group(keys, projections + hidden, scope))
          grouped = true
        }
        Analytic(_) | AnalyticExpressions(_, _) | Select(_, _) if !grouped => {
          operations.push(Group([], selected + hidden, SqlSelect))
          operations.push(operation)
          grouped = true
        }
        _ => operations.push(operation)
      }
    }
    term = { ..term, operations, }
  }
  if sets.is_empty() && !order_windows.is_empty() {
    if term.operations.any(operation => operation is Select(_, true)) {
      raise QueryAbort(
        "Analytic ORDER BY is not allowed after SELECT DISTINCT", order_start,
      )
    }
    let operations : Array[QueryOperation] = []
    let mut inserted = false
    for operation in term.operations {
      if !inserted && (operation is Qualify(_, _) || operation is Select(_, _)) {
        operations.push(OrderAnalytic(order_windows, true))
        inserted = true
      }
      operations.push(operation)
    }
    term = { ..term, operations, }
  }
  if sets.is_empty() {
    { ..term, operations: term.operations + tail, work: self.work, }
  } else {
    { ..term, bindings, sets, final_operations: tail, work: self.work, }
  }
}

///|
fn QueryParser::pipe(
  self : QueryParser,
  context? : QueryContext = StatementQuery,
) -> Query raise QueryAbort {
  let (
    relation,
    source_alias,
    bindings,
    implicit_source_alias,
    file_listing,
    graph,
    joins,
    operations,
  ) = self.initial_from(allow_graph_marker=true)
  self.pipe_tail(
    {
      source: self.source,
      primary: None,
      implicit_source_alias,
      positional_output: false,
      bound_source: None,
      bindings,
      relation,
      source_alias,
      file_listing,
      graph,
      joins,
      operations,
      sets: [],
      final_operations: [],
      effect: None,
      table_effect: None,
      store_effect: None,
      insert_effect: None,
      short_command_effect: None,
      commands: [],
      work: self.work,
    },
    context~,
  )
}

///|
// Standard SELECT and FROM-starting Pipe use the same scope and operators.
fn QueryParser::pipe_tail(
  self : QueryParser,
  input : Query,
  context? : QueryContext = StatementQuery,
) -> Query raise QueryAbort {
  let relation = input.relation
  let source_alias = input.source_alias
  let file_listing = input.file_listing
  let bindings = input.bindings.copy()
  let mut graph = input.graph
  let joins = input.joins.copy()
  let operations = input.operations.copy()
  let sets = input.sets.copy()
  let final_operations = input.final_operations.copy()
  let mut effect = input.effect
  let mut table_effect = input.table_effect
  let mut store_effect = input.store_effect
  let mut insert_effect = input.insert_effect
  let mut short_command_effect = input.short_command_effect
  let commands = input.commands.copy()
  while self.peek().value == Pipe {
    if effect is Some(_) ||
      table_effect is Some(_) ||
      store_effect is Some(_) ||
      insert_effect is Some(_) ||
      short_command_effect is Some(_) {
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
        primary: input.primary,
        implicit_source_alias: input.implicit_source_alias,
        positional_output: input.positional_output,
        bound_source: input.bound_source,
        bindings,
        relation,
        source_alias,
        file_listing,
        graph,
        joins,
        operations,
        sets,
        final_operations,
        effect: None,
        table_effect: None,
        store_effect: None,
        insert_effect: None,
        short_command_effect: None,
        commands: [],
        work: self.work,
      }
      return self.pipe_tail(self.bind_query(producer), context~)
    }
    // A typed Carrier call consumes the current relational prefix. Reuse the
    // checked producer continuation rather than sending a later GraphCall to
    // the ordinary Relation lowerer or discarding that prefix's operations.
    if carrier_call_head(next) &&
      (
        !joins.is_empty() ||
        operations.any(operation => !(operation is GraphCall(_)))
      ) {
      let producer : Query = {
        source: self.source,
        primary: input.primary,
        implicit_source_alias: input.implicit_source_alias,
        positional_output: input.positional_output,
        bound_source: input.bound_source,
        bindings,
        relation,
        source_alias,
        file_listing,
        graph,
        joins,
        operations,
        sets,
        final_operations,
        effect: None,
        table_effect: None,
        store_effect: None,
        insert_effect: None,
        short_command_effect: None,
        commands: [],
        work: self.work,
      }
      self.spend(operations.length())
      return self.pipe_tail(
        self.bind_query(producer, carry_ranges=pipe_join_range_input(producer)),
        context~,
      )
    }
    if pipe_join_head(next) &&
      !self.starts_correlated_unnest(lookahead_offset=1) &&
      !(keyword(next, "INNER") &&
      set_operator_token(token_at(self.source, self.index + 2).unwrap())) &&
      !operations.is_empty() &&
      !(operations.length() == 1 && operations[0] is Where(_)) {
      let producer : Query = {
        source: self.source,
        primary: input.primary,
        implicit_source_alias: input.implicit_source_alias,
        positional_output: input.positional_output,
        bound_source: input.bound_source,
        bindings,
        relation,
        source_alias,
        file_listing,
        graph,
        joins,
        operations,
        sets,
        final_operations,
        effect: None,
        table_effect: None,
        store_effect: None,
        insert_effect: None,
        short_command_effect: None,
        commands: [],
        work: self.work,
      }
      self.spend(operations.length())
      if pipe_join_input_alias(producer) is Some(current_range) {
        // A terminal AS affects only the following JOIN's range. Move that
        // binding out of the producer so it does not force an identity SELECT.
        let body_operations = operations.copy()
        while body_operations.last() is Some(Alias(_)) {
          ignore(body_operations.pop())
        }
        let bound = self.bind_query({ ..producer, operations: body_operations, })
        return self.pipe_tail(
          { ..bound, source_alias: current_range, },
          context~,
        )
      } else if pipe_join_range_input(producer) {
        // Continue the same logical row with its immutable ranges. An
        // authored CTE/subquery still exports only its projected columns.
        return self.pipe_tail(
          self.bind_query(producer, carry_ranges=true),
          context~,
        )
      }
    }
    ignore(self.advance())
    self.node()
    if self.has("TIME_SERIES") || self.has("CALENDAR_SERIES") {
      raise QueryAbort(
        "Relation generator cannot consume an input",
        self.peek().start,
      )
    } else if sga_call_head(self.peek()) {
      if graph is Some(current) && current.pattern is Some(_) {
        raise QueryAbort(
          "SGA call requires a Graph input before MATCH",
          self.peek().start,
        )
      }
      operations.push(GraphCall(self.sga_call(current_alias=source_alias)))
    } else if self.has("MATCH") {
      match graph {
        Some(current) if current.pattern is None => {
          let pattern = self.graph_match()
          // The resolved Graph owns label membership, independently of
          // ordinary property values and optional FROM GRAPH spelling.
          graph = Some({ ..current, pattern: Some(pattern), })
        }
        Some(_) =>
          raise QueryAbort(
            "GRAPH_PATTERN_UNSUPPORTED_SHAPE: a second MATCH needs a separate Graph input",
            self.peek().start,
          )
        None =>
          graph = Some({ pattern: Some(self.graph_match()), expectation: None, })
      }
    } else if self.has("UNION") ||
      self.has("INTERSECT") ||
      self.has("EXCEPT") ||
      self.starts_inner_set() {
      if !final_operations.is_empty() {
        raise QueryAbort(
          "Set input cannot follow final ordering",
          self.peek().start,
        )
      }
      let inner_by_name = if self.has("INNER") {
        self.keyword("INNER")
        true
      } else {
        false
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
      let (by_name, inner_by_name, by_name_columns) = self.set_name_matching(
        inner_by_name,
      )
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
      let parsed = self.query(context=PureQuery)
      self.source_depth -= 1
      let right = if !parsed.sets.is_empty() {
        self.bind_query(
          if !by_name {
            self.mark_positional_output(parsed)
          } else {
            parsed
          },
        )
      } else {
        parsed
      }
      for cte in right.bindings {
        bindings.push(cte)
      }
      if self.advance().value != Symbol(41) {
        raise QueryAbort(
          "Expected Pipe set closing parenthesis",
          self.peek().start,
        )
      }
      sets.push({
        kind,
        duplicates,
        by_name,
        inner_by_name,
        sql_chain: false,
        by_name_columns,
        right: { ..right, bindings: [], },
      })
    } else if self.starts_correlated_unnest() {
      if !sets.is_empty() {
        raise QueryAbort(
          "Correlated UNNEST after Pipe set is not supported",
          self.peek().start,
        )
      }
      self.correlated_unnest(operations)
    } else if self.starts_join() {
      if !sets.is_empty() || operations.length() > 1 {
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
        bindings.push(cte)
      }
    } else if self.has("WHERE") {
      self.keyword("WHERE")
      let (predicate, windows, calls) = self.window_expression(
        "aql_pipe_where_window_",
      )
      if !calls.is_empty() {
        raise QueryAbort(
          "Pipe WHERE cannot introduce ordinary aggregation",
          self.peek().start,
        )
      }
      if !windows.is_empty() {
        operations.append(
          self.resolve_window_operations(
            [AnalyticExpressions(windows, windows.map(p => p.name.unwrap()))],
            [],
          ),
        )
      }
      operations.push(Where(predicate))
    } else if self.has("EXTEND") {
      self.keyword("EXTEND")
      let windows : Array[Projection] = []
      let (values, _) = self.projections(windows~, window_expressions=true)
      if values.any(p => {
          p.name is None ||
          (p.expression is None && p.analytic is None) ||
          p.star is Some(_)
        }) {
        raise QueryAbort(
          "EXTEND requires named scalar or window expressions",
          self.peek().start,
        )
      }
      let calls : Array[(NamePart, AggregateCall)] = []
      let definitions = if self.has("WINDOW") {
        self.window_definitions(calls)
      } else {
        []
      }
      if !calls.is_empty() {
        raise QueryAbort(
          "Pipe EXTEND cannot introduce ordinary aggregation",
          self.peek().start,
        )
      }
      let window_operations : Array[QueryOperation] = []
      if values.any(p => p.analytic is Some(_)) || !windows.is_empty() {
        window_operations.push(
          if windows.is_empty() {
            Analytic(values)
          } else {
            AnalyticExpressions(
              values + windows,
              windows.map(p => p.name.unwrap()),
            )
          },
        )
      }
      window_operations.push(Extend(values))
      // WINDOW names belong only to this EXTEND, not to a subsequent operator.
      operations.append(
        self.resolve_window_operations(window_operations, definitions),
      )
    } else if self.has("UNPIVOT") {
      operations.push(Unpivot(self.unpivot_clause()))
      if self.has("AS") {
        self.keyword("AS")
        operations.push(Alias(self.binding_name()))
      } else if self.peek().value is Word(_) ||
        self.peek().value is QuotedName(_) {
        operations.push(Alias(self.binding_name()))
      }
    } else if self.has("SET") {
      self.keyword("SET")
      let values : Array[(NamePart, Expression)] = []
      let windows : Array[Projection] = []
      while true {
        self.node()
        let name = self.name()
        if self.advance().value != Symbol(61) {
          raise QueryAbort("SET requires an equals sign", self.peek().start)
        }
        let (expression, extracted, calls) = self.window_expression(
          "aql_pipe_set_window_",
        )
        if !calls.is_empty() {
          raise QueryAbort(
            "Pipe SET cannot introduce ordinary aggregation",
            self.peek().start,
          )
        }
        windows.append(extracted)
        values.push((name, expression))
        if self.peek().value != Symbol(44) {
          break
        }
        ignore(self.advance())
      }
      if !windows.is_empty() {
        operations.append(
          self.resolve_window_operations(
            [AnalyticExpressions(windows, windows.map(p => p.name.unwrap()))],
            [],
          ),
        )
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
    } else if self.has("PIVOT") {
      operations.push(Pivot(self.pivot_clause()))
      if self.optional_output_alias() is Some(result_range) {
        operations.push(Alias(result_range))
      }
    } else if self.has("AS") {
      self.keyword("AS")
      operations.push(Alias(self.binding_name()))
    } else if self.has("AGGREGATE") {
      self.keyword("AGGREGATE")
      let aggregate_order : Array[PipeAggregateOrder] = []
      let (aggregates, embedded) = if self.has("GROUP") {
        ([], [])
      } else {
        self.projections(
          aggregate_expressions=true,
          ordering=Some(aggregate_order),
        )
      }
      if aggregates.any(projection => {
          if projection.name is None ||
            projection.analytic is Some(_) ||
            projection.star is Some(_) {
            return true
          }
          if projection.aggregate is Some(_) {
            return false
          }
          guard projection.expression is Some(expression) else { return true }
          !expression.nodes.any(node => {
            node.kind is Reference(path) &&
            embedded.any(pair => path == [pair.0])
          })
        }) {
        raise QueryAbort(
          "AGGREGATE requires named expressions containing aggregate calls",
          self.peek().start,
        )
      }
      let names : Array[NamePart?] = []
      let group_order : Array[PipeAggregateOrder] = []
      let keys = if self.has("GROUP") {
        self.group_keys(names=Some(names), ordering=Some(group_order))
      } else {
        []
      }
      let calls = embedded.map(pair => {
        expression: None,
        aggregate: Some(pair.1),
        analytic: None,
        name: Some(pair.0),
        star: None,
        except_columns: [],
        replacements: [],
      })
      operations.push(
        Group(
          keys,
          aggregates + calls,
          PipeAggregate(names, embedded.map(pair => pair.0)),
        ),
      )
      if !group_order.is_empty() || !aggregate_order.is_empty() {
        let terms : Array[SortTerm] = []
        for item in group_order {
          terms.push(self.aggregate_order_term(item, 0))
        }
        for item in aggregate_order {
          terms.push(self.aggregate_order_term(item, keys.length()))
        }
        operations.push(Order(terms))
      }
    } else if self.has("DISTINCT") {
      self.keyword("DISTINCT")
      operations.push(Distinct)
    } else if self.has("SELECT") {
      self.keyword("SELECT")
      let distinct = self.has("DISTINCT")
      if distinct {
        self.keyword("DISTINCT")
      } else if self.has("ALL") {
        self.keyword("ALL")
      }
      let windows : Array[Projection] = []
      let (projections, _) = self.projections(windows~, window_expressions=true)
      let calls : Array[(NamePart, AggregateCall)] = []
      let definitions = if self.has("WINDOW") {
        self.window_definitions(calls)
      } else {
        []
      }
      let window_operations : Array[QueryOperation] = []
      if projections.any(projection => {
          projection.analytic is Some(_) ||
          projection.replacements.any(value => value.analytic is Some(_))
        }) ||
        !windows.is_empty() {
        window_operations.push(
          if windows.is_empty() {
            Analytic(projections)
          } else {
            AnalyticExpressions(
              projections + windows,
              windows.map(projection => projection.name.unwrap()),
            )
          },
        )
      }
      window_operations.push(Select(projections, distinct))
      let resolved = self.resolve_window_operations(
        window_operations, definitions,
      )
      if !self.used_named_window_aggregates(resolved, calls).is_empty() {
        raise QueryAbort(
          "Pipe SELECT cannot introduce ordinary aggregation",
          self.peek().start,
        )
      }
      // WINDOW names are consumed here, before the next Pipe operator.
      operations.append(resolved)
    } else if self.has("ORDER") {
      self.keyword("ORDER")
      self.keyword("BY")
      let windows : Array[Projection] = []
      let operation = Order(self.order(windows=Some(windows)))
      let destination = if sets.is_empty() {
        operations
      } else {
        final_operations
      }
      if !windows.is_empty() {
        destination.push(OrderAnalytic(windows, false))
      }
      destination.push(operation)
    } else if self.has("LIMIT") {
      let operation = self.limit()
      if sets.is_empty() {
        operations.push(operation)
      } else {
        final_operations.push(operation)
      }
    } else if self.has("RESULT") {
      if context == PureQuery {
        raise QueryAbort(
          "RESULT is not allowed in a producer body",
          self.peek().start,
        )
      }
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
      if context != StatementQuery {
        raise QueryAbort(
          "EFFECT is not allowed in a declaration body",
          self.peek().start,
        )
      }
      if token_at(self.source, self.index + 2)
        .map(token => keyword(token, "CREATE"))
        .unwrap_or(false) &&
        !token_at(self.source, self.index + 3)
        .map(token => token.value == Symbol(46))
        .unwrap_or(false) {
        self.keyword("EFFECT")
        let name = self.name()
        table_effect = Some(self.table_create_clause(Some(name)))
      } else if self.effect_is_short_command() {
        short_command_effect = Some(self.short_command_effect_clause())
      } else if self.effect_is_insert() {
        insert_effect = Some(self.insert_effect_clause())
      } else if self.effect_is_store() {
        store_effect = Some(self.store_effect_clause())
      } else {
        effect = Some(self.update_effect_clause())
      }
    } else if self.has("CREATE") {
      if context != StatementQuery {
        raise QueryAbort(
          "Table write is not allowed in a declaration body",
          self.peek().start,
        )
      }
      table_effect = Some(self.table_create_clause(None))
    } else if self.has("INFER") {
      if context == PureQuery {
        raise QueryAbort(
          "INFER is not allowed in a CTE body",
          self.peek().start,
        )
      }
      operations.push(Infer(self.infer_clause()))
    } else if self.has("SERIALIZE") {
      operations.push(Serialize(self.serialize_clause()))
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
  if bindings.length() > self.limits.max_cte_count {
    raise QueryAbort("CTE count limit", self.peek().start)
  }
  {
    source: self.source,
    primary: input.primary,
    implicit_source_alias: input.implicit_source_alias,
    positional_output: input.positional_output,
    bound_source: input.bound_source,
    bindings,
    relation,
    source_alias,
    file_listing,
    graph,
    joins,
    operations,
    sets,
    final_operations,
    effect,
    table_effect,
    store_effect,
    insert_effect,
    short_command_effect,
    commands,
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
  let origin = token_origin(self.source, self.index)
  self.keyword("INFER")
  let contract = self.name()
  let keys = if self.has("ITEM") {
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
    Some(keys)
  } else {
    None
  }
  self.keyword("INPUT")
  self.symbol(40)
  let inputs : Array[(NamePart, Expression)] = []
  if self.peek().value != Symbol(41) {
    while true {
      self.node()
      if token_at(self.source, self.index + 1)
        .map(token => token.value == Symbol(61))
        .unwrap_or(false) {
        // The left side is a closed ModelTask schema key, not a binding.
        let name = self.name()
        self.symbol(61)
        inputs.push((name, self.expression()))
      } else {
        let token = self.peek()
        if token.value is Word(value) && query_reserved_word(value) {
          raise QueryAbort(
            "Reserved identifier requires backticks",
            token.start,
          )
        }
        // Parse the original reference so its UTF-8 origin and expression
        // limits are the same as an authored assignment's right side.
        let expression = self.expression()
        guard expression_node(expression, expression_root(expression)).unwrap().kind
          is Reference([name]) else {
          raise QueryAbort(
            "INFER INPUT shorthand requires one identifier; use name = expression",
            token.start,
          )
        }
        inputs.push((name, expression))
      }
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
  }
  self.symbol(41)
  // The text default is exactly the existing wildcard projection. The machine
  // infer body and stored Programs retain their independent output contract.
  let keep = if self.has("KEEP") {
    self.keep_clause()
  } else {
    [{ path: [], wildcard: true, name: None, }]
  }
  self.keyword("AS")
  { contract, keys, inputs, keep, name: self.name(), origin, }
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
  let relation = self.resolve_producer(self.path())
  let candidate_alias_explicit = self.has("AS")
  let candidate_alias = if candidate_alias_explicit {
    self.keyword("AS")
    self.name()
  } else {
    relation.last().unwrap()
  }
  let query_vector = if self.has("USING") {
    self.keyword("USING")
    Some(self.expression())
  } else {
    None
  }
  if query_vector is Some(_) && self.has("QUERY") {
    raise QueryAbort(
      "USING and QUERY VECTOR cannot both supply the query vector",
      self.peek().start,
    )
  }
  let query_roles = if self.has("QUERY") {
    self.keyword("QUERY")
    let keys = self.nearest_keys()
    self.keyword("VECTOR")
    Some({ keys, vector: self.expression(), })
  } else {
    None
  }
  let candidate_roles = if self.has("CANDIDATE") {
    self.keyword("CANDIDATE")
    let keys = self.nearest_keys()
    self.keyword("VECTOR")
    Some({ keys, vector: self.expression(), })
  } else {
    None
  }
  let metric = if self.has("METRIC") {
    self.keyword("METRIC")
    let metric_start = self.peek().start
    let metric = self.name()
    if metric.quoted ||
      !["COSINE", "DOT", "L2"].contains(ascii_upper(metric.value)) {
      raise QueryAbort("NEAREST metric must be cosine, dot or l2", metric_start)
    }
    metric.value.to_lower()
  } else {
    "cosine"
  }
  self.keyword("K")
  let k = self.safe_integer(false)
  let keep = self.keep_clause()
  self.keyword("AS")
  {
    relation,
    candidate_alias,
    candidate_alias_explicit,
    query_vector,
    query_roles,
    candidate_roles,
    metric,
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
  parse_query_tokens(source, limits)
}

///|
fn parse_query_tokens(
  source : Tokens,
  limits : QueryLimits,
  observe_work? : ((Int) -> Unit)? = None,
) -> Result[Query, Diagnostic] {
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
  let result = try {
    let query = parser.query()
    let commands : Array[CommandEffectClause] = []
    if parser.peek().value == Symbol(59) {
      ignore(parser.advance())
      while parser.has("EFFECT") {
        if query.effect is Some(_) ||
          query.table_effect is Some(_) ||
          query.store_effect is Some(_) ||
          query.insert_effect is Some(_) {
          raise QueryAbort(
            "Conflicting terminal Effect declarations",
            parser.peek().start,
          )
        }
        let at = parser.peek().start
        let clause = parser.command_effect_clause()
        let duplicate_terminal_name = match query.short_command_effect {
          Some({ name: Some(name), .. }) => same_binding_name(name, clause.name)
          _ => false
        }
        if duplicate_terminal_name ||
          commands.any(previous => same_binding_name(previous.name, clause.name)) {
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
    Ok({ ..query, commands, work: parser.work, })
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
  if observe_work is Some(observe) {
    observe(parser.work)
  }
  result
}

///|
pub fn terminal_effect(query : Query) -> UpdateEffectClause? {
  query.effect.map(clause => {
    ..clause,
    target: match clause.target {
      ConcreteTarget(value) => ConcreteTarget(value)
      LogicalTarget(path) => LogicalTarget(path.copy())
    },
    set: clause.set.copy(),
  })
}

///|
pub fn terminal_table_effect(query : Query) -> TableEffectClause? {
  query.table_effect.map(clause => { ..clause, target: clause.target.copy(), })
}

///|
pub fn terminal_store_effect(query : Query) -> StoreEffectClause? {
  query.store_effect.map(clause => {
    ..clause,
    target: clause.target.copy(),
    set: clause.set.copy(),
  })
}

///|
fn QueryParser::effect_is_store(self : QueryParser) -> Bool {
  guard token_at(self.source, self.index + 1) is Some(first) else {
    return false
  }
  guard token_at(self.source, self.index + 2) is Some(second) else {
    return false
  }
  let third = token_at(self.source, self.index + 3)
  if third.map(token => token.value != Symbol(46)).unwrap_or(false) &&
    (
      keyword(second, "UPDATE") ||
      keyword(second, "UPSERT") ||
      keyword(second, "DELETE") ||
      keyword(second, "INSERT") ||
      keyword(second, "CREATE") ||
      keyword(second, "STORE") ||
      keyword(second, "COMMAND")
    ) {
    return keyword(second, "STORE")
  }
  keyword(first, "STORE")
}

///|
fn QueryParser::store_effect_clause(
  self : QueryParser,
) -> StoreEffectClause raise QueryAbort {
  self.node()
  let start = self.peek().start
  self.keyword("EFFECT")
  let name = if self.has("STORE") &&
    !(token_at(self.source, self.index + 1)
    .map(token => keyword(token, "STORE"))
    .unwrap_or(false) &&
    token_at(self.source, self.index + 2)
    .map(token => token.value != Symbol(46))
    .unwrap_or(false)) {
    None
  } else {
    Some(self.binding_name())
  }
  self.keyword("STORE")
  let target = self.path()
  if target.length() < 2 {
    raise QueryAbort(
      "Effect logical target requires a qualified name",
      self.peek().start,
    )
  }
  let assignments : Array[(NamePart, Expression)] = []
  let assigned : Map[String, Bool] = Map([])
  if self.has("SET") {
    self.keyword("SET")
    self.symbol(40)
    while true {
      self.node()
      let field = self.name()
      self.spend(field.value.length())
      let key = ascii_upper(field.value)
      if assigned.contains(key) {
        raise QueryAbort("Duplicate STORE input field", self.peek().start)
      }
      assigned[key] = true
      self.symbol(61)
      assignments.push((field, self.expression()))
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
    self.symbol(41)
  }
  {
    name,
    target,
    set: assignments,
    start,
    end: token_at(self.source, self.index - 1).unwrap().end,
  }
}

///|
fn QueryParser::table_create_clause(
  self : QueryParser,
  name : NamePart?,
) -> TableEffectClause raise QueryAbort {
  self.node()
  self.keyword("CREATE")
  let allow_replace = self.has("OR")
  if allow_replace {
    self.keyword("OR")
    self.keyword("REPLACE")
  }
  self.keyword("TABLE")
  { name, target: self.path(), allow_replace, }
}

///|
// Preserve the parsed source and expression origins when a checked Model
// producer is retained before an Effect continuation. This is AST slicing,
// not reparsing text or constructing another execution language.
pub fn effect_result_continuation(
  query : Query,
  input : NamePart,
  has_postlude? : Bool = false,
) -> (Query, Query)? {
  if (
      !has_postlude &&
      query.commands.is_empty() &&
      query.effect is None &&
      query.table_effect is None &&
      query.store_effect is None &&
      query.insert_effect is None &&
      query.short_command_effect is None
    ) ||
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
          table_effect: None,
          store_effect: None,
          insert_effect: None,
          short_command_effect: None,
          commands: [],
        }
        let tail = {
          ..query,
          relation: [input],
          source_alias: None,
          file_listing: None,
          graph: None,
          joins: [],
          bindings: [],
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
  let name = if keyed_effect_word(self.peek()) &&
    !(token_at(self.source, self.index + 1)
    .map(keyed_effect_word)
    .unwrap_or(false) &&
    token_at(self.source, self.index + 2)
    .map(token => token.value != Symbol(46))
    .unwrap_or(false)) {
    None
  } else {
    Some(self.name())
  }
  let kind = if self.has("UPDATE") {
    self.keyword("UPDATE")
    KeyedEffectKind::Update
  } else if self.has("UPSERT") {
    self.keyword("UPSERT")
    KeyedEffectKind::Upsert
  } else if self.has("DELETE") {
    self.keyword("DELETE")
    KeyedEffectKind::Delete
  } else {
    raise QueryAbort("Expected UPDATE, UPSERT or DELETE", self.peek().start)
  }
  let (target, mapping) = self.record_effect_target()
  let result = if self.has("FROM") {
    self.keyword("FROM")
    self.keyword("RESULT")
    Some(self.name())
  } else {
    None
  }
  self.keyword("ID")
  let (id, id_expression) = if token_at(self.source, self.index + 1)
    .map(token => token.value == Symbol(46))
    .unwrap_or(false) {
    let id_start = self.peek().start
    let original_id = self.expression()
    let path = match
      expression_node(original_id, expression_root(original_id)).unwrap().kind {
      Reference(path) => path
      _ => raise QueryAbort("Record Effect ID requires a field path", id_start)
    }
    (path.last().unwrap(), Some(original_id))
  } else {
    // The original single-field UPDATE consumes exactly its historical tokens
    // and budget; only new qualified/property paths use an expression owner.
    (self.name(), None)
  }
  let assignments : Array[(NamePart, Expression)] = []
  if kind != Delete {
    self.keyword("SET")
    self.symbol(40)
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
  }
  { kind, name, target, mapping, result, id, id_expression, set: assignments, }
}
