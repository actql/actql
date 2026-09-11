///|
pub(all) enum ApplicationCoverageIssue {
  InvalidLimits
  ForeignProgram
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
  max_work~ : Int,
) -> Result[ApplicationCoverage, ApplicationCoverageIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if joins is Some(joined) &&
    !physical_equal(program, @program.join_application_program(joined)) {
    return Err(ForeignProgram)
  }
  let sources = match check_source_coverage(graph, program, max_work~) {
    Ok(v) => v
    Err(e) => return Err(Source(e))
  }
  let consumers = match
    check_consumer_coverage(
      graph,
      sequence,
      joins~,
      max_work=max_work - sources.work,
    ) {
    Ok(v) => v
    Err(e) => return Err(Consumer(e))
  }
  Ok({ sources, consumers, work: sources.work + consumers.work, })
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
