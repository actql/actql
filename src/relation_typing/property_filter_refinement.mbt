///|
// A true strict comparison cannot have a NULL operand. Retain only direct
// checked property paths; no function result, literal, parameter or outcome
// spelling can supply an object-field proof.
fn filter_property_path(
  b : Budget,
  source : @decode.Cursor,
  expression : @typing.TypedExpression,
  start : Int,
) -> (String, Array[String])? raise Stop {
  let path : Array[String] = []
  let mut index = start
  while true {
    spend(b, source)
    match @typing.node_form(expression, index) {
      Some(Expression("property", body)) => {
        let object = @decode.open_object(body).unwrap()
        let name = @decode.text(@decode.lookup(object, "name").unwrap()).unwrap()
        charge(b, source, name)
        path.push(name)
        index = @typing.child_at(expression, index, 0).unwrap()
      }
      Some(Expression("field", body)) if !path.is_empty() => {
        let name = @decode.text(body).unwrap()
        charge(b, source, name)
        spend(b, source, count=path.length())
        for i in 0..<(path.length() / 2) {
          let j = path.length() - 1 - i
          let saved = path[i]
          path[i] = path[j]
          path[j] = saved
        }
        return Some((name, path))
      }
      _ => return None
    }
  }
  None
}

///|
// Rebuild only the declared Object path. All sibling fields and their types
// survive. A NULL receiver propagates NULL through property evaluation, so a
// non-NULL leaf proves each receiver on this same original path non-NULL.
fn filter_nonnull_object_path(
  b : Budget,
  source : @decode.Cursor,
  original : @contract.Contract,
  path : Array[String],
) -> @contract.Contract raise Stop {
  let parents : Array[(@contract.Fields, String)] = []
  let mut current = original
  for name in path {
    spend(b, source)
    guard current.shape is @contract.Object(fields) else { return original }
    let count = @contract.field_count(fields)
    spend(b, source, count~)
    let mut child : @contract.Contract? = None
    for index in 0..<count {
      let field = @contract.field_at(fields, index).unwrap()
      charge(b, source, field.name)
      if field.name == name {
        child = Some(field.contract)
      }
    }
    guard child is Some(value) else { return original }
    parents.push((fields, name))
    current = value
  }
  if b.nodes == 0 {
    fail(source, BudgetExceeded)
  }
  b.nodes -= 1
  let mut refined = @contract.with_nullability(current, false)
  while parents.pop() is Some((fields, name)) {
    let count = @contract.field_count(fields)
    spend(b, source, count~)
    let declarations : Array[(String, @contract.Contract)] = []
    for index in 0..<count {
      let field = @contract.field_at(fields, index).unwrap()
      charge(b, source, field.name)
      declarations.push(
        (field.name, if field.name == name { refined } else { field.contract }),
      )
    }
    if b.nodes == 0 {
      fail(source, BudgetExceeded)
    }
    b.nodes -= 1
    refined = @contract.object_contract(
      declarations,
      nullable=false,
      max_fields=count,
      max_name_bytes=@contract.field_name_bytes(fields),
    ).unwrap()
  }
  refined
}

///|
fn filter_property_schema(
  b : Budget,
  source : @decode.Cursor,
  input : @schema.Schema,
  expression : @typing.TypedExpression,
) -> @schema.Schema raise Stop {
  let predicates = [0]
  let paths : Array[(String, Array[String])] = []
  while predicates.pop() is Some(index) {
    spend(b, source)
    match @typing.node_form(expression, index) {
      Some(Expression("and", _)) => {
        let count = @typing.child_count(expression, index).unwrap()
        spend(b, source, count~)
        for child in 0..<count {
          predicates.push(@typing.child_at(expression, index, child).unwrap())
        }
      }
      Some(Expression("eq" | "neq" | "lt" | "lte" | "gt" | "gte", _)) => {
        let count = @typing.child_count(expression, index).unwrap()
        spend(b, source, count~)
        for child in 0..<count {
          if filter_property_path(
              b,
              source,
              expression,
              @typing.child_at(expression, index, child).unwrap(),
            )
            is Some(path) {
            paths.push(path)
          }
        }
      }
      // OR, NOT, CASE, null-safe comparison and computed receivers do not
      // establish this conjunctive proof. Every branch was still type checked.
      _ => ()
    }
  }
  if paths.is_empty() {
    return input
  }
  let fields : Array[(@schema.FieldName, @contract.Contract, @schema.Presence)] = []
  let count = @schema.field_count(input)
  spend(b, source, count~)
  let bytes = b.text
  for index in 0..<count {
    let field = @schema.field_at(input, index).unwrap()
    let name = @schema.reference_name(field.name)
    charge(b, source, name)
    let mut contract = field.contract
    spend(b, source, count=paths.length())
    for (root, path) in paths {
      if root == name {
        contract = filter_nonnull_object_path(b, source, contract, path)
      }
    }
    fields.push((field.name, contract, field.presence))
  }
  @schema.from_presence_fields(fields, max_fields=count, max_name_bytes=bytes).unwrap()
}
