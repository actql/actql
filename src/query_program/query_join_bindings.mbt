///|
// Standalone JOIN stages have private bindings. Several JOINs composed into a
// WITH pipeline instead reserve those same roles in the shared step scope.
// This changes binding names only; expression, key and order lowering remain
// shared with ordinary SQL/CTE JOINs.
fn join_step_binding(bindings : Map[String, String], role : String) -> String {
  bindings.get(role).unwrap_or(role)
}

///|
// The specialized CTE JOIN consumes two already-retained Results. A right
// Values input instead needs the existing shared input-binding path.
// Resolve the actual producer kind; names alone do not establish retention.
fn join_requires_input_binding(
  query : @query.Query,
  context : Context,
) -> Bool raise Abort {
  // INFER checks the original joined producer through the shared Script
  // prefix. The retained-Result specialization has no INFER tail lowering.
  if @query.join_part_count(query) > 0 {
    for index in 0..<@query.operation_count(query) {
      if @query.operation_at(query, index) is Some(Infer(_)) {
        return true
      }
    }
  }
  if @query.join_part_count(query) != 1 {
    return false
  }
  let part = @query.join_part_at(query, 0).unwrap()
  if part.file_listing is Some(_) {
    return true
  }
  let right = selected_relation(part.relation, context)
  right.source is GeneratedValues(_)
}

///|
fn script_join_bindings(reserved : Array[String]) -> Map[String, String] {
  let bindings : Map[String, String] = Map([])
  for
    role in [
      "aql_join_prefiltered", "aql_join_output", "aql_join_raw", "aql_join_filtered",
      "aql_join_derived", "aql_join_order_derived", "aql_join_unique", "aql_join_sorted",
      "aql_join_taken", "aql_join_visible", "aql_join_result", "aql_join_merged",
    ] {
    let name = pipe_physical_name(reserved, role + "_")
    reserved.push(name)
    bindings[role] = name
  }
  bindings
}

