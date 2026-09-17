///|
/// Typed in-memory representation of actql-expression-node/0.1. Source and
/// resolved field identity are non-wire sidecars, not a new expression language.
struct Expression {
  typed_owner : @typing.TypedExpression
  body : ExpressionBody
  contract : @contract.Contract
  source : @decode.Cursor
  location : @syntax.Location
}

///|
pub enum ExpressionBody {
  Field(String, @relation.ReferenceTarget)
  Literal(@value.CheckedValue)
  TypedNull
  Unary(UnaryOperator, Expression)
  Binary(BinaryOperator, Expression, Expression)
  Many(ManyOperator, Array[Expression])
  Conditional(Expression, Expression, Expression)
  Case(Array[(Expression, Expression)], Expression)
}

///|
pub(all) enum UnaryOperator {
  Negate
  Not
  IsNull
  NotNull
  IsTrue
  IsFalse
  IsUnknown
} derive(Eq, Debug)

///|
pub(all) enum BinaryOperator {
  Add
  Subtract
  Multiply
  Divide
  Modulo
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
  NullIf
} derive(Eq, Debug)

///|
pub(all) enum ManyOperator {
  And
  Or
  Coalesce
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
    Many(op, children) => Many(op, children.copy())
    Case(clauses, otherwise) => Case(clauses.copy(), otherwise)
    other => other
  }
}

///|
/// O(1), allocation-free number of entries copied by expression_body.
pub fn expression_view_entries(value : Expression) -> Int {
  match value.body {
    Many(_, children) => children.length()
    Case(clauses, _) => clauses.length()
    Field(_, _)
    | Literal(_)
    | TypedNull
    | Unary(_, _)
    | Binary(_, _, _)
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
    | "$param"
    | "negate"
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
    | "modulo"
    | "eq"
    | "neq"
    | "lt"
    | "lte"
    | "gt"
    | "gte"
    | "nullif"
    | "and"
    | "or"
    | "coalesce"
    | "if"
    | "case" => ()
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
    "literal" | "field" | "$param" => []
    "negate"
    | "not"
    | "is_null"
    | "not_null"
    | "is_true"
    | "is_false"
    | "is_unknown" => [body]
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
    }
  }
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
    let op = match step.payload {
      Derive(op) | Where(op) | AssertRows(op) => op
      Values(_)
      | Select(_)
      | Limit(_)
      | Distinct(_)
      | Dedupe(_)
      | Sort(_)
      | CountGroup(_)
      | JsonPick(_)
      | InnerJoin(_)
      | AppendRows(_) => expression_fail(step.source, MissingCheckedBinding)
    }
    guard @relation.binding_at(op, binding_index) is Some(binding) else {
      expression_fail(step.source, MissingCheckedBinding)
    }
    let typed = binding.expression
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
    for i = 0; i < @typing.node_count(typed); i = i + 1 {
      expression_spend(budget, root)
      let node = @typing.node_at(typed, i).unwrap()
      if node.role == @typing.ExpressionNode ||
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
        }
      }
    }
    let pending = @typing.pending_validations(typed)
    if pending.get(0) is Some(obligation) {
      expression_fail(
        @typing.node_at(typed, obligation.node_index).unwrap().source,
        PendingValidation(obligation.kind),
      )
    }
    let fields : Map[String, @relation.ReferenceTarget] = Map([])
    for ref_ in @relation.references(binding) {
      expression_spend(budget, root)
      fields[ref_.occurrence.name] = ref_.target
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
        "field" => {
          let name = @decode.text(body).unwrap()
          guard fields.get(name) is Some(target) else {
            expression_fail(cursor, MissingResolvedField(name))
          }
          ExpressionBody::Field(name, target)
        }
        "literal" => {
          charge_literal(budget, body)
          if @decode.is_null(body) {
            TypedNull
          } else {
            let value = match
              @value.admit(contract, body, {
                max_nodes: limits.max_literal_nodes,
                max_depth: limits.max_depth,
                max_text_bytes: limits.max_literal_text_bytes,
              }) {
              Ok(value) => value
              Err(issue) => expression_fail(cursor, LiteralAdmission(issue))
            }
            Literal(value)
          }
        }
        "$param" => {
          let name = @decode.text(body).unwrap()
          guard bound.by_name.get(name) is Some(value) else {
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
        "modulo" => Binary(Modulo, args[0], args[1])
        "eq" => Binary(Equal, args[0], args[1])
        "neq" => Binary(NotEqual, args[0], args[1])
        "lt" => Binary(Less, args[0], args[1])
        "lte" => Binary(LessEqual, args[0], args[1])
        "gt" => Binary(Greater, args[0], args[1])
        "gte" => Binary(GreaterEqual, args[0], args[1])
        "nullif" => Binary(NullIf, args[0], args[1])
        "and" => Many(And, args)
        "or" => Many(Or, args)
        "coalesce" => Many(Coalesce, args)
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
      }
    }
    Ok(
      (completed.get(@decode.tree_index(root, root).unwrap()).unwrap(), budget),
    )
  } catch {
    ExpressionStop(issue) => Err(issue)
  }
}
