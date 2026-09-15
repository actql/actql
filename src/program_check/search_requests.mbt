///|
// The failed search collector already validated ownership and measured both
// operands. Read its retained frontier; never rerun proof search in diagnostics.
fn search_request_parts(
  cause : LocalConstructionFailure,
) -> (@decode.Cursor, Bool, Bool)? {
  let (owner, index, left, right) = match cause {
    Closure(AsOfSearch(MissingSearchBound(bounds))) =>
      (
        @context.asof_search_bound_owner(bounds),
        @context.asof_search_bound_requirement(bounds),
        @context.asof_search_bound_candidate_count(bounds, 0) == 0,
        @context.asof_search_bound_candidate_count(bounds, 1) == 0,
      )
    Closure(IntervalSearch(MissingSearchBound(bounds))) =>
      (
        @context.interval_search_bound_owner(bounds),
        @context.interval_search_bound_requirement(bounds),
        @context.interval_search_bound_candidate_count(bounds, 0) == 0,
        @context.interval_search_bound_candidate_count(bounds, 1) == 0,
      )
    _ => return None
  }
  guard left || right else { return None }
  guard @context.operation_requirements_at(
      @context.operation_resolution_requirements(owner),
      index,
    )
    is Some(site) &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return None
  }
  Some((step.source, left, right))
}
