///|
// A whole-row AS range can export positional occurrences through its star.
// Field/object stars and ranges reset by another projection do not establish
// this role. Actual star expansion and visibility remain with the lowerer.
fn positional_whole_range_star(
  query : @query.Query,
  projection_index : Int,
  projection : @query.Projection,
) -> Bool {
  guard projection.expression is Some(receiver) else { return false }
  guard @query.expression_node(receiver, @query.expression_root(receiver))
    is Some({ kind: Reference(path), .. }) &&
    path.length() == 1 else {
    return false
  }
  let mut index = projection_index - 1
  while index >= 0 {
    match @query.operation_at(query, index).unwrap() {
      Alias(name) => return same_name(path[0], name)
      Order(_)
      | Limit(_, _)
      | Where(_)
      | Distinct
      | AssertUnique(_)
      | Set(_)
      | Drop(_)
      | Rename(_)
      | Extend(_)
      | UnnestSource(_, _, _)
      | Analytic(_)
      | AnalyticExpressions(_, _)
      | OrderAnalytic(_, _) => index -= 1
      _ => return false
    }
  }
  false
}

///|
// Pure column edits, filters, ordering and analytic steps retain positional inputs.
// EXCEPT/REPLACE address named columns without naming retained anonymous values.
fn positional_set_terminal_projection(query : @query.Query) -> Int? {
  let mut index = @query.operation_count(query) - 1
  let mut projection : Int? = None
  while index >= 0 {
    match @query.operation_at(query, index).unwrap() {
      Order(_)
      | Limit(_, _)
      | Where(_)
      | Distinct
      | AssertUnique(_)
      | Set(_)
      | Drop(_)
      | Rename(_)
      | Extend(_)
      | Alias(_)
      | Unpivot(_)
      | Pivot(_)
      | UnnestSource(_, _, _)
      | Analytic(_)
      | AnalyticExpressions(_, _)
      | OrderAnalytic(_, _) => index -= 1
      Select(projections, _) => {
        projection = Some(index)
        if projections.length() == 1 &&
          projections[0].star == Some("*") &&
          (
            projections[0].expression is None ||
            positional_whole_range_star(query, index, projections[0])
          ) {
          index -= 1
        } else {
          return projection
        }
      }
      _ => return projection
    }
  }
  projection
}

///|
// Positional duplicate columns keep separate physical slots and their authored
// names. Column removal and star exclusion use the same name correspondence.
fn positional_authored_column_name(
  name : String,
  authored_aliases : Array[(String, String)],
) -> String {
  for mapping in authored_aliases {
    if mapping.0 == name {
      return mapping.1
    }
  }
  name
}

///|
// A range may qualify authored duplicate names, but cannot give an anonymous
// occurrence its private storage name. Keep the physical value slots intact.
fn positional_named_expression_columns(
  columns : Array[(String, String)],
  private_fields : Array[String],
  authored_aliases : Array[(String, String)],
) -> Array[(String, String)] {
  columns
  .filter(column => {
    !private_fields.contains(column.0) ||
    authored_aliases.any(mapping => mapping.0 == column.0)
  })
  .map(column => {
    (positional_authored_column_name(column.0, authored_aliases), column.1)
  })
}

///|
// These are authored expression trees, before star expansion creates its
// internal physical-field references. Reuse the ordinary reference guards.
fn positional_projection_expressions(
  projections : Array[@query.Projection],
) -> Array[@query.Expression] {
  let expressions : Array[@query.Expression] = []
  let add_aggregate = fn(call : @query.AggregateCall) {
    if call.argument is Some(expression) {
      expressions.push(expression)
    }
    if call.filter is Some(expression) {
      expressions.push(expression)
    }
    expressions.append(call.order_by.map(term => term.expression))
  }
  let add_analytic = fn(call : @query.AnalyticCall) {
    if call.expression is Some(expression) {
      expressions.push(expression)
    }
    if call.aggregate is Some(aggregate) {
      add_aggregate(aggregate)
    }
    expressions.append(call.window.partition_by)
    expressions.append(call.window.order_by.map(term => term.expression))
  }
  for projection in projections {
    if projection.expression is Some(expression) {
      expressions.push(expression)
    }
    if projection.aggregate is Some(call) {
      add_aggregate(call)
    }
    if projection.analytic is Some(call) {
      add_analytic(call)
    }
    for replacement in projection.replacements {
      if replacement.expression is Some(expression) {
        expressions.push(expression)
      }
      if replacement.aggregate is Some(call) {
        add_aggregate(call)
      }
      if replacement.analytic is Some(call) {
        add_analytic(call)
      }
    }
  }
  expressions
}

