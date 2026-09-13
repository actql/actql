///|
fn same_guard_bindings(
  a : @pipeline.BoundAuthorGuards,
  b : @pipeline.BoundAuthorGuards,
) -> Bool {
  if !physical_equal(
      @pipeline.author_guards_pipeline(@pipeline.bound_guard_occurrences(a)),
      @pipeline.author_guards_pipeline(@pipeline.bound_guard_occurrences(b)),
    ) {
    return false
  }
  match (@pipeline.bound_guard_bindings(a), @pipeline.bound_guard_bindings(b)) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
/// Same immutable pipeline and effective Parameter binding, not numeric equality.
pub fn application_guard_bindings_match(
  v : Applications,
  expected : @pipeline.BoundAuthorGuards,
) -> Bool {
  if !physical_equal(
      v.pipeline,
      @pipeline.author_guards_pipeline(
        @pipeline.bound_guard_occurrences(expected),
      ),
    ) {
    return false
  }
  match v.guards {
    None => true
    Some(bound) => same_guard_bindings(bound, expected)
  }
}
