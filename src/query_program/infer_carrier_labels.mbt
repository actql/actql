///|
// These names describe exact checked slots. They are metadata only: neither
// the copied-slot map nor the labels choose or prove an INFER item key.
fn infer_carrier_slot_name(
  construction : Construction,
  field : @schema.FieldName,
) -> String raise Abort {
  construction.infer_budget.spend(1, construction.generated)
  match field {
    Unqualified(name) =>
      construction.infer_budget.spend_text(name, construction.generated)
    Qualified(side, name) => {
      construction.infer_budget.spend_text(name, construction.generated)
      construction.infer_budget.spend(
        if side == @schema.Left {
          5
        } else {
          6
        },
        construction.generated,
      )
    }
  }
  @schema.reference_name(field)
}

///|
fn infer_carrier_input_slots(
  construction : Construction,
  carrier : @carrier.Carrier,
) -> Map[String, Bool] raise Abort {
  let slots : Map[String, Bool] = Map([])
  let records = match carrier {
    Relation(records) => Some(records)
    VectorValue(vectors) => Some(@carrier.vector_records(vectors))
    EventValue(events) => Some(@carrier.event_records(events))
    _ => None
  }
  if records is Some(records) {
    for index in 0..<@carrier.field_count(records) {
      let field = @carrier.field_at(records, index).unwrap()
      let slot = infer_carrier_slot_name(construction, field.name)
      slots[slot] = true
    }
  }
  slots
}

///|
fn infer_carrier_label_index(
  construction : Construction,
  labels : Array[(String, String)],
) -> Map[String, String] raise Abort {
  let index : Map[String, String] = Map([])
  for entry in labels {
    spend_infer_key_label_pair(construction, entry)
    index[entry.0] = entry.1
  }
  index
}

///|
// Resolve the checked operand's producer, never a same-spelled carrier field.
// An existing scope owns its complete history, including an intentionally
// absent label. Only an unscoped declared Input has fresh public field names.
fn infer_carrier_target_labels(
  construction : Construction,
  sources : ScriptSources,
  pipeline : @pipeline.CheckedPipeline,
  target : @pipeline.Target,
  known : Array[Input],
) -> Map[String, String] raise Abort {
  construction.infer_budget.spend(1, construction.generated)
  let name = match target {
    Input(index) => @pipeline.input_at(pipeline, index).map(input => input.0)
    Step(index) =>
      match @pipeline.step_at(pipeline, index) {
        Some(step) => step.binding_name
        None => None
      }
  }
  guard name is Some(name) else { return Map([]) }
  construction.infer_budget.spend_text(name, construction.generated)
  if sources.ranges.get(name) is Some(scope) {
    return infer_carrier_label_index(construction, scope.key_labels)
  }
  construction.infer_budget.spend_text(name, construction.generated)
  if sources.value_tables.get(name) is Some(scope) {
    return infer_carrier_label_index(construction, scope.key_labels)
  }
  for input in known {
    construction.infer_budget.spend(1, construction.generated)
    construction.infer_budget.spend_text(input.name, construction.generated)
    let bound = sources.bound.get(input.name).unwrap_or(input)
    spend_infer_key_label_pair(construction, (bound.name, name))
    if bound.name == name {
      let labels : Map[String, String] = Map([])
      for field in bound.visible_fields {
        spend_infer_key_label_pair(construction, (field, field))
        labels[field] = field
      }
      return labels
    }
  }
  Map([])
}

///|
// Every explicit temporal select output is an authored name introduction for
// its checked operand/slot. The no-select interval form only qualifies slots;
// it does not rename the identity labels carried by either operand.
fn infer_carrier_temporal_projection(
  construction : Construction,
  projection : @join_shape.Projection,
  labels : Map[String, String],
) -> Unit raise Abort {
  let output = infer_carrier_slot_name(construction, projection.output)
  // Reading the checked input keeps this path tied to an actual selected slot,
  // rather than treating an output spelling as evidence of a surviving value.
  ignore(infer_carrier_slot_name(construction, projection.input))
  spend_infer_key_label_pair(construction, (output, output))
  labels[output] = output
}