///|
// A terminal positional right operand needs physical fields, not authored
// aliases. ORDER may use their positions or evaluated expressions, never
// their private names. Filters see only authored output aliases. Existing
// ordinal alignment supplies the public names.
fn anonymous_set_projection_name(
  projections : Array[@query.Projection],
  physical : Array[String],
  selected : Array[String],
  reserved_names? : Array[@query.NamePart] = [],
) -> String {
  let reserved = physical + selected
  for projection in projections {
    if projection_alias(projection) is Some(name) {
      reserved.push(name.value)
    }
  }
  let mut name = pipe_physical_name(reserved, "aql_set_anonymous_")
  while reserved_names.any(authored => {
          same_name(authored, { value: name, quoted: false, })
        }) {
    reserved.push(name)
    name = pipe_physical_name(reserved, "aql_set_anonymous_")
  }
  name
}

///|
// A terminal positional operand exports values by ordinal, not its authored
// names. Keep each duplicate occurrence in a distinct physical column until
// the existing set alignment replaces those names with the left output names.
// This is not a public duplicate-name policy or an alias lookup rule.
fn privatize_positional_duplicate_columns(
  construction : Construction,
  names : Array[String],
  bindings : Array[(String, String)],
  selected : Array[@builder.Node],
  physical : Array[String],
  authored_aliases? : Array[(String, String)]? = None,
  reserved_names? : Array[@query.NamePart] = [],
) -> Array[String] raise Abort {
  let private_fields : Array[String] = []
  let counts : Map[String, Int] = Map([])
  for name in names {
    let key = ascii_upper(name)
    counts[key] = counts.get(key).unwrap_or(0) + 1
  }
  let reserved = physical + names
  for index in 0..<names.length() {
    if counts[ascii_upper(names[index])] > 1 {
      let mut name = pipe_physical_name(reserved, "aql_set_duplicate_")
      while reserved_names.any(authored => {
              same_name(authored, { value: name, quoted: false, })
            }) {
        reserved.push(name)
        name = pipe_physical_name(reserved, "aql_set_duplicate_")
      }
      reserved.push(name)
      let source = bindings[index].1
      if authored_aliases is Some(aliases) {
        aliases.push((name, names[index]))
      }
      names[index] = name
      private_fields.push(name)
      bindings[index] = (name, source)
      selected[index] = construction.object([(name, construction.text(source))])
    }
  }
  private_fields
}

///|
fn duplicate_projection_alias(
  projections : Array[@query.Projection],
  name : String,
) -> Bool {
  let mut found = false
  for projection in projections {
    if projection_alias(projection)
      .map(output => ascii_upper(output.value) == ascii_upper(name))
      .unwrap_or(false) {
      if found {
        return true
      }
      found = true
    }
  }
  false
}

///|
// Duplicate SELECT aliases cannot supply a HAVING/QUALIFY receiver. A longer
// qualified input prefix keeps its existing meaning; do not flatten it to an
// unqualified output alias merely because its first token has the same name.
fn reject_duplicate_projection_references(
  projections : Array[@query.Projection],
  references : Array[Array[@query.NamePart]],
  resolve : (Array[@query.NamePart]) -> String?,
) -> Unit raise Abort {
  for path in references {
    if duplicate_projection_alias(projections, path[0].value) {
      let qualified = order_reference_identity(path, resolve)
        .map(identity => identity.1 > 1)
        .unwrap_or(false)
      if !qualified {
        raise Abort(AmbiguousColumn)
      }
    }
  }
}

///|
// Physical set aggregate outputs retain each evaluated call's input meaning.
// Neither anonymous nor repeated output aliases identify the call by themselves.
fn positional_set_aggregate_slot(
  call : @query.AggregateCall,
  outputs : Array[(@query.AggregateCall, String)],
  scope : JoinChainScope,
) -> String raise Abort {
  let resolve = path => scope_expression_slot(path, scope)
  for (previous, slot) in outputs {
    if same_aggregate_call(previous, call, resolve, resolve) {
      return slot
    }
  }
  raise Abort(UnsupportedAggregate)
}

