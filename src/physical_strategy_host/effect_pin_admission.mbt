///|
/// An already funded Effect dependency admission on one original DAG. The
/// caller retains it before entering any pin mutation. No loan escapes until
/// the complete set has been adopted by that same caller.
struct CapturedEffectPinAdmission {
  run : CapturedEffectRunDAG
  mut entered : Bool
  mut pending : CapturedEffectPinMutation?
  mut inputs : CapturedEffectInputs?
  mut unknown : Bool
}

///|
priv struct CapturedEffectPinMutation {
  task : Int
  lifetime : TaskLifetime
  before : Int
  previous : CapturedEffectPinMutation?
}

///|
pub fn prepare_captured_effect_pin_admission(
  run : CapturedEffectRunDAG,
) -> CapturedEffectPinAdmission {
  { run, entered: false, pending: None, inputs: None, unknown: false, }
}

///|
fn begin_captured_effect_pin_admission(
  admission : CapturedEffectPinAdmission,
  run : CapturedEffectRunDAG,
) -> Bool {
  let dag = run.captured
  if !physical_equal(admission.run, run) ||
    admission.entered ||
    dag.stopped ||
    dag.effect_pin_admission is Some(_) {
    return false
  }
  admission.entered = true
  dag.effect_pin_admission = Some(admission)
  true
}

///|
// Journal the exact before count before changing it. Only the selected
// admission can change any task pin count while this DAG owns the journal.
fn acquire_captured_task_pin(
  dag : CapturedDAG,
  task : Int,
  max_pins : Int,
  admission : CapturedEffectPinAdmission?,
) -> Result[Unit, RunIssue] {
  let lifetime = dag.lifetimes[task]
  match (dag.effect_pin_admission, admission) {
    (None, None) => ()
    (Some(active), Some(selected)) if physical_equal(active, selected) => ()
    _ => return Err(ForeignCandidate)
  }
  let before = lifetime.pins
  if before >= max_pins {
    return Err(Physical(@resources.HoldingLimit))
  }
  if admission is Some(selected) {
    selected.pending = Some({
      task,
      lifetime,
      before,
      previous: selected.pending,
    })
  }
  lifetime.pins = before + 1
  Ok(())
}

///|
/// Adopt the exact complete candidate only after the caller has retained it.
/// The final DAG field assignment is the only commit point.
pub fn complete_captured_effect_pin_admission(
  admission : CapturedEffectPinAdmission,
  inputs : CapturedEffectInputs,
) -> Bool {
  let dag = admission.run.captured
  guard dag.effect_pin_admission is Some(active) &&
    physical_equal(active, admission) &&
    admission.inputs is Some(candidate) &&
    physical_equal(inputs, candidate) &&
    !dag.stopped &&
    !admission.unknown else {
    return false
  }
  dag.effect_pin_admission = None
  admission.pending = None
  true
}

///|
/// A serialized owner may unwind an unpublished acquisition after the
/// synchronous call returns or traps. The last entry observes exactly either
/// side of the count write. On retirement retry it can also observe the
/// restored count before removal of that journal entry.
pub fn cancel_captured_effect_pin_admission(
  admission : CapturedEffectPinAdmission,
) -> Result[Bool, RunIssue] {
  if admission.unknown {
    return Err(ForeignCandidate)
  }
  let dag = admission.run.captured
  match dag.effect_pin_admission {
    // A cleared DAG slot with an issued candidate means adoption committed.
    // The retained concrete inputs still require ordinary child-first release.
    None => {
      admission.entered = true
      return Ok(admission.inputs is Some(_))
    }
    Some(active) if physical_equal(active, admission) => ()
    Some(_) => return Err(ForeignCandidate)
  }
  while admission.pending is Some(entry) {
    let lifetime = dag.lifetimes[entry.task]
    if !physical_equal(lifetime, entry.lifetime) ||
      (lifetime.pins != entry.before && lifetime.pins != entry.before + 1) {
      admission.unknown = true
      return Err(ForeignCandidate)
    }
    lifetime.pins = entry.before
    admission.pending = entry.previous
  }
  // Clear the unpublished candidate before removing the exclusive owner.
  admission.inputs = None
  dag.effect_pin_admission = None
  collect_captured_retention(dag)
  Ok(false)
}
