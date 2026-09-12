///|
pub(all) struct Limits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub enum Issue {
  InvalidLimits
  InvalidStage
  BudgetExceeded
  Declaration(String, @local_input.Issue)
  ForeignStage
  ForeignInput(String)
  ForeignSourceViews
}

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
struct Prepared {
  source : @stages.Source
  stage : Int
  entries : Array[(String, @local_input.Checked)]
  usage : Usage
  sourceviews : @sourceviews.Inputs?
}

///|
struct Attached {
  prepared : Prepared
  stage : @stages.CollectedStage
  work : Int
}

///|
/// Read actual local Relation slots; Result/receipt imports belong to their
/// separate source-bound passes. Connector slots may be partitioned only by a
/// validated SourceView collection owned by this exact Program source.
pub fn prepare(
  source : @stages.Source,
  stage_index : Int,
  limits : Limits,
  sourceviews? : @sourceviews.Inputs? = None,
) -> Result[Prepared, Issue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let stage = match @stages.stage_at(source, stage_index) {
    Some(v) => v
    None => return Err(InvalidStage)
  }
  let object = @decode.open_object(@syntax.stage_body(stage)).unwrap()
  let inputs = @decode.required(object, "inputs").unwrap()
  let count = @decode.object_length(inputs).unwrap()
  let imports = @syntax.import_count(stage)
  let mut work = limits.max_work
  if sourceviews is Some(views) {
    if !physical_equal(source, @sourceviews.source(views)) {
      return Err(ForeignSourceViews)
    }
    if @sourceviews.work(views) > work {
      return Err(BudgetExceeded)
    }
    work -= @sourceviews.work(views)
  }
  if count > work {
    return Err(BudgetExceeded)
  }
  work -= count
  if imports > work {
    return Err(BudgetExceeded)
  }
  work -= imports
  let imported : Map[String, Bool] = Map([])
  for i in 0..<imports {
    let (name, _) = @syntax.import_at(stage, i).unwrap()
    imported[name] = true
  }
  let entries = []
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes
  for i in 0..<count {
    let (name, at) = @decode.field_at(inputs, i).unwrap()
    if imported.contains(name) {
      continue
    }
    if sourceviews is Some(views) {
      if name.length() > work {
        return Err(BudgetExceeded)
      }
      work -= name.length()
      if @sourceviews.input_for(views, stage_index, name) is Some(_) {
        continue
      }
    }
    let value = match
      @local_input.read(at, {
        max_nodes: if nodes < work {
          nodes
        } else {
          work
        },
        max_depth: limits.max_depth,
        max_text_bytes: text,
      }) {
      Ok(v) => v
      Err(e) => return Err(Declaration(name, e))
    }
    let usage = @local_input.usage(value)
    work -= usage.nodes
    nodes -= usage.nodes
    text -= usage.text_bytes
    entries.push((name, value))
  }
  Ok({
    source,
    stage: stage_index,
    entries,
    sourceviews,
    usage: {
      work: limits.max_work - work,
      nodes: limits.max_nodes - nodes,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
/// Retained source-only partition proof; this does not admit Catalog contracts,
/// requests, modes or execution authority for the omitted Connector slots.
pub fn sourceview_inputs(v : Prepared) -> @sourceviews.Inputs? {
  v.sourceviews
}

///|
pub fn count(v : Prepared) -> Int {
  v.entries.length()
}

///|
pub fn entry_at(v : Prepared, index : Int) -> (String, @local_input.Checked)? {
  v.entries.get(index)
}

///|
pub fn usage(v : Prepared) -> Usage {
  v.usage
}

///|
pub fn source(v : Prepared) -> @stages.Source {
  v.source
}

///|
pub fn stage_index(v : Prepared) -> Int {
  v.stage
}

///|
pub fn input_at(
  v : Prepared,
  index : Int,
) -> (String, @pipeline.InputContract)? {
  v.entries
  .get(index)
  .map(pair => {
    (
      pair.0,
      match @local_input.primary_key(pair.1) {
        Some(key) => @pipeline.KeyedInput(key)
        None => @pipeline.CarrierInput(@local_input.carrier(pair.1))
      },
    )
  })
}

///|
/// Attach the source-only input path. Extra Host/producer/ranking/key evidence
/// is not reconciled by comparing equal schemas; it needs its own admitted path.
pub fn attach(
  prepared : Prepared,
  stage : @stages.CollectedStage,
  max_work~ : Int,
) -> Result[Attached, Issue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(prepared.source, @stages.source(stage)) ||
    prepared.stage != @stages.stage_index(stage) {
    return Err(ForeignStage)
  }
  let mut remaining = max_work
  for amount in [prepared.usage.work, @stages.collection_work(stage)] {
    if amount > remaining {
      return Err(BudgetExceeded)
    }
    remaining -= amount
  }
  let pipeline = @collection.pipeline(@stages.collection(stage))
  let count = @pipeline.input_count(pipeline)
  if count > remaining {
    return Err(BudgetExceeded)
  }
  remaining -= count
  let registered : Map[String, Int] = Map([])
  for i in 0..<count {
    let (name, _) = @pipeline.input_at(pipeline, i).unwrap()
    registered[name] = i
  }
  for pair in prepared.entries {
    if remaining == 0 {
      return Err(BudgetExceeded)
    }
    remaining -= 1
    let index = match registered.get(pair.0) {
      Some(i) => i
      None => return Err(ForeignInput(pair.0))
    }
    let supplied = @pipeline.input_contract_at(pipeline, index).unwrap()
    let same = match (@local_input.primary_key(pair.1), supplied) {
      (Some(expected), @pipeline.KeyedInput(actual)) =>
        physical_equal(expected, actual)
      (None, @pipeline.CarrierInput(actual)) =>
        physical_equal(@local_input.carrier(pair.1), actual)
      _ => false
    }
    if !same {
      return Err(ForeignInput(pair.0))
    }
  }
  Ok({ prepared, stage, work: max_work - remaining, })
}

///|
pub fn attached_inputs(v : Attached) -> Prepared {
  v.prepared
}

///|
pub fn attached_stage(v : Attached) -> @stages.CollectedStage {
  v.stage
}

///|
pub fn attached_work(v : Attached) -> Int {
  v.work
}
