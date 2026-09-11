///|
pub(all) enum ApplicationCoverageIssue {
  InvalidLimits
  ForeignProgram
  WorkLimit
  MissingJoinApplications(Int)
  MissingComponentsApplications(Int)
  Source(SourceCoverageIssue)
  Consumer(ConsumerCoverageIssue)
} derive(Eq, Debug)

///|
/// Combined supported source/application and limit-consumer coverage.
/// Not external source authority, producer closure or execution permission.
struct ApplicationCoverage {
  sources : SourceCoverage
  consumers : ConsumerCoverage
  work : Int
}

///|
pub fn check_application_coverage(
  graph : GraphInputs,
  program : @program.Applications,
  sequence : @sequence.Applications,
  joins? : @program.JoinApplications? = None,
  components? : @program.ComponentsApplications? = None,
  max_work~ : Int,
) -> Result[ApplicationCoverage, ApplicationCoverageIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if joins is Some(joined) &&
    !physical_equal(program, @program.join_application_program(joined)) {
    return Err(ForeignProgram)
  }
  if components is Some(apps) &&
    !physical_equal(program, @program.components_application_program(apps)) {
    return Err(ForeignProgram)
  }
  let sources = match check_source_coverage(graph, program, max_work~) {
    Ok(v) => v
    Err(e) => return Err(Source(e))
  }
  let mut remaining = max_work - sources.work
  // An absent ledger is valid only if the pipeline has no corresponding steps.
  // Limit-set completeness alone cannot prove operation coverage: the caller
  // could omit both an operation's application and its limit artifact.
  if joins is None || components is None {
    let steps = @pipeline.step_count(checked_pipeline(graph))
    if steps > remaining {
      return Err(WorkLimit)
    }
    remaining -= steps
    for i in 0..<steps {
      match @pipeline.step_at(checked_pipeline(graph), i).unwrap().operation {
        @pipeline.Join(..)
        | @pipeline.CrossJoin(..)
        | @pipeline.IntervalJoin(..) =>
          if joins is None {
            return Err(MissingJoinApplications(i))
          }
        @pipeline.Graph(op) =>
          if components is None && @graph.operation(op) == @graph.Components {
            return Err(MissingComponentsApplications(i))
          }
        _ => ()
      }
    }
  }
  let consumers = match
    check_consumer_coverage(
      graph,
      sequence,
      joins~,
      components~,
      max_work=remaining,
    ) {
    Ok(v) => v
    Err(e) => return Err(Consumer(e))
  }
  Ok({ sources, consumers, work: max_work - remaining + consumers.work, })
}

///|
pub fn application_coverage_sources(v : ApplicationCoverage) -> SourceCoverage {
  v.sources
}

///|
pub fn application_coverage_consumers(
  v : ApplicationCoverage,
) -> ConsumerCoverage {
  v.consumers
}

///|
pub fn application_coverage_work(v : ApplicationCoverage) -> Int {
  v.work
}
