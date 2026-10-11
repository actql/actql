///|
// SQL range names remain logical names. Each carried column has its own
// physical slot, so a later ON or qualified ORDER BY can name an earlier
// input without reviving a dropped range or confusing equal column names.
priv struct JoinChainScope {
  visible : Array[(String, String)]
  columns : Array[(String, String)]
  value_table : Bool
  value_columns : Array[(String, String, Array[(String, String)])]
  ranges : Array[(@query.NamePart, Array[(String, String)])]
  star_ranges : Array[(@query.NamePart, Array[(String, String)])]
  receivers : Array[(@query.NamePart, String)]
  scalar_ranges : Array[(@query.NamePart, String)]
}

///|
// Whole rows and explicit range-property receivers need the shared binder. This
// applicability check does not decide whether a same-named value or range wins;
// the ordinary scope resolver retains that distinction.
fn join_has_range_expression(
  expression : @query.Expression,
  ranges : Array[@query.NamePart],
) -> Bool {
  for index in 0..<@query.expression_node_count(expression) {
    if @query.expression_node(expression, index).unwrap().kind
      is Reference(path) &&
      path.length() == 1 &&
      ranges.any(name => same_name(name, path[0])) {
      return true
    }
    guard @query.expression_node(expression, index).unwrap().kind
      is Property(receiver, _) else {
      continue
    }
    let mut current = receiver
    while @query.expression_node(expression, current).unwrap().kind
          is Parenthesized(child) {
      current = child
    }
    if @query.expression_node(expression, current).unwrap().kind
      is Reference(path) &&
      path.length() == 1 &&
      ranges.any(name => same_name(name, path[0])) {
      return true
    }
  }
  false
}

///|
// RIGHT/FULL JOIN, GROUP, star, DISTINCT, row expressions and column edits
// need the shared row scope. Pipe DISTINCT compares the current JOIN row;
// SELECT DISTINCT orders through its materialized output aliases.
fn join_requires_group_scope(query : @query.Query) -> Bool {
  let ranges : Array[@query.NamePart] = []
  let primary = match @query.relation_alias(query) {
    Some(name) => Some(name)
    None => @query.relation(query).last()
  }
  if primary is Some(name) {
    ranges.push(name)
  }
  for index in 0..<@query.join_part_count(query) {
    let part = @query.join_part_at(query, index).unwrap()
    let kind = part.kind
    if kind == "right" || kind == "full" {
      return true
    }
    // A pre-JOIN predicate is stored on its JOIN part, rather than among
    // continuation operations. CTE JOIN specialization does not bind explicit
    // range receivers; use the existing shared row scope for that shape.
    if part.pre_join_filter is Some(predicate) &&
      join_has_range_expression(predicate, [query_range_name(query)]) {
      return true
    }
    let range = match part.source_alias {
      Some(name) => Some(name)
      None => part.relation.last()
    }
    if range is Some(name) {
      ranges.push(name)
    }
    // ON has the same operand range scope as SELECT. A bare ordinary range
    // must not enter the scalar-column specialization through a name collision.
    if part.on is Some(predicate) &&
      join_has_range_expression(predicate, ranges) {
      return true
    }
  }
  // The projection specialization consumes at most one WHERE before SELECT.
  // Other current-row prefixes must retain their authored order in the shared
  // compiler; moving a WHERE across LIMIT would change which rows survive.
  let select_index = if @query.operation_at(query, 0) is Some(Where(_)) {
    1
  } else {
    0
  }
  if !(@query.operation_at(query, select_index) is Some(Select(_, _))) {
    return true
  }
  for index in 0..<@query.operation_count(query) {
    let expressions = match @query.operation_at(query, index) {
      Some(Where(expression)) => [expression]
      Some(Select(projections, _)) =>
        projections.filter_map(projection => projection.expression)
      Some(Order(terms)) => terms.map(term => term.expression)
      _ => []
    }
    if expressions.any(expression => {
        join_has_range_expression(expression, ranges)
      }) {
      return true
    }
    if @query.operation_at(query, index)
      is Some(
        Group(_, _, _)
        | Qualify(_, _)
        | UnnestSource(_, _, _)
        | Extend(_)
        | Set(_)
        | Drop(_)
        | Rename(_)
        | Distinct
      ) {
      return true
    }
    if @query.operation_at(query, index) is Some(Select(projections, distinct)) &&
      (projections.any(projection => projection.star is Some(_)) || distinct) {
      return true
    }
  }
  false
}

