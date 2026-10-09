///|
// Named windows are query-local specifications, never Relation producers.
fn QueryParser::window_reference(
  self : QueryParser,
) -> (NamePart, Int) raise QueryAbort {
  let at = self.peek().start
  self.node()
  (self.name(), at)
}

///|
fn QueryParser::window_specification(
  self : QueryParser,
  calls? : Array[(NamePart, AggregateCall)]? = None,
  aggregate_prefix? : String = "aql_window_aggregate_",
) -> AnalyticWindow raise QueryAbort {
  if self.peek().value != Symbol(40) {
    return {
      reference: Some(self.window_reference()),
      partition_by: [],
      order_by: [],
      frame: None,
    }
  }
  self.symbol(40)
  let reference = match self.peek().value {
    Word(_) | QuotedName(_) if !self.has("PARTITION") &&
      !self.has("ORDER") &&
      !self.has("ROWS") &&
      !self.has("RANGE") &&
      !self.has("GROUPS") => Some(self.window_reference())
    _ => None
  }
  let partition_by : Array[Expression] = []
  if self.has("PARTITION") {
    self.keyword("PARTITION")
    self.keyword("BY")
    while true {
      partition_by.push(
        match calls {
          Some(outputs) => {
            let (expression, embedded) = self.aggregate_expression(
              aggregate_prefix,
            )
            outputs.append(embedded)
            expression
          }
          None => self.expression()
        },
      )
      if self.peek().value != Symbol(44) {
        break
      }
      ignore(self.advance())
    }
  }
  let order_by = if self.has("ORDER") {
    self.keyword("ORDER")
    self.keyword("BY")
    self.order(calls~, aggregate_prefix~)
  } else {
    []
  }
  let frame = if self.has("ROWS") {
    self.keyword("ROWS")
    if self.has("BETWEEN") {
      self.keyword("BETWEEN")
      let start = self.frame_boundary()
      self.keyword("AND")
      let end = self.frame_boundary()
      Some({ start, end, })
    } else {
      // GoogleSQL's single-boundary frame ends at CURRENT ROW. Keep interval
      // and bound-parameter validation in the existing common frame checker.
      Some({ start: self.frame_boundary(), end: CurrentRow, })
    }
  } else {
    None
  }
  self.symbol(41)
  { reference, partition_by, order_by, frame, }
}

///|
fn QueryParser::resolve_window(
  self : QueryParser,
  window : AnalyticWindow,
  definitions : Array[(NamePart, AnalyticWindow)],
) -> AnalyticWindow raise QueryAbort {
  guard window.reference is Some((name, at)) else { return window }
  let mut inherited : AnalyticWindow? = None
  for (candidate, definition) in definitions {
    self.spend(1)
    if same_cte_name(candidate, name) {
      inherited = Some(definition)
      break
    }
  }
  guard inherited is Some(base) else {
    raise QueryAbort("Unknown named window", at)
  }
  // These constraints also apply to inheritance between WINDOW definitions.
  // The selected GoogleSQL resolver checks declarations in source order.
  if !window.partition_by.is_empty() {
    raise QueryAbort("Named window cannot be combined with PARTITION BY", at)
  }
  if !window.order_by.is_empty() && !base.order_by.is_empty() {
    raise QueryAbort("Duplicate named window ORDER BY", at)
  }
  if base.frame is Some(_) &&
    (!window.order_by.is_empty() || window.frame is Some(_)) {
    raise QueryAbort("Cannot extend a framed named window", at)
  }
  self.spend(base.partition_by.length() + base.order_by.length())
  {
    reference: None,
    partition_by: base.partition_by.copy(),
    order_by: if window.order_by.is_empty() {
      base.order_by.copy()
    } else {
      window.order_by
    },
    frame: match window.frame {
      Some(_) => window.frame
      None => base.frame
    },
  }
}

