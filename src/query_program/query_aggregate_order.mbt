///|
// DISTINCT collection ordering must name its input argument. Qualification,
// quotation and static property syntax do not change an admitted receiver.
// Resolve against the same immutable aggregate input scope for both sides.
fn aggregate_order_matches_argument(
  argument : @query.Expression,
  order : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
) -> Bool {
  let identity = fn(
    expression : @query.Expression,
  ) -> (Array[String], String, Array[@query.NamePart])? {
    let mut index = @query.expression_root(expression)
    let signs : Array[String] = []
    let suffix : Array[@query.NamePart] = []
    while true {
      match @query.expression_node(expression, index).unwrap().kind {
        Parenthesized(child) => index = child
        Unary("+" | "-" as sign, child) => {
          // Only peel outer numeric signs. A property of a signed receiver
          // is a different expression and remains subject to common typing.
          if !suffix.is_empty() {
            return None
          }
          signs.push(sign)
          index = child
        }
        Property(child, name) => {
          suffix.push(name)
          index = child
        }
        Reference(parts) => {
          // Resolve this receiver before appending explicit property nodes.
          // (payload).name must not become the range-qualified payload.name.
          guard order_reference_identity(parts, resolve) is Some((slot, length)) else {
            return None
          }
          let members = parts[length:].to_owned()
          for i = suffix.length() - 1; i >= 0; i = i - 1 {
            members.push(suffix[i])
          }
          return Some((signs, slot, members))
        }
        _ => return None
      }
    } nobreak {
      None
    }
  }
  match (identity(argument), identity(order)) {
    (Some((left_signs, a, left)), Some((right_signs, b, right))) => {
      if a != b || left.length() != right.length() || left_signs != right_signs {
        return false
      }
      for index in 0..<left.length() {
        if !same_name(left[index], right[index]) {
          return false
        }
      }
      true
    }
    // Resolve every receiver inside computed trees, not only a root column.
    // Spelling equality cannot establish input identity after Pipe rebinding.
    _ => same_group_expression_in_scopes(argument, order, resolve, resolve)
  }
}

///|
// Aggregate-local order keys use the input scope, never SELECT siblings.
// Typed parameters, static properties, numeric unary signs, comparisons,
// predicates and conditional trees with total operands are total after
// admission. The common checker
// validates receivers and numeric signatures;
// the expression owner preserves NULL propagation and evaluates each operand
// once. Do not hoist potentially failing calls or binary arithmetic out of
// aggregate demand here.
fn aggregate_order_fields(
  construction : Construction,
  call : @query.AggregateCall,
  resolve : (Array[@query.NamePart]) -> String?,
  reserved : Array[String],
  evaluated : Array[(@query.Expression, String)],
  derives : Array[(String, @builder.Node)],
  max_work : Int,
) -> Array[String] raise Abort {
  let fields : Array[String] = []
  for term in call.order_by {
    let expression = term.expression
    let mut root = @query.expression_node(
      expression,
      @query.expression_root(expression),
    ).unwrap()
    let mut transformed = false
    while true {
      match root.kind {
        Parenthesized(child) =>
          root = @query.expression_node(expression, child).unwrap()
        Property(child, _) | Unary("+" | "-", child) => {
          transformed = true
          root = @query.expression_node(expression, child).unwrap()
        }
        _ => break
      }
    }
    match root.kind {
      Reference(path) => {
        if !transformed {
          if resolve(path) is Some(field) {
            fields.push(field)
            continue
          }
        }
        // Keep the original Property/unary AST. Do not concatenate members
        // into a range path or substitute a signed key with its input column.
        let mut receiver = transformed && resolve(path) is Some(_)
        for length = 1; length < path.length(); length = length + 1 {
          if resolve(path[:length].to_owned()) is Some(_) {
            receiver = true
            break
          }
        }
        if !receiver {
          raise Abort(UnknownColumn)
        }
      }
      ParameterReference(_) => ()
      Call(_, _)
      | SearchedCase(_, _)
      | Binary(_, _, _)
      | Predicate(_, _)
      | Unary("NOT", _) =>
        if !aggregate_order_total_conditional(expression) {
          raise Abort(UnsupportedAggregate)
        }
      _ => raise Abort(UnsupportedAggregate)
    }
    let mut reused : String? = None
    for (previous, field) in evaluated {
      // Every comparison uses this same immutable GROUP input resolver.
      if same_group_expression_in_scopes(expression, previous, resolve, resolve) {
        reused = Some(field)
        break
      }
    }
    if reused is Some(field) {
      fields.push(field)
      continue
    }
    let value = match
      @expression.append_with_properties(
        expression,
        resolve,
        construction.builder,
        max_work,
        resolve_parameter=construction.parameter_resolver(),
      ) {
      Ok(value) => value
      Err(error) => raise Abort(Expression(error))
    }
    let field = pipe_physical_name(reserved, "aql_aggregate_sort_")
    reserved.push(field)
    evaluated.push((expression, field))
    derives.push((field, value))
    fields.push(field)
  }
  fields
}

///|
// This is an admission guard for moving an order key before GROUP, not an
// evaluator or a type checker. In particular, laziness inside IF/CASE does
// not prove that a failing operand is safe outside aggregate demand.
fn aggregate_order_total_conditional(expression : @query.Expression) -> Bool {
  let total : Array[Bool] = []
  for index in 0..<@query.expression_node_count(expression) {
    let admitted = match
      @query.expression_node(expression, index).unwrap().kind {
      Null
      | Boolean(_)
      | Number(_)
      | StringLiteral(_)
      | Reference(_)
      | ParameterReference(_) => true
      Parenthesized(child) | Property(child, _) => total[child]
      ArrayConstructor(items, _) => items.all(child => total[child])
      StructConstructor(fields) => fields.all(field => total[field.1])
      Unary("+" | "-" | "NOT", child) => total[child]
      Binary(
        "="
        | "!="
        | "<>"
        | "<"
        | "<="
        | ">"
        | ">="
        | "AND"
        | "OR",
        left,
        right
      ) => total[left] && total[right]
      Predicate(
        "IS NULL"
        | "IS NOT NULL"
        | "IS TRUE"
        | "IS NOT TRUE"
        | "IS FALSE"
        | "IS NOT FALSE"
        | "IS UNKNOWN"
        | "IS NOT UNKNOWN"
        | "BETWEEN"
        | "NOT BETWEEN"
        | "IS DISTINCT FROM"
        | "IS NOT DISTINCT FROM"
        | "IN"
        | "NOT IN"
        | "IN UNNEST"
        | "NOT IN UNNEST",
        args
      ) => args.all(child => total[child])
      Call(path, args) =>
        path.length() == 1 &&
        ["COALESCE", "IFNULL", "IF", "NULLIF"].contains(
          ascii_upper(path[0].value),
        ) &&
        args.all(child => total[child])
      SearchedCase(branches, otherwise) =>
        total[otherwise] &&
        branches.all(branch => total[branch.0] && total[branch.1])
      _ => false
    }
    total.push(admitted)
  }
  total[@query.expression_root(expression)]
}