///|
fn join_chain_reference(
  path : Array[@query.NamePart],
  scope : JoinChainScope,
  right_scope : JoinChainScope,
) -> (String, String) raise Abort {
  let matches : Array[(String, String)] = []
  if path.length() == 1 {
    // Resolve value receivers across both operands before ordinary columns.
    // USING has its independent column-target resolution below.
    for (side, candidate) in [("left", scope), ("right", right_scope)] {
      for receiver in candidate.receivers + candidate.scalar_ranges {
        if same_name(path[0], receiver.0) {
          matches.push((side, receiver.1))
        }
      }
    }
    if !matches.is_empty() {
      if matches.length() == 1 {
        return matches[0]
      }
      raise Abort(AmbiguousColumn)
    }
    // Ordinary ranges denote closed row objects. The existing equijoin profile
    // accepts comparable scalar key slots, not whole-row keys. Keep that
    // unsupported boundary explicit instead of substituting a same-named field.
    if scope.ranges.any(range => same_name(path[0], range.0)) ||
      right_scope.ranges.any(range => same_name(path[0], range.0)) {
      raise Abort(UnsupportedJoin)
    }
  }
  for (side, candidate) in [("left", scope), ("right", right_scope)] {
    if path.length() == 1 {
      for entry in candidate.visible {
        if same_name(path[0], { value: entry.0, quoted: false, }) {
          matches.push((side, entry.1))
        }
      }
    } else if path.length() == 2 {
      for range in candidate.ranges {
        if same_name(path[0], range.0) {
          for entry in range.1 {
            if same_name(path[1], { value: entry.0, quoted: false, }) {
              matches.push((side, entry.1))
            }
          }
        }
      }
    }
  }
  if matches.length() == 1 {
    matches[0]
  } else {
    raise Abort(AmbiguousColumn)
  }
}

///|
fn validate_join_using_names(part : @query.JoinPart) -> Unit raise Abort {
  let seen : Array[@query.NamePart] = []
  for name in part.using_columns {
    if seen.any(previous => same_name(name, previous)) {
      raise Abort(DuplicateOutput)
    }
    seen.push(name)
  }
}

///|
fn join_chain_keys(
  part : @query.JoinPart,
  scope : JoinChainScope,
  right_scope : JoinChainScope,
) -> Array[(String, String)] raise Abort {
  validate_join_using_names(part)
  let pairs : Array[(String, String)] = []
  if part.on is Some(expression) {
    let pending = [@query.expression_root(expression)]
    while pending.pop() is Some(index) {
      match @query.expression_node(expression, index).unwrap().kind {
        Parenthesized(child) => pending.push(child)
        Binary("AND", left, right_index) => {
          pending.push(right_index)
          pending.push(left)
        }
        Binary("=", left, right_index) => {
          guard @query.expression_node(expression, left).unwrap().kind
            is Reference(left_path) &&
            @query.expression_node(expression, right_index).unwrap().kind
            is Reference(right_path) else {
            raise Abort(UnsupportedJoin)
          }
          let a = join_chain_reference(left_path, scope, right_scope)
          let b = join_chain_reference(right_path, scope, right_scope)
          if a.0 == "left" && b.0 == "right" {
            pairs.push((a.1, b.1))
          } else if a.0 == "right" && b.0 == "left" {
            pairs.push((b.1, a.1))
          } else {
            raise Abort(UnsupportedJoin)
          }
        }
        _ => raise Abort(UnsupportedJoin)
      }
    }
  } else {
    for name in part.using_columns {
      guard pipe_slot([name], scope.visible, scope.ranges) is Some(left) &&
        pipe_slot([name], right_scope.visible, []) is Some(right_field) else {
        raise Abort(AmbiguousColumn)
      }
      pairs.push((left, right_field))
    }
  }
  if pairs.is_empty() && part.kind != "cross" {
    raise Abort(UnsupportedJoin)
  }
  pairs
}