///|
// A set operand's last pure column projection and its immediate alignment
// are one projection. Preserve the evaluated sources, output spelling/order
// and producer name; never move it across another operation or retained tap.
fn fold_script_set_terminal_select(
  construction : Construction,
  steps : Array[@builder.Node],
  first_step : Int,
  producer : String,
  fields : Array[String],
  matched : Array[String],
) -> Bool raise Abort {
  if steps.length() <= first_step || fields.length() != matched.length() {
    return false
  }
  let source = member_construct(
    @builder.snapshot(construction.builder, steps[steps.length() - 1]),
  )
  let cursor = @builder.cursor(source)
  if @wire.object_length(cursor) != Some(3) {
    return false
  }
  guard @wire.open_object(cursor) is Ok(object) else { return false }
  guard @wire.lookup(object, "as") is Some(name) else { return false }
  guard @wire.text(name) is Ok(name) && name == producer else { return false }
  guard @wire.lookup(object, "from") is Some(from) else { return false }
  guard @wire.text(from) is Ok(from) else { return false }
  guard @wire.lookup(object, "select") is Some(select) else { return false }
  guard @wire.array_length(select) is Some(count) else { return false }
  let columns : Map[String, String] = Map([])
  for index in 0..<count {
    let entry = @wire.element_at(select, index).unwrap()
    let (output, input) = match @wire.text(entry) {
      Ok(name) => (name, name)
      Err(_) => {
        if @wire.object_length(entry) != Some(1) {
          return false
        }
        guard @wire.field_at(entry, 0) is Some((output, input)) else {
          return false
        }
        guard @wire.text(input) is Ok(input) else { return false }
        (output, input)
      }
    }
    if columns.contains(output) {
      return false
    }
    columns[output] = input
  }
  let projected : Array[@builder.Node] = []
  for index in 0..<fields.length() {
    guard columns.get(matched[index]) is Some(input) else { return false }
    projected.push(
      if fields[index] == input {
        construction.text(input)
      } else {
        construction.object([(fields[index], construction.text(input))])
      },
    )
  }
  steps[steps.length() - 1] = construction.object([
    ("from", construction.text(from)),
    ("select", construction.array(projected)),
    ("as", construction.text(producer)),
  ])
  true
}

///|
fn set_operand_retains_result(query : @query.Query) -> Bool {
  for index in 0..<@query.operation_count(query) {
    if @query.operation_at(query, index) is Some(RetainResult(_)) {
      return true
    }
  }
  for index in 0..<@query.set_part_count(query) {
    if set_operand_retains_result(
        @query.set_part_at(query, index).unwrap().right,
      ) {
      return true
    }
  }
  for index in 0..<@query.cte_count(query) {
    if set_operand_retains_result(@query.cte_at(query, index).unwrap().query) {
      return true
    }
  }
  false
}

///|
// The set owner has already aligned its columns and removed hidden ORDER
// inputs. Bind that locally generated final producer without another SELECT.
// This only changes its structural name, never the operation or its arguments.
fn rebind_script_set_terminal_output(
  construction : Construction,
  steps : Array[@builder.Node],
  first_step : Int,
  producer : String,
  output : String,
) -> Bool raise Abort {
  if steps.length() <= first_step {
    return false
  }
  let source = member_construct(
    @builder.snapshot(construction.builder, steps[steps.length() - 1]),
  )
  let cursor = @builder.cursor(source)
  guard @wire.object_length(cursor) is Some(3) else { return false }
  guard @wire.open_object(cursor) is Ok(object) else { return false }
  guard @wire.lookup(object, "as") is Some(name) else { return false }
  guard @wire.text(name) is Ok(name) && name == producer else { return false }
  guard @wire.lookup(object, "from") is Some(from) else { return false }
  guard @wire.text(from) is Ok(_) else { return false }
  let allowed = [
    "append", "intersect", "except", "distinct", "sort", "take", "select",
  ]
  if !allowed.any(operation => @wire.lookup(object, operation) is Some(_)) {
    return false
  }
  steps[steps.length() - 1] = import_script_seed(construction, cursor, output)
  true
}
