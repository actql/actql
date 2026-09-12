///|
pub(all) struct ProgramSemanticsLimits {
  max_work : Int
  max_stages : Int
  max_hash_bytes : Int
  max_hash_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub enum ProgramSemanticsIssue {
  InvalidLimits
  BudgetExceeded
  StageHash(Int, @encode.EncodeFailure)
}

///|
priv struct Descriptor {
  stage : @stage.Stage
  cid : String
  imports : Array[(String, @stage.ImportPort)]
}

///|
struct ProgramSemantics {
  usage : DeclarationUsage
  descriptors : Array[Descriptor]
  exports : Array[(String, String, String)]
  work : Int
  hash_bytes : Int
  hash_nodes : Int
}

///|
/// Prepare the unbound Program source preimage, not executable admission.
/// Hash budgets are cumulative across stages; structural work includes the
/// existing use check and retained stage/import/export entries and name units.
pub fn prepare_program_semantics(
  usage : DeclarationUsage,
  limits : ProgramSemanticsLimits,
) -> Result[ProgramSemantics, ProgramSemanticsIssue] {
  if limits.max_work < 0 ||
    limits.max_stages < 0 ||
    limits.max_hash_bytes < 0 ||
    limits.max_hash_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let source = @requests.source(usage.inventory.requests)
  let count = @stages.stage_count(source)
  if count > limits.max_stages || usage.work >= limits.max_work {
    return Err(BudgetExceeded)
  }
  let mut work = usage.work + 1
  let mut bytes = 0
  let mut nodes = 0
  let descriptors = []
  for i in 0..<count {
    let stage = @stages.stage_at(source, i).unwrap()
    if work >= limits.max_work || stage.id.length() > limits.max_work - work - 1 {
      return Err(BudgetExceeded)
    }
    work += stage.id.length() + 1
    let n = @stage.import_count(stage)
    if n > limits.max_work - work {
      return Err(BudgetExceeded)
    }
    work += n
    let imports = []
    for j in 0..<n {
      let entry = @stage.import_at(stage, j).unwrap()
      if entry.0.length() > limits.max_work - work {
        return Err(BudgetExceeded)
      }
      work += entry.0.length()
      imports.push(entry)
    }
    imports.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
    let hashed = try {
      let writer = @encode.hashing_writer(
        limits.max_hash_bytes - bytes,
        limits.max_hash_nodes - nodes,
        limits.max_depth,
      )
      emit_stage_semantics(stage_semantics_at(usage, i).unwrap(), writer)
      @encode.finish_hash_usage(writer)
    } catch {
      e => return Err(StageHash(i, e))
    }
    bytes += hashed.1
    nodes += hashed.2
    descriptors.push({ stage, cid: "sha256:" + hashed.0, imports, })
  }
  let program = @stages.program(source)
  let n = @stage.export_count(program)
  if n > limits.max_work - work {
    return Err(BudgetExceeded)
  }
  work += n
  let exports = []
  for i in 0..<n {
    let entry = @stage.export_at(program, i).unwrap()
    if entry.0.length() > limits.max_work - work {
      return Err(BudgetExceeded)
    }
    work += entry.0.length()
    exports.push(entry)
  }
  exports.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
  Ok({
    usage,
    descriptors,
    exports,
    work,
    hash_bytes: bytes,
    hash_nodes: nodes,
  })
}

///|
pub fn program_semantics_usage(v : ProgramSemantics) -> DeclarationUsage {
  v.usage
}

///|
pub fn program_semantics_work(v : ProgramSemantics) -> Int {
  v.work
}

///|
pub fn program_semantics_hash_usage(v : ProgramSemantics) -> (Int, Int) {
  (v.hash_bytes, v.hash_nodes)
}

///|
pub fn program_semantics_stage_cid(v : ProgramSemantics, i : Int) -> String? {
  v.descriptors.get(i).map(d => d.cid)
}

///|
pub fn program_semantics_stage_count(v : ProgramSemantics) -> Int {
  v.descriptors.length()
}

///|
pub fn emit_program_semantics(
  v : ProgramSemantics,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let references = v.usage.inventory.program
  @encode.begin_object(writer)
  @encode.key(writer, "actql_version")
  @encode.string_value(writer, "actql/0.1")
  @encode.key(writer, "binding_references")
  emit_binding_references(references, writer)
  @encode.key(writer, "bindings")
  emit_used_bindings(references, writer)
  @encode.key(writer, "expression_contract_cid")
  @encode.string_value(writer, stage_expression_contract_cid)
  @encode.key(writer, "parameter_references")
  @parameters.emit_references(references.parameters, writer)
  @encode.key(writer, "parameters")
  @parameters.emit_used_declarations(references.parameters, writer)
  @encode.key(writer, "program_template")
  @encode.begin_object(writer)
  @encode.key(writer, "exports")
  @encode.begin_object(writer)
  for (name, stage, result) in v.exports {
    @encode.key(writer, name)
    @encode.begin_object(writer)
    @encode.key(writer, "from")
    @encode.begin_object(writer)
    @encode.key(writer, "result")
    @encode.string_value(writer, result)
    @encode.key(writer, "stage")
    @encode.string_value(writer, stage)
    @encode.end_object(writer)
    @encode.end_object(writer)
  }
  @encode.end_object(writer)
  @encode.key(writer, "stages")
  @encode.begin_array(writer)
  for d in v.descriptors {
    @encode.begin_object(writer)
    @encode.key(writer, "after")
    @encode.string_value(
      writer,
      match d.stage.predecessor {
        Initial => "initial"
        Completed(_) => "completed"
        Accepted(_) => "accepted"
      },
    )
    @encode.key(writer, "id")
    @encode.string_value(writer, d.stage.id)
    @encode.key(writer, "imports")
    @encode.begin_object(writer)
    for (name, port) in d.imports {
      @encode.key(writer, name)
      @encode.begin_object(writer)
      match port {
        @stage.Result(producer~, result~) => {
          @encode.key(writer, "result")
          @encode.begin_object(writer)
          @encode.key(writer, "result")
          @encode.string_value(writer, result)
          @encode.key(writer, "stage")
          @encode.string_value(writer, producer)
        }
        @stage.Receipt(producer~, effect~) => {
          @encode.key(writer, "receipt")
          @encode.begin_object(writer)
          @encode.key(writer, "effect")
          @encode.string_value(writer, effect)
          @encode.key(writer, "stage")
          @encode.string_value(writer, producer)
        }
      }
      @encode.end_object(writer)
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    @encode.key(writer, "stage_semantics_cid")
    @encode.string_value(writer, d.cid)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-program-semantics/0.1")
  @encode.end_object(writer)
}

///|
pub fn program_semantics_cid(
  v : ProgramSemantics,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_program_semantics(v, writer)
  "sha256:" + @encode.finish_hash(writer)
}