///|
// Bind each producer once at the caller's existing boundary. This function
// appends ordinary join/derive/sort operations; it neither acquires
// inputs nor chooses a provider, task partition or execution strategy.
fn compile_join_chain_steps(
  construction : Construction,
  query : @query.Query,
  inputs : Array[(Input, String)],
  limits : Limits,
  reserved : Array[String],
  retained : Array[RetainedResult]?,
  initial_scope? : JoinChainScope? = None,
  right_scopes? : Array[JoinChainScope?] = [],
  preserved_scope? : Array[JoinChainScope]? = None,
  parameter_declarations? : @parameters.Declarations? = None,
  prefix_steps? : Array[@builder.Node] = [],
  prefix_context? : Context? = None,
  positional_set_output? : Bool = false,
) -> (Array[@builder.Node], Array[String], String) raise Abort {
  if inputs.length() != @query.join_part_count(query) + 1 ||
    (
      !right_scopes.is_empty() &&
      right_scopes.length() != @query.join_part_count(query)
    ) ||
    inputs.length() < 2 ||
    limits.max_join_output_rows < 1L ||
    limits.max_join_output_rows > 9007199254740991L {
    raise Abort(UnsupportedJoin)
  }
  let left = inputs[0]
  let fields = columns(left.0)
  let physical = fields.copy()
  let slots : Map[String, String] = Map([])
  for field in fields {
    let slot = pipe_physical_name(physical, "aql_chain_column_")
    physical.push(slot)
    slots[field] = slot
  }
  let original = fields.map(field => (field, field))
  let source_scope = initial_scope.unwrap_or({
    visible: original,
    columns: original.copy(),
    value_table: false,
    value_columns: [],
    star_ranges: [],
    ranges: [(query_range_name(query), original.copy())],
    receivers: [],
    scalar_ranges: [],
  })
  let visible = source_scope.visible.map(entry => (entry.0, slots[entry.1]))
  let first_columns = source_scope.columns.map(column => {
    (column.0, slots[column.1])
  })
  let first_ranges = source_scope.ranges.map(range => {
    (range.0, range.1.map(entry => (entry.0, slots[entry.1])))
  })
  // The first JOIN's existing projection assigns the private left slots.
  // An extra seed SELECT would retain a needless intermediate relation and
  // consume another bounded provider allowance for exactly the same fields.
  let steps : Array[@builder.Node] = []
  let mut from = left.1
  let mut scope : JoinChainScope = source_scope
  for index in 0..<@query.join_part_count(query) {
    let part = @query.join_part_at(query, index).unwrap()
    let right = inputs[index + 1]
    let right_fields = columns(right.0)
    let qualifier = part.source_alias.unwrap_or(part.relation.last().unwrap())
    let right_columns = right_fields.map(field => (field, field))
    let preserved_right = match right_scopes.get(index) {
      Some(scope) => scope
      None => None
    }
    let right_scope = preserved_right.unwrap_or({
      visible: right_columns,
      columns: right_columns.copy(),
      value_table: false,
      value_columns: [],
      star_ranges: [],
      ranges: [(qualifier, right_columns.copy())],
      receivers: [],
      scalar_ranges: [],
    })
    if right_scope.ranges.any(right_range => {
        scope.ranges.any(range => same_name(range.0, right_range.0))
      }) {
      raise Abort(AmbiguousRelation)
    }
    if part.pre_join_filter is Some(predicate) {
      let filtered = pipe_physical_name(reserved, "aql_chain_filter_")
      reserved.push(filtered)
      steps.push(
        construction.object([
          ("from", construction.text(from)),
          (
            "filter",
            append_pipe_expression(
              construction,
              predicate,
              unnest_expression_columns(
                scope.visible,
                scope.receivers,
                scope.scalar_ranges,
                scope.columns,
              ),
              scope.ranges,
              limits.max_expression_work,
            ),
          ),
          ("as", construction.text(filtered)),
        ]),
      )
      from = filtered
    }
    let keys = join_chain_keys(part, scope, right_scope)
    let reversed = part.kind == "right"
    let left_side = if reversed { "right." } else { "left." }
    let right_side = if reversed { "left." } else { "right." }
    let projected : Array[(String, @builder.Node)] = []
    // Qualified references keep both USING columns. Only the unqualified
    // visible row merges that key according to the join kind.
    if index == 0 {
      for field in fields {
        projected.push((slots[field], construction.text(left_side + field)))
      }
    } else {
      for slot in physical {
        if !fields.contains(slot) {
          projected.push((slot, construction.text(left_side + slot)))
        }
      }
    }
    let right_slots : Map[String, String] = Map([])
    let mut next_visible = if index == 0 {
      visible.copy()
    } else {
      scope.visible.copy()
    }
    let mut next_columns = if index == 0 {
      first_columns.copy()
    } else {
      scope.columns.copy()
    }
    for field in right_fields {
      let slot = pipe_physical_name(physical, "aql_chain_column_")
      physical.push(slot)
      right_slots[field] = slot
      projected.push((slot, construction.text(right_side + field)))
    }
    let right_range = right_scope.visible.map(entry => {
      (entry.0, right_slots[entry.1])
    })
    for entry in right_range {
      if !part.using_columns.any(name => {
          same_name(name, { value: entry.0, quoted: false, })
        }) {
        next_visible.push(entry)
      }
    }
    for entry in right_scope.columns {
      if !part.using_columns.any(name => {
          same_name(name, { value: entry.0, quoted: false, })
        }) {
        next_columns.push((entry.0, right_slots[entry.1]))
      }
    }
    let coalesced : Array[(String, @builder.Node)] = []
    if !part.using_columns.is_empty() {
      // USING keys lead the visible row in authored order. Qualified ranges
      // retain both originals; RIGHT uses its preserved right key unqualified.
      let merged : Array[(String, String)] = []
      for name in part.using_columns {
        if merged.any(entry => {
            same_name(name, { value: entry.0, quoted: false, })
          }) {
          raise Abort(DuplicateOutput)
        }
        guard pipe_slot(
            [name],
            if reversed {
              right_range
            } else {
              next_visible
            },
            [],
          )
          is Some(slot) else {
          raise Abort(AmbiguousColumn)
        }
        let display = next_visible.filter(entry => {
            same_name(name, { value: entry.0, quoted: false, })
          })[0].0
        let merged_slot = if part.kind == "full" {
          guard pipe_slot([name], right_range, []) is Some(right_slot) else {
            raise Abort(AmbiguousColumn)
          }
          let merged_slot = pipe_physical_name(physical, "aql_chain_column_")
          physical.push(merged_slot)
          coalesced.push(
            (
              merged_slot,
              construction.object([
                (
                  "coalesce",
                  construction.array([
                    construction.object([("field", construction.text(slot))]),
                    construction.object([
                      ("field", construction.text(right_slot)),
                    ]),
                  ]),
                ),
              ]),
            ),
          )
          merged_slot
        } else {
          slot
        }
        merged.push((display, merged_slot))
      }
      next_columns = merged +
        next_columns.filter(column => {
          !part.using_columns.any(name => {
            same_name(name, { value: column.0, quoted: false, })
          })
        })
      next_visible = merged +
        next_visible.filter(entry => {
          !part.using_columns.any(name => {
            same_name(name, { value: entry.0, quoted: false, })
          })
        })
    }
    let body = [
      ("with", construction.text(if reversed { from } else { right.1 })),
      (
        "max_output_rows",
        construction.add(Number(authored_join_bound(part, limits).to_double())),
      ),
      ("select", construction.object(projected)),
    ]
    let operation = if part.kind == "cross" {
      ("cross_join", construction.object(body))
    } else {
      body.push(
        ("kind", construction.text(if reversed { "left" } else { part.kind })),
      )
      body.push(
        (
          "on",
          construction.array(
            keys.map(pair => {
              construction.object([
                (
                  "left",
                  construction.text(if reversed { pair.1 } else { pair.0 }),
                ),
                (
                  "right",
                  construction.text(if reversed { pair.0 } else { pair.1 }),
                ),
              ])
            }),
          ),
        ),
      )
      ("join", construction.object(body))
    }
    let joined = pipe_physical_name(reserved, "aql_chain_join_")
    reserved.push(joined)
    steps.push(
      construction.object([
        ("from", construction.text(if reversed { right.1 } else { from })),
        operation,
        ("as", construction.text(joined)),
      ]),
    )
    from = joined
    if !coalesced.is_empty() {
      // Coalescing changes only the unqualified current row. The original
      // qualified keys remain carried, with typing and evidence checked by
      // the common operation owners.
      let merged = pipe_physical_name(reserved, "aql_chain_merged_")
      reserved.push(merged)
      steps.push(
        construction.object([
          ("from", construction.text(from)),
          ("derive", construction.object(coalesced)),
          ("as", construction.text(merged)),
        ]),
      )
      from = merged
    }
    scope = {
      visible: next_visible,
      columns: next_columns,
      value_table: false,
      value_columns: (if index == 0 {
        source_scope.value_columns.map(column => {
          (
            column.0,
            slots[column.1],
            column.2.map(field => (field.0, slots[field.1])),
          )
        })
      } else {
        scope.value_columns.copy()
      }) +
      right_scope.value_columns.map(column => {
        (
          column.0,
          right_slots[column.1],
          column.2.map(field => (field.0, right_slots[field.1])),
        )
      }),
      star_ranges: (if index == 0 {
        source_scope.star_ranges.map(range => {
          (range.0, range.1.map(field => (field.0, slots[field.1])))
        })
      } else {
        scope.star_ranges.copy()
      }) +
      right_scope.star_ranges.map(range => {
        (range.0, range.1.map(field => (field.0, right_slots[field.1])))
      }),
      ranges: (if index == 0 { first_ranges } else { scope.ranges }) +
      right_scope.ranges.map(range => {
        (range.0, range.1.map(field => (field.0, right_slots[field.1])))
      }),
      scalar_ranges: (if index == 0 {
        source_scope.scalar_ranges.map(receiver => {
          (receiver.0, slots[receiver.1])
        })
      } else {
        scope.scalar_ranges.copy()
      }) +
      right_scope.scalar_ranges.map(receiver => {
        (receiver.0, right_slots[receiver.1])
      }),
      receivers: (if index == 0 {
        source_scope.receivers.map(receiver => (receiver.0, slots[receiver.1]))
      } else {
        scope.receivers.copy()
      }) +
      right_scope.receivers.map(receiver => {
        (receiver.0, right_slots[receiver.1])
      }),
    }
  }
  let final_from = pipe_physical_name(reserved, "aql_chain_result_")
  reserved.push(final_from)
  // Type inspection needs the already-bound inputs and actual JOIN projection.
  // Forward that prefix without adding acquisition or evaluation steps.
  let (tail, output) = compile_steps(
    construction,
    query,
    { ..left.0, name: from, source: StepReference, },
    physical.filter(field => !fields.contains(field)),
    limits.max_expression_work,
    limits,
    limits.max_collection_items,
    limits.max_collection_bytes,
    0,
    true,
    final_from,
    retained~,
    initial_scope=Some(scope),
    preserved_scope~,
    parameter_declarations~,
    prefix_steps=prefix_steps + steps,
    prefix_context~,
    positional_set_output~,
  )
  steps.append(tail)
  (steps, output, if tail.is_empty() { from } else { final_from })
}