///|
fn infer_carrier_qualified_labels(
  construction : Construction,
  side : @schema.Side,
  previous : Map[String, String],
  schema : @schema.Schema,
  labels : Map[String, String],
) -> Unit raise Abort {
  for index in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, index).unwrap()
    let slot = infer_carrier_slot_name(construction, field.name)
    if previous.get(slot) is Some(label) {
      let output = infer_carrier_slot_name(
        construction,
        @schema.Qualified(side, slot),
      )
      spend_infer_key_label_pair(construction, (output, label))
      labels[output] = label
    }
  }
}

///|
// A fused ranking has a new value generation. Its selected group/candidate
// roles receive their currently authored selector names, not the chronological
// label of a former row merely because the physical spelling is reused.
fn infer_carrier_ranking_role(
  construction : Construction,
  argument : @query.SgaArgument,
  fields : Array[@schema.FieldName],
  labels : Map[String, String],
) -> Unit raise Abort {
  let arguments = match argument {
    ListValue(items) => items
    _ => [argument]
  }
  if arguments.length() != fields.length() {
    raise Abort(InvalidContext)
  }
  for index in 0..<fields.length() {
    construction.infer_budget.spend(1, construction.generated)
    guard arguments[index] is FieldReference(path) && !path.is_empty() else {
      raise Abort(InvalidContext)
    }
    let authored = path.last().unwrap().value
    let slot = infer_carrier_slot_name(construction, fields[index])
    spend_infer_key_label_pair(construction, (slot, authored))
    let label = match labels.get(slot) {
      Some(previous) => {
        spend_infer_key_label_pair(construction, (previous, authored))
        // An ambiguous name is unusable only if Common later selects this
        // slot. Keep the marker sticky; an unrelated discarded branch must
        // not fail merely because another branch contains an omitted key.
        if previous == authored {
          authored
        } else {
          ""
        }
      }
      None => authored
    }
    construction.infer_budget.spend_text(slot, construction.generated)
    labels[slot] = label
  }
}

