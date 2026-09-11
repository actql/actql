///|
/// Conditional successful output of an immutable producer, not measured data.
struct ProducedInput {
  pipeline : CheckedPipeline
  target : Target
  carrier : @carrier.Carrier
  rows : RowCount?
  graph : GraphCount?
  keys : @evidence.KeySet?
  ranking : @vector.RankingInput?
  order : LogicalOrder?
  window : WindowEvidence?
  delta : DeltaEvidence
}

///|
/// Retains the producer and its unresolved obligations. No public count or
/// uniqueness assertion can be substituted for this owner.
pub fn produced_input(
  pipeline : CheckedPipeline,
  target : Target,
) -> ProducedInput? {
  guard carrier_at(pipeline, target) is Some(carrier) else { return None }
  Some({
    pipeline,
    target,
    carrier,
    rows: row_count(pipeline, target),
    graph: graph_count(pipeline, target),
    keys: key_at(target, pipeline.keyed_inputs, pipeline.keyed_steps),
    ranking: ranking_evidence(pipeline, target),
    order: logical_order(pipeline, target),
    window: window_evidence_at(pipeline, target),
    delta: delta_at(target, pipeline.delta_inputs, pipeline.delta_steps),
  })
}

///|
pub fn input_producer(
  pipeline : CheckedPipeline,
  index : Int,
) -> ProducedInput? {
  pipeline.produced_inputs.get(index).bind(v => v)
}

///|
pub fn producer_pipeline(input : ProducedInput) -> CheckedPipeline {
  input.pipeline
}

///|
pub fn producer_target(input : ProducedInput) -> Target {
  input.target
}

///|
/// Original order in producer_pipeline's coordinates, with all producer debts.
pub fn producer_order(input : ProducedInput) -> LogicalOrder? {
  input.order
}
