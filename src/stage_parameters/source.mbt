///|
struct Source {
  program : @stage.Program
  stages : Array[@stage.Stage]
  declarations : @parameter.Declarations
}

///|
pub(all) enum Issue {
  Declarations(@parameter.Issue)
  InvalidStage
  ForeignDeclarations
  ForeignSteps
  ForeignInitialFrom
  InputCountMismatch
  ForeignInput(String)
  Collection(@collection.Issue)
} derive(Eq, Debug)

///|
struct CollectedStage {
  source : Source
  stage_index : Int
  collection : @collection.Collected
  work : Int
}

///|
/// Read declarations from the retained Program, not from a separate caller map.
pub fn prepare(
  program : @stage.Program,
  limits : @parameter.DeclarationLimits,
) -> Result[Source, Issue] {
  let root = @decode.open_object(@stage.program_body(program)).unwrap()
  match @parameter.read_declarations(@decode.lookup(root, "params"), limits) {
    Err(e) => Err(Declarations(e))
    Ok(declarations) =>
      Ok({ program, stages: @stage.stages(program), declarations, })
  }
}

///|
pub fn declarations(source : Source) -> @parameter.Declarations {
  source.declarations
}

///|
pub fn program(source : Source) -> @stage.Program {
  source.program
}

///|
pub fn stage_count(source : Source) -> Int {
  source.stages.length()
}

///|
pub fn stage_at(source : Source, index : Int) -> @stage.Stage? {
  source.stages.get(index)
}

///|
fn same_cursor(a : @decode.Cursor, b : @decode.Cursor) -> Bool {
  @decode.tree_index(a, b) == @decode.tree_index(a, a)
}

///|
fn same_optional(a : @decode.Cursor?, b : @decode.Cursor?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(a), Some(b)) => same_cursor(a, b)
    _ => false
  }
}

///|
/// Collect local operation references with paths relative to the stage body.
/// This does not certify input contracts, Results, Effects or full Program use.
pub fn collect(
  source : Source,
  index : Int,
  pipeline : @pipeline.CheckedPipeline,
  limits : @collection.Limits,
) -> Result[CollectedStage, Issue] {
  if limits.max_work < 0 ||
    limits.max_slots < 0 ||
    limits.max_references < 0 ||
    limits.max_pointer_units < 0 ||
    limits.max_direct_text_bytes < 0 {
    return Err(Collection(@collection.InvalidLimits))
  }
  let stage = match stage_at(source, index) {
    None => return Err(InvalidStage)
    Some(stage) => stage
  }
  match @pipeline.parameters(pipeline) {
    Some(d) =>
      if !physical_equal(d, source.declarations) {
        return Err(ForeignDeclarations)
      }
    None => return Err(ForeignDeclarations)
  }
  let body = @stage.stage_body(stage)
  let object = @decode.open_object(body).unwrap()
  let steps = @decode.required(object, "steps").unwrap()
  if !same_cursor(steps, @pipeline.source(pipeline)) {
    return Err(ForeignSteps)
  }
  if !same_optional(
      @decode.lookup(object, "from"),
      @pipeline.initial_from(pipeline),
    ) {
    return Err(ForeignInitialFrom)
  }
  let inputs = @decode.required(object, "inputs").unwrap()
  let count = @decode.object_length(inputs).unwrap()
  if count != @pipeline.input_count(pipeline) {
    return Err(InputCountMismatch)
  }
  // Charge both source-name registration and pipeline-name lookup before
  // allocating the index. Input enumeration order is not semantic.
  if count > limits.max_work || count > limits.max_work - count {
    return Err(Collection(@collection.WorkLimit))
  }
  let names : Map[String, Bool] = Map([])
  for i in 0..<count {
    let (name, _) = @decode.field_at(inputs, i).unwrap()
    names[name] = true
  }
  for i in 0..<count {
    let (name, _) = @pipeline.input_at(pipeline, i).unwrap()
    if !names.contains(name) {
      return Err(ForeignInput(name))
    }
  }
  let input_work = count + count
  match
    @collection.collect(body, pipeline, {
      ..limits,
      max_work: limits.max_work - input_work,
    }) {
    Err(e) => Err(Collection(e))
    Ok(collection) =>
      Ok({
        source,
        stage_index: index,
        collection,
        work: input_work + @collection.work(collection),
      })
  }
}

///|
pub fn source(value : CollectedStage) -> Source {
  value.source
}

///|
pub fn stage_index(value : CollectedStage) -> Int {
  value.stage_index
}

///|
pub fn collection(value : CollectedStage) -> @collection.Collected {
  value.collection
}

///|
/// Source input-name checks plus local operation collection work.
pub fn collection_work(value : CollectedStage) -> Int {
  value.work
}