///|
fn script_carrier_key_labels(
  construction : Construction,
  sources : ScriptSources,
  scope : JoinChainScope,
  pipeline : @pipeline.CheckedPipeline,
  target : @pipeline.Target,
  known : Array[Input],
  fields : Array[String],
  call : @query.SgaCall,
) -> Array[(String, String)] raise Abort {
  if !construction.infer_labels {
    return []
  }
  construction.infer_budget.spend(1, construction.generated)
  guard target is Step(index) &&
    @pipeline.step_at(pipeline, index) is Some(step) &&
    step.input is Some(input) &&
    @pipeline.carrier_at(pipeline, input) is Some(input_carrier) else {
    raise Abort(InvalidContext)
  }
  let original = infer_carrier_input_slots(construction, input_carrier)
  let previous = infer_carrier_label_index(construction, scope.key_labels)
  let mut copied = original
  let labels : Map[String, String] = Map([])
  let excluded : Map[String, Bool] = Map([])
  let mut fresh = true
  match step.operation {
    Vector(checked) =>
      if @vector.operation(checked) == @vector.NormalizeVectors {
        guard @vector.input(checked) is VectorValue(vectors) else {
          raise Abort(InvalidContext)
        }
        let slot = infer_carrier_slot_name(
          construction,
          @carrier.vector_components(vectors).name,
        )
        copied[slot] = false
        // A replaced Vector is never a scalar item-key component. Do not
        // reuse its former label or expose its possibly private slot spelling.
        excluded[slot] = true
      }
    Pool(checked) => {
      copied = Map([])
      let options = @vector.pooled_options(checked)
      for index in 0..<@vector.pool_group_count(options) {
        let slot = infer_carrier_slot_name(
          construction,
          @vector.pool_group_at(options, index).unwrap(),
        )
        copied[slot] = true
      }
      let components = infer_carrier_slot_name(
        construction,
        @carrier.vector_components(@vector.pool_member_vectors(checked)).name,
      )
      // Pool reduction creates a new Vector value, not the old components
      // slot. Vectors cannot enter a scalar INFER key tuple.
      excluded[components] = true
      if @vector.pool_output_id(options) is Some(name) {
        // output_id is a new authored alias even when it spells the sole by
        // field's name; the group value correspondence is Common-checked.
        spend_infer_key_label_pair(construction, (name, name))
        labels[name] = name
      }
    }
    WindowGroup(checked) => {
      copied = Map([])
      construction.infer_budget.spend(
        @schema.field_count(@relation.output_schema(checked)),
        construction.generated,
      )
      guard @relation.group(checked) is Some(group) else {
        raise Abort(InvalidContext)
      }
      for key in @relation.group_keys(group) {
        let slot = infer_carrier_slot_name(construction, key.field)
        copied[slot] = true
      }
    }
    Sequence(checked) => {
      copied = Map([])
      construction.infer_budget.spend(
        @schema.field_count(@relation.sequence_output(checked)),
        construction.generated,
      )
      for key in @relation.sequence_keys(checked) {
        let slot = infer_carrier_slot_name(construction, key.field)
        copied[slot] = true
      }
    }
    AsOfJoin(checked~, ..) => {
      copied = Map([])
      fresh = false
      for index in 0..<@evidence.asof_projection_count(checked) {
        infer_carrier_temporal_projection(
          construction,
          @evidence.asof_projection_at(checked, index).unwrap(),
          labels,
        )
      }
    }
    IntervalJoin(right~, checked~) => {
      copied = Map([])
      fresh = false
      construction.infer_budget.spend(fields.length(), construction.generated)
      match @join_shape.interval_projection(checked) {
        Some(projections) =>
          for projection in projections {
            infer_carrier_temporal_projection(construction, projection, labels)
          }
        None => {
          infer_carrier_qualified_labels(
            construction,
            @schema.Left,
            previous,
            @join_shape.interval_input_schema(checked, @schema.Left),
            labels,
          )
          let kind = @join_shape.interval_kind(checked)
          if kind != @join_shape.Semi && kind != @join_shape.Anti {
            let right_labels = infer_carrier_target_labels(
              construction, sources, pipeline, right, known,
            )
            infer_carrier_qualified_labels(
              construction,
              @schema.Right,
              right_labels,
              @join_shape.interval_input_schema(checked, @schema.Right),
              labels,
            )
          }
        }
      }
    }
    Ranking(checked) => {
      copied = Map([])
      fresh = false
      let options = @vector.merged_ranking_options(checked)
      for (role, argument) in call.arguments {
        construction.infer_budget.spend(1, construction.generated)
        construction.infer_budget.spend_text(role, construction.generated)
        if role == "by" {
          construction.infer_budget.spend(
            @vector.ranking_by_count(options),
            construction.generated,
          )
          infer_carrier_ranking_role(
            construction,
            argument,
            @vector.ranking_by(options),
            labels,
          )
        } else if role == "candidate" {
          infer_carrier_ranking_role(
            construction,
            argument,
            [@vector.ranking_candidate(options)],
            labels,
          )
        }
      }
      for name in ["score", "rank"] {
        spend_infer_key_label_pair(construction, (name, name))
        labels[name] = name
      }
    }
    Event(_) | Window(_) | Calendar(_) | Projection(_) | Unary(_) => ()
    _ => raise Abort(InvalidContext)
  }
  let result : Array[(String, String)] = []
  for slot in fields {
    construction.infer_budget.spend(1, construction.generated)
    construction.infer_budget.spend_text(slot, construction.generated)
    let label = match labels.get(slot) {
      Some(label) => Some(label)
      None => {
        construction.infer_budget.spend_text(slot, construction.generated)
        if copied.get(slot).unwrap_or(false) {
          construction.infer_budget.spend_text(slot, construction.generated)
          previous.get(slot)
        } else {
          construction.infer_budget.spend_text(slot, construction.generated)
          if fresh && !excluded.contains(slot) {
            Some(slot)
          } else {
            None
          }
        }
      }
    }
    if label is Some(label) {
      spend_infer_key_label_pair(construction, (slot, label))
      result.push((slot, label))
    }
  }
  result
}