///|
fn compile_join_chain_stage_body(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  context : Context,
  limits : Limits,
  retained : Array[RetainedResult]?,
) -> (
  Array[@builder.Node],
  Array[String],
  Array[(String, @builder.Node)],
  String,
) raise Abort {
  let scoped = { ..context, inputs: known, }
  let selected = [selected_input(query, scoped, limits)]
  for index in 0..<@query.join_part_count(query) {
    selected.push(
      selected_relation(
        @query.join_part_at(query, index).unwrap().relation,
        scoped,
      ),
    )
  }
  let declarations : Array[(String, @builder.Node)] = []
  let inputs : Array[(Input, String)] = []
  let reserved : Array[String] = []
  let seeds : Array[@builder.Node] = []
  for index in 0..<selected.length() {
    let input = selected[index]
    let name = "aql_chain_input_" + index.to_string()
    reserved.push(name)
    match input.source {
      StageResult(stage, result) =>
        declarations.push(
          (
            name,
            construction.object([
              (
                "result",
                construction.object([
                  ("stage", construction.text(stage)),
                  ("result", construction.text(result)),
                ]),
              ),
            ]),
          ),
        )
      GeneratedValues(source) =>
        seeds.push(import_script_seed(construction, source, name))
      _ => raise Abort(UnsupportedJoin)
    }
    inputs.push((input, name))
  }
  let (steps, output, from) = compile_join_chain_steps(
    construction,
    query,
    inputs,
    limits,
    reserved,
    retained,
    parameter_declarations=context.parameter_declarations,
    prefix_steps=seeds,
    prefix_context=Some(context),
  )
  (seeds + steps, output, declarations, from)
}

