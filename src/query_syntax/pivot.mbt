///|
fn QueryParser::pivot_clause(
  self : QueryParser,
) -> PivotClause raise QueryAbort {
  self.keyword("PIVOT")
  self.symbol(40)
  let function_name = self.name().value.to_upper()
  if !["SUM", "AVG", "COUNT", "MIN", "MAX"].contains(function_name) {
    raise QueryAbort("Unsupported PIVOT aggregate", self.peek().start)
  }
  self.symbol(40)
  let count_star = self.peek().value == Symbol(42)
  let (argument, argument_expression) = if count_star {
    if function_name != "COUNT" {
      raise QueryAbort("Only COUNT accepts PIVOT star", self.peek().start)
    }
    self.symbol(42)
    ([], None)
  } else {
    let expression = self.expression()
    for index in 0..<expression_node_count(expression) {
      let node = expression_node(expression, index).unwrap()
      if node.kind is Call(name, _) &&
        name.length() == 1 &&
        query_aggregate_function_name(name[0].value) {
        raise QueryAbort(
          "PIVOT argument cannot contain an aggregate",
          node.start,
        )
      }
    }
    match
      expression_node(expression, expression_root(expression)).unwrap().kind {
      Reference(path) => (path, Some(expression))
      _ => ([], Some(expression))
    }
  }
  self.symbol(41)
  let prefix = self.optional_output_alias()
  self.keyword("FOR")
  let column = self.path()
  self.keyword("IN")
  self.symbol(40)
  let values : Array[(String, NamePart?)] = []
  while true {
    self.node()
    let expression = self.expression()
    let mut value_root = expression_root(expression)
    while expression_node(expression, value_root).unwrap().kind
          is Parenthesized(child) {
      value_root = child
    }
    guard expression_node(expression, value_root).unwrap().kind
      is StringLiteral(value) else {
      raise QueryAbort(
        "PIVOT currently requires constant String values",
        self.peek().start,
      )
    }
    values.push((value, self.optional_output_alias()))
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  self.symbol(41)
  self.symbol(41)
  {
    function_name,
    count_star,
    argument,
    argument_expression,
    column,
    prefix,
    values,
  }
}
