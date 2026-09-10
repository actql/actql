///|
priv struct Node {
  source : @decode.Cursor
  tag : String
  body : @decode.Cursor
  children : Array[Int]
  names : Array[String]
  mut inferred : Int
  role : AnnotationRole
}

///|
priv enum Input {
  Form
  Literal
  MissingElse
  Membership
}

///|
priv struct Visit {
  source : @decode.Cursor
  input : Input
  parent : Int?
  depth : Int
}

///|
fn flatten(
  expression : @syntax.Expression,
  budget : Budget,
) -> Array[Node] raise Stop {
  let root = @syntax.tree(expression)
  let nodes : Array[Node] = []
  let work = [{ source: root, input: Form, parent: None, depth: 0, }]
  while work.pop() is Some(visit) {
    spend(budget, visit.source)
    if nodes.length() >= budget.limits.max_nodes ||
      visit.depth > budget.limits.max_depth {
      fail(visit.source, BudgetExceeded)
    }
    let (tag, body) = match visit.input {
      Literal => ("literal", visit.source)
      MissingElse => ("#null", visit.source)
      Form | Membership => {
        let names = decoded(
          @decode.object_field_names(visit.source),
          visit.source,
        )
        if names.length() != 1 {
          fail(visit.source, TypeMismatch("admitted expression"))
        }
        (names[0], part(visit.source, names[0]))
      }
    }
    charge(budget, visit.source, tag)
    let id = nodes.length()
    let node : Node = {
      source: visit.source,
      tag,
      body,
      children: [],
      names: [],
      inferred: -1,
      role: if visit.input is MissingElse {
        ImplicitElse
      } else if visit.parent is Some(parent) && nodes[parent].tag == "#in_list" {
        MembershipElement
      } else if visit.input is Membership && tag == "literal" {
        MembershipList
      } else {
        ExpressionNode
      },
    }
    nodes.push(node)
    if visit.parent is Some(parent) {
      nodes[parent].children.push(id)
    }
    let children : Array[(@decode.Cursor, Input)] = []
    match tag {
      "field"
      | "$param"
      | "literal"
      | "template"
      | "#null"
      | "join_field"
      | "empty_array" => ()
      "cast"
      | "property"
      | "subscript"
      | "try_decimal"
      | "quantize"
      | "decimal_divide"
      | "split_part"
      | "substring"
      | "utf8_truncate"
      | "try_number"
      | "parse_timestamp"
      | "try_timestamp"
      | "format_timestamp"
      | "regex_match"
      | "regex_extract"
      | "regex_replace"
      | "vector_score" => {
        let names = match tag {
          "decimal_divide" | "vector_score" => ["left", "right"]
          "subscript" => ["value", "index"]
          "split_part" => ["value", "delimiter", "index"]
          "substring" => ["value", "start", "length"]
          "utf8_truncate" => ["value", "max_bytes"]
          "regex_extract" => ["value", "pattern", "capture"]
          "regex_replace" => ["value", "pattern", "replacement"]
          "parse_timestamp"
          | "try_timestamp"
          | "format_timestamp"
          | "regex_match" => ["value", "pattern"]
          _ => ["value"]
        }
        for name in names {
          children.push((part(body, name), Form))
        }
      }
      "case" => {
        let clauses = decoded(@decode.elements(part(body, "when")), body)
        spend(budget, body, amount=clauses.length())
        for clause in clauses {
          children.push((part(clause, "when"), Form))
          children.push((part(clause, "then"), Form))
        }
        let obj = decoded(@decode.open_object(body), body)
        match @decode.lookup(obj, "else") {
          Some(otherwise) => children.push((otherwise, Form))
          None => children.push((body, MissingElse))
        }
      }
      "object" => {
        let names = decoded(@decode.object_field_names(body), body)
        spend(budget, body, amount=names.length())
        let obj = decoded(@decode.open_object(body), body)
        for name in names {
          charge(budget, body, name)
          node.names.push(name)
          children.push((@decode.lookup(obj, name).unwrap(), Form))
        }
      }
      "in" | "not_in" => {
        let args = decoded(@decode.elements(body), body)
        children.push((args[0], Form))
        children.push((args[1], Membership))
      }
      "negate"
      | "not"
      | "is_null"
      | "not_null"
      | "is_true"
      | "is_false"
      | "is_unknown"
      | "len"
      | "sqrt"
      | "floor"
      | "lower"
      | "upper"
      | "trim"
      | "nfkc"
      | "case_fold" => children.push((body, Form))
      _ =>
        for child in decoded(@decode.elements(body), body) {
          children.push((child, Form))
        }
    }
    // IN's immediate literal list has scalar values and Parameter holes, not
    // arbitrary expression children and not a generic JSON array type.
    let in_list = visit.input is Membership && tag == "literal"
    if in_list {
      let values = decoded(@decode.elements(body), body)
      for value in values {
        let input = match @decode.view(value) {
          ObjectValue(_) => Form
          _ => Literal
        }
        children.push((value, input))
      }
      // Tag stored separately from the admitted source; source remains intact.
      nodes[id] = { ..node, tag: "#in_list", }
    }
    if children.length() >
      budget.limits.max_nodes - nodes.length() - work.length() {
      fail(visit.source, BudgetExceeded)
    }
    spend(budget, visit.source, amount=children.length())
    for i = children.length() - 1; i >= 0; i = i - 1 {
      work.push({
        source: children[i].0,
        input: children[i].1,
        parent: Some(id),
        depth: visit.depth + 1,
      })
    }
  }
  nodes
}

///|
priv struct Scopes {
  fields : Map[String, Int]
  left : Map[String, Int]?
  right : Map[String, Int]?
  parameters : Map[String, Int]
}

///|
fn scope(
  t : Types,
  contract : @contract.Contract?,
  name : String,
  source : @decode.Cursor,
) -> Map[String, Int]? raise Stop {
  match contract {
    None => None
    Some(c) => {
      if c.nullable {
        fail(source, InvalidScope(name))
      }
      let id = import_type(t, c, source)
      match t.entries[id].kind {
        Product(fields) => {
          let map : Map[String, Int] = Map([])
          for (name, id) in fields {
            spend(t.budget, source)
            map[name] = id
          }
          Some(map)
        }
        _ => fail(source, InvalidScope(name))
      }
    }
  }
}

///|
fn scopes(
  t : Types,
  env : Environment,
  source : @decode.Cursor,
) -> Scopes raise Stop {
  let fields = scope(t, env.fields, "fields", source).unwrap_or(Map([]))
  let left = scope(t, env.left, "left", source)
  let right = scope(t, env.right, "right", source)
  let parameters : Map[String, Int] = Map([])
  if env.parameters is Some(declarations) {
    let count = @parameter.declaration_count(declarations)
    spend(t.budget, source, amount=count)
    for i in 0..<count {
      let declaration = @parameter.declaration_at(declarations, i).unwrap()
      spend(t.budget, source)
      charge(t.budget, source, declaration.name)
      parameters[declaration.name] = import_type(
        t,
        declaration.parameter_type.contract,
        source,
      )
    }
  }
  { fields, left, right, parameters, }
}
