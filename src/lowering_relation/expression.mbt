///|
/// Typed in-memory representation of actql-expression-node/0.1. Source and
/// resolved field identity are non-wire sidecars, not a new expression language.
struct Expression {
  typed_owner : @typing.TypedExpression
  body : ExpressionBody
  contract : @contract.Contract
  source : @decode.Cursor
  location : @syntax.Location
  uses_veca : Bool
}

///|
pub enum ExpressionBody {
  Field(String, @relation.ReferenceTarget)
  Literal(@value.CheckedValue)
  TypedNull
  Array(Array[Expression])
  EmptyArray
  Object(Array[(String, Expression)])
  Property(Expression, String, Int)
  Subscript(Expression, Expression)
  Cast(Expression)
  Unary(UnaryOperator, Expression)
  Binary(BinaryOperator, Expression, Expression)
  VectorScore(VectorMetric, Expression, Expression)
  VectorConcat(Array[Expression])
  Many(ManyOperator, Array[Expression])
  Conditional(Expression, Expression, Expression)
  Case(Array[(Expression, Expression)], Expression)
}

///|
pub(all) enum VectorMetric {
  Cosine
  Dot
  L2
} derive(Eq, Debug)

///|
pub(all) enum UnaryOperator {
  Negate
  Not
  IsNull
  NotNull
  IsTrue
  IsFalse
  IsUnknown
  Length
  ByteLength
  Unicode
  Chr
  Reverse
  Upper
  Lower
  Trim
  LTrim
  RTrim
  Floor
  Sqrt
  Cbrt
  Sin
  Cos
  Tan
  Asin
  Acos
  Atan
  Sinh
  Cosh
  Tanh
  Asinh
  Acosh
  Atanh
  Exp
  Ln
  Log10
  Abs
  Sign
  Round
  Trunc
  SafeNegate
} derive(Eq, Debug)

///|
pub(all) enum BinaryOperator {
  Add
  Subtract
  Multiply
  Divide
  SafeDivide
  SafeAdd
  SafeSubtract
  SafeMultiply
  Modulo
  Pow
  Atan2
  Log
  RoundAt
  TruncAt
  Strpos
  TrimSet
  LTrimSet
  RTrimSet
  StartsWith
  EndsWith
  Equal
  NotEqual
  IsDistinctFrom
  Less
  LessEqual
  Greater
  GreaterEqual
  NullIf
  In
  NotIn
  Contains
  DateTruncate
} derive(Eq, Debug)

///|
pub(all) enum ManyOperator {
  And
  Or
  Coalesce
  Greatest
  Least
  Concat
  ConcatStrict
  Replace
  Repeat
  Translate
  Instr
  Split
  Substring
  LeftString
  RightString
  LPad
  RPad
  Between
  DateDifference
  DateAddition
} derive(Eq, Debug)

