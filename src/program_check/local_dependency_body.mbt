///|
pub(all) enum LocalDependencyBodyKind {
  UnitDefinition
  LocalBody
  ParameterDeclarations
  UsedValues
  LocalContracts
  LocalPolicy
  ResultInterface(Int)
  ResultType(Int)
  IncomingGate(Int)
  SourceSchema(Int)
  SourceCapability(Int)
  SourceViewContract(Int)
  RegistryContract(Int)
} derive(Eq, Debug)

///|
pub(all) enum LocalDependencyBodyIssue {
  MissingUnit
  MissingDependency
  Encoding(@encode.EncodeFailure)
  ForeignBody
  BudgetExceeded
} derive(Eq, Debug)

///|
/// Exact bounded serialization from the existing checked owner. Issuing this
/// body neither checks a second Program nor creates an execution capability.
struct CheckedLocalDependencyBody {
  owner : CheckedProgram
  unit : Int
  kind : LocalDependencyBodyKind
  cid : String
  wire : String
}

///|
/// Select only the Catalog body named by an admitted observation. Lookup is
/// bounded and uses the checked environment, not a caller-supplied document.
/// This is body custody, not current Source or Effect authorization.
pub fn checked_local_catalog_dependency_body(
  program : CheckedProgram,
  unit : Int,
  role : String,
  identity : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((Int, Int, Int) -> Bool)? = None,
) -> Result[CheckedLocalDependencyBody, LocalDependencyBodyIssue] {
  guard local_catalog_selection_role(role) is Some((section, _)) else {
    return Err(MissingDependency)
  }
  let count = @environment.member_count(checked_environment(program), section)
  // Standalone/public lookup preserves its original refusal before any cursor
  // or body constructor, including callers that supply before_body.
  if count > 4096 {
    return Err(BudgetExceeded)
  }
  let selected = match
    begin_checked_local_catalog_selection(program, unit, role, identity) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match advance_checked_local_catalog_selection(selected, count) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard checked_local_catalog_selection_geometry(selected)
    is Some((bytes, nodes, depth)) else {
    return Err(MissingDependency)
  }
  if before_body is Some(prepare) && !prepare(bytes, nodes, depth) {
    return Err(BudgetExceeded)
  }
  finish_checked_local_catalog_selection(
    selected, max_bytes, max_nodes, max_depth,
  )
}

///|
/// Static bodies required by one checked local Invocation, including every
/// exact import position and incoming gate. No unrelated Unit is traversed.
pub fn checked_local_dependency_bodies(
  program : CheckedProgram,
  unit_index : Int,
  max_entries : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, CheckedLocalDependencyBody)],
  LocalDependencyBodyIssue,
] {
  collect_checked_local_dependency_bodies(
    program,
    unit_index,
    max_entries,
    max_bytes,
    max_nodes,
    max_depth,
    (role, body, _, _, _) => (role, body),
  )
}

///|
/// Return checked bodies with the byte, node and depth usage of their
/// original encoder. The dimensions are only data for funding a later parse.
pub fn checked_local_dependency_bodies_with_wire_usage(
  program : CheckedProgram,
  unit_index : Int,
  max_entries : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, CheckedLocalDependencyBody, Int, Int, Int)],
  LocalDependencyBodyIssue,
] {
  collect_checked_local_dependency_bodies(
    program,
    unit_index,
    max_entries,
    max_bytes,
    max_nodes,
    max_depth,
    (role, body, bytes, nodes, depth) => (role, body, bytes, nodes, depth),
  )
}

