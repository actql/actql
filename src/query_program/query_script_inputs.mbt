///|
priv struct ScriptSources {
  declarations : Array[(String, @builder.Node)]
  stages : Array[@builder.Node]
  bound : Map[String, Input]
}

///|
// DATA reuses an admitted input, never reads a provider or creates another
// ledger. Keep the Host-requested capture boundary and retain its Result once
// across every query/constructor reference to this input.
fn bind_script_input(
  construction : Construction,
  input : Input,
  context : Context,
  sources : ScriptSources,
  steps : Array[@builder.Node],
  reserved : Array[String],
) -> Input raise Abort {
  let fields = columns(input)
  match input.source {
    StepReference => input
    GeneratedValues(source) => {
      let name = pipe_physical_name(reserved, "aql_script_seed_")
      reserved.push(name)
      steps.push(import_script_seed(construction, source, name))
      { ..input, name, source: StepReference, visible_fields: fields, }
    }
    Captured(declaration) => {
      if sources.bound.get(input.name) is Some(bound) {
        return bound
      }
      let imported = import_query_cursor(construction, declaration)
      let reference = match context.captured_stage {
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
          let (capture, reference) = capture_source_boundary(
            construction,
            stage_id,
            input.name,
            imported,
            fields,
            construction.object([("literal", construction.add(Bool(true)))]),
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
