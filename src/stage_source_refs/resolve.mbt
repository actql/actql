///|
pub(all) struct Limits {
  max_work : Int
  max_text_bytes : Int
}

///|
pub(all) struct Usage {
  work : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  UnknownStage(String)
  UnknownInput(String, String)
  NonLocalInput(String, String)
  DuplicateReference(String)
} derive(Eq, Debug)

///|
priv struct Slot {
  cursor : @decode.Cursor
  is_local : Bool
}

///|
priv struct StageIndex {
  position : Int
  inputs : Map[String, Slot]
}

///|
struct Index {
  source : @stages.Source
  stages : Map[String, StageIndex]
  usage : Usage
}

///|
struct ResolvedInput {
  owner : Index
  reference : @reference.Reference
  stage : Int
  cursor : @decode.Cursor
}

///|
struct Resolved {
  owner : Index
  inputs : Array[ResolvedInput]
  usage : Usage
}

///|
priv struct Budget {
  mut work : Int
  mut text : Int
}

///|
priv suberror Stop {
  Stop
}

///|
fn charge(b : Budget, work : Int) -> Unit raise Stop {
  if work > b.work {
    raise Stop
  }
  b.work -= work
}

///|
fn text(b : Budget, value : String) -> Unit raise Stop {
  match @scalar.admit_utf8_length(value, b.text) {
    Ok(n) => b.text -= n
    Err(_) => raise Stop
  }
}

///|
/// Index source locations only; declaration types and evidence remain unchecked.
pub fn prepare(
  source : @stages.Source,
  limits : Limits,
) -> Result[Index, Issue] {
  prepare_owned(source, limits)
}

///|
/// Observe the SAME indexer's charged policy work and successfully admitted
/// name UTF8 bytes, including partial typed refusal. These are distinct units,
/// not scan instructions, CPU, byte allocation or a Resource grant. The
/// ordinary entrance allocates no observer; successful usage is the SAME fact.
pub fn observe_prepare(
  source : @stages.Source,
  limits : Limits,
) -> (Result[Index, Issue], Usage) {
  let observed = Ref(index_zero_usage)
  let result = prepare_owned(source, limits, usage_out=Some(observed))
  (result, observed.val)
}

///|
fn preparation_limits_invalid(limits : Limits) -> Bool {
  limits.max_work < 0 || limits.max_text_bytes < 0
}

///|
fn prepare_owned(
  source : @stages.Source,
  limits : Limits,
  usage_out? : Ref[Usage]? = None,
) -> Result[Index, Issue] {
  if preparation_limits_invalid(limits) {
    return Err(InvalidLimits)
  }
  let b : Budget = { work: limits.max_work, text: limits.max_text_bytes, }
  let result = try {
    let stages : Map[String, StageIndex] = Map([])
    charge(b, @stages.stage_count(source))
    for i in 0..<@stages.stage_count(source) {
      let stage = @stages.stage_at(source, i).unwrap()
      text(b, stage.id)
      let body = @decode.open_object(@syntax.stage_body(stage)).unwrap()
      let inputs = @decode.required(body, "inputs").unwrap()
      let count = @decode.object_length(inputs).unwrap()
      charge(b, count)
      let imported : Map[String, Bool] = Map([])
      charge(b, @syntax.import_count(stage))
      for j in 0..<@syntax.import_count(stage) {
        let (name, _) = @syntax.import_at(stage, j).unwrap()
        text(b, name)
        imported[name] = true
      }
      let slots : Map[String, Slot] = Map([])
      for j in 0..<count {
        let (name, cursor) = @decode.field_at(inputs, j).unwrap()
        text(b, name)
        let mut is_local = !imported.contains(name)
        if is_local && @decode.object_length(cursor) is Some(fields) {
          charge(b, fields)
          for k in 0..<fields {
            let (key, _) = @decode.field_at(cursor, k).unwrap()
            text(b, key)
            if key == "connector" {
              is_local = false
            }
          }
        }
        slots[name] = { cursor, is_local, }
      }
      stages[stage.id] = { position: i, inputs: slots, }
    }
    Ok({
      source,
      stages,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop => Err(BudgetExceeded)
  }
  if usage_out is Some(observed) {
    observed.val = match result {
      Ok(index) => index.usage
      Err(_) =>
        {
          work: limits.max_work - b.work,
          text_bytes: limits.max_text_bytes - b.text,
        }
    }
  }
  result
}

///|
// Immutable initial observation only. Its equality never admits another input.
let index_zero_usage : Usage = { work: 0, text_bytes: 0, }

///|
/// Additional observer Ref1H1R, Some1H1R1W, result/Usage pair1H2R and
/// failure-only Usage1H2W. Successful observation reuses Index.usage itself.
/// Original result/index/Map/input backing and retained caller Some are separate.
pub fn index_preparation_observation_control_extent() -> @shape.CollectionConstructionExtent {
  index_observer_units
}

///|
let index_observer_units : @shape.CollectionConstructionExtent = {
  record_headers: 4L,
  reference_slots: 4L,
  scalar_words: 3L,
}

///|
/// Resolve all selectors or return failure; duplicate snapshots are not merged.
pub fn resolve(
  index : Index,
  references : Array[@reference.Reference],
  limits : Limits,
) -> Result[Resolved, Issue] {
  if limits.max_work < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if index.usage.text_bytes > limits.max_text_bytes {
    return Err(BudgetExceeded)
  }
  try {
    let b = {
      work: limits.max_work,
      text: limits.max_text_bytes - index.usage.text_bytes,
    }
    charge(b, index.usage.work)
    charge(b, references.length())
    let seen : Map[String, Bool] = Map([])
    let inputs = []
    for reference in references {
      let encoded = @reference.stringify(reference)
      text(b, encoded)
      if seen.contains(encoded) {
        return Err(DuplicateReference(encoded))
      }
      seen[encoded] = true
      let stage_name = @reference.stage_name(reference)
      let name = @reference.input_name(reference)
      let stage = match index.stages.get(stage_name) {
        Some(v) => v
        None => return Err(UnknownStage(stage_name))
      }
      let slot = match stage.inputs.get(name) {
        Some(v) => v
        None => return Err(UnknownInput(stage_name, name))
      }
      if !slot.is_local {
        return Err(NonLocalInput(stage_name, name))
      }
      inputs.push({
        owner: index,
        reference,
        stage: stage.position,
        cursor: slot.cursor,
      })
    }
    Ok({
      owner: index,
      inputs,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop => Err(BudgetExceeded)
  }
}

///|
pub fn source(v : Index) -> @stages.Source {
  v.source
}

///|
pub fn index_usage(v : Index) -> Usage {
  v.usage
}

///|
pub fn resolved_index(v : Resolved) -> Index {
  v.owner
}

///|
pub fn resolved_usage(v : Resolved) -> Usage {
  v.usage
}

///|
pub fn count(v : Resolved) -> Int {
  v.inputs.length()
}

///|
pub fn entry_at(v : Resolved, index : Int) -> ResolvedInput? {
  v.inputs.get(index)
}

///|
pub fn input_index(v : ResolvedInput) -> Index {
  v.owner
}

///|
pub fn input_reference(v : ResolvedInput) -> @reference.Reference {
  v.reference
}

///|
pub fn stage_index(v : ResolvedInput) -> Int {
  v.stage
}

///|
pub fn declaration(v : ResolvedInput) -> @decode.Cursor {
  v.cursor
}
