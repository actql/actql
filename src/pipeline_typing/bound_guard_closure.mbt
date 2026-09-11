///|
struct BoundGuardClosure {
  closure : ContextualClosure
  entries : Array[BoundAuthorGuards]
  work : Int
  text : Int
}

///|
/// Resolve quantities per producer visit, without claiming Program/Invocation
/// identity or source consistency between different invocations of a template.
pub fn bind_contextual_guards(
  closure : ContextualClosure,
  bindings : Array[@parameter.BoundValues?],
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[BoundGuardClosure, ProducerOrderIssue] {
  let mut current = closure.entries[0].pipeline
  try {
    if max_work < 0 || max_text_bytes < 0 {
      fail(current.source, InvalidLimits)
    }
    if bindings.length() != closure.guards.length() {
      fail(current.source, GuardBindingCountMismatch)
    }
    let mut work = max_work
    let mut text = max_text_bytes
    let entries : Array[BoundAuthorGuards] = []
    for i in 0..<closure.guards.length() {
      let guards = closure.guards[i]
      current = guards.pipeline
      if work == 0 {
        fail(current.source, BudgetExceeded)
      }
      work -= 1
      let bound = match
        bind_author_guards(
          guards,
          bindings[i],
          max_work=work,
          max_text_bytes=text,
        ) {
        Ok(v) => v
        Err(e) => raise Stop(e)
      }
      let (w, t) = bound_guard_usage(bound)
      work -= w
      text -= t
      entries.push(bound)
    }
    Ok({ closure, entries, work: max_work - work, text: max_text_bytes - text, })
  } catch {
    Stop(issue) => Err({ pipeline: current, issue, })
  }
}

///|
pub fn bound_guard_closure_source(v : BoundGuardClosure) -> ContextualClosure {
  v.closure
}

///|
pub fn bound_guard_closure_at(
  v : BoundGuardClosure,
  index : Int,
) -> BoundAuthorGuards? {
  v.entries.get(index)
}

///|
/// Additional binding cost; does not include the retained closure's usage.
pub fn bound_guard_closure_usage(v : BoundGuardClosure) -> (Int, Int) {
  (v.work, v.text)
}
