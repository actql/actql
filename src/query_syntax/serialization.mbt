///|
/// Authored ordering and static profile options, not a checked byte profile or
/// permission to issue a ContentRef. Common Program owners resolve both.
pub(all) struct SerializeClause {
  format : String
  order_by : Array[SortTerm]
  preserve_order : Bool
  options : Array[(NamePart, Expression)]
}

///|
fn QueryParser::serialize_clause(
  self : QueryParser,
) -> SerializeClause raise QueryAbort {
  self.node()
  self.keyword("SERIALIZE")
  self.keyword("FORMAT")
  let token = self.advance()
  let format = match token.value {
    Word(name) if ["csv", "jsonl"].contains(name.to_lower()) => name.to_lower()
    _ => raise QueryAbort("Expected CSV or JSONL format", token.start)
  }
  let preserve_order = self.has("PRESERVE")
  let order_by = if preserve_order {
    self.keyword("PRESERVE")
    self.keyword("ORDER")
    []
  } else {
    self.keyword("ORDER")
    self.keyword("BY")
    self.order()
  }
  self.keyword("OPTIONS")
  self.symbol(40)
  let options : Array[(NamePart, Expression)] = []
  while self.peek().value != Symbol(41) {
    self.node()
    let at = self.peek().start
    let name = self.name()
    let key = name.value.to_lower()
    if name.quoted ||
      ![
        "name", "header", "null_marker", "field_delimiter", "encoding", "line_ending",
        "max_rows", "max_bytes",
      ].contains(key) {
      raise QueryAbort("Unknown SERIALIZE option", at)
    }
    if options.any(option => option.0.value == key) {
      raise QueryAbort("Duplicate SERIALIZE option", at)
    }
    self.symbol(61)
    options.push(({ value: key, quoted: false, }, self.expression()))
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
    if self.peek().value == Symbol(41) {
      raise QueryAbort("Expected SERIALIZE option", self.peek().start)
    }
  }
  self.symbol(41)
  { format, order_by, preserve_order, options, }
}
