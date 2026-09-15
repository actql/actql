///|
// Private to one construction attempt. Neither the cache nor its mutable state
// escapes into CheckedProgram. A failed conversion invalidates the session.
priv struct ProofConversion {
  owners : Map[(String, Int, Int), Array[BuiltUnit]]
  cache : Map[String, Array[ReidentifiedStep]]
  graph_cache : Map[String, Array[ReidentifiedGraphInput]]
  mut failed : Bool
  on_construct : ((@step_bounds.StepBound) -> Unit)?
}

///|
fn proof_owner_bucket(
  pipeline : @pipeline.CheckedPipeline,
  budget : IdentityBudget,
) -> (String, Int, Int) raise UnitBuildFailure {
  let span = @decode.cursor_span(@pipeline.source(pipeline))
  identity_charge(budget, span.source_path.length())
  identity_charge(budget, 1)
  // Coordinates only accelerate lookup; physical pipeline ownership below is
  // authoritative. Identical spans from separate admissions remain distinct.
  (span.source_path, span.start_byte, span.end_byte)
}

///|
fn proof_conversion(
  units : Array[BuiltUnit],
  budget : IdentityBudget,
  on_construct? : ((@step_bounds.StepBound) -> Unit)? = None,
) -> ProofConversion raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  let owners : Map[(String, Int, Int), Array[BuiltUnit]] = Map([])
  identity_charge(remaining, units.length())
  for unit in units {
    let key = proof_owner_bucket(unit.pipeline, remaining)
    match owners.get(key) {
      Some(bucket) => {
        for previous in bucket {
          identity_charge(remaining, 1)
          if physical_equal(previous.pipeline, unit.pipeline) {
            raise ForeignOwner
          }
        }
        bucket.push(unit)
      }
      None => owners[key] = [unit]
    }
  }
  budget.work = remaining.work
  { owners, cache: Map([]), graph_cache: Map([]), failed: false, on_construct, }
}

///|
fn proof_conversion_owner(
  session : ProofConversion,
  pipeline : @pipeline.CheckedPipeline,
  budget : IdentityBudget,
) -> BuiltUnit raise UnitBuildFailure {
  let key = proof_owner_bucket(pipeline, budget)
  if session.owners.get(key) is Some(bucket) {
    for unit in bucket {
      identity_charge(budget, 1)
      if physical_equal(unit.pipeline, pipeline) {
        return unit
      }
    }
  }
  raise ForeignOwner
}

///|
fn converted_proof(
  session : ProofConversion,
  original : @step_bounds.StepBound,
  budget : IdentityBudget,
) -> ReidentifiedStep? raise UnitBuildFailure {
  let key = @wire.cid(
    @wire.program_proof_witness(@step_bounds.checked_proof(original)),
  )
  identity_charge(budget, key.length())
  if session.cache.get(key) is Some(bucket) {
    for entry in bucket {
      identity_charge(budget, 1)
      if physical_equal(entry.original, original) {
        return Some(entry)
      }
    }
  }
  None
}
