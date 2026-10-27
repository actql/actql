///|
struct Source {
  program : @stage.Program?
  prefix : @stage.Prefix?
  stages : Array[@stage.Stage]
  declarations : @parameter.Declarations
  declaration_limits : @parameter.DeclarationLimits
  binding_read : @parameter.BindingReadInput?
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
  original? : Source? = None,
) -> Result[Source, Issue] {
  // Only this private holder has completed these exact Program declarations.
  // Relaxing resource ceilings cannot invalidate an already accepted value.
  if original is Some(source) &&
    source.program is Some(owner) &&
    physical_equal(owner, program) &&
    source.declaration_limits.max_parameters <= limits.max_parameters &&
    source.declaration_limits.max_nodes <= limits.max_nodes &&
    source.declaration_limits.max_depth <= limits.max_depth &&
    source.declaration_limits.max_text_bytes <= limits.max_text_bytes {
    return Ok(source)
  }
  let root = @decode.open_object(@stage.program_body(program)).unwrap()
  match @parameter.read_declarations(@decode.lookup(root, "params"), limits) {
    Err(e) => Err(Declarations(e))
    Ok(declarations) =>
      Ok({
        program: Some(program),
        prefix: None,
        stages: @stage.stages(program),
        declarations,
        declaration_limits: limits,
        binding_read: None,
      })
  }
}

///|
pub fn declarations(source : Source) -> @parameter.Declarations {
  source.declarations
}

///|
/// Complete sources only. Mixed static callers use complete_program instead.
pub fn program(source : Source) -> @stage.Program {
  source.program.unwrap()
}

///|
/// A prefix cannot be converted into an admitted complete Program.
pub fn complete_program(source : Source) -> @stage.Program? {
  source.program
}

///|
/// Retain declarations from the actual opaque prefix owner, never a caller map.
pub fn prepare_prefix(
  prefix : @stage.Prefix,
  limits : @parameter.DeclarationLimits,
) -> Result[Source, Issue] {
  let root = @decode.open_object(@stage.prefix_body(prefix)).unwrap()
  match @parameter.read_declarations(@decode.lookup(root, "params"), limits) {
    Err(e) => Err(Declarations(e))
    Ok(declarations) =>
      Ok({
        program: None,
        prefix: Some(prefix),
        stages: @stage.prefix_stages(prefix),
        declarations,
        declaration_limits: limits,
        binding_read: None,
      })
  }
}

///|
pub fn prefix(source : Source) -> @stage.Prefix? {
  source.prefix
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

///|
/// Preserve the actual complete or check-only source tree for declaration use.
pub fn source_body(source : Source) -> @decode.Cursor {
  match source.program {
    Some(program) => @stage.program_body(program)
    None => @stage.prefix_body(source.prefix.unwrap())
  }
}
