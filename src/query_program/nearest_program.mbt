///|
// Complete only against this exact checked target. Common owns closed-schema
// vector selection and eligible key evidence, including runtime obligations.
fn nearest_complete_relation_roles(
  construction : Construction,
  clause : @query.NearestClause,
  pipeline : @pipeline.CheckedPipeline,
  producer : String,
  vector : String,
  visible : Array[(String, String)],
  query_side : Bool,
  limits : Limits,
) -> (Array[(String, String)], String) raise Abort {
  let target = @pipeline.lookup(pipeline, producer).unwrap()
  let carrier = @pipeline.carrier_at(pipeline, target).unwrap()
  let supplied = match @pipeline.candidate_keys(pipeline, target) {
    Some(keys) => @evidence.KeySource(keys)
    None => @evidence.CarrierSource(carrier)
  }
  let options = [
    ("queries", construction.text(producer)),
    ("metric", construction.text(clause.metric)),
    ("k", construction.add(Number(clause.k.to_double()))),
  ]
  if !vector.is_empty() {
    options.push((if query_side { "query_vector" } else { "candidate_vector" }, construction.text(vector)))
  }
  let at = construction.object(options)
  let source = match @builder.snapshot(construction.builder, at) {
    Ok(source) => source
    Err(issue) => raise Abort(Construction(issue))
  }
  let budget = construction.infer_budget
  let bound : @vector.Limits = {
    max_work: budget.remaining_work,
    max_nodes: limits.source.tree.max_nodes,
    max_depth: limits.source.tree.max_depth,
    max_text_bytes: limits.source.tree.max_total_string_bytes,
  }
  let options = match @vector.read_nearest_options(@builder.cursor(source), bound) {
    Ok(options) => options
    Err(_) => raise Abort(UnsupportedNearest)
  }
  budget.spend(@vector.nearest_options_usage(options).work, construction.generated)
  let checked = match @vector.check_nearest_source(options, if query_side { @evidence.Queries } else { @evidence.Candidates }, supplied, { ..bound, max_work: budget.remaining_work }) {
    Ok(checked) => checked
    Err({ kind: BudgetExceeded, .. }) => raise Abort(Expression({ issue: @expression.WorkLimit, origin: Some(construction.generated), }))
    Err(_) => raise Abort(UnsupportedNearest)
  }
  budget.spend(@vector.nearest_input_usage(checked).work, construction.generated)
  let vectors = @vector.nearest_input_vectors(checked).unwrap()
  let keys = @carrier.vector_identities(vectors).map(field => {
    let slot = @schema.reference_name(field.name)
    let label = visible.filter(entry => entry.1 == slot).get(0).map(entry => entry.0).unwrap_or(slot)
    (label, slot)
  })
  (keys, @schema.reference_name(@carrier.vector_components(vectors).name))
}

///|
fn import_query_cursor(
  construction : Construction,
  cursor : @wire.Cursor,
) -> @builder.Node raise Abort {
  match
    @builder.import_cursor(construction.builder, cursor, construction.generated) {
    Ok(node) => node
    Err(issue) => raise Abort(Construction(issue))
  }
}

///|
// Resolve published sources once. KEEP is not another acquisition of either side.
fn nearest_dependencies(
  query : @query.Query,
  known : Array[Input],
) -> Array[Input] raise Abort {
  let dependencies : Array[Input] = []
  for i in 0..<@query.operation_count(query) {
    if @query.operation_at(query, i) is Some(Nearest(clause)) {
      let matches = known.filter(input => {
        same_relation_path(input.relation, clause.relation)
      })
      guard matches.length() == 1 else {
        raise Abort(
          if matches.is_empty() {
            UnknownRelation
          } else {
            AmbiguousRelation
          },
        )
      }
      let input = matches[0]
      if dependencies.any(other => {
          other.name == input.name &&
          !same_relation_path(other.relation, input.relation)
        }) {
        raise Abort(InvalidContext)
      }
      if !dependencies.any(other => other.name == input.name) {
        dependencies.push(input)
      }
    }
  }
  dependencies
}