///|
fn QueryParser::window_definitions(
  self : QueryParser,
  calls : Array[(NamePart, AggregateCall)],
) -> Array[(NamePart, AnalyticWindow)] raise QueryAbort {
  self.keyword("WINDOW")
  let definitions : Array[(NamePart, AnalyticWindow)] = []
  while true {
    self.node()
    let at = self.peek().start
    let name = self.name()
    for (previous, _) in definitions {
      self.spend(1)
      if same_cte_name(previous, name) {
        raise QueryAbort("Duplicate named window", at)
      }
    }
    self.keyword("AS")
    let specification = self.window_specification(calls=Some(calls))
    // Store an already resolved declaration. Forward references and cycles
    // cannot enter the map; no expression is expanded or evaluated here.
    definitions.push((name, self.resolve_window(specification, definitions)))
    if self.peek().value != Symbol(44) {
      break
    }
    ignore(self.advance())
  }
  definitions
}

///|
// Resolved consumers retain parser-owned references through inheritance.
// Unused declarations must not introduce aggregation or evaluate their keys.
fn QueryParser::used_named_window_aggregates(
  self : QueryParser,
  operations : Array[QueryOperation],
  candidates : Array[(NamePart, AggregateCall)],
) -> Array[(NamePart, AggregateCall)] raise QueryAbort {
  let used : Array[(NamePart, AggregateCall)] = []
  for candidate in candidates {
    self.spend(1)
    let mut referenced = false
    for operation in operations {
      self.spend(1)
      let projections = match operation {
        Analytic(projections) | AnalyticExpressions(projections, _) =>
          projections
        _ => []
      }
      for projection in projections {
        self.spend(1)
        let windows : Array[AnalyticWindow] = []
        if projection.analytic is Some(call) {
          windows.push(call.window)
        }
        for replacement in projection.replacements {
          self.spend(1)
          if replacement.analytic is Some(call) {
            windows.push(call.window)
          }
        }
        for window in windows {
          let expressions = window.partition_by +
            window.order_by.map(term => term.expression)
          for expression in expressions {
            for node in expression.nodes {
              self.spend(1)
              if node.kind is Reference([name]) && name == candidate.0 {
                referenced = true
              }
            }
          }
        }
      }
    }
    if referenced {
      used.push(candidate)
    }
  }
  used
}

///|
fn QueryParser::resolve_window_projections(
  self : QueryParser,
  projections : Array[Projection],
  definitions : Array[(NamePart, AnalyticWindow)],
) -> Array[Projection] raise QueryAbort {
  let resolved : Array[Projection] = []
  for projection in projections {
    self.spend(1)
    let analytic = match projection.analytic {
      Some(call) =>
        Some({ ..call, window: self.resolve_window(call.window, definitions), })
      None => None
    }
    let replacements : Array[StarReplacement] = []
    for replacement in projection.replacements {
      self.spend(1)
      let call = match replacement.analytic {
        Some(call) =>
          Some({
            ..call,
            window: self.resolve_window(call.window, definitions),
          })
        None => None
      }
      replacements.push({ ..replacement, analytic: call, })
    }
    resolved.push({ ..projection, analytic, replacements, })
  }
  resolved
}

///|
fn QueryParser::resolve_window_operations(
  self : QueryParser,
  operations : Array[QueryOperation],
  definitions : Array[(NamePart, AnalyticWindow)],
) -> Array[QueryOperation] raise QueryAbort {
  let resolved : Array[QueryOperation] = []
  for operation in operations {
    resolved.push(
      match operation {
        Group(keys, projections, scope) =>
          Group(
            keys,
            self.resolve_window_projections(projections, definitions),
            scope,
          )
        Analytic(projections) =>
          Analytic(self.resolve_window_projections(projections, definitions))
        AnalyticExpressions(projections, names) =>
          AnalyticExpressions(
            self.resolve_window_projections(projections, definitions),
            names,
          )
        Extend(projections) =>
          Extend(self.resolve_window_projections(projections, definitions))
        Select(projections, distinct) =>
          Select(
            self.resolve_window_projections(projections, definitions),
            distinct,
          )
        _ => operation
      },
    )
  }
  resolved
}
