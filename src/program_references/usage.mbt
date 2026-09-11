///|
pub enum UsageIssue {
  InvalidLimits
  WorkLimit
  UnusedParameter(@parameter.Declaration)
  UnusedBinding(@bindings.Declaration)
}

///|
struct DeclarationUsage {
  inventory : Inventory
  work : Int
}

///|
priv suberror UsageStop {
  UsageStop(UsageIssue)
}

///|
priv struct UsageBudget {
  mut remaining : Int
}

///|
fn usage_spend(b : UsageBudget, n : Int) -> Unit raise UsageStop {
  if n > b.remaining {
    raise UsageStop(WorkLimit)
  }
  b.remaining -= n
}

///|
fn usage_name(b : UsageBudget, name : String) -> Unit raise UsageStop {
  usage_spend(b, 1)
  usage_spend(b, name.length())
}

///|
/// Check declaration use across the entire owned inventory, never one stage.
/// This is not complete source, value, authority, or executable admission.
pub fn check_declaration_usage(
  inventory : Inventory,
  max_work~ : Int,
) -> Result[DeclarationUsage, UsageIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let b = UsageBudget::{ remaining: max_work, }
  try {
    usage_spend(b, inventory.work)
    let names : Map[String, Unit] = Map([])
    let index = inventory.program.parameters
    for i in 0..<@parameters.reference_count(index) {
      let r = @parameters.reference_at(index, i).unwrap()
      usage_name(b, r.name)
      names[r.name] = ()
    }
    let declarations = @parameters.declarations(index)
    for i in 0..<@parameter.declaration_count(declarations) {
      let d = @parameter.declaration_at(declarations, i).unwrap()
      usage_name(b, d.name)
      if !names.contains(d.name) {
        raise UsageStop(UnusedParameter(d))
      }
    }
    let bindings = @requests.bindings(inventory.requests)
    let used = inventory.program.used_bindings
    // Both declaration lists are unique and UTF-16 sorted. The inventory
    // guarantees that every used binding belongs to this exact declaration set.
    let mut position = 0
    for i in 0..<@bindings.count(bindings) {
      let d = @bindings.at(bindings, i).unwrap()
      usage_name(b, d.name)
      if position >= used.length() || used[position].name != d.name {
        raise UsageStop(UnusedBinding(d))
      }
      position += 1
    }
    Ok({ inventory, work: max_work - b.remaining, })
  } catch {
    UsageStop(issue) => Err(issue)
  }
}

///|
pub fn usage_inventory(value : DeclarationUsage) -> Inventory {
  value.inventory
}

///|
pub fn usage_work(value : DeclarationUsage) -> Int {
  value.work
}