///|
fn[T] collect_checked_local_dependency_bodies(
  program : CheckedProgram,
  unit_index : Int,
  max_entries : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  project : (String, CheckedLocalDependencyBody, Int, Int, Int) -> T,
) -> Result[Array[T], LocalDependencyBodyIssue] {
  guard program.units.get(unit_index) is Some(unit) else {
    return Err(MissingUnit)
  }
  guard @context.program_incoming_gates_count(program.gates, unit_index)
    is Some(gates) else {
    return Err(MissingDependency)
  }
  if max_entries < 6 ||
    max_entries > 4096 ||
    max_bytes < 1 ||
    unit.interfaces.length() > (max_entries - 6) / 2 ||
    gates > max_entries - 6 - 2 * unit.interfaces.length() {
    return Err(BudgetExceeded)
  }
  let selected : Array[(String, LocalDependencyBodyKind)] = [
    ("local_dependencies", UnitDefinition),
    ("local_body", LocalBody),
    ("parameter_declarations", ParameterDeclarations),
    ("used_values", UsedValues),
    ("local_contracts", LocalContracts),
    ("local_policy", LocalPolicy),
  ]
  for index in 0..<unit.interfaces.length() {
    selected.push(("result_import_interface", ResultInterface(index)))
    selected.push(("result_import_type", ResultType(index)))
  }
  for index in 0..<gates {
    selected.push(("gate_requirement", IncomingGate(index)))
  }
  let bodies : Array[T] = []
  let mut remaining = max_bytes
  for (role, kind) in selected {
    let (body, bytes, nodes, depth) = match
      issue_checked_local_dependency_body_with_wire_usage(
        program,
        unit_index,
        kind,
        remaining,
        max_nodes,
        max_depth,
        (body, bytes, nodes, depth) => (body, bytes, nodes, depth),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    remaining -= bytes
    bodies.push(project(role, body, bytes, nodes, depth))
  }
  Ok(bodies)
}

///|
pub fn checked_local_dependency_body(
  program : CheckedProgram,
  unit_index : Int,
  kind : LocalDependencyBodyKind,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CheckedLocalDependencyBody, LocalDependencyBodyIssue] {
  issue_checked_local_dependency_body_with_wire_usage(
    program,
    unit_index,
    kind,
    max_bytes,
    max_nodes,
    max_depth,
    (body, _, _, _) => body,
  )
}

///|
fn[T] issue_checked_local_dependency_body_with_wire_usage(
  program : CheckedProgram,
  unit_index : Int,
  kind : LocalDependencyBodyKind,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  project : (CheckedLocalDependencyBody, Int, Int, Int) -> T,
) -> Result[T, LocalDependencyBodyIssue] {
  guard program.units.get(unit_index) is Some(_) else {
    return Err(MissingUnit)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    issue => return Err(Encoding(issue))
  }
  let cid = match
    emit_checked_local_dependency_body(program, unit_index, kind, writer) {
    Ok(cid) => cid
    Err(issue) => return Err(issue)
  }
  let (wire, bytes, nodes, depth) = @encode.finish_text_usage(writer) catch {
    issue => return Err(Encoding(issue))
  }
  Ok(
    project(
      { owner: program, unit: unit_index, kind, cid, wire, },
      bytes,
      nodes,
      depth,
    ),
  )
}

///|
pub fn checked_local_dependency_body_matches(
  value : CheckedLocalDependencyBody,
  program : CheckedProgram,
  unit : Int,
  kind : LocalDependencyBodyKind,
) -> Bool {
  physical_equal(value.owner, program) &&
  value.unit == unit &&
  value.kind == kind
}

///|
pub fn checked_local_dependency_body_cid(
  value : CheckedLocalDependencyBody,
) -> String {
  value.cid
}

///|
pub fn checked_local_dependency_body_json(
  value : CheckedLocalDependencyBody,
) -> String {
  value.wire
}

///|
/// Recovery compares saved canonical bytes to the body issued by this
/// checked owner. No CID-only admission, legacy normalization, second
/// compilation or execution is performed by this boundary.
pub fn admit_checked_local_dependency_body(
  program : CheckedProgram,
  unit : Int,
  kind : LocalDependencyBodyKind,
  expected : CheckedLocalDependencyBody,
  saved_wire : String,
) -> Result[CheckedLocalDependencyBody, LocalDependencyBodyIssue] {
  if !checked_local_dependency_body_matches(expected, program, unit, kind) ||
    saved_wire != expected.wire {
    return Err(ForeignBody)
  }
  Ok(expected)
}

///|
// One exact emitter for legacy text, private geometry census and funded owned
// text. The sink changes construction/work only; selected semantic fields,
// owner, CIDs, contracts, incoming gates and environment remain identical.
fn emit_checked_local_dependency_body(
  program : CheckedProgram,
  unit_index : Int,
  kind : LocalDependencyBodyKind,
  writer : @encode.Writer,
) -> Result[String, LocalDependencyBodyIssue] {
  guard program.units.get(unit_index) is Some(unit) else {
    return Err(MissingUnit)
  }
  try {
    @encode.construction_work_step(writer, 1)
    Ok(
      match kind {
        UnitDefinition => {
          let incoming = @context.incoming_links_requirements(
            @context.program_incoming_gates_owner(program.gates),
          )
          guard @context.program_incoming_namespace(incoming, unit_index)
            is Some((program_id, node_id)) else {
            return Err(MissingDependency)
          }
          emit_unit_preimage(
            {
              program_id,
              node_id,
              local_body: @context.stage_identity_local_body_cid(unit.source),
              declarations: @context.stage_identity_parameter_declarations_cid(
                unit.source,
              ),
              contracts: unit.contracts_cid,
              imports: unit.imports,
              gates: unit.gates,
            },
            writer,
            self_cid=Some(unit.definition_cid),
          )
          unit.definition_cid
        }
        LocalBody => {
          @references.emit_stage_semantics(
            @references.stage_definition_semantics(
              @context.stage_identity_definition(unit.source),
            ),
            writer,
          )
          @context.stage_identity_local_body_cid(unit.source)
        }
        ParameterDeclarations => {
          @references.emit_stage_parameter_declarations(
            @references.stage_definition_semantics(
              @context.stage_identity_definition(unit.source),
            ),
            writer,
          )
          @context.stage_identity_parameter_declarations_cid(unit.source)
        }
        UsedValues => {
          @parameter_refs.emit_used_values(
            @context.stage_identity_parameter_values(unit.source),
            writer,
          )
          @context.stage_identity_parameter_values_cid(unit.source)
        }
        LocalContracts => {
          // Stream the already sorted selection without allocating a second
          // array proportional to the complete contract inventory.
          @encode.begin_object(writer)
          @encode.key(writer, "contracts")
          @encode.begin_array(writer)
          for (cid, _) in unit.contracts {
            @encode.construction_work_step(writer, 1)
            @encode.string_value(writer, cid)
          }
          @encode.end_array(writer)
          @encode.key(writer, "version")
          @encode.string_value(writer, "actql-local-contracts/0.1")
          @encode.end_object(writer)
          unit.contracts_cid
        }
        LocalPolicy => {
          let selected = checked_selected_policy(program)
          let wiring = @context.reconciled_wiring(
            @context.policy_context(selected),
          )
          let policy = @context.stage_policy(
            @context.wired_stage_contexts(wiring),
          )
          @policy.emit(policy, writer)
          @policy.cid(policy)
        }
        ResultInterface(index) => {
          guard unit.interfaces.get(index) is Some(value) else {
            return Err(MissingDependency)
          }
          emit_result_interface(
            value.input_name,
            value.producer_program_id,
            value.producer_node_id,
            value.producer_unit_definition_cid,
            value.result_name,
            @context.result_import_type_cid(value.row),
            writer,
            self_cid=Some(value.cid),
          )
          value.cid
        }
        ResultType(index) => {
          guard unit.interfaces.get(index) is Some(value) else {
            return Err(MissingDependency)
          }
          @contract.emit_checked(
            @context.result_import_type_contract(value.row),
            writer,
          )
          @context.result_import_type_cid(value.row)
        }
        IncomingGate(index) => {
          guard @context.program_incoming_gates_at(
              program.gates,
              unit_index,
              index,
            )
            is Some(value) else {
            return Err(MissingDependency)
          }
          @context.emit_incoming_gate(value, writer)
          @context.incoming_gate_cid(value)
        }
        SourceSchema(index) | SourceCapability(index) => {
          let section = match kind {
            SourceSchema(_) => @environment.SchemaSnapshots
            _ => @environment.ConnectorCapabilities
          }
          guard @environment.member_at(
              checked_environment(program),
              section,
              index,
            )
            is Some(selected) else {
            return Err(MissingDependency)
          }
          // Source Evidence binds the complete admitted member, not the
          // Source View's contract identity. Preserve that exact preimage.
          @environment.emit_member(selected, writer)
          @environment.member_cid(selected)
        }
        SourceViewContract(index) | RegistryContract(index) => {
          let (section, identity_field) = match kind {
            SourceViewContract(_) => (@environment.SourceViews, "contract_cid")
            _ => (@environment.ContractRegistry, "cid")
          }
          guard @environment.member_at(
              checked_environment(program),
              section,
              index,
            )
            is Some(selected) else {
            return Err(MissingDependency)
          }
          guard @decode.open_object(@environment.member_body(selected))
            is Ok(object) &&
            @decode.lookup(object, identity_field) is Some(identity) &&
            @decode.text(identity) is Ok(identity) else {
            return Err(MissingDependency)
          }
          // These self identities were checked with the Catalog. In contrast
          // to schema/capability observations, the self field is excluded.
          @environment.emit_member(selected, writer)
          identity
        }
      },
    )
  } catch {
    issue => return Err(Encoding(issue))
  }
}
