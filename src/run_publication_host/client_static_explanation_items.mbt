///|
fn write_static_explanation_binding(
  writer : @encode.Writer,
  original : ClientStaticEffectExplanationOriginal,
) -> Unit raise {
  let declarations = original.declarations
  let plan_cid = explanation_original_text(original.map, "compiled_plan_cid")
  if plan_cid != declarations.compiled_plan_cid ||
    explanation_original_text(original.map, "program_definition_cid") !=
    declarations.program.program_definition_cid {
    raise StaticExplanationForeignSubject
  }
  @encode.begin_object(writer)
  explanation_text(
    writer,
    "check_environment_cid",
    declarations.check_environment_cid,
  )
  explanation_text(writer, "compiled_plan_cid", plan_cid)
  explanation_text(
    writer,
    "logical_map_cid",
    explanation_original_text(original.map, "self_cid"),
  )
  explanation_text(
    writer,
    "parameter_values_cid",
    declarations.program.parameter_values_cid,
  )
  explanation_text(
    writer,
    "program_definition_cid",
    declarations.program.program_definition_cid,
  )
  @encode.end_object(writer)
}

///|
// Look up the compiler-issued logical port using its original step key. A
// declaration whose producer is missing from this map remains unprojected.
fn write_static_explanation_output(
  writer : @encode.Writer,
  steps : @canonical.FrozenArray[@canonical.CanonicalValue],
  stage : Int,
  target : @pipeline.Target,
  remaining : Ref[Int],
) -> Unit raise {
  let (kind, field, ordinal) = match target {
    @pipeline.Step(step) => ("operation", "operation_ordinal", step)
    @pipeline.Input(input) => ("input_output", "input_port_ordinal", input)
  }
  @encode.begin_object(writer)
  for index in 0..<@canonical.array_count(steps) {
    spend_static_explanation_work(remaining)
    let step = @canonical.array_at(steps, index).unwrap()
    let key = explanation_original_field(step, "key")
    let occurrence = explanation_original_field(key, "occurrence")
    if explanation_original_ordinal(key, "stage_ordinal") != stage ||
      explanation_original_text(occurrence, "kind") != kind ||
      explanation_original_ordinal(occurrence, field) != ordinal {
      continue
    }
    guard @canonical.object_field(step, "ports")
      is Some(@canonical.Array(ports)) else {
      raise @encode.InvalidStructure
    }
    for index in 0..<@canonical.array_count(ports) {
      spend_static_explanation_work(remaining)
      let port = @canonical.array_at(ports, index).unwrap()
      if explanation_original_text(port, "role") == "output" {
        explanation_text(
          writer,
          "port_id",
          explanation_original_text(port, "port_id"),
        )
        explanation_text(writer, "state", "projected")
        explanation_text(
          writer,
          "step_id",
          explanation_original_text(step, "step_id"),
        )
        @encode.end_object(writer)
        return
      }
    }
  }
  explanation_text(writer, "reason", "no_original_port")
  explanation_text(writer, "state", "not_projected")
  @encode.end_object(writer)
}

///|
fn write_static_explanation_model_input(
  writer : @encode.Writer,
  binding : @infer.InputBinding,
) -> Unit raise @encode.EncodeFailure {
  let expression = binding.expression
  let node = @expression.node_at(expression, 0).unwrap()
  @encode.begin_object(writer)
  @encode.key(writer, "binding")
  @encode.begin_object(writer)
  match @expression.node_form(expression, 0) {
    Some(Expression(form, body)) if form == "field" || form == "$param" => {
      guard @decode.text(body) is Ok(name) else {
        raise @encode.InvalidStructure
      }
      explanation_text(writer, "name", name)
      explanation_text(
        writer,
        "state",
        if form == "$param" {
          "parameter"
        } else {
          "field"
        },
      )
    }
    Some(Expression("literal", _)) =>
      explanation_text(writer, "state", "redacted")
    _ => {
      explanation_text(writer, "reason", "expression_form_not_projected")
      explanation_text(writer, "state", "not_projected")
    }
  }
  @encode.end_object(writer)
  explanation_text(writer, "role", @infer.input_binding_role(binding))
  @encode.key(writer, "type")
  explanation_type(writer, node.contract)
  @encode.end_object(writer)
}

///|
fn write_static_explanation_models(
  writer : @encode.Writer,
  steps : @canonical.FrozenArray[@canonical.CanonicalValue],
  original : ClientStaticEffectExplanationOriginal,
  remaining : Ref[Int],
) -> Unit raise {
  for component in original.compiled.compiled.infers {
    spend_static_explanation_work(remaining)
    let selected = component.occurrence
    guard client_infer_occurrence_matches_effect(selected, original.prepared) &&
      client_infer_occurrence_matches_plan(selected, component) &&
      @lower.node_at(
        @lower.bound_preparation(selected.preparation),
        selected.step,
      )
      is Some(node) &&
      @lower.payload(node) is @lower.Infer(infer) else {
      raise StaticExplanationForeignSubject
    }
    let task = @infer.model_task(infer)
    let (task_id, task_version, contract_cid) = @environment.model_task_identity(
      task,
    )
    @encode.begin_object(writer)
    explanation_text(writer, "contract_cid", contract_cid)
    explanation_text(writer, "dispatch_unit", "input_row")
    @encode.key(writer, "input_bindings")
    @encode.begin_array(writer)
    for index in 0..<@infer.input_binding_count(infer) {
      spend_static_explanation_work(remaining)
      write_static_explanation_model_input(
        writer,
        @infer.input_binding_at(infer, index).unwrap(),
      )
    }
    @encode.end_array(writer)
    explanation_text(writer, "kind", "model_task")
    @encode.key(writer, "output_fields")
    @encode.begin_array(writer)
    guard @environment.model_task_output(task).shape is @contract.Object(fields) else {
      raise StaticExplanationForeignSubject
    }
    for index in 0..<@contract.field_count(fields) {
      spend_static_explanation_work(remaining)
      let field = @contract.field_at(fields, index).unwrap()
      @encode.begin_object(writer)
      explanation_text(writer, "name", field.name)
      @encode.key(writer, "type")
      explanation_type(writer, field.contract)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "producer")
    write_static_explanation_output(
      writer,
      steps,
      selected.stage,
      @pipeline.Step(selected.step),
      remaining,
    )
    explanation_text(writer, "task_id", task_id)
    explanation_text(writer, "task_version", task_version)
    @encode.end_object(writer)
  }
}

