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
/// Consumption for Graph input, sequence and optional join applications.
/// Source authority and other operation obligations remain separate.
struct ConsumerCoverage {
  graph : GraphInputs
  sequence : @sequence.Applications
  joins : @program.JoinApplications?
  work : Int
}

///|
pub fn check_consumer_coverage(
  graph : GraphInputs,
  sequence : @sequence.Applications,
  joins? : @program.JoinApplications? = None,
  max_work~ : Int,
) -> Result[ConsumerCoverage, ConsumerCoverageIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(
      checked_pipeline(graph),
      @sequence.application_pipeline(sequence),
    ) {
    return Err(ForeignPipeline)
  }
  if !physical_equal(
      checked_sources(graph),
      @sequence.application_sources(sequence),
    ) {
    return Err(ForeignSources)
  }
  if @policy.cid(selected_policy(graph)) !=
    @policy.cid(@sequence.application_policy(sequence)) {
    return Err(ForeignPolicy)
  }
  if joins is Some(joined) {
    if !physical_equal(
        checked_pipeline(graph),
        @program.join_application_pipeline(joined),
      ) {
      return Err(ForeignPipeline)
    }
    if !physical_equal(
        checked_sources(graph),
        @program.join_application_sources(joined),
      ) {
      return Err(ForeignSources)
    }
    if @policy.cid(selected_policy(graph)) !=
      @policy.cid(@program.join_application_policy(joined)) {
      return Err(ForeignPolicy)
    }
  }
  let mixed = @wire.program_claim_mixed(
    @host.source_claims(checked_sources(graph)),
  ).unwrap()
  let n = @wire.mixed_limit_count(mixed)
  let inputs = @pipeline.input_count(checked_pipeline(graph))
  if inputs > max_work / 2 || n > max_work - inputs * 2 {
    return Err(WorkLimit)
  }
  let graph_limits : Map[String, Bool] = Map([])
  for i in 0..<inputs {
    for limit in [input_limit(graph, i, Nodes), input_limit(graph, i, Edges)] {
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
    let join_consumes = match joins {
      Some(joined) => @program.join_consumes_limit(joined, i)
      None => false
    }
    if (graph_consumes && sequence_consumes) ||
      (graph_consumes && join_consumes) ||
      (sequence_consumes && join_consumes) {
      return Err(DuplicateConsumer(i))
    }
    if !graph_consumes && !sequence_consumes && !join_consumes {
      return Err(UnconsumedLimit(i))
    }
  }
  Ok({ graph, sequence, joins, work: inputs * 2 + n, })
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

///|
pub fn consumer_coverage_joins(
  v : ConsumerCoverage,
) -> @program.JoinApplications? {
  v.joins
}
