///|
// Existing explicit/logical record target syntax, shared without extra parser
// work or any installation/Mapping inference.
fn QueryParser::record_effect_target(
  self : QueryParser,
) -> (UpdateEffectTarget, NamePart?) raise QueryAbort {
  if self.has("TARGET") &&
    !token_at(self.source, self.index + 1)
    .map(token => token.value == Symbol(46))
    .unwrap_or(false) {
    self.keyword("TARGET")
    let expression = self.expression()
    let target = match
      expression_node(expression, expression_root(expression)).unwrap().kind {
      StringLiteral(value) => value
      _ =>
        raise QueryAbort(
          "Effect TARGET requires a string literal",
          self.peek().start,
        )
    }
    self.keyword("MAPPING")
    (ConcreteTarget(target), Some(self.name()))
  } else {
    let path = self.path()
    if path.length() < 2 {
      raise QueryAbort(
        "Effect logical target requires a qualified name",
        self.peek().start,
      )
    }
    let mapping = if self.has("MAPPING") {
      self.keyword("MAPPING")
      Some(self.name())
    } else {
      None
    }
    (LogicalTarget(path), mapping)
  }
}