///|
fn lower_script_join_relation(
  construction : Construction,
  query : @query.Query,
  known : Array[Input],
  context : Context,
  sources : ScriptSources,
  limits : Limits,
  steps : Array[@builder.Node],
  reserved : Array[String],
  retained : Array[RetainedResult]?,
  preserved_scope? : Array[JoinChainScope]? = None,
  positional_set_output? : Bool = false,
) -> Input raise Abort {
  // Bind independent right inputs through their original Source owner and
  // requested capture boundary. Correlated UNNEST stays in the JOIN-chain
  // operations; its current-row dependency is not a Source capture.
  if @query.join_part_count(query) < 1 {
    raise Abort(UnsupportedJoin)
  }
  let scoped = { ..context, inputs: known, }
  let selected = selected_input(query, scoped, limits)
  let initial_scope = script_input_scope(
    construction,
    sources,
    selected.name,
    query_range_name(query),
  )
  let right_scopes : Array[JoinChainScope?] = []
  for index in 0..<@query.join_part_count(query) {
    let part = @query.join_part_at(query, index).unwrap()
    let right = selected_relation(part.relation, scoped)
    right_scopes.push(
      script_input_scope(
        construction,
        sources,
        right.name,
        part.source_alias.unwrap_or(part.relation.last().unwrap()),
      ),
    )
  }
  if @query.join_part_count(query) > 1 ||
    join_requires_group_scope(query) ||
    initial_scope is Some(_) ||
    right_scopes.any(scope => scope is Some(_)) ||
    preserved_scope is Some(_) ||
    (
      positional_set_output &&
      @query.operation_at(query, @query.operation_count(query) - 1)
      is Some(Select(projections, _)) &&
      projections.any(projection => projection_alias(projection) is None)
    ) {
    let left = bind_script_input(
      construction, selected, context, sources, steps, reserved,
    )
    let inputs = [(selected, left.name)]
    for index in 0..<@query.join_part_count(query) {
      let part = @query.join_part_at(query, index).unwrap()
      let selected = selected_join_input(query, part, scoped, limits)
      // An existing bound leaf retains its original placement; do not create
      // another classification/probe for a later use of the same input.
      let capture = if sources.bound.contains(selected.name) {
        false
      } else {
        right_source_capture_allowed(query, selected, context, limits)
      }
      let bound = bind_script_input(
        construction,
        selected,
        context,
        sources,
        steps,
        reserved,
        capture~,
      )
      inputs.push((selected, bound.name))
    }
    let nearest_inputs = bind_script_nearest_inputs(
      construction, query, known, selected, left, context, sources, steps, reserved,
    )
    let nearest_vectors = script_nearest_vector_inputs(
      construction, query, nearest_inputs, context, sources, limits, steps,
    )
    let (body, fields, from) = compile_join_chain_steps(
      construction,
      query,
      inputs,
      limits,
      reserved,
      retained,
      initial_scope~,
      right_scopes~,
      preserved_scope~,
      parameter_declarations=context.parameter_declarations,
      prefix_steps=steps.copy(),
      prefix_context=Some(context),
      nearest_inputs~,
      nearest_vectors~,
      positional_set_output~,
      checked_nearest_prefix=Some(nodes => {
        script_nearest_prefix_pipeline(
          construction, query, context, sources, nodes, limits,
        )
      }),
      checked_infer_prefix=Some((nodes, producer, visible, authored_aliases) => {
        script_infer_prefix_check(
          construction, query, context, sources, nodes, producer, limits, visible,
          authored_aliases,
        )
      }),
    )
    steps.append(body)
    return {
      relation: [],
      name: from,
      source: StepReference,
      visible_fields: fields,
      graph_bindings: [],
    }
  }
  let part = @query.join_part_at(query, 0).unwrap()
  let scoped = { ..context, inputs: known, }
  let left = selected_input(query, scoped, limits)
  let right = selected_join_input(query, part, scoped, limits)
  let left_fields = columns(left)
  let right_fields = columns(right)
  let values_bound = if left.source is GeneratedValues(_) &&
    right.source is GeneratedValues(_) {
    Some(values_join_output_bound(part, left, right, limits))
  } else {
    None
  }
  // An independent right Source needs its own capture Stage and both retained
  // Results must precede the local JOIN. Otherwise keep the left leading WHERE
  // and full projection at their original Direct capture prefix;
  // a keyed right request must remain at the original JoinRight occurrence.
  // Shared/already-bound script producers retain their prior boundary.
  // LIST_FILES adds its Request identity to the lowered binding name; sharing
  // is counted against the original published Source name, not that suffix.
  let original_left = selected_relation(@query.relation(query), scoped)
  let capture_right = if !sources.bound.contains(right.name) &&
    context.source_catalog is Some(_) &&
    right.source is Captured(right_declaration) &&
    @wire.open_object(right_declaration) is Ok(right_object) &&
    @wire.lookup(right_object, "connector") is Some(_) &&
    @wire.lookup(right_object, "resource") is Some(_) {
    right_source_capture_allowed(query, right, context, limits) catch {
      Abort(BindingPreparation(SourceSelection(issue))) =>
        // No selected Source contract means no proof of independence. Keep the
        // prior consumer placement; ordinary Program checking still rejects an
        // unresolved declaration. This does not invent a Direct or keyed use.
        if issue.kind is @source_resolution.Unresolved {
          false
        } else {
          raise Abort(BindingPreparation(SourceSelection(issue)))
        }
      Abort(issue) => raise Abort(issue)
    }
  } else {
    false
  }
  let capture_left = !capture_right &&
    context.captured_stage is Some(_) &&
    sources.unshared.contains(original_left.name) &&
    !sources.bound.contains(left.name) &&
    left.source is Captured(left_declaration) &&
    right.source is Captured(right_declaration) &&
    @wire.open_object(left_declaration) is Ok(left_object) &&
    @wire.open_object(right_declaration) is Ok(right_object) &&
    @wire.lookup(left_object, "connector") is Some(_) &&
    @wire.lookup(left_object, "resource") is Some(_) &&
    @wire.lookup(right_object, "connector") is Some(_) &&
    @wire.lookup(right_object, "resource") is Some(_)
  let bound_left = bind_script_input(
    construction,
    left,
    context,
    sources,
    steps,
    reserved,
    capture=!capture_left,
  )
  let bound_right = bind_script_input(
    construction,
    right,
    context,
    sources,
    steps,
    reserved,
    capture=capture_right,
  )
  let bindings = script_join_bindings(reserved)
  let (body, fields, from) = compile_join_steps(
    construction,
    query,
    @query.relation(query).last().unwrap(),
    left_fields,
    part.relation.last().unwrap(),
    right_fields,
    limits,
    retained~,
    left_from=bound_left.name,
    right_from=bound_right.name,
    step_bindings=bindings,
    capture_left~,
    values_bound~,
    prefix_steps=steps.copy(),
    checked_nearest_prefix=Some(nodes => {
      script_nearest_prefix_pipeline(
        construction, query, context, sources, nodes, limits,
      )
    }),
    reserved_bindings=reserved,
    checked_infer_prefix=Some((nodes, producer, visible, authored_aliases) => {
      script_infer_prefix_check(
        construction, query, context, sources, nodes, producer, limits, visible,
        authored_aliases,
      )
    }),
  )
  steps.append(body)
  {
    relation: [],
    name: from,
    source: StepReference,
    visible_fields: fields,
    graph_bindings: [],
  }
}