///|
fn compile_join_chain_query(
  query : @query.Query,
  context : Context,
  limits : Limits,
) -> Result[@program.Program, Issue] {
  if context.captured_stage is Some(_) ||
    context.program_id == "" ||
    context.stage_id == "" ||
    context.stage_result == "" ||
    context.result_name == "" {
    return Err(UnsupportedJoin)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => return Err(Construction(issue))
  }
  let parameter_names = query_parameter_names(
    context.parameter_declarations,
    limits.max_expression_work,
  ) catch {
    Abort(issue) => {
      @builder.discard(builder)
      return Err(issue)
    }
  }
  let construction : Construction = {
    builder,
    generated,
    model_tasks: context.model_tasks,
    parameter_names,
  }
  try {
    let selected = [selected_input(query, context, limits)]
    for index in 0..<@query.join_part_count(query) {
      selected.push(
        selected_relation(
          @query.join_part_at(query, index).unwrap().relation,
          context,
        ),
      )
    }
    let stages : Array[@builder.Node] = []
    let known : Array[Input] = []
    let mut bound = join_values_rows(selected[0]).to_int64()
    for index in 0..<selected.length() {
      let input = selected[index]
      if index > 0 {
        let part = @query.join_part_at(query, index - 1).unwrap()
        let count = join_values_rows(input).to_int64()
        let factor = if part.kind == "right" && bound == 0L {
          1L
        } else {
          bound
        }
        let count = if part.kind == "left" && count == 0L { 1L } else { count }
        if count != 0L && factor > 9007199254740991L / count {
          raise Abort(UnsupportedJoin)
        }
        bound = factor * count
        if limits.max_join_output_rows < 1L ||
          bound > limits.max_join_output_rows {
          raise Abort(UnsupportedJoin)
        }
      }
      if known.any(existing => {
          same_relation_path(existing.relation, input.relation)
        }) {
        continue
      }
      let stage_name = "aql_chain_source_" + index.to_string()
      if stage_name == context.stage_id {
        raise Abort(UnsupportedJoin)
      }
      stages.push(
        join_seed_stage(
          construction,
          input,
          columns(input),
          stage_name,
          query,
          None,
          limits.max_expression_work,
        ),
      )
      known.push({ ..input, source: StageResult(stage_name, stage_name), })
    }
    let retained : Array[RetainedResult] = []
    let (steps, output, declarations, from) = compile_join_chain_stage_body(
      construction,
      query,
      known,
      context,
      limits,
      Some(retained),
    )
    stages.push(
      construction.object([
        ("id", construction.text(context.stage_id)),
        ("inputs", construction.object(declarations)),
        ("steps", construction.array(steps)),
        (
          "results",
          retained_stage_results(
            construction,
            context.stage_result,
            construction.object([
              ("from", construction.text(from)),
              (
                "fields",
                construction.array(
                  output.map(field => construction.text(field)),
                ),
              ),
            ]),
            retained,
          ),
        ),
      ]),
    )
    let root = program_root(
      construction,
      context,
      stages,
      result_exports=retained_result_exports(context, retained),
    )
    let source = match @builder.finish(builder, root) {
      Ok(source) => source
      Err(issue) => raise Abort(Construction(issue))
    }
    admit_query_source(source, document, context, limits)
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}
