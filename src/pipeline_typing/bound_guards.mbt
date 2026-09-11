///|
struct BoundAuthorGuards {
  occurrences : AuthorGuards
  bindings : @parameter.BoundValues?
  values : Array[Int64]
  work : Int
  text : Int
}

///|
pub fn bound_guard_occurrences(v : BoundAuthorGuards) -> AuthorGuards {
  v.occurrences
}

///|
pub fn bound_guard_bindings(v : BoundAuthorGuards) -> @parameter.BoundValues? {
  v.bindings
}

///|
pub fn bound_guard_value_at(v : BoundAuthorGuards, index : Int) -> Int64? {
  v.values.get(index)
}

///|
pub fn bound_guard_usage(v : BoundAuthorGuards) -> (Int, Int) {
  (v.work, v.text)
}

///|
/// Bind guard quantities only. Source/witness identities, governing laws,
/// candidate completeness and enforcement remain separate checks.
pub fn bind_author_guards(
  guards : AuthorGuards,
  bindings : @parameter.BoundValues?,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[BoundAuthorGuards, Issue] {
  try {
    let p = guards.pipeline
    if max_work < 0 || max_text_bytes < 0 {
      fail(p.source, InvalidLimits)
    }
    let b : Budget = {
      limits: {
        max_steps: 0,
        max_work,
        max_text_bytes,
        max_nodes: 0,
        max_tokens: 0,
        max_depth: 0,
      },
      work: max_work,
      text: max_text_bytes,
      nodes: 0,
      tokens: 0,
    }
    let by_name : Map[String, @parameter.BoundParameter] = Map([])
    if bindings is Some(values) {
      guard p.parameters is Some(declarations) &&
        physical_equal(declarations, @parameter.bound_declarations(values)) else {
        fail(p.source, GuardBindingOwnerMismatch)
      }
      spend(b, p.source, @parameter.bound_value_count(values))
      for i in 0..<@parameter.bound_value_count(values) {
        let value = @parameter.bound_value_at(values, i).unwrap()
        charge(b, p.source, value.name)
        by_name[value.name] = value
      }
    }
    spend(b, p.source, guards.entries.length())
    let values : Array[Int64] = []
    for occurrence in guards.entries {
      let number = match occurrence.value {
        Literal(n) => n
        Parameter(name) => {
          charge(b, occurrence.source, name)
          let entry = match by_name.get(name) {
            Some(v) => v
            None => fail(occurrence.source, MissingGuardBinding(name))
          }
          let n = match entry.value.value {
            Number(n) =>
              match @scalar.read_safe_integer(n) {
                Some(n) if n > 0L => n
                _ => fail(occurrence.source, InvalidGuardValue(name))
              }
            _ => fail(occurrence.source, InvalidGuardValue(name))
          }
          n
        }
      }
      values.push(number)
    }
    Ok({
      occurrences: guards,
      bindings,
      values,
      work: max_work - b.work,
      text: max_text_bytes - b.text,
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}
