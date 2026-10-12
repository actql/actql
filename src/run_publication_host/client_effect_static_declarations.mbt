///|
/// Checked declaration facts only. This metadata never denotes a resolved
/// physical target, captured Preview, credential, grant or approval.
pub(all) enum ClientEffectStaticContractDeclaration {
  MappingDeclaration(String, String, String)
  CommandDeclaration(String, String, String)
} derive(Eq, Debug)

///|
pub(all) enum ClientEffectStaticInputDeclaration {
  ResultDeclaration(String)
  TableInputDeclaration(String)
  NoRowInputDeclaration
} derive(Eq, Debug)

///|
pub(all) struct ClientEffectStaticMemberDeclaration {
  member_ordinal : Int
  stage_ordinal : Int
  effect_id : String
  effect_kind : String
  contract : ClientEffectStaticContractDeclaration
  input : ClientEffectStaticInputDeclaration
  failure_policy : String
  minimum_approval : ClientEffectStaticMinimumApproval
} derive(Eq, Debug)

///|
/// A readonly snapshot, not opaque execution custody. A later wire issuer
/// must read the original Owners again, never trust a caller's copied snapshot.
pub(all) struct ClientEffectStaticDeclarationSet {
  program : ClientProgramIdentity
  compiled_plan_cid : String
  check_environment_cid : String
  unit_id : String
  members : Array[ClientEffectStaticMemberDeclaration]
} derive(Eq, Debug)

///|
pub(all) enum ClientEffectStaticDeclarationIssue {
  ForeignCompilation
  InvalidLimits
  WorkLimit
  IncompleteInventory
  Member(ClientEffectMemberDescriptorIssue)
} derive(Debug)

///|
/// The original Mapping's minimum, not current authorization or an observed
/// approval. A Command is not a Mapping with minimum "none".
pub(all) enum ClientEffectStaticMinimumApproval {
  ContractMinimumNone
  ContractMinimumRequired
  ContractMinimumNotRepresented
} derive(Eq, Debug)

///|
fn client_effect_static_mapping_minimum(
  shapes : @stage_results.EffectMappingShapes,
  stage : Int,
  effect_id : String,
) -> Result[
  ClientEffectStaticMinimumApproval,
  ClientEffectStaticDeclarationIssue,
] {
  // The caller precharges this finite scan and three original-body reads.
  for index in 0..<@stage_results.effect_mapping_shape_count(shapes) {
    guard @stage_results.effect_mapping_shape_at(shapes, index) is Some(shape) else {
      return Err(IncompleteInventory)
    }
    let selected = @stage_results.effect_result_binding_header(
      @stage_results.effect_mapping_shape_effect(shape),
    )
    if @syntax.effect_header_stage(selected) != stage ||
      @syntax.effect_header_id(selected) != effect_id {
      continue
    }
    let body = @environment.member_body(
      @environment.mapping_shape_member(
        @stage_results.effect_mapping_shape_contract(shape),
      ),
    )
    guard @decode.open_object(body) is Ok(object) &&
      @decode.lookup(object, "minimum_approval") is Some(value) else {
      return Err(IncompleteInventory)
    }
    return match @decode.text(value) {
      Ok("none") => Ok(ContractMinimumNone)
      Ok("required") => Ok(ContractMinimumRequired)
      _ => Err(IncompleteInventory)
    }
  }
  Err(IncompleteInventory)
}

///|
/// Project the original checked Effect set with one shared finite work bound.
/// The member descriptor keeps Mapping and Command resolution with its Owner.
/// Neither a Checkpoint nor current approval can be inferred from these facts.
pub fn client_effect_static_declarations(
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  max_members : Int,
  max_work : Int,
) -> Result[
  ClientEffectStaticDeclarationSet,
  ClientEffectStaticDeclarationIssue,
] {
  if !physical_equal(compiled.owner, prepared) {
    return Err(ClientEffectStaticDeclarationIssue::ForeignCompilation)
  }
  // Reuse the finite original Effect-checkpoint member projection profile.
  if max_members < 1 || max_members > 64 || max_work < 1 || max_work > 10000 {
    return Err(InvalidLimits)
  }
  let headers = @checked.effect_program_static_headers(prepared.candidate)
  let count = @syntax.effect_header_count(headers)
  if count < 1 || count > max_members {
    return Err(IncompleteInventory)
  }
  let effects = @checked.effect_program_static_effects(prepared.candidate)
  let shapes = @stage_results.effect_mapping_rules_shapes(
    @stage_results.effect_static_candidate_mapping_rules(effects),
  )
  let commands = @stage_results.effect_static_candidate_command_inputs(effects)
  let mapping_count = @stage_results.effect_mapping_shape_count(shapes)
  let command_count = @stage_results.effect_command_input_count(commands)
  // Charge an upper bound for each complete descriptor scan before allocating
  // its snapshot. Do not reset the caller's total work for every member.
  if count > max_work ||
    mapping_count > max_work - count ||
    command_count > max_work - count - mapping_count {
    return Err(WorkLimit)
  }
  let descriptor_work = count + mapping_count + command_count
  // One outer read, a complete original Mapping scan, and three reads of its
  // admitted body. Check sums before bounded division to avoid overflow.
  if mapping_count > max_work - descriptor_work ||
    max_work - descriptor_work - mapping_count < 4 {
    return Err(WorkLimit)
  }
  let per_member_work = descriptor_work + mapping_count + 4
  if count > max_work / per_member_work {
    return Err(WorkLimit)
  }
  let members : Array[ClientEffectStaticMemberDeclaration] = []
  for index in 0..<count {
    guard @syntax.effect_header_at(headers, index) is Some(header) else {
      return Err(IncompleteInventory)
    }
    let stage = @syntax.effect_header_stage(header)
    let id = @syntax.effect_header_id(header)
    let (
      ordinal,
      selected_id,
      kind,
      target,
      reference,
      cid,
      result,
      failure,
      table,
    ) = match
      client_effect_member_descriptor(prepared, stage, id, descriptor_work) {
      Ok(value) => value
      Err(issue) => return Err(Member(issue))
    }
    if ordinal != index || selected_id != id {
      return Err(IncompleteInventory)
    }
    let input = match (result, table) {
      (Some(result), None) => ResultDeclaration(result)
      (None, Some(table)) => TableInputDeclaration(table)
      (None, None) => NoRowInputDeclaration
      (Some(_), Some(_)) => return Err(IncompleteInventory)
    }
    let (contract, minimum_approval) = if kind == "command" {
      // For Commands this third component is Resource kind, not a Mapping URI.
      (
        CommandDeclaration(reference, cid, target),
        ContractMinimumNotRepresented,
      )
    } else {
      let minimum = match
        client_effect_static_mapping_minimum(shapes, stage, id) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      (MappingDeclaration(reference, cid, target), minimum)
    }
    members.push({
      member_ordinal: index,
      stage_ordinal: stage,
      effect_id: id,
      effect_kind: kind,
      contract,
      input,
      failure_policy: failure,
      minimum_approval,
    })
  }
  Ok({
    program: prepared_client_effect_identity(prepared),
    compiled_plan_cid: @publication.publication_contract_identity(
      compiled.compiled.compiled_plan,
    ),
    check_environment_cid: prepared_client_effect_computation_environment_cid(
      prepared,
    ),
    unit_id: client_effect_compilation_unit_id(compiled),
    members,
  })
}
