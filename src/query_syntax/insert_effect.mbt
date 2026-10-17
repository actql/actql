///|
pub(all) struct InsertEffectClause {
  name : NamePart?
  target : UpdateEffectTarget
  mapping : NamePart?
  fields : Array[NamePart]
  values : Array[Expression]?
}

///|
pub fn terminal_insert_effect(query : Query) -> InsertEffectClause? {
  query.insert_effect.map(clause => {
    ..clause,
    target: match clause.target {
      ConcreteTarget(value) => ConcreteTarget(value)
      LogicalTarget(path) => LogicalTarget(path.copy())
    },
    fields: clause.fields.copy(),
    values: clause.values.map(values => values.copy()),
  })
}

///|
fn QueryParser::effect_is_insert(self : QueryParser) -> Bool {
  guard token_at(self.source, self.index + 1) is Some(first) &&
    token_at(self.source, self.index + 2) is Some(second) else {
    return false
  }
  let third = token_at(self.source, self.index + 3)
  if third.map(token => token.value != Symbol(46)).unwrap_or(false) &&
    (
      keyword(second, "UPDATE") ||
      keyword(second, "UPSERT") ||
      keyword(second, "DELETE") ||
      keyword(second, "INSERT") ||
      keyword(second, "CREATE") ||
      keyword(second, "STORE") ||
      keyword(second, "COMMAND")
    ) {
    return keyword(second, "INSERT")
  }
  keyword(first, "INSERT")
}

///|
fn QueryParser::insert_effect_clause(
  self : QueryParser,
) -> InsertEffectClause raise QueryAbort {
  self.node()
  self.keyword("EFFECT")
  let name = if self.has("INSERT") &&
    !(token_at(self.source, self.index + 1)
    .map(token => keyword(token, "INSERT"))
    .unwrap_or(false) &&
    token_at(self.source, self.index + 2)
    .map(token => token.value != Symbol(46))
    .unwrap_or(false)) {
    None
  } else {
    Some(self.name())
  }
  self.keyword("INSERT")
  let (target, mapping) = self.record_effect_target()
  self.symbol(40)
  let fields : Array[NamePart] = []
  while true {
    self.node()
    let at = self.peek().start
    let field = self.name()
    if fields.any(previous => same_binding_name(previous, field)) {
      raise QueryAbort("Duplicate INSERT field", at)
    }
    fields.push(field)
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  self.symbol(41)
  let values = if self.has("VALUES") {
    self.keyword("VALUES")
    self.symbol(40)
    let values = [self.expression()]
    while self.peek().value == Symbol(44) {
      ignore(self.advance())
      values.push(self.expression())
    }
    self.symbol(41)
    if values.length() != fields.length() {
      raise QueryAbort(
        "INSERT fields and VALUES require equal arity",
        self.peek().start,
      )
    }
    Some(values)
  } else {
    None
  }
  { name, target, mapping, fields, values, }
}
