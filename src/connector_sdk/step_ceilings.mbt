///|
/// Snapshot a finite, occurrence-indexed declaration from trusted Connector
/// wiring. This is not a checked limit claim or a permission to discharge it:
/// the Host still compares each declaration against the selected owned task.
fn snapshot_step_ceilings(
  supplied : Array[(Int, Int64)],
  step_count : Int,
) -> Array[(Int, Int64)]? {
  if step_count < 0 || supplied.length() > step_count {
    return None
  }
  let snapshot = []
  let mut previous = -1
  for (step, ceiling) in supplied {
    if step <= previous || step >= step_count || ceiling < 0L {
      return None
    }
    snapshot.push((step, ceiling))
    previous = step
  }
  Some(snapshot)
}

///|
fn step_ceiling(ceilings : Array[(Int, Int64)], step : Int) -> Int64? {
  for (index, ceiling) in ceilings {
    if index == step {
      return Some(ceiling)
    }
    if index > step {
      break
    }
  }
  None
}
