///|
pub suberror UnitBuildFailure {
  ForeignOwner
  UnresolvedProducer
  UnsupportedReceipt
  BudgetExceeded
  Encoding(@encode.EncodeFailure)
  ImportType(@context.ResultImportTypeIssue)
  PublicationRows(@context.PublicationRowLimitIssue)
  PublicationWire(@wire.Issue)
  PublicationArithmetic(@wire.ClosureIssue)
  PublicationHost(@host.Issue)
  Expressions(@context.ExpressionClosureIssue)
  UnconvertedProofInput
  AmbiguousProofInput
  ProofConversion(Error)
  PublicationMixed(@wire.MixedIssue)
  UnsupportedStaticPath(@decode.Cursor)
  UnclosedSourceExecution(Int, Int)
  UnclosedPublicationPolicy(Int, Int)
}

///|
priv struct IdentityBudget {
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  depth : Int
}

///|
priv struct BuiltUnit {
  source : @context.StageSourceIdentity
  pipeline : @pipeline.CheckedPipeline
  definition_cid : String
  contracts_cid : String
  contract_inventory : @context.CoreContractInventory
  expressions : @context.ProgramExpressionClosure
  expression_execution : Array[ExpressionExecution]
  source_execution : Array[SourceExecution]
  local_inputs : @context.ProgramLocalInputClosure
  contracts : Array[(String, @context.CoreContractBody)]
  imports : Array[String]
  interfaces : Array[BuiltResultInterface]
  gates : Array[String]
  publication_rows : Array[@context.PublicationRowLimit]
  publications : Array[PublicationExecution]
}

///|
// Retain the same admitted type/occurrence used to hash the interface. A
// consumer must not reconstruct this correspondence from source or CID order.
pub struct BuiltResultInterface {
  input_name : String
  producer_program_id : String
  producer_node_id : String
  producer_unit_definition_cid : String
  result_name : String
  row : @context.ResultImportType
  cid : String
}

///|
fn identity_charge(
  b : IdentityBudget,
  cost : Int,
) -> Unit raise UnitBuildFailure {
  if cost < 0 || cost > b.work {
    raise BudgetExceeded
  }
  b.work -= cost
}

///|
fn identity_writer(b : IdentityBudget) -> @encode.Writer raise UnitBuildFailure {
  @encode.hashing_writer(
    Int::min(b.bytes, b.work),
    Int::min(b.nodes, b.work),
    b.depth,
  ) catch {
    e => raise Encoding(e)
  }
}

///|
fn identity_finish(
  b : IdentityBudget,
  writer : @encode.Writer,
) -> String raise UnitBuildFailure {
  let (digest, bytes, nodes) = @encode.finish_hash_usage(writer) catch {
    e => raise Encoding(e)
  }
  identity_charge(b, bytes)
  identity_charge(b, nodes)
  b.bytes -= bytes
  b.nodes -= nodes
  "sha256:" + digest
}

///|
// Charge a conservative comparison bound before the shared comparator scans.
// A comparison count alone does not bound work for long import names.
fn identity_compare(
  left : String,
  right : String,
  b : IdentityBudget,
) -> Int raise UnitBuildFailure {
  identity_charge(b, Int::min(left.length(), right.length()))
  identity_charge(b, 1)
  @canonical.compare_utf16(left, right)
}

///|
// Private stable merge sort permits work checks during comparisons, unlike a
// non-raising library comparator. No quadratic insertion or alias expansion.
fn[T] identity_sort(
  values : Array[(String, T)],
  b : IdentityBudget,
) -> Unit raise UnitBuildFailure {
  let n = values.length()
  identity_charge(b, n)
  let buffer = values.copy()
  let mut width = 1
  while width < n {
    let mut start = 0
    while start < n {
      let middle = start + Int::min(width, n - start)
      let end = middle + Int::min(width, n - middle)
      let mut left = start
      let mut right = middle
      for out in start..<end {
        identity_charge(b, 1)
        if right == end ||
          (
            left < middle &&
            identity_compare(values[left].0, values[right].0, b) <= 0
          ) {
          buffer[out] = values[left]
          left += 1
        } else {
          buffer[out] = values[right]
          right += 1
        }
      }
      start = end
    }
    identity_charge(b, n)
    for i in 0..<n {
      values[i] = buffer[i]
    }
    width = if width > n - width { n } else { width + width }
  }
}

