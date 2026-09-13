///|
pub(all) enum GuardBindingIssue {
  InvalidLimits
  WorkLimit
  BindingMismatch(Int)
} derive(Eq, Debug)

///|
/// Local proof bindings agree with one already bound guard context.
/// Foreign producer applications still require their own context checks.
struct GuardApplications {
  applications : Applications
  guards : @pipeline.BoundAuthorGuards
  local_count : Int
  work : Int
}

///|
pub fn check_guard_bindings(
  applications : Applications,
  guards : @pipeline.BoundAuthorGuards,
  max_work~ : Int,
) -> Result[GuardApplications, GuardBindingIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let n = applications.entries.length()
  if n > max_work {
    return Err(WorkLimit)
  }
  let p = @pipeline.author_guards_pipeline(
    @pipeline.bound_guard_occurrences(guards),
  )
  let expected = @pipeline.bound_guard_bindings(guards)
  let mut local_count = 0
  for i, entry in applications.entries {
    if entry is Some(app) && physical_equal(app.pipeline, p) {
      local_count += 1
      if app.bindings is Some(bindings) {
        guard expected is Some(values) &&
          physical_equal(bindings.values, values) else {
          return Err(BindingMismatch(i))
        }
      }
      if app.enforcement is Some(SequenceEnforcement(selection)) &&
        @sequence.bound_guards(selection) is Some(bound) {
        match (@pipeline.bound_guard_bindings(bound), expected) {
          (None, None) => ()
          (Some(actual), Some(expected)) if physical_equal(actual, expected) =>
            ()
          _ => return Err(BindingMismatch(i))
        }
      }
    }
  }
  Ok({ applications, guards, local_count, work: n, })
}

///|
pub fn guard_application_source(v : GuardApplications) -> Applications {
  v.applications
}

///|
pub fn guard_application_context(
  v : GuardApplications,
) -> @pipeline.BoundAuthorGuards {
  v.guards
}

///|
pub fn guard_application_count(v : GuardApplications) -> Int {
  v.local_count
}

///|
pub fn guard_application_work(v : GuardApplications) -> Int {
  v.work
}
