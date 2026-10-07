///|
// SQL range names remain logical names. Each carried column has its own
// physical slot, so a later ON or qualified ORDER BY can name an earlier
// input without reviving a dropped range or confusing equal column names.
priv struct JoinChainScope {
  visible : Array[(String, String)]
  ranges : Array[(@query.NamePart, Array[(String, String)])]
}

///|
// GROUP, star and DISTINCT projections need the shared joined-row scope.
// DISTINCT ORDER expressions resolve after materialization, using evaluated
// output aliases rather than the projection-only specialization's input scope.
fn join_requires_group_scope(query : @query.Query) -> Bool {
  let mut has_full = false
  for index in 0..<@query.join_part_count(query) {
    let kind = @query.join_part_at(query, index).unwrap().kind
    if kind == "right" {
      return true
    }
    if kind == "full" {
      has_full = true
    }
  }
  for index in 0..<@query.operation_count(query) {
    if @query.operation_at(query, index) is Some(Group(_, _, _) | Qualify(_, _)) {
      return true
    }
    if @query.operation_at(query, index) is Some(Select(projections, distinct)) &&
      (
        projections.any(projection => projection.star is Some(_)) ||
        // FULL retains its existing coalesced-key projection owner.
        (distinct && !has_full)
      ) {
      return true
    }
  }
  false
}

///|
fn join_chain_reference(
  path : Array[@query.NamePart],
  scope : JoinChainScope,
  right : @query.NamePart,
  right_fields : Array[String],
) -> (String, String) raise Abort {
  let matches : Array[(String, String)] = []
  if path.length() == 1 {
    for entry in scope.visible {
      if same_name(path[0], { value: entry.0, quoted: false, }) {
        matches.push(("left", entry.1))
      }
    }
  } else if path.length() == 2 {
    for range in scope.ranges {
      if same_name(path[0], range.0) {
        for entry in range.1 {
          if same_name(path[1], { value: entry.0, quoted: false, }) {
            matches.push(("left", entry.1))
          }
        }
      }
    }
  }
  if path.length() == 1 || (path.length() == 2 && same_name(path[0], right)) {
    for field in right_fields {
      if same_name(path.last().unwrap(), { value: field, quoted: false, }) {
        matches.push(("right", field))
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
fn join_chain_keys(
  part : @query.JoinPart,
  scope : JoinChainScope,
  right : @query.NamePart,
  right_fields : Array[String],
) -> Array[(String, String)] raise Abort {
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
          let a = join_chain_reference(left_path, scope, right, right_fields)
          let b = join_chain_reference(right_path, scope, right, right_fields)
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
        pipe_slot([name], right_fields.map(field => (field, field)), [])
        is Some(right_field) else {
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
) -> (Array[@builder.Node], Array[String], String) raise Abort {
  if inputs.length() != @query.join_part_count(query) + 1 ||
    inputs.length() < 2 ||
    limits.max_join_output_rows < 1L ||
    limits.max_join_output_rows > 9007199254740991L {
    raise Abort(UnsupportedJoin)
  }
  let left = inputs[0]
  let fields = columns(left.0)
  let physical = fields.copy()
  let visible : Array[(String, String)] = []
  for field in fields {
    let slot = pipe_physical_name(physical, "aql_chain_column_")
    physical.push(slot)
    visible.push((field, slot))
  }
  // The first JOIN's existing projection assigns the private left slots.
  // An extra seed SELECT would retain a needless intermediate relation and
  // consume another bounded provider allowance for exactly the same fields.
  let steps : Array[@builder.Node] = []
  let mut from = left.1
  let original = fields.map(field => (field, field))
  let mut scope : JoinChainScope = {
    visible: original,
    ranges: [(query_range_name(query), original.copy())],
  }
  for index in 0..<@query.join_part_count(query) {
    let part = @query.join_part_at(query, index).unwrap()
    // FULL still requires the common stable-row identity/coalescence path.
    // Do not replace it with a left join or invent row identities here.
    if part.kind == "full" {
      raise Abort(UnsupportedJoin)
    }
    let right = inputs[index + 1]
    let right_fields = columns(right.0)
    let qualifier = part.source_alias.unwrap_or(part.relation.last().unwrap())
    if scope.ranges.any(range => same_name(range.0, qualifier)) {
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
              scope.visible,
              scope.ranges,
              limits.max_expression_work,
            ),
          ),
          ("as", construction.text(filtered)),
        ]),
      )
      from = filtered
    }
    let keys = join_chain_keys(part, scope, qualifier, right_fields)
    let reversed = part.kind == "right"
    let left_side = if reversed { "right." } else { "left." }
    let right_side = if reversed { "left." } else { "right." }
    let projected : Array[(String, @builder.Node)] = []
    // Qualified references keep both USING columns. Only the unqualified
    // visible row coalesces that key for the supported INNER/LEFT profiles.
    if index == 0 {
      for (field, slot) in visible {
        projected.push((slot, construction.text(left_side + field)))
      }
    } else {
      for slot in physical {
        if !fields.contains(slot) {
          projected.push((slot, construction.text(left_side + slot)))
        }
      }
    }
    let right_range : Array[(String, String)] = []
    let mut next_visible = if index == 0 {
      visible.copy()
    } else {
      scope.visible.copy()
    }
    for field in right_fields {
      let slot = pipe_physical_name(physical, "aql_chain_column_")
      physical.push(slot)
      right_range.push((field, slot))
      projected.push((slot, construction.text(right_side + field)))
      if !part.using_columns.any(name => {
          same_name(name, { value: field, quoted: false, })
        }) {
        next_visible.push((field, slot))
      }
    }
    if !part.using_columns.is_empty() {
      // USING keys lead the visible row in authored order. Qualified ranges
      // retain both originals; RIGHT uses its preserved right key unqualified.
      let merged : Array[(String, String)] = []
      for name in part.using_columns {
        if merged.any(entry => {
            same_name(name, { value: entry.0, quoted: false, })
          }) {
          raise Abort(UnsupportedJoin)
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
        merged.push((display, slot))
      }
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
    scope = {
      visible: next_visible,
      ranges: (if index == 0 {
        [(query_range_name(query), visible.copy())]
      } else {
        scope.ranges
      }) +
      [(qualifier, right_range)],
    }
  }
  let final_from = pipe_physical_name(reserved, "aql_chain_result_")
  reserved.push(final_from)
  let (tail, output) = compile_steps(
    construction,
    query,
    { ..left.0, name: from, source: StepReference, },
    physical.filter(field => !fields.contains(field)),
    limits.max_expression_work,
    limits.max_collection_items,
    limits.max_collection_bytes,
    0,
    true,
    final_from,
    retained~,
    initial_scope=Some(scope),
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
  for index in 0..<selected.length() {
    let input = selected[index]
    guard input.source is StageResult(stage, result) else {
      raise Abort(UnsupportedJoin)
    }
    let name = "aql_chain_input_" + index.to_string()
    reserved.push(name)
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
    inputs.push((input, name))
  }
  let (steps, output, from) = compile_join_chain_steps(
    construction, query, inputs, limits, reserved, retained,
  )
  (steps, output, declarations, from)
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
  let construction : Construction = { builder, generated, }
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
    @program.admit_generated_source(source, limits.program).map_err(issue => {
      Admission(issue)
    })
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}
