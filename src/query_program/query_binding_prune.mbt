///|
// Copy retained values and origins through the existing builder. No expression,
// Graph definition, typed key or semantic producer name is rewritten here.
fn binding_demand_object(
  builder : @builder.Builder,
  source : @builder.Source,
  cursor : @wire.Cursor,
  replacements : Array[(String, @builder.Node)],
  keep : (String) -> Bool,
) -> @builder.Node raise Abort {
  let fields : Array[@builder.Field] = []
  let origin = @builder.origin(source, cursor).unwrap()
  for index in 0..<@wire.object_length(cursor).unwrap() {
    let (key, value) = @wire.field_at(cursor, index).unwrap()
    if !keep(key) { continue }
    let mut replacement = None
    for (name, node) in replacements {
      if name == key { replacement = Some(node); break }
    }
    fields.push({
      key,
      origin: @builder.key_origin(source, value).unwrap_or(origin),
      value: match replacement {
        Some(node) => node
        None => member_construct(@builder.import_source(builder, source, value))
      },
    })
  }
  member_construct(@builder.add(builder, Object(fields), origin))
}

///|
fn prune_query_binding_source(
  source : @builder.Source,
  demand : ScriptDemand,
  document : @origin.Document,
  limits : Limits,
) -> Result[@builder.Source, Issue] {
  if !demand.steps.any(stage => stage.any(kept => !kept)) &&
    !demand.inputs.any(stage => stage.any(kept => !kept)) {
    return Ok(source)
  }
  let builder = match @builder.create(document, limits.source) {
    Ok(builder) => builder
    Err(issue) => return Err(Construction(issue))
  }
  try {
    let root = @builder.cursor(source)
    let root_object = @wire.open_object(root).unwrap()
    let original_stages = @wire.lookup(root_object, "stages").unwrap()
    let stages = []
    for stage in 0..<demand.steps.length() {
      if !demand.steps[stage].any(kept => kept) &&
        !demand.inputs[stage].any(kept => kept) { continue }
      let body = @wire.element_at(original_stages, stage).unwrap()
      let object = @wire.open_object(body).unwrap()
      let original_steps = @wire.lookup(object, "steps").unwrap()
      let steps = []
      for index, kept in demand.steps[stage] {
        if kept {
          steps.push(member_construct(@builder.import_source(
            builder, source, @wire.element_at(original_steps, index).unwrap(),
          )))
        }
      }
      let step_node = member_construct(@builder.add(
        builder, Array(steps), @builder.origin(source, original_steps).unwrap(),
      ))
      let original_inputs = @wire.lookup(object, "inputs").unwrap()
      let names = []
      for index, kept in demand.inputs[stage] {
        if kept {
          names.push(@pipeline.input_at(demand.pipelines[stage], index).unwrap().0)
        }
      }
      let input_node = binding_demand_object(
        builder, source, original_inputs, [], name => names.contains(name),
      )
      stages.push(binding_demand_object(
        builder, source, body, [("inputs", input_node), ("steps", step_node)], _ => true,
      ))
    }
    let stage_node = member_construct(@builder.add(
      builder, Array(stages), @builder.origin(source, original_stages).unwrap(),
    ))
    let root = binding_demand_object(
      builder, source, root, [("stages", stage_node)], _ => true,
    )
    @builder.finish(builder, root).map_err(issue => Construction(issue))
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}
