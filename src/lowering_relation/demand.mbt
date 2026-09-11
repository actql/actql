///|
/// Occurrence-bound demand facts. Source-pointer serialization is deliberately
/// separate: these IDs are not semantic CIDs or wire paths.
struct DemandIndex {
  roots : RootIndex
  entries : Array[DemandEntry]
  conditions : Array[DemandCondition]
}

///|
pub struct DemandEntry {
  root_index : Int
  // Parent occurrence and semantic child ordinal (CASE: condition/branch pairs,
  // then ELSE). This distinguishes repeated occurrences of a shared expression.
  parent : (Int, Int)?
  expression : Expression
  condition : Int?
}

///|
pub(all) enum DemandTest {
  True
  NotTrue
  Null
} derive(Eq, Debug)

///|
pub struct DemandCondition {
  previous : Int?
  entry : Int
  predicate : DemandTest
}

///|
pub(all) struct DemandLimits {
  max_entries : Int
  max_conditions : Int
  max_pending : Int
  max_work : Int
}

///|
pub(all) enum DemandIssue {
  InvalidDemandLimits
  DemandLimit
}

///|
priv suberror DemandStop {
  Stop(DemandIssue)
}

///|
priv struct DemandBuilder {
  limits : DemandLimits
  mut work : Int
  entries : Array[DemandEntry]
  conditions : Array[DemandCondition]
  pending : Array[Int]
}

///|
fn DemandBuilder::tick(self : DemandBuilder) -> Unit raise DemandStop {
  if self.work == 0 {
    raise Stop(DemandLimit)
  }
  self.work -= 1
}

///|
fn DemandBuilder::entry(
  self : DemandBuilder,
  root : Int,
  expression : Expression,
  condition : Int?,
  parent? : (Int, Int)? = None,
) -> Int raise DemandStop {
  self.tick()
  if self.entries.length() == self.limits.max_entries {
    raise Stop(DemandLimit)
  }
  let id = self.entries.length()
  self.entries.push({ root_index: root, parent, expression, condition, })
  id
}

///|
fn DemandBuilder::condition(
  self : DemandBuilder,
  previous : Int?,
  entry : Int,
  predicate : DemandTest,
) -> Int raise DemandStop {
  self.tick()
  if self.conditions.length() == self.limits.max_conditions {
    raise Stop(DemandLimit)
  }
  let id = self.conditions.length()
  self.conditions.push({ previous, entry, predicate, })
  id
}

///|
pub fn demand_roots(index : DemandIndex) -> RootIndex {
  index.roots
}

///|
pub fn demand_entry_count(index : DemandIndex) -> Int {
  index.entries.length()
}

///|
pub fn demand_entry_at(index : DemandIndex, i : Int) -> DemandEntry? {
  index.entries.get(i)
}

///|
pub fn demand_condition_count(index : DemandIndex) -> Int {
  index.conditions.length()
}

///|
pub fn demand_condition_at(index : DemandIndex, i : Int) -> DemandCondition? {
  index.conditions.get(i)
}

///|
/// All children are recorded, including currently unselected branches. Tests
/// reference expression occurrences in this index, never reevaluation callbacks.
pub fn prepare_demand(
  roots : RootIndex,
  limits : DemandLimits,
) -> Result[DemandIndex, DemandIssue] {
  if limits.max_entries < 0 ||
    limits.max_conditions < 0 ||
    limits.max_pending < 0 ||
    limits.max_work < 0 {
    return Err(InvalidDemandLimits)
  }
  let b : DemandBuilder = {
    limits,
    work: limits.max_work,
    entries: [],
    conditions: [],
    pending: [],
  }
  try {
    for r = 0; r < roots.entries.length(); r = r + 1 {
      if limits.max_pending == 0 {
        raise Stop(DemandLimit)
      }
      b.pending.push(b.entry(r, roots.entries[r].expression, None))
      while b.pending.pop() is Some(id) {
        b.tick()
        let item = b.entries[id]
        let base = b.entries.length()
        match item.expression.body {
          Field(_, _) | Literal(_) | TypedNull => ()
          Unary(_, arg) => {
            let _ = b.entry(r, arg, item.condition, parent=Some((id, 0)))
          }
          Binary(_, left, right) => {
            let _ = b.entry(r, left, item.condition, parent=Some((id, 0)))
            let _ = b.entry(r, right, item.condition, parent=Some((id, 1)))
          }
          Many(op, args) => {
            let mut prefix = item.condition
            for i = 0; i < args.length(); i = i + 1 {
              let entry = b.entry(r, args[i], prefix, parent=Some((id, i)))
              if op == Coalesce && i + 1 < args.length() {
                prefix = Some(b.condition(prefix, entry, Null))
              }
            }
          }
          Conditional(condition, yes, no) => {
            let condition = b.entry(
              r,
              condition,
              item.condition,
              parent=Some((id, 0)),
            )
            let yes_path = b.condition(item.condition, condition, True)
            let no_path = b.condition(item.condition, condition, NotTrue)
            let _ = b.entry(r, yes, Some(yes_path), parent=Some((id, 1)))
            let _ = b.entry(r, no, Some(no_path), parent=Some((id, 2)))
          }
          Case(clauses, otherwise) => {
            let mut prefix = item.condition
            for (condition, branch) in clauses {
              let slot = b.entries.length() - base
              let condition = b.entry(
                r,
                condition,
                prefix,
                parent=Some((id, slot)),
              )
              let yes_path = b.condition(prefix, condition, True)
              let _ = b.entry(
                r,
                branch,
                Some(yes_path),
                parent=Some((id, slot + 1)),
              )
              prefix = Some(b.condition(prefix, condition, NotTrue))
            }
            let _ = b.entry(
              r,
              otherwise,
              prefix,
              parent=Some((id, b.entries.length() - base)),
            )
          }
        }
        let count = b.entries.length() - base
        if count > limits.max_pending - b.pending.length() {
          raise Stop(DemandLimit)
        }
        // Reverse push preserves source child visitation order without recursion.
        for i = b.entries.length() - 1; i >= base; i = i - 1 {
          b.tick()
          b.pending.push(i)
        }
      }
    }
    Ok({ roots, entries: b.entries, conditions: b.conditions, })
  } catch {
    Stop(issue) => Err(issue)
  }
}
