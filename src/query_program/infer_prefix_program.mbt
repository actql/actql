///|
// All inferred-key prefixes in one compilation share this allowance. Checking
// binds existing evidence; it neither acquires inputs nor invokes a ModelTask.
priv struct InferPrefixBudget {
  mut remaining_work : Int
}

///|
// Names are projected only after Common proves the exact physical key tuple.
// Chronological authored labels remain bound to a slot hidden by a later SET.
priv struct InferInputLabels {
  visible : Array[(String, String)]
  ranges : Array[(@query.NamePart, Array[(String, String)])]
  key_labels : Array[(String, String)]
}

///|
priv struct InferPrefixProjection {
  checked : @evidence.CheckedInfer
  keys : Array[(String, String)]
}

///|
fn InferPrefixBudget::spend(
  self : InferPrefixBudget,
  used : Int,
  origin : @origin.Origin,
) -> Unit raise Abort {
  if used < 0 || used > self.remaining_work {
    raise Abort(
      Expression({ issue: @expression.WorkLimit, origin: Some(origin), }),
    )
  }
  self.remaining_work -= used
}

///|
// The builder/common schema owner already admitted scalar strings. Count their
// UTF-8 bytes without allocating an encoded copy or an unbounded search array.
fn InferPrefixBudget::spend_text(
  self : InferPrefixBudget,
  text : String,
  origin : @origin.Origin,
) -> Unit raise Abort {
  for char in text {
    let scalar = char.to_int()
    self.spend(
      if scalar < 128 {
        1
      } else if scalar < 2048 {
        2
      } else if scalar < 65536 {
        3
      } else {
        4
      },
      origin,
    )
  }
}

///|
// Retain the original producer stages, input declarations, parameters, Catalog
// and selected environment owners. Carrier probes and omitted-key INFER share
// this owner and allowance rather than independently renewing checker work.
fn checked_query_prefix_pipeline(
  construction : Construction,
  query : @query.Query,
  context : Context,
  prior_stages : Array[@builder.Node],
  declarations : Array[(String, @builder.Node)],
  prefix_nodes : Array[@builder.Node],
  limits : Limits,
  budget : InferPrefixBudget,
) -> @pipeline.CheckedPipeline raise Abort {
  if budget.remaining_work <= 0 {
    raise Abort(
      Expression({
        issue: @expression.WorkLimit,
        origin: Some(construction.generated),
      }),
    )
  }
  let root = program_root(
    construction,
    context,
    prior_stages +
    [
      construction.object([
        ("id", construction.text(context.stage_id)),
        ("inputs", construction.object(declarations)),
        ("steps", construction.array(prefix_nodes)),
        ("results", construction.object([])),
      ]),
    ],
    staged_result_exports=Some([]),
  )
  // The construction owner already bounds snapshot admission. Charge its
  // measured tree before lending the remaining work to any semantic owner.
  let source = match @builder.snapshot(construction.builder, root) {
    Ok(source) => source
    Err(issue) => raise Abort(Construction(issue))
  }
  budget.spend(@builder.usage(source).nodes, construction.generated)
  // Successful member probes report their actual work. A refused probe keeps
  // its existing full reservation; do not mint another allowance for checking.
  let (source, member_work) = resolve_query_members_accounted(
    source,
    @query.query_document(query),
    context,
    { ..limits, max_expression_work: budget.remaining_work, },
    defer_terminal_infer_output=true,
  )
  budget.spend(member_work, construction.generated)
  // Prefix envelope admission scans the retained source independently of the
  // builder's tree admission and the member-resolution pass.
  budget.spend(@builder.usage(source).nodes, construction.generated)
  let prefix = match @program.admit_generated_prefix(source, limits.program) {
    Ok(prefix) => prefix
    Err(issue) => raise Abort(Admission(issue))
  }
  let checked = match
    check_query_prefix(prefix, context, {
      ..limits,
      max_expression_work: budget.remaining_work,
    }) {
    Ok(checked) => checked
    Err(issue) => raise Abort(BindingPreparationSource(issue, source))
  }
  // This aggregate includes declaration admission and, where applicable,
  // Catalog registration, local preparation, calendar checks and attachments.
  budget.spend(checked.work, construction.generated)
  budget.spend(1, construction.generated)
  let stage = match
    @stage_results.topology_stage_at(checked.topology, prior_stages.length()) {
    Some(stage) => stage
    None => raise Abort(InvalidContext)
  }
  @pipeline_parameters.pipeline(
    @stage_parameters.collection(@stage_results.topology_stage_source(stage)),
  )
}

