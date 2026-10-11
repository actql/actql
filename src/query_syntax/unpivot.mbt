///|
fn QueryParser::unpivot_clause(
  self : QueryParser,
) -> UnpivotClause raise QueryAbort {
  let start = self.peek().start
  self.keyword("UNPIVOT")
  let include_nulls = if self.has("INCLUDE") {
    self.keyword("INCLUDE")
    self.keyword("NULLS")
    true
  } else {
    if self.has("EXCLUDE") {
      self.keyword("EXCLUDE")
      self.keyword("NULLS")
    }
    false
  }
  self.symbol(40)
  let value_column = self.name()
  self.keyword("FOR")
  let name_column = self.name()
  self.keyword("IN")
  self.symbol(40)
  let columns : Array[NamePart] = []
  let row_labels : Array[UnpivotRowLabel?] = []
  while true {
    self.node()
    columns.push(self.name())
    let explicit = self.has("AS")
    if explicit {
      self.keyword("AS")
    }
    let label = if explicit ||
      self.peek().value is Text(_) ||
      self.peek().value is Numeric(_) {
      let expression = self.expression()
      let node = expression_node(expression, expression_root(expression)).unwrap()
      match node.kind {
        StringLiteral(value) => Some(TextLabel(value))
        Number(value) => {
          for index in 0..<value.length() {
            if value[index] < '0' || value[index] > '9' {
              raise QueryAbort(
                "UNPIVOT row alias requires a String or integer literal",
                node.start,
              )
            }
          }
          Some(IntegerLabel(value))
        }
        _ =>
          raise QueryAbort(
            "UNPIVOT row alias requires a String or integer literal",
            node.start,
          )
      }
    } else {
      None
    }
    row_labels.push(label)
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  self.symbol(41)
  self.symbol(41)
  if row_labels.any(label => label is Some(IntegerLabel(_))) &&
    !row_labels.all(label => label is Some(IntegerLabel(_))) {
    raise QueryAbort(
      "Integer UNPIVOT row aliases must be specified for every column with the same type",
      start,
    )
  }
  { columns, row_labels, value_column, name_column, include_nulls, }
}