///|
// Used only inside formal construction after complete role selection. This
// function binds identities to owned stages; it is not a closure certificate.
fn build_units(
  contracts : @context.CoreContractInventory,
  requirements : @context.StageRequirementClosure,
  gates : @context.ProgramIncomingGates,
  b : IdentityBudget,
) -> Array[BuiltUnit] raise UnitBuildFailure {
  let owner = @context.stage_requirement_owner(requirements)
  let incoming = @context.incoming_links_requirements(owner)
  let identity = @context.program_incoming_identity(incoming)
  if !physical_equal(@context.core_contract_identity(contracts), identity) ||
    !physical_equal(@context.program_incoming_gates_owner(gates), owner) {
    raise ForeignOwner
  }
  let profiles = @context.operation_profile_links_calendar(
    @context.incoming_links_profiles(owner),
  )
  guard @context.core_contract_profile_checks(contracts) is Some(selected) &&
    physical_equal(selected, profiles) else {
    raise ForeignOwner
  }
  let stages = @context.program_identity_stage_count(identity)
  let (identity_work, _, _) = @context.program_identity_usage(identity)
  let expression_limit = identity_work +
    Int::min(b.work, 2147483647 - identity_work)
  let expressions = match
    @context.close_program_expressions(identity, expression_limit, b.work) {
    Ok(v) => v
    Err(e) => raise Expressions(e)
  }
  // The source prefix was charged by preparation. This pass adds only its
  // exhaustive obligation accounting, and retains the original owner.
  identity_charge(
    b,
    @context.expression_closure_work(expressions) - identity_work,
  )
  identity_charge(b, stages)
  let by_stage : Array[Array[Int]] = Array::makei(stages, _ => [])
  identity_charge(b, stages)
  let publication_rows : Array[Array[@context.PublicationRowLimit]] = Array::makei(
    stages,
    _ => [],
  )
  let publications = @context.stage_requirement_publications(requirements)
  let publication_prefix = @context.publication_closure_work(publications)
  for index in 0..<@context.publication_closure_count(publications) {
    identity_charge(b, 1)
    let ceiling = publication_prefix +
      Int::min(b.work, 2147483647 - publication_prefix)
    let selected = match
      @context.select_publication_row_limit(
        publications,
        index,
        ceiling,
        b.work,
      ) {
      Ok(v) => v
      Err(e) => raise PublicationRows(e)
    }
    identity_charge(
      b,
      @context.publication_row_limit_work(selected) - publication_prefix,
    )
    publication_rows[@context.publication_row_limit_result(selected).stage].push(
      selected,
    )
  }
  for index in 0..<@context.program_incoming_count(incoming) {
    identity_charge(b, 1)
    by_stage[@context.program_incoming_at(incoming, index).unwrap().stage].push(
      index,
    )
  }
  let completed : Map[String, BuiltUnit] = Map([])
  let expression_execution = prepare_expression_execution(expressions, b)
  let source_execution = prepare_source_execution(identity, b)
  let units = []
  for stage in 0..<stages {
    identity_charge(b, 1)
    let source = @context.program_identity_stage_at(identity, stage).unwrap()
    let pipeline = unit_source_pipeline(identity, stage, b)
    let (program_id, node_id) = @context.program_incoming_namespace(
      incoming, stage,
    ).unwrap()
    let selected = []
    for
      i in 0..<@context.core_contract_stage_body_count(contracts, stage).unwrap() {
      identity_charge(b, 1)
      let body = @context.core_contract_stage_body_at(contracts, stage, i).unwrap()
      selected.push((@context.core_contract_cid(body), body))
    }
    identity_sort(selected, b)
    identity_charge(b, selected.length())
    let contract_cids = selected.map(pair => pair.0)
    let writer = identity_writer(b)
    emit_contract_set(contract_cids, writer) catch {
      e => raise Encoding(e)
    }
    let contracts_cid = identity_finish(b, writer)
    let named_imports = []
    for index in by_stage[stage] {
      identity_charge(b, 1)
      let site = @context.program_incoming_at(incoming, index).unwrap()
      match site.requirement {
        @context.Success(_, _) => ()
        @context.Receipt(_, _, _) => raise UnsupportedReceipt
        @context.Result(name, producer, port) => {
          let producer_stage = @context.stage_identity_definition(producer)
          // Namespace lookup is followed by exact producer-owner validation.
          let producer_id = @references.stage_definition_id(producer_stage)
          identity_charge(b, producer_id.length())
          guard completed.get(producer_id) is Some(unit) &&
            physical_equal(unit.source, producer) else {
            raise UnresolvedProducer
          }
          let row = match
            @context.identify_result_import_type(
              owner,
              index,
              Int::min(b.bytes, b.work),
              Int::min(b.nodes, b.work),
              b.depth,
            ) {
            Ok(Some(row)) => row
            Ok(None) => raise UnresolvedProducer
            Err(e) => raise ImportType(e)
          }
          let (bytes, nodes) = @context.result_import_type_usage(row)
          identity_charge(b, bytes)
          identity_charge(b, nodes)
          b.bytes -= bytes
          b.nodes -= nodes
          let writer = identity_writer(b)
          let result_name = @publication.name(
            @publication.port_result(@results.input_port(port)),
          )
          emit_result_interface(
            name,
            program_id,
            producer_id,
            unit.definition_cid,
            result_name,
            @context.result_import_type_cid(row),
            writer,
          ) catch {
            e => raise Encoding(e)
          }
          named_imports.push(
            (
              name,
              BuiltResultInterface::{
                input_name: name,
                producer_program_id: program_id,
                producer_node_id: producer_id,
                producer_unit_definition_cid: unit.definition_cid,
                result_name,
                row,
                cid: identity_finish(b, writer),
              },
            ),
          )
        }
      }
    }
    identity_sort(named_imports, b)
    identity_charge(b, named_imports.length())
    let interfaces = named_imports.map(pair => pair.1)
    identity_charge(b, interfaces.length())
    let imports = interfaces.map(value => value.cid)
    let gate_cids = []
    for i in 0..<@context.program_incoming_gates_count(gates, stage).unwrap() {
      identity_charge(b, 1)
      gate_cids.push(
        @context.incoming_gate_cid(
          @context.program_incoming_gates_at(gates, stage, i).unwrap(),
        ),
      )
    }
    let writer = identity_writer(b)
    emit_unit_preimage(
      {
        program_id,
        node_id,
        local_body: @context.stage_identity_local_body_cid(source),
        declarations: @context.stage_identity_parameter_declarations_cid(source),
        contracts: contracts_cid,
        imports,
        gates: gate_cids,
      },
      writer,
    ) catch {
      e => raise Encoding(e)
    }
    let unit = {
      source,
      pipeline,
      definition_cid: identity_finish(b, writer),
      contracts_cid,
      contract_inventory: contracts,
      expressions,
      expression_execution,
      source_execution,
      local_inputs: @context.stage_requirement_inputs(requirements),
      contracts: selected,
      imports,
      interfaces,
      gates: gate_cids,
      publication_rows: publication_rows[stage],
      publications: [],
    }
    identity_charge(b, node_id.length())
    completed[node_id] = unit
    units.push(unit)
  }
  units
}
