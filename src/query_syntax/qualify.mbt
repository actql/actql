///|
// Clause-owned window/aggregate calls use the same bounded parsed token stream.
// Private references are AST placeholders, not user aliases or execution slots.
fn QueryParser::qualify_expression(
  self : QueryParser,
) -> (Expression, Array[Projection], Array[(NamePart, AggregateCall)]) raise QueryAbort {
  let windows : Array[Projection] = []
  let calls : Array[(NamePart, AggregateCall)] = []
  let serial = [self.synthetic_sources]
  let syntax_nodes = [0]
  let limits = {
    ..self.limits.expression,
    max_nodes: self.limits.expression.max_nodes - self.expression_nodes,
    max_work: self.limits.expression.max_work.min(
      self.limits.max_work - self.work,
    ),
  }
  let primary = fn(
    index : Int,
    limits : ExpressionLimits,
  ) -> Result[(NamePart, Int, Int, Int)?, Diagnostic] {
    let parser : QueryParser = {
      source: self.source,
      limits: {
        ..self.limits,
        expression: limits,
        max_work: limits.max_work,
        max_syntax_nodes: self.limits.max_syntax_nodes -
        self.syntax_nodes -
        syntax_nodes[0],
      },
      index,
      work: 0,
      expression_nodes: 0,
      syntax_nodes: 0,
      source_depth: 0,
      synthetic_sources: serial[0],
      cte_scopes: [],
    }
    let window_head = match parser.peek().value {
      Word(name) =>
        [
          "ROW_NUMBER", "RANK", "DENSE_RANK", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
        ].contains(ascii_upper(name)) &&
        parser.source.tokens[index + 1].value == Symbol(40)
      _ => false
    }
    let aggregate_head = parser.aggregate_head()
    if !window_head && !aggregate_head {
      return Ok(None)
    }
    try {
      let (expression, aggregate) = if aggregate_head {
        (None, Some(parser.aggregate()))
      } else {
        (Some(parser.expression()), None)
      }
      let name = parser.fresh_producer("aql_qualify_call_")
      if parser.has("OVER") {
        let window = parser.over()
        windows.push({
          expression: None,
          aggregate: None,
          analytic: Some({ expression, aggregate, window, }),
          name: Some(name),
          star: None,
          except_columns: [],
          replacements: [],
        })
      } else if aggregate is Some(call) {
        calls.push((name, call))
      } else {
        raise QueryAbort(
          "QUALIFY window call requires OVER",
          parser.peek().start,
        )
      }
      serial[0] = parser.synthetic_sources
      syntax_nodes[0] += parser.syntax_nodes
      Ok(Some((name, parser.index, parser.work, parser.expression_nodes)))
    } catch {
      QueryExpression(error) => Err(error)
      QueryAbort(message, at) =>
        Err({
          issue: Syntax(message),
          span: Some(
            @origin.span(@origin.range(self.source.document, at, at).unwrap()),
          ),
        })
    }
  }
  match
    parse_fragment_resolved(self.source, self.index, limits, Some(primary)) {
    Ok((expression, next, embedded_nodes)) => {
      self.spend(expression.work)
      self.expression_nodes += expression.nodes.length() + embedded_nodes
      self.syntax_nodes += syntax_nodes[0]
      self.index = next
      self.synthetic_sources = serial[0]
      (expression, windows, calls)
    }
    Err(error) => raise QueryExpression(error)
  }
}