///|
fn nearest_key_slots(
  paths : Array[Array[@query.NamePart]],
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
) -> Array[(String, String)] raise Abort {
  let keys : Array[(String, String)] = []
  for path in paths {
    let slot = match pipe_slot(path, visible, ranges) {
      Some(slot) => slot
      None => raise Abort(UnknownColumn)
    }
    let scope = if path.length() == 2 {
      ranges.filter(range => same_name(range.0, path[0]))[0].1
    } else {
      visible
    }
    let name = scope.filter(entry => {
        entry.1 == slot &&
        same_name(path.last().unwrap(), { value: entry.0, quoted: false, })
      })[0].0
    if keys.any(key => key.1 == slot || ascii_upper(key.0) == ascii_upper(name)) {
      raise Abort(UnsupportedNearest)
    }
    keys.push((name, slot))
  }
  if keys.is_empty() {
    raise Abort(UnsupportedNearest)
  }
  keys
}

///|
fn nearest_vector_slot(
  construction : Construction,
  expression : @query.Expression,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  reserved : Array[String],
  fields : Array[(String, @builder.Node)],
  max_work : Int,
) -> String raise Abort {
  if @query.expression_node(expression, @query.expression_root(expression)).unwrap().kind
    is Reference(path) {
    if pipe_slot(path, visible, ranges) is Some(slot) {
      return slot
    }
  }
  let slot = pipe_physical_name(reserved, "aql_nearest_vector_")
  reserved.push(slot)
  fields.push(
    (
      slot,
      append_pipe_expression(
        construction, expression, visible, ranges, max_work,
      ),
    ),
  )
  slot
}

///|
// Exact role restatement is checked against the admitted Carrier, never inferred
// from a field's spelling or replaced by a constructed identity.
fn nearest_vector_roles(
  pair : @query.NearestRolePair?,
  vectors : @carrier.Vectors,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
) -> (Array[(String, String)], String) raise Abort {
  let keys = @carrier.vector_identities(vectors).map(field => {
    let name = @schema.reference_name(field.name)
    (name, name)
  })
  let component = @schema.reference_name(
    @carrier.vector_components(vectors).name,
  )
  if pair is Some(pair) {
    let supplied = nearest_key_slots(pair.keys, visible, ranges)
    if supplied.map(key => key.1) != keys.map(key => key.1) {
      raise Abort(InvalidQuery)
    }
    let mut node = @query.expression_node(
      pair.vector,
      @query.expression_root(pair.vector),
    ).unwrap()
    while node.kind is Parenthesized(child) {
      node = @query.expression_node(pair.vector, child).unwrap()
    }
    guard node.kind is Reference(path) &&
      pipe_slot(path, visible, ranges) == Some(component) else {
      raise Abort(InvalidQuery)
    }
  }
  (keys, component)
}

