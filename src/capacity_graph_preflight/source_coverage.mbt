///|
pub(all) enum SourceCoverageIssue {
  InvalidLimits
  ForeignClaims
  WorkLimit
  UnsupportedSource(Int)
} derive(Eq, Debug)

///|
/// Source application coverage for the Host/Program/Graph-preflight subset.
/// Not policy authority, full consumer coverage or execution permission.
struct SourceCoverage {
  graph : GraphInputs
  program : @program.Applications
  work : Int
}

///|
pub fn check_source_coverage(
  graph : GraphInputs,
  program : @program.Applications,
  max_work~ : Int,
) -> Result[SourceCoverage, SourceCoverageIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let claims = @host.source_claims(checked_sources(graph))
  if !physical_equal(claims, @program.application_claims(program)) {
    return Err(ForeignClaims)
  }
  // GraphInputs is only constructed after successful mixed-closure admission.
  let mixed = @wire.program_claim_mixed(claims).unwrap()
  let arithmetic = @wire.program_claim_arithmetic(claims)
  let n = @wire.claim_count(arithmetic)
  if n > max_work {
    return Err(WorkLimit)
  }
  for i in 0..<n {
    if @host.source_at(checked_sources(graph), i) is Some(_) ||
      @program.application_at(program, i) is Some(_) ||
      @wire.mixed_enforced_limit(mixed, i) is Some(_) {
      continue
    }
    return Err(UnsupportedSource(i))
  }
  Ok({ graph, program, work: n, })
}

///|
pub fn source_coverage_graph(v : SourceCoverage) -> GraphInputs {
  v.graph
}

///|
pub fn source_coverage_program(v : SourceCoverage) -> @program.Applications {
  v.program
}

///|
pub fn source_coverage_work(v : SourceCoverage) -> Int {
  v.work
}
