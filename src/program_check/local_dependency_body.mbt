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
  Encoding
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
) -> Result[CheckedLocalDependencyBody, LocalDependencyBodyIssue] {
  let (section, self_field) = match role {
    "schema_evidence" => (@environment.SchemaSnapshots, None)
    "capability_evidence" => (@environment.ConnectorCapabilities, None)
    "source_contract" | "source_view_contract" =>
      (@environment.SourceViews, Some("contract_cid"))
    "data_policy" => (@environment.ContractRegistry, Some("cid"))
    _ => return Err(MissingDependency)
  }
  let environment = checked_environment(program)
  let count = @environment.member_count(environment, section)
  if count > 4096 {
    return Err(BudgetExceeded)
  }
  let mut selected : Int? = None
  for index in 0..<count {
    let item = @environment.member_at(environment, section, index).unwrap()
    let actual = match self_field {
      None => @environment.member_cid(item)
      Some(field) => {
        guard @decode.open_object(@environment.member_body(item)) is Ok(object) &&
          @decode.lookup(object, field) is Some(value) &&
          @decode.text(value) is Ok(text) else {
          return Err(MissingDependency)
        }
        text
      }
    }
    if actual == identity {
      if selected is Some(_) {
        return Err(ForeignBody)
      }
      selected = Some(index)
    }
  }
  guard selected is Some(index) else { return Err(MissingDependency) }
  let kind = match role {
    "schema_evidence" => SourceSchema(index)
    "capability_evidence" => SourceCapability(index)
    "data_policy" => RegistryContract(index)
    _ => SourceViewContract(index)
  }
  checked_local_dependency_body(
    program, unit, kind, max_bytes, max_nodes, max_depth,
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
  let bodies : Array[(String, CheckedLocalDependencyBody)] = []
  let mut remaining = max_bytes
  for (role, kind) in selected {
    let body = match
      checked_local_dependency_body(
        program, unit_index, kind, remaining, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    remaining -= @utf8.encode(body.wire).length()
    bodies.push((role, body))
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
  guard program.units.get(unit_index) is Some(unit) else {
    return Err(MissingUnit)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let cid = try {
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
    }
  } catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ owner: program, unit: unit_index, kind, cid, wire, })
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
