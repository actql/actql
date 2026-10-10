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
  let argument = self.path()
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
    guard expression_node(expression, expression_root(expression)).unwrap().kind
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
  { function_name, argument, column, prefix, values, }
}