///|
pub(all) struct ExpressionLimits {
  max_nodes : Int
  max_work : Int
  max_depth : Int
  max_literal_nodes : Int
  max_literal_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum ExpressionIssueKind {
  InvalidExpressionLimits
  ExpressionBudgetExceeded
  MissingCheckedBinding
  MissingParameter(String)
  MissingTypeAnnotation
  MissingResolvedField(String)
  PendingValidation(@typing.ObligationKind)
  ExpressionNotImplemented(String)
  LiteralAdmission(@value.Issue)
  JsonLiteralAdmission(@value.JsonLiteralIssue)
} derive(Eq, Debug)

///|
pub struct ExpressionIssue {
  kind : ExpressionIssueKind
  source : @decode.Cursor
}

///|
priv suberror ExpressionStop {
  ExpressionStop(ExpressionIssue)
}

///|
pub fn expression_body(value : Expression) -> ExpressionBody {
  match value.body {
    Array(children) => Array(children.copy())
    Object(fields) => Object(fields.copy())
    VectorConcat(children) => VectorConcat(children.copy())
    Many(op, children) => Many(op, children.copy())
    Case(clauses, otherwise) => Case(clauses.copy(), otherwise)
    other => other
  }
}

///|
/// O(1), allocation-free number of entries copied by expression_body.
pub fn expression_view_entries(value : Expression) -> Int {
  match value.body {
    Array(children) => children.length()
    Object(fields) => fields.length()
    VectorConcat(children) => children.length()
    Many(_, children) => children.length()
    Case(clauses, _) => clauses.length()
    Field(_, _)
    | Literal(_)
    | TypedNull
    | EmptyArray
    | Property(_, _, _)
    | Subscript(_, _)
    | Cast(_)
    | Unary(_, _)
    | Binary(_, _, _)
    | VectorScore(_, _, _)
    | Conditional(_, _, _) => 0
  }
}

///|
pub fn expression_contract(value : Expression) -> @contract.Contract {
  value.contract
}

///|
pub fn expression_source(value : Expression) -> @decode.Cursor {
  value.source
}

///|
pub fn expression_location(value : Expression) -> @syntax.Location {
  value.location
}

///|
/// Allocation-free capability summary computed during bounded lowering.
pub fn expression_uses_veca(value : Expression) -> Bool {
  value.uses_veca
}

///|
fn[T] expression_fail(
  source : @decode.Cursor,
  kind : ExpressionIssueKind,
) -> T raise ExpressionStop {
  raise ExpressionStop({ source, kind, })
}

///|
fn expression_tag(
  tag : String,
  source : @decode.Cursor,
) -> Unit raise ExpressionStop {
  match tag {
    "field"
    | "literal"
    | "typed_literal"
    | "$param"
    | "negate"
    | "upper"
    | "lower"
    | "trim"
    | "ltrim"
    | "rtrim"
    | "floor"
    | "sqrt"
    | "cbrt"
    | "sin"
    | "cos"
    | "tan"
    | "asin"
    | "acos"
    | "atan"
    | "sinh"
    | "cosh"
    | "tanh"
    | "asinh"
    | "acosh"
    | "atanh"
    | "exp"
    | "ln"
    | "log10"
    | "abs"
    | "sign"
    | "round"
    | "trunc"
    | "safe_negate"
    | "is_true"
    | "is_false"
    | "is_unknown"
    | "not"
    | "is_null"
    | "not_null"
    | "add"
    | "subtract"
    | "multiply"
    | "divide"
    | "safe_divide"
    | "safe_add"
    | "safe_subtract"
    | "safe_multiply"
    | "modulo"
    | "pow"
    | "atan2"
    | "log"
    | "strpos"
    | "contains"
    | "starts_with"
    | "ends_with"
    | "eq"
    | "neq"
    | "is_distinct_from"
    | "lt"
    | "lte"
    | "gt"
    | "gte"
    | "nullif"
    | "in"
    | "not_in"
    | "between"
    | "and"
    | "or"
    | "coalesce"
    | "greatest"
    | "least"
    | "concat"
    | "concat_strict"
    | "len"
    | "byte_length"
    | "unicode"
    | "chr"
    | "reverse"
    | "repeat"
    | "translate"
    | "instr"
    | "replace"
    | "split"
    | "substring"
    | "left"
    | "right"
    | "lpad"
    | "rpad"
    | "vector_score"
    | "vector_concat"
    | "cast"
    | "if"
    | "case"
    | "date_diff"
    | "date_add"
    | "date_trunc" => ()
    "array" | "empty_array" | "object" | "property" | "subscript" => ()
    other => expression_fail(source, ExpressionNotImplemented(other))
  }
}

///|
fn expression_children(
  tag : String,
  body : @decode.Cursor,
  max_nodes : Int,
) -> Array[@decode.Cursor] raise ExpressionStop {
  match tag {
    "substring" => {
      let obj = @decode.open_object(body).unwrap()
      let children = [
        @decode.lookup(obj, "value").unwrap(),
        @decode.lookup(obj, "start").unwrap(),
      ]
      if @decode.lookup(obj, "length") is Some(length) {
        children.push(length)
      }
      children
    }
    "property" =>
      [@decode.lookup(@decode.open_object(body).unwrap(), "value").unwrap()]
    "subscript" => {
      let object = @decode.open_object(body).unwrap()
      [
        @decode.lookup(object, "value").unwrap(),
        @decode.lookup(object, "index").unwrap(),
      ]
    }
    "object" => {
      let count = @decode.object_length(body).unwrap()
      if count > max_nodes {
        expression_fail(body, ExpressionBudgetExceeded)
      }
      let children = []
      for i in 0..<count {
        children.push(@decode.field_at(body, i).unwrap().1)
      }
      children
    }
    "empty_array" | "literal" | "typed_literal" | "field" | "$param" => []
    "cast" => {
      let obj = @decode.open_object(body).unwrap()
      [@decode.lookup(obj, "value").unwrap()]
    }
    "trim" | "ltrim" | "rtrim" | "round" | "trunc" =>
      if @decode.array_length(body) is Some(_) {
        @decode.elements(body).unwrap()
      } else {
        [body]
      }
    "negate"
    | "upper"
    | "lower"
    | "floor"
    | "sqrt"
    | "cbrt"
    | "sin"
    | "cos"
    | "tan"
    | "asin"
    | "acos"
    | "atan"
    | "sinh"
    | "cosh"
    | "tanh"
    | "asinh"
    | "acosh"
    | "atanh"
    | "exp"
    | "ln"
    | "log10"
    | "abs"
    | "sign"
    | "safe_negate"
    | "not"
    | "is_null"
    | "not_null"
    | "is_true"
    | "is_false"
    | "is_unknown" => [body]
    "len" | "byte_length" | "unicode" | "chr" | "reverse" => [body]
    "case" => {
      let obj = @decode.open_object(body).unwrap()
      let clauses = @decode.lookup(obj, "when").unwrap()
      let count = @decode.array_length(clauses).unwrap()
      if count > max_nodes / 2 {
        expression_fail(body, ExpressionBudgetExceeded)
      }
      let children = []
      for i = 0; i < count; i = i + 1 {
        let clause = @decode.open_object(
          @decode.element_at(clauses, i).unwrap(),
        ).unwrap()
        children.push(@decode.lookup(clause, "when").unwrap())
        children.push(@decode.lookup(clause, "then").unwrap())
      }
      if @decode.lookup(obj, "else") is Some(otherwise) {
        children.push(otherwise)
      }
      children
    }
    "vector_score" => {
      let obj = @decode.open_object(body).unwrap()
      [
        @decode.lookup(obj, "left").unwrap(),
        @decode.lookup(obj, "right").unwrap(),
      ]
    }
    _ => {
      if @decode.array_length(body).unwrap() > max_nodes {
        expression_fail(body, ExpressionBudgetExceeded)
      }
      @decode.elements(body).unwrap()
    }
  }
}

///|
priv struct ExpressionBudget {
  limits : ExpressionLimits
  mut work : Int
  mut nodes : Int
  mut literal_nodes : Int
  mut literal_bytes : Int
}

///|
fn expression_spend(
  b : ExpressionBudget,
  source : @decode.Cursor,
) -> Unit raise ExpressionStop {
  if b.work >= b.limits.max_work {
    expression_fail(source, ExpressionBudgetExceeded)
  }
  b.work += 1
}

///|
/// Charge every nested literal node, without treating business objects as AST.
fn charge_literal(
  b : ExpressionBudget,
  root : @decode.Cursor,
) -> Unit raise ExpressionStop {
  let todo = [(root, 0)]
  while todo.pop() is Some((cursor, depth)) {
    expression_spend(b, cursor)
    if b.literal_nodes >= b.limits.max_literal_nodes ||
      depth > b.limits.max_depth {
      expression_fail(cursor, ExpressionBudgetExceeded)
    }
    b.literal_nodes += 1
    match @decode.view(cursor) {
      NullValue | BoolValue(_) | NumberValue(_) => ()
      TextValue(s) => charge_expression_text(b, cursor, s)
      ArrayValue(children) => {
        if children.length() >
          b.limits.max_literal_nodes - b.literal_nodes - todo.length() {
          expression_fail(cursor, ExpressionBudgetExceeded)
        }
        for child in children {
          todo.push((child, depth + 1))
        }
      }
      ObjectValue(_) => {
        let count = @decode.object_length(cursor).unwrap()
        if count > b.limits.max_literal_nodes - b.literal_nodes - todo.length() {
          expression_fail(cursor, ExpressionBudgetExceeded)
        }
        for i = 0; i < count; i = i + 1 {
          let (name, child) = @decode.field_at(cursor, i).unwrap()
          charge_expression_text(b, cursor, name)
          todo.push((child, depth + 1))
        }
      }
    }
  }
}

///|
fn charge_expression_text(
  b : ExpressionBudget,
  source : @decode.Cursor,
  s : String,
) -> Unit raise ExpressionStop {
  let left = b.limits.max_literal_text_bytes - b.literal_bytes
  if s.length() > left {
    expression_fail(source, ExpressionBudgetExceeded)
  }
  let bytes = @utf8.encode(s).length()
  if bytes > left {
    expression_fail(source, ExpressionBudgetExceeded)
  }
  b.literal_bytes += bytes
}

///|
fn charge_bound_literal(
  b : ExpressionBudget,
  source : @decode.Cursor,
  value : @value.Value,
) -> Unit raise ExpressionStop {
  let todo = [(value, 0)]
  while todo.pop() is Some((value, depth)) {
    expression_spend(b, source)
    if b.literal_nodes >= b.limits.max_literal_nodes ||
      depth > b.limits.max_depth {
      expression_fail(source, ExpressionBudgetExceeded)
    }
    b.literal_nodes += 1
    match value {
      @value.Null | @value.Number(_) | @value.Boolean(_) => ()
      @value.Text(s) | @value.Date(s) | @value.Timestamp(s) =>
        charge_expression_text(b, source, s)
      @value.Decimal(d) => charge_expression_text(b, source, decimal_wire(d))
      @value.Signed64(value) =>
        charge_expression_text(b, source, value.to_string())
      @value.Array(items) => {
        let count = @value.element_count(items)
        if count > b.limits.max_literal_nodes - b.literal_nodes - todo.length() {
          expression_fail(source, ExpressionBudgetExceeded)
        }
        for i = 0; i < count; i = i + 1 {
          todo.push((@value.element_at(items, i).unwrap(), depth + 1))
        }
      }
      @value.Object(fields) => {
        let count = @value.element_count(fields)
        if count > b.limits.max_literal_nodes - b.literal_nodes - todo.length() {
          expression_fail(source, ExpressionBudgetExceeded)
        }
        for i = 0; i < count; i = i + 1 {
          let (name, child) = @value.element_at(fields, i).unwrap()
          charge_expression_text(b, source, name)
          todo.push((child, depth + 1))
        }
      }
      @value.Vector(items) => {
        let count = @value.element_count(items)
        if (count > 0 && depth >= b.limits.max_depth) ||
          count > b.limits.max_literal_nodes - b.literal_nodes - todo.length() ||
          count > b.limits.max_work - b.work {
          expression_fail(source, ExpressionBudgetExceeded)
        }
        b.literal_nodes += count
        b.work += count
      }
      @value.Reference(_) => abort("opaque reference literal")
      @value.JsonData(payload) => {
        b.literal_nodes -= 1
        todo.push((payload, depth))
      }
    }
  }
}

///|
fn graph_predicate_fields(
  predicate : @graph.CheckedPredicate,
) -> Array[(String, @relation.ReferenceTarget)]? {
  let references : Array[(String, @relation.ReferenceTarget)] = []
  for index in 0..<@graph.predicate_reference_count(predicate) {
    guard @graph.predicate_reference_name(predicate, index) is Some(name) &&
      @graph.predicate_reference_field(predicate, index) is Some(field) else {
      return None
    }
    references.push((name, @relation.InputField(field)))
  }
  Some(references)
}

///|
pub fn lower_expression(
  bound : BoundPrepared,
  step_index : Int,
  binding_index : Int,
  limits : ExpressionLimits,
) -> Result[Expression, ExpressionIssue] {
  lower_expression_measured(bound, step_index, binding_index, limits).map(p => {
    p.0
  })
}

///|
fn lower_expression_measured(
  bound : BoundPrepared,
  step_index : Int,
  binding_index : Int,
  limits : ExpressionLimits,
) -> Result[(Expression, ExpressionBudget), ExpressionIssue] {
  try {
    let source = @pipeline.source(bound.prepared.owner)
    if limits.max_nodes < 0 ||
      limits.max_work < 0 ||
      limits.max_depth < 0 ||
      limits.max_literal_nodes < 0 ||
      limits.max_literal_text_bytes < 0 {
      expression_fail(source, InvalidExpressionLimits)
    }
    guard bound.prepared.nodes.get(step_index) is Some(step) else {
      expression_fail(source, MissingCheckedBinding)
    }
    let (typed, resolved_fields) = match step.payload {
      Infer(_) | Serialize(_) =>
        expression_fail(step.source, MissingCheckedBinding)
      Derive(op)
      | Where(op)
      | CountGroup(op)
      | WindowGroup(op)
      | Analytic(op)
      | AssertRows(op) => {
        guard @relation.binding_at(op, binding_index) is Some(binding) else {
          expression_fail(step.source, MissingCheckedBinding)
        }
        let references : Array[(String, @relation.ReferenceTarget)] = []
        for ref_ in @relation.references(binding) {
          references.push((ref_.occurrence.name, ref_.target))
        }
        (binding.expression, references)
      }
      GraphMatchRows(checked) => {
        if binding_index != 0 {
          expression_fail(step.source, MissingCheckedBinding)
        }
        guard @graph.match_predicate(checked) is Some(predicate) else {
          expression_fail(step.source, MissingCheckedBinding)
        }
        guard graph_predicate_fields(predicate) is Some(references) else {
          expression_fail(step.source, MissingResolvedField(""))
        }
        (@graph.predicate_expression(predicate), references)
      }
      GraphSubgraphValue(checked) => {
        if binding_index != 0 {
          expression_fail(step.source, MissingCheckedBinding)
        }
        guard @graph.subgraph_edges(checked) is Some(predicate) else {
          expression_fail(step.source, MissingCheckedBinding)
        }
        guard graph_predicate_fields(predicate) is Some(references) else {
          expression_fail(step.source, MissingResolvedField(""))
        }
        (@graph.predicate_expression(predicate), references)
      }
      GraphTraverseRows(checked) => {
        let selector = @graph.traverse_start(checked)
        let predicate = if binding_index ==
          @graph.traverse_hop_count(checked) * 2 {
          @graph.selector_predicate(selector)
        } else if binding_index == @graph.traverse_hop_count(checked) * 2 + 1 {
          @graph.traverse_shortest(checked)
          .map(@graph.shortest_targets)
          .bind(@graph.selector_predicate)
        } else {
          let hop_index = binding_index / 2
          guard binding_index >= 0 &&
            @graph.traverse_hop_at(checked, hop_index) is Some(hop) else {
            expression_fail(step.source, MissingCheckedBinding)
          }
          if binding_index % 2 == 0 {
            @graph.hop_edge_predicate(hop)
          } else {
            @graph.hop_node_predicate(hop)
          }
        }
        guard predicate is Some(predicate) else {
          expression_fail(step.source, MissingCheckedBinding)
        }
        guard graph_predicate_fields(predicate) is Some(references) else {
          expression_fail(step.source, MissingResolvedField(""))
        }
        (@graph.predicate_expression(predicate), references)
      }
      SequenceRows(checked) => {
        guard @relation.sequence_pattern_at(checked, binding_index)
          is Some(pattern) else {
          expression_fail(step.source, MissingCheckedBinding)
        }
        let syntax = @typing.expression(pattern.predicate)
        let references : Array[(String, @relation.ReferenceTarget)] = []
        for reference in @syntax.field_references(syntax) {
          references.push(
            (
              reference.name,
              @relation.InputField(@schema.Unqualified(reference.name)),
            ),
          )
        }
        (pattern.predicate, references)
      }
      Values(_)
      | TimeSeriesValue(_)
      | CalendarValue(_)
      | RowWindow(_)
      | Select(_)
      | Limit(_)
      | TopK(_)
      | TopKBy(_)
      | Pivot(_)
      | Unnest(_)
      | Unpivot(_)
      | Distinct(_)
      | Dedupe(_)
      | Sort(_)
      | Lag(_)
      | Watermark(_)
      | JsonPick(_)
      | InnerJoin(_)
      | IntervalJoinRows(_)
      | AsOfJoinRows(_)
      | CrossJoinRows(_)
      | AppendRows(_)
      | SetRows(_)
      | NestRows(_)
      | GraphBoundsRows(_)
      | GraphDegreeRows(_)
      | GraphEqualityRows(_)
      | GraphNormalizeValue(_)
      | GraphDeltaValue(_)
      | GraphUnionValue(_)
      | GraphMeanValue(_)
      | GraphSubtractionValue(_)
      | GraphComponentsRows(_)
      | GraphConstructionValue(_)
      | VectorValue(_)
      | NearestValue(_)
      | PoolValue(_)
      | RankingValue(_)
      | EventValue(_)
      | CarrierProjection(_) =>
        expression_fail(step.source, MissingCheckedBinding)
    }
    lower_typed_expression_measured(
      typed,
      resolved_fields,
      bound.by_name,
      profile => expression_profile_admitted(bound, profile),
      limits,
    )
  } catch {
    ExpressionStop(issue) => Err(issue)
  }
}

///|
/// One lowering implementation for checked Relation and acquisition bindings.
/// Callers retain their own exact checked owner and declaration association.
fn lower_typed_expression_measured(
  typed : @typing.TypedExpression,
  resolved_fields : Array[(String, @relation.ReferenceTarget)],
  parameters : Map[String, @value.CheckedValue],
  profile_admitted : (String) -> Bool,
  limits : ExpressionLimits,
) -> Result[(Expression, ExpressionBudget), ExpressionIssue] {
  try {
    let syntax = @typing.expression(typed)
    let root = @syntax.tree(syntax)
    let budget : ExpressionBudget = {
      limits,
      work: 0,
      nodes: 0,
      literal_nodes: 0,
      literal_bytes: 0,
    }
    let annotations : Map[Int, @contract.Contract] = Map([])
    let implicit_else : Map[Int, @contract.Contract] = Map([])
    let membership_lists : Map[Int, Int] = Map([])
    for i = 0; i < @typing.node_count(typed); i = i + 1 {
      expression_spend(budget, root)
      let node = @typing.node_at(typed, i).unwrap()
      if node.role == @typing.ExpressionNode ||
        node.role == @typing.MembershipList ||
        node.role == @typing.ImplicitElse {
        if annotations.length() + implicit_else.length() >= limits.max_nodes {
          expression_fail(node.source, ExpressionBudgetExceeded)
        }
        guard @decode.tree_index(root, node.source) is Some(index) else {
          expression_fail(node.source, MissingTypeAnnotation)
        }
        if node.role == @typing.ImplicitElse {
          implicit_else[index] = node.contract
        } else {
          annotations[index] = node.contract
          if node.role == @typing.MembershipList {
            membership_lists[index] = i
          }
        }
      }
    }
    for obligation in @typing.pending_validations(typed) {
      let admitted = match obligation.kind {
        @typing.ProfileAdmission(profile) => profile_admitted(profile)
        @typing.PatternValidation(_) | @typing.HostEnvelope => false
      }
      if !admitted {
        expression_fail(
          @typing.node_at(typed, obligation.node_index).unwrap().source,
          PendingValidation(obligation.kind),
        )
      }
    }
    let fields : Map[String, @relation.ReferenceTarget] = Map([])
    for (name, target) in resolved_fields {
      expression_spend(budget, root)
      fields[name] = target
    }
    let completed : Map[Int, Expression] = Map([])
    let todo = [(root, 0, false)]
    while todo.pop() is Some((cursor, depth, visited)) {
      expression_spend(budget, cursor)
      if depth > limits.max_depth {
        expression_fail(cursor, ExpressionBudgetExceeded)
      }
      let (tag, body) = @decode.field_at(cursor, 0).unwrap()
      expression_tag(tag, cursor)
      let index = @decode.tree_index(root, cursor).unwrap()
      let children = expression_children(tag, body, limits.max_nodes)
      if !visited {
        if budget.nodes >= limits.max_nodes {
          expression_fail(cursor, ExpressionBudgetExceeded)
        }
        budget.nodes += 1
        if children.length() > limits.max_nodes - budget.nodes {
          expression_fail(cursor, ExpressionBudgetExceeded)
        }
        todo.push((cursor, depth, true))
        for i = children.length() - 1; i >= 0; i = i - 1 {
          todo.push((children[i], depth + 1, false))
        }
        continue
      }
      guard annotations.get(index) is Some(contract) else {
        expression_fail(cursor, MissingTypeAnnotation)
      }
      let args = children.map(c => {
        completed.get(@decode.tree_index(root, c).unwrap()).unwrap()
      })
      let lowered = match tag {
        "array" => Array(args)
        "empty_array" => EmptyArray
        "subscript" => Subscript(args[0], args[1])
        "object" => {
          guard contract.shape is @contract.Object(contracts) else {
            expression_fail(cursor, MissingTypeAnnotation)
          }
          let fields = []
          let object = @decode.open_object(body).unwrap()
          for i in 0..<@contract.field_count(contracts) {
            expression_spend(budget, cursor)
            let name = @contract.field_at(contracts, i).unwrap().name
            let child = @decode.lookup(object, name).unwrap()
            fields.push(
              (
                name,
                completed.get(@decode.tree_index(root, child).unwrap()).unwrap(),
              ),
            )
          }
          // Checked syntax fixes canonical field evaluation order.
          Object(fields)
        }
        "property" => {
          let name = @decode.text(
            @decode.lookup(@decode.open_object(body).unwrap(), "name").unwrap(),
          ).unwrap()
          guard args[0].contract.shape is @contract.Object(fields) else {
            expression_fail(cursor, MissingTypeAnnotation)
          }
          let mut ordinal = -1
          for i in 0..<@contract.field_count(fields) {
            expression_spend(budget, cursor)
            if @contract.field_at(fields, i).unwrap().name == name {
              ordinal = i
            }
          }
          if ordinal < 0 {
            expression_fail(cursor, MissingResolvedField(name))
          }
          Property(args[0], name, ordinal)
        }
        "field" => {
          let name = @decode.text(body).unwrap()
          guard fields.get(name) is Some(target) else {
            expression_fail(cursor, MissingResolvedField(name))
          }
          ExpressionBody::Field(name, target)
        }
        "typed_literal" => {
          let text = @decode.text(
            @decode.lookup(@decode.open_object(body).unwrap(), "value").unwrap(),
          ).unwrap()
          let (value, nodes, _) = match
            @value.admit_json_literal(text, {
              max_nodes: limits.max_literal_nodes - budget.literal_nodes,
              max_depth: limits.max_depth,
              max_text_bytes: limits.max_literal_text_bytes -
              budget.literal_bytes,
            }) {
            Ok(value) => value
            Err(issue) => expression_fail(cursor, JsonLiteralAdmission(issue))
          }
          let bytes = @scalar.admit_utf8_length(
            text,
            limits.max_literal_text_bytes - budget.literal_bytes,
          ).unwrap()
          budget.literal_nodes += nodes
          budget.literal_bytes += bytes
          if nodes > limits.max_work - budget.work {
            expression_fail(cursor, ExpressionBudgetExceeded)
          }
          budget.work += nodes
          if bytes > limits.max_work - budget.work {
            expression_fail(cursor, ExpressionBudgetExceeded)
          }
          budget.work += bytes
          Literal(value)
        }
        "literal" =>
          if membership_lists.get(index) is Some(list_index) {
            Literal(
              lower_membership_literal(
                typed, list_index, parameters, budget, depth,
              ),
            )
          } else if @decode.is_null(body) {
            charge_literal(budget, body)
            TypedNull
          } else {
            Literal(lower_comparison_literal(contract, body, budget))
          }
        "$param" => {
          let name = @decode.text(body).unwrap()
          guard parameters.get(name) is Some(value) else {
            expression_fail(cursor, MissingParameter(name))
          }
          charge_bound_literal(budget, cursor, value.value)
          if value.value is @value.Null {
            TypedNull
          } else {
            Literal(value)
          }
        }
        "negate" => Unary(Negate, args[0])
        "upper" => Unary(Upper, args[0])
        "lower" => Unary(Lower, args[0])
        "trim" =>
          if args.length() == 1 {
            Unary(Trim, args[0])
          } else {
            Binary(TrimSet, args[0], args[1])
          }
        "ltrim" =>
          if args.length() == 1 {
            Unary(LTrim, args[0])
          } else {
            Binary(LTrimSet, args[0], args[1])
          }
        "rtrim" =>
          if args.length() == 1 {
            Unary(RTrim, args[0])
          } else {
            Binary(RTrimSet, args[0], args[1])
          }
        "floor" => Unary(Floor, args[0])
        "sqrt" => Unary(Sqrt, args[0])
        "cbrt" => Unary(Cbrt, args[0])
        "sin" => Unary(Sin, args[0])
        "cos" => Unary(Cos, args[0])
        "tan" => Unary(Tan, args[0])
        "asin" => Unary(Asin, args[0])
        "acos" => Unary(Acos, args[0])
        "atan" => Unary(Atan, args[0])
        "sinh" => Unary(Sinh, args[0])
        "cosh" => Unary(Cosh, args[0])
        "tanh" => Unary(Tanh, args[0])
        "asinh" => Unary(Asinh, args[0])
        "acosh" => Unary(Acosh, args[0])
        "atanh" => Unary(Atanh, args[0])
        "exp" => Unary(Exp, args[0])
        "ln" => Unary(Ln, args[0])
        "log10" => Unary(Log10, args[0])
        "abs" => Unary(Abs, args[0])
        "sign" => Unary(Sign, args[0])
        "round" =>
          if args.length() == 1 {
            Unary(Round, args[0])
          } else {
            Binary(RoundAt, args[0], args[1])
          }
        "trunc" =>
          if args.length() == 1 {
            Unary(Trunc, args[0])
          } else {
            Binary(TruncAt, args[0], args[1])
          }
        "safe_negate" => Unary(SafeNegate, args[0])
        "len" => Unary(Length, args[0])
        "byte_length" => Unary(ByteLength, args[0])
        "unicode" => Unary(Unicode, args[0])
        "chr" => Unary(Chr, args[0])
        "reverse" => Unary(Reverse, args[0])
        "cast" => Cast(args[0])
        "not" => Unary(Not, args[0])
        "is_null" => Unary(IsNull, args[0])
        "not_null" => Unary(NotNull, args[0])
        "is_true" => Unary(IsTrue, args[0])
        "is_false" => Unary(IsFalse, args[0])
        "is_unknown" => Unary(IsUnknown, args[0])
        "add" => Binary(Add, args[0], args[1])
        "subtract" => Binary(Subtract, args[0], args[1])
        "multiply" => Binary(Multiply, args[0], args[1])
        "divide" => Binary(Divide, args[0], args[1])
        "safe_divide" => Binary(SafeDivide, args[0], args[1])
        "safe_add" => Binary(SafeAdd, args[0], args[1])
        "safe_subtract" => Binary(SafeSubtract, args[0], args[1])
        "safe_multiply" => Binary(SafeMultiply, args[0], args[1])
        "modulo" => Binary(Modulo, args[0], args[1])
        "pow" => Binary(Pow, args[0], args[1])
        "atan2" => Binary(Atan2, args[0], args[1])
        "log" => Binary(Log, args[0], args[1])
        "strpos" => Binary(Strpos, args[0], args[1])
        "date_diff" => Many(DateDifference, args)
        "date_add" => Many(DateAddition, args)
        "date_trunc" => Binary(DateTruncate, args[0], args[1])
        "contains" => Binary(Contains, args[0], args[1])
        "starts_with" => Binary(StartsWith, args[0], args[1])
        "ends_with" => Binary(EndsWith, args[0], args[1])
        "eq" => Binary(Equal, args[0], args[1])
        "neq" => Binary(NotEqual, args[0], args[1])
        "is_distinct_from" => Binary(IsDistinctFrom, args[0], args[1])
        "lt" => Binary(Less, args[0], args[1])
        "lte" => Binary(LessEqual, args[0], args[1])
        "gt" => Binary(Greater, args[0], args[1])
        "gte" => Binary(GreaterEqual, args[0], args[1])
        "nullif" => Binary(NullIf, args[0], args[1])
        "in" => Binary(In, args[0], args[1])
        "not_in" => Binary(NotIn, args[0], args[1])
        "vector_score" => {
          let obj = @decode.open_object(body).unwrap()
          let metric = match
            @decode.text(@decode.lookup(obj, "metric").unwrap()).unwrap() {
            "cosine" => VectorMetric::Cosine
            "dot" => VectorMetric::Dot
            "l2" => VectorMetric::L2
            other => expression_fail(cursor, ExpressionNotImplemented(other))
          }
          VectorScore(metric, args[0], args[1])
        }
        "vector_concat" => VectorConcat(args)
        "and" => Many(And, args)
        "or" => Many(Or, args)
        "coalesce" => Many(Coalesce, args)
        "greatest" => Many(Greatest, args)
        "least" => Many(Least, args)
        "concat" => Many(Concat, args)
        "concat_strict" => Many(ConcatStrict, args)
        "between" => Many(Between, args)
        "replace" => Many(Replace, args)
        "repeat" => Many(Repeat, args)
        "translate" => Many(Translate, args)
        "instr" => Many(Instr, args)
        "split" => Many(Split, args)
        "substring" => Many(Substring, args)
        "left" => Many(LeftString, args)
        "right" => Many(RightString, args)
        "lpad" => Many(LPad, args)
        "rpad" => Many(RPad, args)
        "if" => Conditional(args[0], args[1], args[2])
        "case" => {
          let count = args.length() / 2
          let otherwise = if args.length() % 2 == 1 {
            args[args.length() - 1]
          } else {
            guard implicit_else.get(@decode.tree_index(root, body).unwrap())
              is Some(null_contract) else {
              expression_fail(body, MissingTypeAnnotation)
            }
            if budget.nodes >= limits.max_nodes {
              expression_fail(body, ExpressionBudgetExceeded)
            }
            budget.nodes += 1
            {
              typed_owner: typed,
              body: TypedNull,
              contract: null_contract,
              source: body,
              location: @syntax.origin(syntax, body).unwrap(),
              uses_veca: false,
            }
          }
          let clauses = []
          for i = 0; i < count; i = i + 1 {
            clauses.push((args[i * 2], args[i * 2 + 1]))
          }
          Case(clauses, otherwise)
        }
        other => expression_fail(cursor, ExpressionNotImplemented(other))
      }
      completed[index] = {
        typed_owner: typed,
        body: lowered,
        contract,
        source: cursor,
        location: @syntax.origin(syntax, cursor).unwrap(),
        uses_veca: match lowered {
          VectorScore(_, _, _) | VectorConcat(_) => true
          Unary(_, child) => child.uses_veca
          Property(child, _, _) => child.uses_veca
          Subscript(value, index) => value.uses_veca || index.uses_veca
          Array(children) => children.any(child => child.uses_veca)
          Object(fields) => fields.any(field => field.1.uses_veca)
          Cast(child) => child.uses_veca
          Binary(_, left, right) => left.uses_veca || right.uses_veca
          Many(_, children) => children.any(child => child.uses_veca)
          Conditional(condition, yes, no) =>
            condition.uses_veca || yes.uses_veca || no.uses_veca
          Case(clauses, otherwise) =>
            otherwise.uses_veca ||
            clauses.any(pair => pair.0.uses_veca || pair.1.uses_veca)
          Field(_, _) | Literal(_) | TypedNull | EmptyArray => false
        },
      }
    }
    Ok(
      (completed.get(@decode.tree_index(root, root).unwrap()).unwrap(), budget),
    )
  } catch {
    ExpressionStop(issue) => Err(issue)
  }
}

///|
// Consume only the checked comparison annotation. This is not schema-directed
// Number admission to int64 and does not reinterpret the source Number token.
fn lower_comparison_literal(
  contract : @contract.Contract,
  body : @decode.Cursor,
  budget : ExpressionBudget,
) -> @value.CheckedValue raise ExpressionStop {
  let limits = budget.limits
  if contract.shape is @contract.Signed64 &&
    @decode.view(body) is NumberValue(number) &&
    @value.signed64_comparison_literal_value(number) is Some(value) {
    charge_bound_literal(budget, body, value)
    guard @value.recheck_runtime_value(value, contract, {
        max_nodes: limits.max_literal_nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_literal_text_bytes,
      })
      is Some(checked) else {
      expression_fail(body, MissingTypeAnnotation)
    }
    return checked
  }
  charge_literal(budget, body)
  match
    @value.admit(contract, body, {
      max_nodes: limits.max_literal_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_literal_text_bytes,
    }) {
    Ok(value) => value
    Err(issue) => expression_fail(body, LiteralAdmission(issue))
  }
}

///|
/// Bind only the checker's immediate membership elements. A parameter hole is
/// not generic JSON substitution, and the emitted RHS remains one typed literal.
fn lower_membership_literal(
  typed : @typing.TypedExpression,
  index : Int,
  parameters : Map[String, @value.CheckedValue],
  budget : ExpressionBudget,
  depth : Int,
) -> @value.CheckedValue raise ExpressionStop {
  let node = @typing.node_at(typed, index).unwrap()
  let limits = budget.limits
  let count = @typing.child_count(typed, index).unwrap()
  if count > limits.max_nodes - budget.nodes ||
    budget.literal_nodes >= limits.max_literal_nodes ||
    (count > 0 && depth >= limits.max_depth) {
    expression_fail(node.source, ExpressionBudgetExceeded)
  }
  budget.nodes += count
  budget.literal_nodes += 1
  let values : Array[@value.Value] = []
  for i in 0..<count {
    expression_spend(budget, node.source)
    let child_index = @typing.child_at(typed, index, i).unwrap()
    let child = @typing.node_at(typed, child_index).unwrap()
    guard child.role == @typing.MembershipElement &&
      @typing.node_form(typed, child_index)
      is Some(@typing.Expression(tag, body)) else {
      expression_fail(child.source, MissingTypeAnnotation)
    }
    let value = match tag {
      "$param" => {
        let name = @decode.text(body).unwrap()
        guard parameters.get(name) is Some(value) else {
          expression_fail(child.source, MissingParameter(name))
        }
        charge_bound_literal(budget, child.source, value.value)
        value.value
      }
      "literal" => lower_comparison_literal(child.contract, body, budget).value
      other => expression_fail(child.source, ExpressionNotImplemented(other))
    }
    values.push(value)
  }
  guard @value.recheck_runtime_value(
      @value.array_value(values),
      node.contract,
      {
        max_nodes: limits.max_literal_nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_literal_text_bytes,
      },
    )
    is Some(value) else {
    expression_fail(node.source, MissingTypeAnnotation)
  }
  value
}
