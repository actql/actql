///|
pub(all) enum ClientEffectfulStaticPlanIssue {
  ForeignCompilation
  InvalidLimits
  Computation(ClientInteractivePlanIssue)
  Declarations(ClientEffectStaticDeclarationIssue)
  Contract(@publication.PublicationContractIssue)
  Encoding
  ForeignProjection
} derive(Debug)

///|
fn emit_effectful_static_unknown(
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "reason")
  @encode.string_value(writer, "not_observed")
  @encode.key(writer, "state")
  @encode.string_value(writer, "unknown")
  @encode.end_object(writer)
}

///|
fn emit_effectful_static_member(
  writer : @encode.Writer,
  entry : ClientEffectStaticMemberDeclaration,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "contract")
  @encode.begin_object(writer)
  match entry.contract {
    MappingDeclaration(reference, cid, target) => {
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, cid)
      @encode.key(writer, "declared_target")
      @encode.string_value(writer, target)
      @encode.key(writer, "kind")
      @encode.string_value(writer, "mapping")
      @encode.key(writer, "reference")
      @encode.string_value(writer, reference)
    }
    CommandDeclaration(reference, cid, resource_kind) => {
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, cid)
      @encode.key(writer, "kind")
      @encode.string_value(writer, "command")
      @encode.key(writer, "reference")
      @encode.string_value(writer, reference)
      @encode.key(writer, "resource_kind")
      @encode.string_value(writer, resource_kind)
    }
  }
  @encode.end_object(writer)
  @encode.key(writer, "effect_id")
  @encode.string_value(writer, entry.effect_id)
  @encode.key(writer, "effect_kind")
  @encode.string_value(writer, entry.effect_kind)
  @encode.key(writer, "failure_policy")
  @encode.string_value(writer, entry.failure_policy)
  @encode.key(writer, "input")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  match entry.input {
    ResultDeclaration(name) => {
      @encode.string_value(writer, "result")
      @encode.key(writer, "result_name")
      @encode.string_value(writer, name)
    }
    TableInputDeclaration(name) => {
      @encode.string_value(writer, "table")
      @encode.key(writer, "table_name")
      @encode.string_value(writer, name)
    }
    NoRowInputDeclaration => @encode.string_value(writer, "none")
  }
  @encode.end_object(writer)
  @encode.key(writer, "member_ordinal")
  @encode.number_value(writer, entry.member_ordinal.to_double())
  @encode.key(writer, "minimum_approval")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  match entry.minimum_approval {
    ContractMinimumNone | ContractMinimumRequired => {
      @encode.string_value(writer, "contract_minimum")
      @encode.key(writer, "value")
      @encode.string_value(
        writer,
        if entry.minimum_approval == ContractMinimumRequired {
          "required"
        } else {
          "none"
        },
      )
    }
    ContractMinimumNotRepresented =>
      @encode.string_value(writer, "not_represented")
  }
  @encode.end_object(writer)
  @encode.key(writer, "stage_ordinal")
  @encode.number_value(writer, entry.stage_ordinal.to_double())
  @encode.end_object(writer)
}

///|
// Private emitter accepts only the snapshot freshly read by the same issuer.
// A public caller cannot replace it with a mutable declaration snapshot.
fn emit_effectful_static_plan_view(
  writer : @encode.Writer,
  computation : @canonical.CanonicalValue,
  declarations : ClientEffectStaticDeclarationSet,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "check_environment_cid")
  @encode.string_value(writer, declarations.check_environment_cid)
  @encode.key(writer, "computation")
  @encode.begin_object(writer)
  @encode.key(writer, "plan_view")
  @canonical.emit_value(computation, writer)
  @encode.key(writer, "scope")
  @encode.string_value(writer, "computation_component")
  @encode.end_object(writer)
  @encode.key(writer, "effect_set")
  @encode.begin_object(writer)
  @encode.key(writer, "members")
  @encode.begin_array(writer)
  for entry in declarations.members {
    emit_effectful_static_member(writer, entry)
  }
  @encode.end_array(writer)
  @encode.key(writer, "unit_id")
  @encode.string_value(writer, declarations.unit_id)
  @encode.end_object(writer)
  @encode.key(writer, "observation")
  @encode.string_value(writer, "static")
  @encode.key(writer, "observations")
  @encode.begin_object(writer)
  for field in ["approval", "changed_values", "gate", "permission"] {
    @encode.key(writer, field)
    emit_effectful_static_unknown(writer)
  }
  @encode.key(writer, "preview")
  @encode.begin_object(writer)
  @encode.key(writer, "reason")
  @encode.string_value(writer, "not_sealed")
  @encode.key(writer, "state")
  @encode.string_value(writer, "unavailable")
  @encode.end_object(writer)
  @encode.key(writer, "resolved_targets")
  emit_effectful_static_unknown(writer)
  @encode.end_object(writer)
  @encode.key(writer, "parameter_values_cid")
  @encode.string_value(writer, declarations.program.parameter_values_cid)
  @encode.key(writer, "program_definition_cid")
  @encode.string_value(writer, declarations.program.program_definition_cid)
  @encode.key(writer, "provider_io")
  @encode.number_value(writer, 0.0)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-effectful-static-plan-view/0.1")
  @encode.end_object(writer)
}

///|
/// Static metadata from the exact original checked Effect compilation. The
/// computation component keeps its existing Plan/map identity; declarations
/// do not resolve physical targets or issue Preview, permission or approval.
/// No Run, Source acquisition, Model call or write is started here.
pub fn client_effectful_static_plan_view(
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members? : Int = 64,
  max_work? : Int = 10000,
) -> Result[String, ClientEffectfulStaticPlanIssue] {
  if !physical_equal(compiled.owner, prepared) {
    return Err(ForeignCompilation)
  }
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidLimits)
  }
  let declarations = match
    client_effect_static_declarations(prepared, compiled, max_members, max_work) {
    Ok(value) => value
    Err(issue) => return Err(Declarations(issue))
  }
  let component = match
    client_effect_static_computation_plan_view(
      prepared, compiled, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Computation(issue))
  }
  let computation = match
    @publication.parse_interactive_run_control_shape(
      "plan_view", component, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Contract(issue))
  }
  // A single final writer charges the complete envelope, nested Plan and all
  // members together. Separate successful fragments cannot enlarge this bound.
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_effectful_static_plan_view(writer, computation, declarations) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  match
    @publication.parse_interactive_run_control_shape(
      "effectful_static_plan_view", wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => Ok(wire)
    Err(issue) => Err(Contract(issue))
  }
}

///|
/// Compare a candidate metadata projection with the same original Owners.
/// This read-only comparison neither prepares a Program nor restores custody.
pub fn check_client_effectful_static_plan_view_binding(
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, ClientEffectfulStaticPlanIssue] {
  match
    client_effectful_static_plan_view(
      prepared, compiled, max_bytes, max_nodes, max_depth,
    ) {
    Ok(original) if original == wire => Ok(())
    Ok(_) => Err(ForeignProjection)
    Err(issue) => Err(issue)
  }
}
