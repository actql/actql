///|
pub(all) enum ImportIssue {
  InvalidLimits
  InvalidStage
  ForeignPipeline
  ForeignResults
  ForeignSource
  NotEarlierStage(Int)
  DuplicateProducer(String)
  MissingProducer(String)
  MissingResult(String, String)
  ForeignInput(String)
  BudgetExceeded
} derive(Eq, Debug)

///|
struct StagePorts {
  stage : @parameters.CollectedStage
  ports : @results.ResultPorts
}

///|
/// Bind publication to the exact stage source and source-bound pipeline.
pub fn bind_ports(
  stage : @parameters.CollectedStage,
  ports : @results.ResultPorts,
) -> Result[StagePorts, ImportIssue] {
  let checked = @results.publication_orders_results(
    @results.checked_publication_orders(@results.ports_orders(ports)),
  )
  if !physical_equal(
      @results.pipeline(checked),
      @collection.pipeline(@parameters.collection(stage)),
    ) {
    return Err(ForeignPipeline)
  }
  let source = @parameters.source(stage)
  let body = @decode.open_object(
    @syntax.stage_body(
      @parameters.stage_at(source, @parameters.stage_index(stage)).unwrap(),
    ),
  ).unwrap()
  let expected = @decode.required(body, "results").unwrap()
  if @decode.tree_index(expected, @results.source(checked)) !=
    @decode.tree_index(expected, expected) {
    return Err(ForeignResults)
  }
  Ok({ stage, ports, })
}

///|
pub(all) struct ImportLimits {
  max_work : Int
  max_imports : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
struct ResultImport {
  name : String
  producer : StagePorts
  port : @results.ResultPort
}

///|
struct ResultImports {
  source : @parameters.Source
  stage : Int
  entries : Array[ResultImport]
  work : Int
  text_bytes : Int
}

///|
/// Resolve Result imports only. Receipt and ordinary Input admission are separate.
pub fn resolve_imports(
  source : @parameters.Source,
  stage_index : Int,
  producers : Array[StagePorts],
  limits : ImportLimits,
) -> Result[ResultImports, ImportIssue] {
  if limits.max_work < 0 || limits.max_imports < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let stage = match @parameters.stage_at(source, stage_index) {
    None => return Err(InvalidStage)
    Some(v) => v
  }
  let mut work = limits.max_work
  let mut text = limits.max_text_bytes
  let known : Map[String, StagePorts] = Map([])
  // Charge before constructing indexes, including unused supplied producers.
  if producers.length() > work {
    return Err(BudgetExceeded)
  }
  work -= producers.length()
  for producer in producers {
    if !physical_equal(@parameters.source(producer.stage), source) {
      return Err(ForeignSource)
    }
    let index = @parameters.stage_index(producer.stage)
    if index >= stage_index {
      return Err(NotEarlierStage(index))
    }
    let name = @parameters.stage_at(source, index).unwrap().id
    match @scalar.admit_utf8_length(name, text) {
      Err(_) => return Err(BudgetExceeded)
      Ok(n) => text -= n
    }
    if known.contains(name) {
      return Err(DuplicateProducer(name))
    }
    known[name] = producer
  }
  let count = @syntax.import_count(stage)
  if count > work {
    return Err(BudgetExceeded)
  }
  work -= count
  let entries : Array[ResultImport] = []
  for i in 0..<count {
    let (name, reference) = @syntax.import_at(stage, i).unwrap()
    match reference {
      @syntax.Receipt(..) => ()
      @syntax.Result(producer~, result~) => {
        if entries.length() >= limits.max_imports {
          return Err(BudgetExceeded)
        }
        for value in [name, producer, result] {
          match @scalar.admit_utf8_length(value, text) {
            Err(_) => return Err(BudgetExceeded)
            Ok(n) => text -= n
          }
        }
        let owner = match known.get(producer) {
          None => return Err(MissingProducer(producer))
          Some(v) => v
        }
        let port = match @results.lookup_port(owner.ports, result) {
          None => return Err(MissingResult(producer, result))
          Some(v) => v
        }
        entries.push({ name, producer: owner, port, })
      }
    }
  }
  Ok({
    source,
    stage: stage_index,
    entries,
    work: limits.max_work - work,
    text_bytes: limits.max_text_bytes - text,
  })
}

///|
pub fn stage_port_source(value : StagePorts) -> @parameters.CollectedStage {
  value.stage
}

///|
pub fn stage_port_publications(value : StagePorts) -> @results.ResultPorts {
  value.ports
}

///|
pub fn import_source(value : ResultImports) -> @parameters.Source {
  value.source
}

///|
pub fn import_stage(value : ResultImports) -> Int {
  value.stage
}

///|
pub fn import_count(value : ResultImports) -> Int {
  value.entries.length()
}

///|
pub fn import_at(value : ResultImports, index : Int) -> ResultImport? {
  value.entries.get(index)
}

///|
pub fn import_usage(value : ResultImports) -> (Int, Int) {
  (value.work, value.text_bytes)
}

///|
pub fn input_name(value : ResultImport) -> String {
  value.name
}

///|
pub fn input_port(value : ResultImport) -> @results.ResultPort {
  value.port
}

///|
pub fn input_stage(value : ResultImport) -> StagePorts {
  value.producer
}

///|
pub fn input_producer(value : ResultImport) -> @pipeline.ProducedInput {
  @results.port_input(value.port)
}

///|
struct AttachedImports {
  imports : ResultImports
  stage : @parameters.CollectedStage
  work : Int
}

///|
/// Check that every Result import, used or unused, is the exact resolved input
/// of the source-bound consumer. Ordinary and receipt inputs remain separate.
pub fn attach_imports(
  imports : ResultImports,
  stage : @parameters.CollectedStage,
  max_work~ : Int,
) -> Result[AttachedImports, ImportIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(imports.source, @parameters.source(stage)) {
    return Err(ForeignSource)
  }
  if imports.stage != @parameters.stage_index(stage) {
    return Err(InvalidStage)
  }
  if imports.work > max_work ||
    imports.entries.length() > max_work - imports.work {
    return Err(BudgetExceeded)
  }
  let pipeline = @collection.pipeline(@parameters.collection(stage))
  for entry in imports.entries {
    let index = match @pipeline.lookup(pipeline, entry.name) {
      Some(@pipeline.Input(i)) => i
      _ => return Err(ForeignInput(entry.name))
    }
    match @pipeline.input_producer(pipeline, index) {
      Some(actual) =>
        if !physical_equal(actual, input_producer(entry)) {
          return Err(ForeignInput(entry.name))
        }
      None => return Err(ForeignInput(entry.name))
    }
  }
  Ok({ imports, stage, work: imports.work + imports.entries.length(), })
}

///|
pub fn attached_imports(value : AttachedImports) -> ResultImports {
  value.imports
}

///|
pub fn attached_stage(value : AttachedImports) -> @parameters.CollectedStage {
  value.stage
}

///|
pub fn attached_work(value : AttachedImports) -> Int {
  value.work
}
