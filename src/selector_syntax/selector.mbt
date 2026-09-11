///|
pub enum Issue {
  InvalidLimits
  WorkLimit
  Expression(@expression.Issue)
  RestrictedNode(String, @expression.Location)
}

///|
struct Selector {
  expression : @expression.Expression
  work : Int
}

///|
priv enum Position {
  Predicate
  Operand
}

///|
/// Decode common expression notation, then enforce the closed Effect selector
/// subset. This checks syntax only, not target-field types or permissions.
pub fn admit(
  source : @decode.Cursor,
  limits : @expression.Limits,
  max_work~ : Int,
) -> Result[Selector, Issue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let expression = match
    @expression.admit(source, {
      ..limits,
      max_nodes: Int::min(limits.max_nodes, max_work),
    }) {
    Ok(v) => v
    Err(e) => return Err(Expression(e))
  }
  let mut work = @expression.usage(expression).nodes
  let pending = [(@expression.tree(expression), Predicate)]
  while pending.pop() is Some((cursor, position)) {
    if work >= max_work {
      return Err(WorkLimit)
    }
    work += 1
    // Common syntax already guarantees a single closed tag/body pair.
    let (tag, body) = @decode.field_at(cursor, 0).unwrap()
    let allowed = match position {
      Operand => tag == "field" || tag == "literal" || tag == "$param"
      Predicate =>
        match tag {
          "eq"
          | "neq"
          | "lt"
          | "lte"
          | "gt"
          | "gte"
          | "in"
          | "not_in"
          | "like"
          | "contains"
          | "between" => {
            let count = @decode.array_length(body).unwrap()
            if count > max_work - work {
              return Err(WorkLimit)
            }
            work += count
            for i = count - 1; i >= 0; i = i - 1 {
              pending.push((@decode.element_at(body, i).unwrap(), Operand))
            }
            true
          }
          "and" | "or" => {
            let count = @decode.array_length(body).unwrap()
            if count > max_work - work {
              return Err(WorkLimit)
            }
            work += count
            for i = count - 1; i >= 0; i = i - 1 {
              pending.push((@decode.element_at(body, i).unwrap(), Predicate))
            }
            true
          }
          "not" | "is_null" | "not_null" => {
            if work == max_work {
              return Err(WorkLimit)
            }
            work += 1
            pending.push((body, if tag == "not" { Predicate } else { Operand }))
            true
          }
          _ => false
        }
    }
    if !allowed {
      return Err(
        RestrictedNode(tag, @expression.origin(expression, cursor).unwrap()),
      )
    }
  }
  Ok({ expression, work, })
}

///|
/// Retain common origin diagnostics and unbound Parameter occurrences.
pub fn expression(selector : Selector) -> @expression.Expression {
  selector.expression
}

///|
/// Includes common syntax's node work and the restricted traversal/edge work.
pub fn work(selector : Selector) -> Int {
  selector.work
}
