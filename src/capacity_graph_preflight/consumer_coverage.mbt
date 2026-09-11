///|
pub(all) enum ConsumerCoverageIssue {
  InvalidLimits
  WorkLimit
  ForeignPipeline
  ForeignSources
  ForeignPolicy
  DuplicateConsumer(Int)
  UnconsumedLimit(Int)
} derive(Eq, Debug)

///|
/// Complete consumption for Graph input and sequence limits in this collection.
/// Source authority and other operation obligations remain separate.
struct ConsumerCoverage {
  graph : GraphInputs
  sequence : @sequence.Applications
  work : Int
}

///|
pub fn check_consumer_coverage(
  graph : GraphInputs,
  sequence : @sequence.Applications,
  max_work~ : Int,
) -> Result[ConsumerCoverage, ConsumerCoverageIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(graph.pipeline, @sequence.application_pipeline(sequence)) {
    return Err(ForeignPipeline)
  }
  if !physical_equal(graph.sources, @sequence.application_sources(sequence)) {
    return Err(ForeignSources)
  }
  if @policy.cid(graph.policy) !=
    @policy.cid(@sequence.application_policy(sequence)) {
    return Err(ForeignPolicy)
  }
  let mixed = @wire.program_claim_mixed(@host.source_claims(graph.sources)).unwrap()
  let n = @wire.mixed_limit_count(mixed)
  let inputs = graph.bindings.length()
  if inputs > max_work / 2 || n > max_work - inputs * 2 {
    return Err(WorkLimit)
  }
  let graph_limits : Map[String, Bool] = Map([])
  for pair in graph.bindings {
    for limit in [pair.0, pair.1] {
      if limit is Some(limit) {
        graph_limits[@wire.limit_cid(limit)] = true
      }
    }
  }
  for i in 0..<n {
    let graph_consumes = graph_limits.contains(
      @wire.limit_cid(@wire.mixed_limit_at(mixed, i).unwrap()),
    )
    let sequence_consumes = @sequence.consumes_limit(sequence, i)
    if graph_consumes && sequence_consumes {
      return Err(DuplicateConsumer(i))
    }
    if !graph_consumes && !sequence_consumes {
      return Err(UnconsumedLimit(i))
    }
  }
  Ok({ graph, sequence, work: inputs * 2 + n, })
}

///|
pub fn consumer_coverage_graph(v : ConsumerCoverage) -> GraphInputs {
  v.graph
}

///|
pub fn consumer_coverage_sequence(
  v : ConsumerCoverage,
) -> @sequence.Applications {
  v.sequence
}

///|
pub fn consumer_coverage_work(v : ConsumerCoverage) -> Int {
  v.work
}
