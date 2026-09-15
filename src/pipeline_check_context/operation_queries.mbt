///|
pub(all) enum OperationQueryIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner(Int)
  InvalidQuery(Int)
  DimensionMismatch(Int, Double, Int)
  InvalidComponent(Int, Int)
  Scalar(OperationScalarIssue)
} derive(Eq, Debug)

///|
struct AdmittedOperationQuery {
  operation : @vector.CheckedVector
  query : @vector.Query
  parameter : @parameter.BoundParameter?
  count : Int
}

///|
pub struct OperationQueryResolution {
  requirement_index : Int
  site : OperationRequirementSite
  query : AdmittedOperationQuery
}

///|
struct ProgramOperationQueries {
  requirements : ProgramOperationRequirements
  ranges : ProgramOperationRanges
  entries : Array[OperationQueryResolution]
  work : Int
}

///|
pub fn operation_query_parameter(
  v : AdmittedOperationQuery,
) -> @parameter.BoundParameter? {
  v.parameter
}

///|
pub fn operation_query_operation(
  v : AdmittedOperationQuery,
) -> @vector.CheckedVector {
  v.operation
}

///|
pub fn operation_query_count(v : AdmittedOperationQuery) -> Int {
  v.count
}

///|
pub fn operation_query_at(v : AdmittedOperationQuery, index : Int) -> Double? {
  match v.parameter {
    Some(p) =>
      match p.value.value {
        Array(values) =>
          match @value.element_at(values, index) {
            Some(Number(n)) => Some(n)
            _ => None
          }
        _ => None
      }
    None => @vector.query_value_at(v.query, index)
  }
}

///|
/// Binary32 nearest-ties-even admission widened exactly to binary64.
/// Source components remain separately available; internal signed zero is kept.
pub fn operation_query_quantized_at(
  v : AdmittedOperationQuery,
  index : Int,
) -> Double? {
  operation_query_at(v, index).map(n => Float::from_double(n).to_double())
}

///|
pub fn check_program_operation_queries(
  ranges : ProgramOperationRanges,
  max_work : Int,
  max_resolutions : Int,
) -> Result[ProgramOperationQueries, OperationQueryIssue] {
  if max_work < 0 || max_resolutions < 0 {
    return Err(InvalidLimits)
  }
  if ranges.work >= max_work {
    return Err(BudgetExceeded)
  }
  let b = { remaining: max_work - ranges.work - 1, }
  let requirements = ranges.requirements
  let stages = requirements.stages
  let entries : Array[OperationQueryResolution] = []
  let mut previous : (Int, Int, Int)? = None
  let mut cached : AdmittedOperationQuery? = None
  try {
    for i in 0..<requirements.entries.length() {
      scalar_spend(b, 1)
      let site = requirements.entries[i]
      let name = match site.requirement {
        VectorRequirement(BindQuery(name)) => Some(name)
        VectorRequirement(MatchDimensions) => None
        _ => continue
      }
      if entries.length() == max_resolutions {
        return Err(BudgetExceeded)
      }
      let coordinate = (site.stage, site.producer_visit, site.step)
      if previous != Some(coordinate) {
        scalar_spend(b, 1)
        let visit = stages.contexts[site.stage].visits[site.producer_visit]
        if !physical_equal(
            @parameter_slots.pipeline(visit.collected),
            site.pipeline,
          ) {
          return Err(ForeignOwner(i))
        }
        guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
          return Err(ForeignOwner(i))
        }
        guard step.operation is @pipeline.Vector(operation) else {
          return Err(ForeignOwner(i))
        }
        guard @vector.query(operation) is Some(query) else {
          return Err(ForeignOwner(i))
        }
        guard @vector.input(operation) is @carrier.VectorValue(vectors) else {
          return Err(ForeignOwner(i))
        }
        let parameter = match @vector.query_parameter(query) {
          Some(n) => Some(operation_scalar_parameter(visit, n, i, b))
          None => None
        }
        let count = match parameter {
          Some(p) =>
            match p.value.value {
              Array(values) => @value.element_count(values)
              _ => return Err(InvalidQuery(i))
            }
          None =>
            match @vector.query_value_count(query) {
              Some(n) => n
              None => return Err(InvalidQuery(i))
            }
        }
        if count == 0 {
          return Err(InvalidQuery(i))
        }
        let expected = @carrier.vector_dimensions(vectors)
        if expected != count.to_double() {
          return Err(DimensionMismatch(i, expected, count))
        }
        scalar_spend(b, count)
        let admitted = { operation, query, parameter, count, }
        for j in 0..<count {
          guard operation_query_at(admitted, j) is Some(n) else {
            return Err(InvalidComponent(i, j))
          }
          if @scalar.read_finite_number(n) is None ||
            (n == 0.0 && 1.0 / n < 0.0) ||
            @scalar.read_finite_number(Float::from_double(n).to_double())
            is None {
            return Err(InvalidComponent(i, j))
          }
        }
        cached = Some(admitted)
        previous = Some(coordinate)
      }
      let query = cached.unwrap()
      if name is Some(n) {
        guard query.parameter is Some(p) else { return Err(ForeignOwner(i)) }
        scalar_spend(b, n.length())
        scalar_spend(b, p.name.length())
        if n != p.name {
          return Err(ForeignOwner(i))
        }
      }
      entries.push({ requirement_index: i, site, query, })
    }
    Ok({ ranges, requirements, entries, work: max_work - b.remaining, })
  } catch {
    OperationScalarStop(BudgetExceeded) => Err(BudgetExceeded)
    OperationScalarStop(issue) => Err(Scalar(issue))
  }
}

///|
pub fn operation_queries_ranges(
  v : ProgramOperationQueries,
) -> ProgramOperationRanges {
  v.ranges
}

///|
pub fn operation_queries_count(v : ProgramOperationQueries) -> Int {
  v.entries.length()
}

///|
pub fn operation_query_resolution_at(
  v : ProgramOperationQueries,
  index : Int,
) -> OperationQueryResolution? {
  v.entries.get(index)
}

///|
pub fn operation_queries_work(v : ProgramOperationQueries) -> Int {
  v.work
}
