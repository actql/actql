///|
// Standalone JOIN stages have private bindings. Several JOINs composed into a
// DATA pipeline instead reserve those same roles in the shared step scope.
// This changes binding names only; expression, key and order lowering remain
// shared with ordinary SQL/CTE JOINs.
fn join_step_binding(bindings : Map[String, String], role : String) -> String {
  bindings.get(role).unwrap_or(role)
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
) -> Input raise Abort {
  if @query.join_part_count(query) != 1 {
    raise Abort(UnsupportedJoin)
  }
  let part = @query.join_part_at(query, 0).unwrap()
  let scoped = { ..context, inputs: known, }
  let left = selected_input(query, scoped, limits)
  let right = selected_relation(part.relation, scoped)
  let left_fields = columns(left)
  let right_fields = columns(right)
  let bound_left = bind_script_input(
    construction, left, context, sources, steps, reserved,
  )
  let bound_right = bind_script_input(
    construction, right, context, sources, steps, reserved,
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
