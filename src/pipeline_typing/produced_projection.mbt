///|
struct ProducedProjection {
  input : ProducedInput
  usage : Usage
}

///|
/// Project a Relation producer without inventing an authored pipeline step.
/// This preserves the original row order; it does not apply Result ordering.
pub fn project_produced_input(
  pipeline : CheckedPipeline,
  target : Target,
  projection : @relation.CheckedOperation,
  limits : Limits,
) -> Result[ProducedProjection, Issue] {
  let source = @relation.source(projection)
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_tokens < 0 ||
      limits.max_depth < 0 ||
      limits.max_steps < 0 {
      fail(source, InvalidLimits)
    }
    if @relation.operation(projection) != @relation.Select {
      fail(source, InvalidBody)
    }
    let schema = match schema_at(pipeline, target) {
      Some(s) => s
      None => fail(source, IncompleteSchema)
    }
    if !physical_equal(schema, @relation.input_schema(projection)) {
      fail(source, KeyEvidence(InputContractMismatch))
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      tokens: limits.max_tokens,
    }
    spend(b, source, 1)
    let original = produced_input(pipeline, target).unwrap()
    let keys = match
      @evidence.advance_keys(original.keys, projection, {
        max_work: b.work,
        max_name_bytes: b.text,
      }) {
      Ok(v) => v
      Err(e) =>
        raise Stop({
          kind: KeyEvidence(e.kind),
          source,
          path: e.path.copy(),
          span: e.span,
          range: None,
        })
    }
    b.work -= keys.work
    b.text -= keys.name_bytes
    let ranked = vector_result(
      source,
      @vector.transfer_ranking_unary(
        original.ranking.unwrap_or(@vector.ranking_relation(original.carrier)),
        projection,
        {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
        },
      ),
    )
    b.work -= ranked.usage.work
    b.nodes -= ranked.usage.nodes
    b.text -= ranked.usage.text_bytes
    let window = transfer_window(
      b,
      source,
      target,
      pipeline.steps,
      Unary(projection),
      pipeline.produced_inputs,
    )
    let delta = transfer_delta(b, source, original.delta, projection)
    Ok({
      input: {
        ..original,
        carrier: @carrier.relation(
          @carrier.typed_rows(@relation.output_schema(projection)),
        ),
        keys: Some(keys.keys),
        ranking: Some(ranked.input),
        window,
        delta,
        projection: Some(projection),
      },
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens: 0,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn projected_input(value : ProducedProjection) -> ProducedInput {
  value.input
}

///|
pub fn projected_input_usage(value : ProducedProjection) -> Usage {
  value.usage
}
