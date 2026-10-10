///|
fn QueryParser::unpivot_clause(
  self : QueryParser,
) -> UnpivotClause raise QueryAbort {
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
  while true {
    self.node()
    columns.push(self.name())
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  self.symbol(41)
  self.symbol(41)
  { columns, value_column, name_column, include_nulls, }
}