///|
// The unfinished Stage ends at INFER before join-back or result projection can
// alter its evidence or slots. Key selection belongs only to Common.
fn infer_prefix_check(
  construction : Construction,
  query : @query.Query,
  context : Context,
  prior_stages : Array[@builder.Node],
  declarations : Array[(String, @builder.Node)],
  prefix_nodes : Array[@builder.Node],
  producer : String,
  limits : Limits,
  budget : InferPrefixBudget,
  visible : InferInputLabels,
  _authored_aliases : Array[(String, String)],
) -> InferPrefixProjection raise Abort {
  let pipeline = checked_query_prefix_pipeline(
    construction, query, context, prior_stages, declarations, prefix_nodes, limits,
    budget,
  )
  let index = match @pipeline.lookup(pipeline, producer) {
    Some(@pipeline.Step(index)) => index
    _ => raise Abort(InvalidContext)
  }
  let infer = match @pipeline.step_at(pipeline, index) {
    Some({ operation: @pipeline.Infer(infer), .. }) => infer
    _ => raise Abort(InvalidContext)
  }
  let witness = @evidence.infer_key_witness(infer)
  let count = @evidence.infer_key_count(infer)
  if @evidence.key_field_count(witness) != count {
    raise Abort(UnsupportedInfer)
  }
  let keys : Array[(String, String)] = []
  for key_index in 0..<count {
    budget.spend(1, construction.generated)
    let binding = @evidence.infer_key_at(infer, key_index).unwrap()
    let slot = @schema.reference_name(binding.field)
    budget.spend_text(slot, construction.generated)
    // The label belongs to this exact surviving slot generation. A newer
    // same-spelled column or an older range snapshot cannot rename its key.
    let mut label : String? = None
    for entry in visible.key_labels {
      budget.spend(1, construction.generated)
      budget.spend_text(slot, construction.generated)
      budget.spend_text(entry.0, construction.generated)
      if entry.0 == slot {
        label = Some(entry.1)
        break
      }
    }
    let name = match label {
      Some(name) => name
      None => raise Abort(UnsupportedInfer)
    }
    budget.spend_text(name, construction.generated)
    let normalized_name = ascii_upper(name)
    if name.is_empty() || ["OUTCOME", "VALUE"].contains(normalized_name) {
      raise Abort(UnsupportedInfer)
    }
    for key in keys {
      budget.spend(1, construction.generated)
      budget.spend_text(key.0, construction.generated)
      budget.spend_text(name, construction.generated)
      budget.spend_text(key.1, construction.generated)
      budget.spend_text(slot, construction.generated)
      if key.1 == slot || ascii_upper(key.0) == normalized_name {
        raise Abort(UnsupportedInfer)
      }
    }
    keys.push((name, slot))
  }
  { checked: infer, keys, }
}

///|
// Script terms and carrier probes lend the same retained allowance. An aborted
// check keeps its reservation rather than leaving a fresh budget for a retry.
fn script_infer_prefix_check(
  construction : Construction,
  query : @query.Query,
  context : Context,
  sources : ScriptSources,
  nodes : Array[@builder.Node],
  producer : String,
  limits : Limits,
  visible : InferInputLabels,
  authored_aliases : Array[(String, String)],
) -> InferPrefixProjection raise Abort {
  let budget = construction.infer_budget
  if budget.remaining_work > sources.carrier_work {
    budget.remaining_work = sources.carrier_work
  }
  sources.carrier_work = 0
  let checked = infer_prefix_check(
    construction,
    query,
    context,
    sources.stages + sources.prior_stages,
    sources.declarations,
    nodes,
    producer,
    limits,
    budget,
    visible,
    authored_aliases,
  )
  sources.carrier_work = budget.remaining_work
  checked
}
