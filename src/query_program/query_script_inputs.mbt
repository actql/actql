///|
priv struct ScriptSources {
  declarations : Array[(String, @builder.Node)]
  stages : Array[@builder.Node]
  prior_stages : Array[@builder.Node]
  bound : Map[String, Input]
  unshared : Array[String]
  ranges : Map[String, JoinChainScope]
  value_tables : Map[String, JoinChainScope]
  binding_ranges : Array[ScriptBindingRange]
  carriers : Map[String, @carrier.Carrier]
  mut carrier_work : Int
}

///|
// Emission ownership only. Input/producer dependence comes from the common
// checked pipeline, never from a second semantic reference scanner.
priv struct ScriptBindingRange {
  steps : Array[@builder.Node]
  start : Int
  end : Int
}

///|
// WITH reuses an admitted input, never reads a provider or creates another
// ledger. Keep the Host-requested capture boundary and retain its Result once
// across every query/constructor reference to this input.
fn bind_script_input(
  construction : Construction,
  input : Input,
  context : Context,
  sources : ScriptSources,
  steps : Array[@builder.Node],
  reserved : Array[String],
  predicate? : @builder.Node? = None,
  capture? : Bool = true,
  capture_originals? : Array[(Int, String, @builder.Node, @builder.Node)]? = None,
) -> Input raise Abort {
  let fields = columns(input)
  match input.source {
    StepReference => input
    GeneratedValues(source) => {
      // Reuse only the original installed Input selected in this Context. A
      // source-free Unit remains local even when its name matches an Input.
      let installed = context.inputs.any(known => physical_equal(known, input))
      if installed && sources.bound.get(input.name) is Some(bound) {
        return bound
      }
      let name = pipe_physical_name(reserved, "aql_script_seed_")
      reserved.push(name)
      let seed_start = steps.length()
      steps.push(import_script_seed(construction, source, name))
      if installed {
        // A shared installed input is its own demand leaf, not an operation
        // owned by the first WITH body that happens to reference it.
        sources.binding_ranges.push({
          steps,
          start: seed_start,
          end: steps.length(),
        })
      }
      let bound = {
        ..input,
        name,
        source: StepReference,
        visible_fields: fields,
      }
      if installed {
        sources.bound[input.name] = bound
      }
      bound
    }
    Captured(declaration) => {
      if sources.bound.get(input.name) is Some(bound) {
        return bound
      }
      let imported = import_query_cursor(construction, declaration)
      let capture_stage = if capture { context.captured_stage } else { None }
      let reference = match capture_stage {
        None => imported
        Some(base) => {
          let stage_id = if sources.stages.is_empty() {
            base
          } else {
            base + "_" + sources.stages.length().to_string()
          }
          if stage_id == context.stage_id {
            raise Abort(InvalidContext)
          }
          let original_predicate = predicate.unwrap_or_else(() => {
            construction.object([("literal", construction.add(Bool(true)))])
          })
          if capture_originals is Some(originals) {
            // Same emission originals, not a second Source or capture owner.
            originals.push(
              (sources.stages.length(), stage_id, imported, original_predicate),
            )
          }
          let (capture, reference) = capture_source_boundary(
            construction,
            stage_id,
            input.name,
            imported,
            fields,
            original_predicate,
          )
          sources.stages.push(capture)
          reference
        }
      }
      sources.declarations.push((input.name, reference))
      let bound = { ..input, source: StepReference, visible_fields: fields, }
      sources.bound[input.name] = bound
      bound
    }
    // A standalone Context does not carry the producer Stage body. Preserve
    // this refusal instead of manufacturing an undeclared Stage dependency.
    StageResult(_, _) => raise Abort(InvalidContext)
  }
}

///|
// Conservatively count raw installed-input references before placing an
// ordinary leading WHERE at the existing capture boundary. Any shared use
// retains the complete source and applies each consumer's filter downstream.
// Producer leaves already carry the parser's lexical resolution and declared
// argument role. This visitor does not interpret strings or check dependencies.
fn script_call_sources(call : @query.SgaCall) -> Array[Array[@query.NamePart]] {
  let paths = []
  let pending = call.arguments.map(argument => argument.1)
  while pending.pop() is Some(argument) {
    match argument {
      Producer(name) => paths.push([name])
      ObjectValue(fields) =>
        for (_, value) in fields {
          pending.push(value)
        }
      FieldMapValue(fields) =>
        for (_, value) in fields {
          pending.push(value)
        }
      ListValue(values) =>
        for value in values {
          pending.push(value)
        }
      _ => ()
    }
  }
  paths
}

///|
fn script_source_is_shadowed(
  path : Array[@query.NamePart],
  bound : Array[@query.NamePart],
) -> Bool {
  path.length() == 1 && bound.any(name => same_name(path[0], name))
}

///|
fn unshared_script_sources(
  script : @query.QueryScript,
  inputs : Array[Input],
) -> Array[String] {
  let counts : Map[String, Int] = Map([])
  let pending = [(@query.script_query(script), [])]
  while pending.pop() is Some((query, inherited)) {
    // A binding sees earlier bindings; its own name enters scope only afterwards.
    let bound = inherited.copy()
    for index in 0..<@query.query_binding_count(query) {
      let binding = @query.query_binding_at(query, index).unwrap()
      pending.push((binding.query, bound.copy()))
      bound.push(binding.name)
    }
    match @query.producer_primary(query) {
      Some(RelationGenerator(_)) => ()
      Some(GraphValue(mapping)) =>
        for
          path in mapping.nodes.map(node => node.producer) +
          mapping.edges.map(edge => edge.producer) {
          for input in inputs {
            if !script_source_is_shadowed(path, bound) &&
              input_relation_matches(path, input) {
              counts[input.name] = counts.get(input.name).unwrap_or(0) + 1
            }
          }
        }
      Some(GraphGenerator(_)) =>
        for input in inputs {
          counts[input.name] = 2
        }
      None => ()
    }
    for index in 0..<@query.set_part_count(query) {
      pending.push(
        (@query.set_part_at(query, index).unwrap().right, bound.copy()),
      )
    }
    let paths = [@query.relation(query)]
    for index in 0..<@query.join_part_count(query) {
      paths.push(@query.join_part_at(query, index).unwrap().relation)
    }
    for index in 0..<@query.operation_count(query) {
      match @query.operation_at(query, index) {
        Some(Nearest(clause)) => paths.push(clause.relation)
        Some(GraphCall(call)) =>
          for path in script_call_sources(call) {
            paths.push(path)
          }
        _ => ()
      }
    }
    for path in paths {
      for input in inputs {
        if !script_source_is_shadowed(path, bound) &&
          input_relation_matches(path, input) {
          counts[input.name] = counts.get(input.name).unwrap_or(0) + 1
        }
      }
    }
  }
  inputs
  .filter(input => counts.get(input.name) == Some(1))
  .map(input => input.name)
}