///|
fn lower_nearest_steps(
  construction : Construction,
  clause : @query.NearestClause,
  candidate : Input,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  physical : Array[String],
  initial : Array[(String, @builder.Node)],
  index : Int,
  input_names : Array[String],
  max_work : Int,
  query_typed? : (@carrier.Vectors, String)? = None,
  candidate_typed? : @carrier.Vectors? = None,
  checked_prefix? : ((Array[@builder.Node]) -> @pipeline.CheckedPipeline raise Abort)? = None,
  completion_limits? : Limits? = None,
) -> (Array[Array[(String, @builder.Node)]], Array[String]) raise Abort {
  if ranges.any(range => same_name(range.0, clause.candidate_alias)) {
    raise Abort(AmbiguousRelation)
  }
  let candidate_columns = columns(candidate)
  let candidate_visible = candidate_columns.map(field => (field, field))
  let candidate_ranges = [(clause.candidate_alias, candidate_visible)]
  // KEEP uses the two scopes simultaneously; an unqualified collision is not
  // silently assigned to either side. Original range snapshots remain available.
  let retained : Array[(String, Bool, String)] = []
  if clause.keep.is_empty() {
    for entry in visible {
      if ascii_upper(entry.0) == ascii_upper(clause.name.value) ||
        retained.any(previous => ascii_upper(previous.0) == ascii_upper(entry.0)) {
        raise Abort(DuplicateOutput)
      }
      retained.push((entry.0, false, entry.1))
    }
  }
  for item in clause.keep {
    let expanded : Array[(String, Bool, String)] = []
    if item.wildcard {
      if item.path.is_empty() {
        expanded.append(visible.map(entry => (entry.0, false, entry.1)))
        expanded.append(
          candidate_visible.map(entry => (entry.0, true, entry.1)),
        )
      } else if item.path.length() == 1 &&
        same_name(item.path[0], clause.candidate_alias) {
        expanded.append(
          candidate_visible.map(entry => (entry.0, true, entry.1)),
        )
      } else if item.path.length() == 1 {
        let matches = ranges.filter(range => same_name(range.0, item.path[0]))
        guard matches.length() == 1 else { raise Abort(UnknownColumn) }
        expanded.append(matches[0].1.map(entry => (entry.0, false, entry.1)))
      } else {
        raise Abort(UnknownColumn)
      }
    } else {
      let query_slot = pipe_slot(item.path, visible, ranges)
      let candidate_slot = pipe_slot(
        item.path,
        candidate_visible,
        candidate_ranges,
      )
      if query_slot is Some(_) && candidate_slot is Some(_) {
        raise Abort(AmbiguousColumn)
      }
      let (is_candidate, slot) = match (query_slot, candidate_slot) {
        (Some(slot), None) => (false, slot)
        (None, Some(slot)) => (true, slot)
        _ => raise Abort(UnknownColumn)
      }
      expanded.push(
        (
          item.name.unwrap_or(item.path.last().unwrap()).value,
          is_candidate,
          slot,
        ),
      )
    }
    for entry in expanded {
      if ascii_upper(entry.0) == ascii_upper(clause.name.value) ||
        retained.any(previous => ascii_upper(previous.0) == ascii_upper(entry.0)) {
        raise Abort(DuplicateOutput)
      }
      retained.push(entry)
    }
  }
  let names = input_names.copy()
  let producer = fn(role : String) {
    let name = pipe_physical_name(
      names,
      "aql_nearest_" + role + "_" + index.to_string() + "_",
    )
    names.push(name)
    name
  }
  let queries = producer("queries")
  let candidates = producer("candidates")
  let query_vectors = producer("query_vectors")
  let candidate_vectors = producer("candidate_vectors")
  let query_reserved = physical.copy()
  let candidate_reserved = candidate_columns.copy()
  let query_derived : Array[(String, @builder.Node)] = []
  let candidate_derived : Array[(String, @builder.Node)] = []
  let query_expression = clause.query_vector.or_else(() => clause.query_roles.map(roles => roles.vector))
  let mut query_vector = match query_typed {
    Some((vectors, _)) => {
      let component = @schema.reference_name(@carrier.vector_components(vectors).name)
      if query_expression is Some(expression) {
        let mut node = @query.expression_node(expression, @query.expression_root(expression)).unwrap()
        while node.kind is Parenthesized(child) { node = @query.expression_node(expression, child).unwrap() }
        guard node.kind is Reference(path) && pipe_slot(path, visible, ranges) == Some(component) else { raise Abort(InvalidQuery) }
      }
      component
    }
    None => match query_expression {
      Some(expression) => nearest_vector_slot(construction, expression, visible, ranges, query_reserved, query_derived, max_work)
      None => ""
    }
  }
  let mut candidate_vector = match candidate_typed {
    Some(vectors) =>
      @schema.reference_name(@carrier.vector_components(vectors).name)
    None => match clause.candidate_roles {
      Some(roles) => nearest_vector_slot(construction, roles.vector, candidate_visible, candidate_ranges, candidate_reserved, candidate_derived, max_work)
      None => ""
    }
  }
  // The adopted hit.body is the candidate's actual body column, not a query
  // row or a fabricated nearest role. Other payload stays available via KEEP.
  let candidate_body = candidate_visible.filter(entry => entry.0 == "body").get(0)
  let steps : Array[Array[(String, @builder.Node)]] = []
  // A typed input already feeds native NEAREST. Bridge records only when
  // KEEP demands that side; do not reserve unused row projections.
  if query_typed is None || retained.any(entry => !entry.1) {
    let query_prefix = initial.copy()
    if query_typed is Some(_) {
      steps.push(query_prefix + [("vectors", construction.add(Bool(true)))])
      query_prefix.clear()
    }
    if !query_derived.is_empty() {
      query_prefix.push(("derive", construction.object(query_derived)))
      // Retain the evaluated vector before reusing this scratch projection.
      steps.push(query_prefix.copy())
      query_prefix.clear()
    }
    query_prefix.push(
      (
        "select",
        construction.array(
          query_reserved.map(field => construction.text(field)),
        ),
      ),
    )
    query_prefix.push(("as", construction.text(queries)))
    steps.push(query_prefix)
  }
  if candidate_typed is None || retained.any(entry => entry.1) || candidate_body is Some(_) {
    let candidate_prefix = [("from", construction.text(candidate.name))]
    if candidate_typed is Some(_) {
      steps.push(candidate_prefix + [("vectors", construction.add(Bool(true)))])
      candidate_prefix.clear()
    }
    if !candidate_derived.is_empty() {
      candidate_prefix.push(("derive", construction.object(candidate_derived)))
    }
    candidate_prefix.push(("as", construction.text(candidates)))
    if candidate_derived.is_empty() {
      candidate_prefix.insert(
        if candidate_typed is Some(_) {
          0
        } else {
          1
        },
        (
          "select",
          construction.array(
            candidate_columns.map(field => construction.text(field)),
          ),
        ),
      )
    }
    steps.push(candidate_prefix)
  }
  let needs_completion = (query_typed is None && clause.query_roles is None) || (candidate_typed is None && clause.candidate_roles is None)
  let checked = if needs_completion {
    guard checked_prefix is Some(check) else { raise Abort(UnsupportedNearest) }
    Some(check(steps.map(members => construction.object(members))))
  } else { None }
  let query_keys = match query_typed {
    Some((vectors, _)) => nearest_vector_roles(clause.query_roles, vectors, visible, ranges).0
    None => match clause.query_roles {
      Some(roles) => nearest_key_slots(roles.keys, visible, ranges)
      None => {
        let (keys, vector) = nearest_complete_relation_roles(construction, clause, checked.unwrap(), queries, query_vector, visible, true, completion_limits.unwrap())
        query_vector = vector
        keys
      }
    }
  }
  let candidate_keys = match candidate_typed {
    Some(vectors) => nearest_vector_roles(clause.candidate_roles, vectors, candidate_visible, candidate_ranges).0
    None => match clause.candidate_roles {
      Some(roles) => nearest_key_slots(roles.keys, candidate_visible, candidate_ranges)
      None => {
        let (keys, vector) = nearest_complete_relation_roles(construction, clause, checked.unwrap(), candidates, candidate_vector, candidate_visible, false, completion_limits.unwrap())
        candidate_vector = vector
        keys
      }
    }
  }
  if (query_typed is None && query_keys.length() != 1) || (candidate_typed is None && candidate_keys.length() != 1) {
    raise Abort(UnsupportedNearest)
  }
  for
    (source, target, keys, vector, typed) in [
      (queries, query_vectors, query_keys, query_vector, query_typed is Some(_)),
      (
        candidates,
        candidate_vectors,
        candidate_keys,
        candidate_vector,
        candidate_typed is Some(_),
      ),
    ] {
    if typed {
      continue
    }
    steps.push([
      ("from", construction.text(source)),
      (
        "to_vectors",
        construction.object([
          ("id", construction.text(keys[0].1)),
          ("vector", construction.text(vector)),
        ]),
      ),
      ("as", construction.text(target)),
    ])
  }
  steps.push([
    (
      "from",
      construction.text(
        if candidate_typed is Some(_) {
          candidate.name
        } else {
          candidate_vectors
        },
      ),
    ),
    (
      "nearest",
      construction.object([
        (
          "queries",
          construction.text(
            query_typed.map(value => value.1).unwrap_or(query_vectors),
          ),
        ),
        ("metric", construction.text(clause.metric)),
        ("k", construction.add(Number(clause.k.to_double()))),
      ]),
    ),
  ])
  let reserved = ["query_id", "candidate_id", "score", "rank"] +
    retained.map(entry => entry.0) +
    [clause.name.value]
  let query_key_slots : Array[(String, String)] = []
  let candidate_key_slots : Array[(String, String)] = []
  let extracted : Array[(String, @builder.Node)] = []
  for
    (role, keys, slots) in [
      ("query_id", query_keys, query_key_slots),
      ("candidate_id", candidate_keys, candidate_key_slots),
    ] {
    for i in 0..<keys.length() {
      let slot = pipe_physical_name(reserved, "aql_nearest_key_")
      reserved.push(slot)
      let value = if keys.length() == 1 {
        infer_field(construction, role)
      } else {
        construction.object([
          (
            "property",
            construction.object([
              ("value", infer_field(construction, role)),
              ("name", construction.text(i.to_string())),
            ]),
          ),
        ])
      }
      extracted.push((slot, value))
      slots.push((keys[i].0, slot))
    }
  }
  steps.push([("derive", construction.object(extracted))])
  let retained_slots : Array[(String, String)] = []
  let mut body_slot : String? = None
  let carried = ["query_id", "candidate_id", "score", "rank"] +
    query_key_slots.map(key => key.1) +
    candidate_key_slots.map(key => key.1)
  for
    (is_candidate, source, keys, slots) in [
      (false, queries, query_keys, query_key_slots),
      (true, candidates, candidate_keys, candidate_key_slots),
    ] {
    let selected = carried.map(field => {
      (field, construction.text("left." + field))
    })
    for entry in retained.filter(entry => entry.1 == is_candidate) {
      let slot = pipe_physical_name(reserved, "aql_nearest_keep_")
      reserved.push(slot)
      selected.push((slot, construction.text("right." + entry.2)))
      retained_slots.push((entry.0, slot))
      carried.push(slot)
    }
    if is_candidate && candidate_body is Some(body) {
      let slot = pipe_physical_name(reserved, "aql_nearest_body_")
      reserved.push(slot)
      selected.push((slot, construction.text("right." + body.1)))
      carried.push(slot)
      body_slot = Some(slot)
    }
    // Repeated matches are many-to-one on each input key, never one-to-one
    // on query_id. The shared join verifies the assertion before output.
    if retained.any(entry => entry.1 == is_candidate) || (is_candidate && candidate_body is Some(_)) {
      steps.push([
        (
          "join",
          construction.object([
            ("with", construction.text(source)),
            ("kind", construction.text("inner")),
            ("cardinality", construction.text("many_to_one")),
            (
              "on",
              construction.array(
                keys.mapi((i, key) => {
                  construction.object([
                    ("left", construction.text(slots[i].1)),
                    ("right", construction.text(key.1)),
                  ])
                }),
              ),
            ),
            ("select", construction.object(selected)),
          ]),
        ),
      ])
    }
  }
  let key_object = fn(keys : Array[(String, String)]) raise Abort {
    construction.object([
      (
        "object",
        construction.object(
          keys.map(key => (key.0, infer_field(construction, key.1))),
        ),
      ),
    ])
  }
  let result_members = [
    ("query_key", key_object(query_key_slots)),
    ("candidate_key", key_object(candidate_key_slots)),
    ("score", infer_field(construction, "score")),
    ("rank", infer_field(construction, "rank")),
  ]
  if body_slot is Some(slot) { result_members.push(("body", infer_field(construction, slot))) }
  let result_slot = pipe_physical_name(reserved, "aql_nearest_result_")
  steps.push([
    (
      "derive",
      construction.object([
        (
          result_slot,
          construction.object([
            (
              "object",
              construction.object(result_members),
            ),
          ]),
        ),
      ]),
    ),
  ])
  let selection = retained.map(entry => {
    let slot = retained_slots.filter(slot => slot.0 == entry.0)[0].1
    construction.object([(entry.0, construction.text(slot))])
  })
  selection.push(
    construction.object([(clause.name.value, construction.text(result_slot))]),
  )
  steps.push([("select", construction.array(selection))])
  (steps, retained.map(entry => entry.0) + [clause.name.value])
}
