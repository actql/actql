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
) -> (Array[Array[(String, @builder.Node)]], Array[String]) raise Abort {
  if ranges.any(range => same_name(range.0, clause.candidate_alias)) {
    raise Abort(AmbiguousRelation)
  }
  let candidate_columns = columns(candidate)
  let candidate_visible = candidate_columns.map(field => (field, field))
  let candidate_ranges = [(clause.candidate_alias, candidate_visible)]
  let query_keys = nearest_key_slots(clause.query_keys, visible, ranges)
  let candidate_keys = nearest_key_slots(
    clause.candidate_keys,
    candidate_visible,
    candidate_ranges,
  )
  // The common JSON rows-to-Vectors bridge currently accepts one ID field.
  // Do not emit an invalid array or replace a typed tuple with a synthetic ID.
  if query_keys.length() != 1 || candidate_keys.length() != 1 {
    raise Abort(UnsupportedNearest)
  }
  // KEEP uses the two scopes simultaneously; an unqualified collision is not
  // silently assigned to either side. Original range snapshots remain available.
  let retained : Array[(String, Bool, String)] = []
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
  let query_vector = nearest_vector_slot(
    construction,
    clause.query_vector,
    visible,
    ranges,
    query_reserved,
    query_derived,
    max_work,
  )
  let candidate_vector = nearest_vector_slot(
    construction,
    clause.candidate_vector,
    candidate_visible,
    candidate_ranges,
    candidate_reserved,
    candidate_derived,
    max_work,
  )
  let steps : Array[Array[(String, @builder.Node)]] = []
  let query_prefix = initial.copy()
  if !query_derived.is_empty() {
    query_prefix.push(("derive", construction.object(query_derived)))
    steps.push(query_prefix)
    query_prefix.clear()
  }
  query_prefix.push(
    (
      "select",
      construction.array(query_reserved.map(field => construction.text(field))),
    ),
  )
  query_prefix.push(("as", construction.text(queries)))
  steps.push(query_prefix)
  let candidate_prefix = [("from", construction.text(candidate.name))]
  if !candidate_derived.is_empty() {
    candidate_prefix.push(("derive", construction.object(candidate_derived)))
  }
  candidate_prefix.push(("as", construction.text(candidates)))
  if candidate_derived.is_empty() {
    candidate_prefix.insert(
      1,
      (
        "select",
        construction.array(
          candidate_columns.map(field => construction.text(field)),
        ),
      ),
    )
  }
  steps.push(candidate_prefix)
  for
    (source, target, keys, vector) in [
      (queries, query_vectors, query_keys, query_vector),
      (candidates, candidate_vectors, candidate_keys, candidate_vector),
    ] {
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
    ("from", construction.text(candidate_vectors)),
    (
      "nearest",
      construction.object([
        ("queries", construction.text(query_vectors)),
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
      extracted.push((slot, infer_field(construction, role)))
      slots.push((keys[i].0, slot))
    }
  }
  steps.push([("derive", construction.object(extracted))])
  let retained_slots : Array[(String, String)] = []
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
    // Repeated matches are many-to-one on each input key, never one-to-one
    // on query_id. The shared join verifies the assertion before output.
    if retained.any(entry => entry.1 == is_candidate) {
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
              construction.object([
                ("query_key", key_object(query_key_slots)),
                ("candidate_key", key_object(candidate_key_slots)),
                ("score", infer_field(construction, "score")),
                ("rank", infer_field(construction, "rank")),
              ]),
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
