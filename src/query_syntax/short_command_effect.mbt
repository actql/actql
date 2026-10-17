///|
/// Authored operation selection only. The Catalog and installed owners still
/// resolve the operation, target policy and original input-key correspondence.
pub(all) struct ShortCommandEffectClause {
  name : NamePart?
  operation : Array[NamePart]
  target : Expression?
  id : Array[NamePart]
  id_expression : Expression
  input : Array[(NamePart, Expression)]
  start : Int
  end : Int
}

///|
pub fn terminal_short_command_effect(
  query : Query,
) -> ShortCommandEffectClause? {
  query.short_command_effect.map(clause => {
    ..clause,
    operation: clause.operation.copy(),
    id: clause.id.copy(),
    input: clause.input.copy(),
  })
}

///|
fn QueryParser::effect_is_short_command(self : QueryParser) -> Bool {
  guard token_at(self.source, self.index + 1) is Some(first) &&
    token_at(self.source, self.index + 2) is Some(second) else {
    return false
  }
  let third = token_at(self.source, self.index + 3)
  if third.map(token => token.value != Symbol(46)).unwrap_or(false) &&
    (
      keyword(second, "UPDATE") ||
      keyword(second, "CREATE") ||
      keyword(second, "STORE") ||
      keyword(second, "COMMAND")
    ) {
    return keyword(second, "COMMAND")
  }
  keyword(first, "COMMAND")
}

///|
fn QueryParser::short_command_effect_clause(
  self : QueryParser,
) -> ShortCommandEffectClause raise QueryAbort {
  self.node()
  let start = self.peek().start
  self.keyword("EFFECT")
  let name = if self.has("COMMAND") &&
    !(token_at(self.source, self.index + 1)
    .map(token => keyword(token, "COMMAND"))
    .unwrap_or(false) &&
    token_at(self.source, self.index + 2)
    .map(token => token.value != Symbol(46))
    .unwrap_or(false)) {
    None
  } else {
    Some(self.binding_name())
  }
  self.keyword("COMMAND")
  let operation = self.path()
  let target = if self.has("TARGET") {
    self.keyword("TARGET")
    Some(self.expression())
  } else {
    None
  }
  self.keyword("ID")
  let id_start = self.peek().start
  let id_expression = self.expression()
  let id = match
    expression_node(id_expression, expression_root(id_expression)).unwrap().kind {
    Reference(parts) => parts.copy()
    _ => raise QueryAbort("COMMAND ID requires a field path", id_start)
  }
  let input : Array[(NamePart, Expression)] = []
  if self.has("INPUT") {
    self.keyword("INPUT")
    self.symbol(40)
    if self.peek().value != Symbol(41) {
      while true {
        self.node()
        let field = self.name()
        if input.any(entry => same_binding_name(entry.0, field)) {
          raise QueryAbort("Duplicate COMMAND input field", self.peek().start)
        }
        self.symbol(61)
        input.push((field, self.expression()))
        if self.peek().value != Symbol(44) {
          break
        }
        ignore(self.advance())
      }
    }
    self.symbol(41)
  }
  let end = token_at(self.source, self.index - 1).unwrap().end
  { name, operation, target, id, id_expression, input, start, end, }
}
