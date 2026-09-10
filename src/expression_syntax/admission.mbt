///|
fn read(root : @decode.Cursor, limits : Limits) -> Expression raise Stop {
  if limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_tokens < 0 ||
    limits.tree.max_nodes < 0 ||
    limits.tree.max_depth < 0 ||
    limits.tree.max_string_bytes < 0 ||
    limits.tree.max_total_string_bytes < 0 {
    invalid(root, Authored, InvalidLimits)
  }
  let budget : Budget = {
    nodes: limits.max_nodes,
    scheduled: 1,
    bytes: limits.max_text_bytes,
    tokens: limits.max_tokens,
    references: [],
    field_indices: [],
    relation_references: [],
  }
  let work : Array[Work] = [Visit(root, Expr, Authored, 0)]
  let values : Array[Node] = []
  while !work.is_empty() {
    match work.pop().unwrap() {
      Finish(cursor, role, origin, count, names) => {
        let children = []
        for i = 0; i < count; i = i + 1 {
          children.push(values.pop().unwrap())
        }
        let result = match names {
          None =>
            node(
              @map.Array(Array::makei(count, i => children[count - 1 - i])),
              cursor,
              origin,
            )
          Some(names) => {
            let object = decoded(@decode.open_object(cursor), origin)
            node(
              @map.Object(
                Array::makei(count, i => {
                  let child = @decode.lookup(object, names[i]).unwrap()
                  {
                    key: names[i],
                    key_span: @decode.cursor_key_span(child).unwrap(),
                    value: children[count - 1 - i],
                  }
                }),
              ),
              cursor,
              origin,
            )
          }
        }
        values.push(finish(result, role, cursor, origin, budget))
      }
      Visit(cursor, initial_role, origin, depth) => {
        budget.scheduled -= 1
        if budget.nodes <= 0 || depth > limits.max_depth {
          invalid(cursor, origin, BudgetExceeded)
        }
        budget.nodes -= 1
        let mut role = initial_role
        let value = @decode.view(cursor)
        if (role is Expr || role is InRight) &&
          value is @decode.TextValue(source) {
          let expression = match
            @text.parse(
              source,
              {
                max_input_bytes: budget.bytes,
                max_nodes: budget.nodes - budget.scheduled,
                max_tokens: budget.tokens,
                max_depth: limits.max_depth - depth,
                tree: limits.tree,
              },
              enclosing_span=@decode.cursor_span(cursor),
            ) {
            Ok(expression) => expression
            Err(issue) =>
              raise Stop({
                kind: Text(issue.kind),
                path: @decode.cursor_path(cursor),
                span: @decode.cursor_span(cursor),
                range: Some(issue.range),
              })
          }
          let usage = @text.usage(expression)
          budget.nodes -= usage.nodes
          budget.bytes -= usage.input_bytes
          budget.tokens -= usage.tokens
          for r in @text.parameter_references(expression) {
            budget.references.push({
              name: r.name,
              location: { source: cursor, range: Some(r.range), },
            })
          }
          for r in @text.relation_references(expression) {
            let qualified = r.name.has_prefix("left.") ||
              r.name.has_prefix("right.")
            let name = if qualified {
              let parts = r.name.split(".").to_array()
              parts[0].to_owned() + "." + parts[1].to_owned()
            } else {
              r.name
            }
            if !qualified {
              budget.field_indices.push(budget.relation_references.length())
            }
            budget.relation_references.push({
              name,
              location: { source: cursor, range: Some(r.range), },
            })
          }
          if budget.nodes <= budget.scheduled {
            invalid(cursor, origin, BudgetExceeded)
          }
          budget.scheduled += 1
          work.push(
            Visit(
              @text.tree(expression),
              role,
              TextDecoded(cursor, expression),
              depth,
            ),
          )
          continue
        }
        if role is ItemContract {
          match
            @contract.read_author(cursor, {
              max_nodes: budget.nodes - budget.scheduled + 1,
              max_depth: limits.max_depth - depth,
              max_text_bytes: budget.bytes,
            }) {
            Ok(_) => ()
            Err(_) => invalid(cursor, origin, InvalidItemContract)
          }
          role = Data
        }
        if role is InItem {
          if value is @decode.ObjectValue(_) {
            let view = closed(cursor, origin, ["$param"], ["$param"])
            let name = decoded(
              @decode.text(decoded(@decode.required(view, "$param"), origin)),
              origin,
            )
            if !parameter_name(name) {
              invalid(cursor, origin, InvalidName(name))
            }
            role = Expr
          } else if value is @decode.ArrayValue(_) {
            invalid(cursor, origin, InvalidArguments)
          } else {
            role = Data
          }
        }
        match value {
          @decode.ObjectValue(object) => {
            let names = decoded(@decode.object_field_names(cursor), origin)
            if names.length() > budget.nodes - budget.scheduled {
              invalid(cursor, origin, BudgetExceeded)
            }
            let roles : Array[Role] = []
            match role {
              Expr | InRight => {
                if names.length() != 1 {
                  invalid(cursor, origin, InvalidExpression)
                }
                let tag = names[0]
                if role is InRight && tag != "literal" && tag != "$param" {
                  invalid(cursor, origin, InvalidArguments)
                }
                roles.push(
                  if role is InRight && tag == "literal" {
                    InList
                  } else {
                    expression_role(tag, cursor, origin)
                  },
                )
                if tag == "$param" {
                  let body = decoded(@decode.required(object, tag), origin)
                  let name = decoded(@decode.text(body), origin)
                  if !parameter_name(name) {
                    invalid(body, origin, InvalidName(name))
                  }
                  if origin is Authored {
                    budget.references.push({
                      name,
                      location: location(cursor, origin),
                    })
                  }
                }
              }
              Body(tag) => {
                let (required, allowed) = body_fields(tag)
                ignore(closed(cursor, origin, required, allowed))
                for name in names {
                  roles.push(body_role(tag, name))
                }
              }
              ObjectFields => {
                if names.is_empty() {
                  invalid(cursor, origin, InvalidArguments)
                }
                for name in names {
                  if !field_name(name) {
                    invalid(cursor, origin, InvalidName(name))
                  }
                  roles.push(Expr)
                }
              }
              Branch => {
                ignore(
                  closed(cursor, origin, ["when", "then"], ["when", "then"]),
                )
                for _ in names {
                  roles.push(Expr)
                }
              }
              CastTarget => {
                let type_cursor = decoded(
                  @decode.required(object, "type"),
                  origin,
                )
                let name = decoded(@decode.text(type_cursor), origin)
                let fields = if name == "decimal" {
                  ["type", "precision", "scale"]
                } else {
                  ["type"]
                }
                if !["number", "string", "boolean", "timestamp", "decimal"].contains(
                    name,
                  ) {
                  invalid(type_cursor, origin, InvalidArguments)
                }
                ignore(closed(cursor, origin, fields, fields))
                for _ in names {
                  roles.push(Data)
                }
              }
              Data =>
                for _ in names {
                  roles.push(Data)
                }
              _ => invalid(cursor, origin, InvalidArguments)
            }
            for name in names {
              charge(name, cursor, origin, budget)
              canonical(name, cursor, origin)
            }
            work.push(Finish(cursor, role, origin, names.length(), Some(names)))
            budget.scheduled += names.length()
            for i = names.length() - 1; i >= 0; i = i - 1 {
              work.push(
                Visit(
                  @decode.lookup(object, names[i]).unwrap(),
                  roles[i],
                  origin,
                  depth + 1,
                ),
              )
            }
          }
          @decode.ArrayValue(children) => {
            if children.length() > budget.nodes - budget.scheduled {
              invalid(cursor, origin, BudgetExceeded)
            }
            match role {
              Arguments(tag) => arity(tag, children.length(), cursor, origin)
              Branches =>
                if children.is_empty() {
                  invalid(cursor, origin, InvalidArguments)
                }
              Data | InList => ()
              _ => invalid(cursor, origin, InvalidArguments)
            }
            work.push(Finish(cursor, role, origin, children.length(), None))
            budget.scheduled += children.length()
            for i = children.length() - 1; i >= 0; i = i - 1 {
              let child_role = match role {
                Arguments("in" | "not_in") if i == 1 => InRight
                Arguments(_) => Expr
                Branches => Branch
                InList => InItem
                _ => Data
              }
              work.push(Visit(children[i], child_role, origin, depth + 1))
            }
          }
          _ => {
            if !(role is Data) {
              invalid(cursor, origin, InvalidArguments)
            }
            let scalar = match value {
              @decode.NullValue => @map.Null
              @decode.BoolValue(b) => @map.Bool(b)
              @decode.NumberValue(n) => {
                if n.is_nan() || n.is_inf() || (n == 0.0 && 1.0 / n < 0.0) {
                  invalid(cursor, origin, InvalidNumber)
                }
                @map.Number(n)
              }
              @decode.TextValue(text) => {
                charge(text, cursor, origin, budget)
                canonical(text, cursor, origin)
                @map.String(text)
              }
              _ => invalid(cursor, origin, InvalidArguments)
            }
            values.push(node(scalar, cursor, origin))
          }
        }
      }
    }
  }
  let (cursor, origins) = decoded(
    @map.admit(values.pop().unwrap(), limits.tree),
    Authored,
  )
  {
    cursor,
    origins,
    references: budget.references,
    field_indices: budget.field_indices,
    relation_references: budget.relation_references,
    usage: {
      nodes: limits.max_nodes - budget.nodes,
      text_bytes: limits.max_text_bytes - budget.bytes,
      tokens: limits.max_tokens - budget.tokens,
    },
  }
}

///|
/// Admit one general Expression position. This is syntax admission, not type
/// checking, evaluation, profile admission, or whole-Program reference analysis.
pub fn admit(
  root : @decode.Cursor,
  limits : Limits,
) -> Result[Expression, Issue] {
  Ok(read(root, limits)) catch {
    Stop(issue) => Err(issue)
  }
}