///|
fn write_static_explanation_results(
  writer : @encode.Writer,
  steps : @canonical.FrozenArray[@canonical.CanonicalValue],
  compiled : ClientEffectCompilation,
  remaining : Ref[Int],
) -> Unit raise {
  let graph = compiled.compiled.owner.graph
  let stages = @checked.unit_count(@strategy.graph_program(graph))
  let tasks = @strategy.graph_task_count(graph)
  for index in 0..<@strategy.graph_result_count(graph) {
    spend_static_explanation_work(remaining)
    // The task-to-stage reader scans the original stage/task inventory.
    spend_static_explanation_work(remaining, count=stages)
    spend_static_explanation_work(remaining, count=tasks)
    guard @strategy.graph_result_occurrence(graph, index) is Some(original) &&
      @strategy.graph_result_task(graph, index) is Some(task) &&
      @strategy.graph_task_unit_index(graph, task) is Some(stage) &&
      @strategy.graph_task_owner(graph, task) is Some(owner) &&
      physical_equal(
        @execution.managed_result_occurrence_owner(original),
        owner,
      ) else {
      raise StaticExplanationForeignSubject
    }
    let port = @execution.managed_result_occurrence_port(original)
    @encode.begin_object(writer)
    explanation_text(writer, "kind", "result")
    explanation_text(
      writer,
      "name",
      @execution.managed_result_occurrence_name(original),
    )
    @encode.key(writer, "producer")
    write_static_explanation_output(
      writer,
      steps,
      stage,
      @results.port_target(port),
      remaining,
    )
    @encode.key(writer, "stage_ordinal")
    @encode.number_value(writer, stage.to_double())
    @encode.end_object(writer)
  }
}

///|
fn write_static_explanation_effect(
  writer : @encode.Writer,
  original : ClientStaticEffectExplanationOriginal,
  remaining : Ref[Int],
) -> Unit raise {
  let declarations = original.declarations
  let effects = @checked.effect_program_static_effects(
    original.prepared.candidate,
  )
  let bindings = @stage_results.effect_static_candidate_results(effects)
  let mappings = @stage_results.effect_static_candidate_mapping_rules(effects)
  if @stage_results.effect_result_binding_count(bindings) !=
    declarations.members.length() {
    raise StaticExplanationForeignSubject
  }
  @encode.begin_object(writer)
  explanation_text(writer, "kind", "effect_set")
  @encode.key(writer, "members")
  @encode.begin_array(writer)
  for index, entry in declarations.members {
    spend_static_explanation_work(remaining)
    let binding = @stage_results.effect_result_binding_at(bindings, index).unwrap()
    let header = @stage_results.effect_result_binding_header(binding)
    if @syntax.effect_header_stage(header) != entry.stage_ordinal ||
      @syntax.effect_header_id(header) != entry.effect_id {
      raise StaticExplanationForeignSubject
    }
    @encode.begin_object(writer)
    @encode.key(writer, "declaration")
    emit_effectful_static_member(writer, entry)
    @encode.key(writer, "write_fields")
    @encode.begin_object(writer)
    match entry.contract {
      MappingDeclaration(_, _, _) =>
        write_static_explanation_mapping_fields(
          writer, mappings, binding, remaining,
        )
      CommandDeclaration(_, _, _) => {
        explanation_text(writer, "reason", "command_fields_not_projected")
        explanation_text(writer, "state", "not_projected")
      }
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  explanation_text(writer, "unit_id", declarations.unit_id)
  @encode.end_object(writer)
}

///|
// The checked mapping rule includes the whole authored write set, including
// literal assignments. Project field names only, never the rule's permission
// names, selected values or an observed write.
fn write_static_explanation_mapping_fields(
  writer : @encode.Writer,
  mappings : @stage_results.EffectMappingRules,
  binding : @stage_results.EffectResultBinding,
  remaining : Ref[Int],
) -> Unit raise {
  for index in 0..<@stage_results.effect_mapping_rule_count(mappings) {
    spend_static_explanation_work(remaining)
    let rule = @stage_results.effect_mapping_rule_at(mappings, index).unwrap()
    let original = @stage_results.effect_mapping_shape_effect(
      @stage_results.effect_mapping_rule_effect(rule),
    )
    if physical_equal(original, binding) {
      let selection = @stage_results.effect_mapping_rule_selection(rule)
      spend_static_explanation_work(
        remaining,
        count=selection.write_fields.length(),
      )
      @encode.key(writer, "fields")
      @encode.begin_array(writer)
      for field in selection.write_fields {
        @encode.string_value(writer, field)
      }
      @encode.end_array(writer)
      explanation_text(writer, "state", "declared")
      return
    }
  }
  raise StaticExplanationForeignSubject
}
