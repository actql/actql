///|
/// Host-only evidence for all static values of one checked Source Request.
/// The Host must verify the actual contributors before binding this evidence.
/// A typed value, Source response policy, or equal CID is not that verification.
/// This handle cannot be authored in a Program and grants no provider access.
struct HostRequestValuePolicyEvidence {
  environment : @environment.WireEnvironment
  program_cid : String
  parameters_cid : String
  stage : Int
  input : Int
  source_view_cid : String
  request_cid : String
  origins : Array[(String, RequestValuePolicyOrigin)]
  policy : @environment.SourceDataPolicy
}

///|
priv enum RequestValuePolicyOrigin {
  Literal
  Parameter(String, @parameters.Origin)
}

///|
// Effective Parameter Values deliberately exclude Default/Supplied origin.
// Preserve it separately: equal values are not interchangeable provenance.
fn request_value_origins(
  request : @sourceviews.AcquisitionRequest,
  budget : IdentityBudget,
) -> Array[(String, RequestValuePolicyOrigin)] raise UnitBuildFailure {
  let count = match request {
    @sourceviews.Direct(_, value) =>
      @sourceviews.parameterized_request_field_count(value)
    @sourceviews.Keyed(_, value) =>
      @sourceviews.parameterized_keyed_request_field_count(value)
  }
  identity_charge(budget, count)
  let fields = []
  for index in 0..<count {
    let field = match request {
      @sourceviews.Direct(_, value) =>
        @sourceviews.parameterized_request_field_at(value, index).unwrap()
      @sourceviews.Keyed(_, value) =>
        @sourceviews.parameterized_keyed_request_field_at(value, index).unwrap()
    }
    identity_charge(budget, field.field.slot.field_name.length())
    let origin = match field.value {
      @sourceviews.CheckedLiteral(_) => Literal
      @sourceviews.BoundParameter(parameter) => {
        identity_charge(budget, parameter.name.length())
        Parameter(parameter.name, parameter.origin)
      }
      @sourceviews.UnboundHostBinding(_) => raise ForeignOwner
    }
    fields.push((field.field.slot.field_name, origin))
  }
  identity_sort(fields, budget)
  fields
}

///|
// Hash exact bound static values with the existing value wire emitter.
// Correlated keyed values retain their separate checked producer provenance.
// Unresolved Host bindings cannot be attested as concrete values.
fn request_value_identity(
  request : @sourceviews.AcquisitionRequest,
  budget : IdentityBudget,
) -> String raise UnitBuildFailure {
  let writer = identity_writer(budget)
  emit_request_value_body(request, budget, writer)
  identity_finish(budget, writer)
}

///|
fn emit_request_value_body(
  request : @sourceviews.AcquisitionRequest,
  budget : IdentityBudget,
  writer : @encode.Writer,
) -> Unit raise UnitBuildFailure {
  let count = match request {
    @sourceviews.Direct(_, value) =>
      @sourceviews.parameterized_request_field_count(value)
    @sourceviews.Keyed(_, value) =>
      @sourceviews.parameterized_keyed_request_field_count(value)
  }
  identity_charge(budget, count)
  let fields = []
  for index in 0..<count {
    let field = match request {
      @sourceviews.Direct(_, value) =>
        @sourceviews.parameterized_request_field_at(value, index).unwrap()
      @sourceviews.Keyed(_, value) =>
        @sourceviews.parameterized_keyed_request_field_at(value, index).unwrap()
    }
    if field.value is @sourceviews.UnboundHostBinding(_) {
      raise ForeignOwner
    }
    fields.push((field.field.slot.field_name, field))
  }
  identity_sort(fields, budget)
  try {
    @encode.begin_object(writer)
    for (name, field) in fields {
      @encode.key(writer, name)
      match field.value {
        @sourceviews.CheckedLiteral(value) =>
          @value.emit_checked_wire_value(value, writer)
        @sourceviews.BoundParameter(parameter) =>
          @value.emit_checked_wire_value(parameter.value, writer)
        @sourceviews.UnboundHostBinding(_) =>
          abort("unbound field escaped request identity admission")
      }
    }
    @encode.end_object(writer)
  } catch {
    e => raise Encoding(e)
  }
}

///|
/// Read the exact static subject for a trusted Host verifier, not a public
/// credential or authored assertion. Preserve raw value strings and origins.
pub fn request_value_policy_subject_wire(
  check : SourceExecution,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  request_value_policy_subject_body(check, budget)
}

///|
/// Bound the whole trusted descriptor inventory with one existing identity
/// budget; per-request ceilings must not multiply into unaccounted retention.
pub fn request_value_policy_subject_wires(
  checks : Array[SourceExecution],
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Array[String] raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  identity_charge(budget, checks.length())
  checks.map(check => request_value_policy_subject_body(check, budget))
}

///|
fn request_value_policy_subject_body(
  check : SourceExecution,
  budget : IdentityBudget,
) -> String raise UnitBuildFailure {
  let subject = check.subject
  let request_cid = request_value_identity(subject.request, budget)
  let origins = request_value_origins(subject.request, budget)
  let writer = @encode.writer(budget.bytes, budget.nodes, budget.depth) catch {
    e => raise Encoding(e)
  }
  emit_request_value_policy_subject(check, request_cid, origins, budget, writer)
  let (body, bytes, nodes, _) = @encode.finish_text_usage(writer) catch {
    e => raise Encoding(e)
  }
  identity_charge(budget, bytes)
  identity_charge(budget, nodes)
  budget.bytes -= bytes
  budget.nodes -= nodes
  body
}

///|
// One descriptor meaning for legacy emission and the same-parent staged
// constructor. Retained request identity/origins are immutable DATA, not a
// verifier answer, policy decision or provider permission.
fn emit_request_value_policy_subject(
  check : SourceExecution,
  request_cid : String,
  origins : Array[(String, RequestValuePolicyOrigin)],
  budget : IdentityBudget,
  writer : @encode.Writer,
) -> Unit raise UnitBuildFailure {
  let subject = check.subject
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "input")
    @encode.number_value(writer, subject.input.to_double())
    @encode.key(writer, "origins")
    @encode.begin_object(writer)
    for (name, origin) in origins {
      @encode.key(writer, name)
      match origin {
        Literal => @encode.string_value(writer, "literal")
        Parameter(name, origin) => {
          @encode.begin_object(writer)
          @encode.key(writer, "origin")
          @encode.string_value(
            writer,
            if origin is @parameters.Default {
              "default"
            } else {
              "supplied"
            },
          )
          @encode.key(writer, "parameter")
          @encode.string_value(writer, name)
          @encode.end_object(writer)
        }
      }
    }
    @encode.end_object(writer)
    @encode.key(writer, "parameters_cid")
    @encode.string_value(
      writer,
      @context.program_identity_parameter_values_cid(subject.owner),
    )
    @encode.key(writer, "program_cid")
    @encode.string_value(
      writer,
      @context.program_identity_definition_cid(subject.owner),
    )
    @encode.key(writer, "request")
  } catch {
    e => raise Encoding(e)
  }
  emit_request_value_body(subject.request, budget, writer)
  try {
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, request_cid)
    @encode.key(writer, "source_ref")
    @encode.string_value(
      writer,
      @environment.data_policy_source(
        @environment.source_view_data_policy(
          subject.response_policy.authoritative,
        ),
      ),
    )
    @encode.key(writer, "source_view_contract_cid")
    @encode.string_value(writer, @sourceviews.selected_cid(subject.source))
    @encode.key(writer, "stage")
    @encode.number_value(writer, subject.stage.to_double())
    @encode.end_object(writer)
  } catch {
    e => raise Encoding(e)
  }
}

///|
/// Select only an already admitted policy from this request's Environment.
/// A matching CID is not verification: the trusted Host must first establish
/// that this policy covers every actual static value contributor.
pub fn bind_host_verified_request_value_policy_cid(
  check : SourceExecution,
  policy_cid : String,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> HostRequestValuePolicyEvidence raise UnitBuildFailure {
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  let policy = request_value_policy_for_cid(check, policy_cid, budget)
  bind_host_verified_request_value_policy(
    check,
    policy,
    budget.work,
    budget.bytes,
    budget.nodes,
    budget.depth,
  )
}

///|
fn request_value_policy_for_cid(
  check : SourceExecution,
  policy_cid : String,
  budget : IdentityBudget,
) -> @environment.SourceDataPolicy raise UnitBuildFailure {
  let policies = source_data_policies(check.subject.source)
  let count = @environment.data_policy_usage(policies).1
  identity_charge(budget, count)
  for index in 0..<count {
    let policy = @environment.data_policy_at(policies, index).unwrap()
    if identity_compare(
        policy_cid,
        @environment.contract_identity(
          @environment.data_policy_envelope(policy),
        ).2,
        budget,
      ) ==
      0 {
      return policy
    }
  }
  raise ForeignOwner
}

///|
/// Bind Host-verified request contributors to their exact admitted policy.
/// Invoke only after the Host verifier accepts every static value. Evidence is
/// reusable only for the same Program, Parameters, occurrence, SourceView,
/// request bytes and admitted Environment. This is not Model approval.
pub fn bind_host_verified_request_value_policy(
  check : SourceExecution,
  policy : @environment.SourceDataPolicy,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> HostRequestValuePolicyEvidence raise UnitBuildFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise BudgetExceeded
  }
  let subject = check.subject
  let environment = request_value_policy_environment(check, policy)
  let budget = IdentityBudget::{
    work: max_work,
    bytes: max_bytes,
    nodes: max_nodes,
    depth: max_depth,
  }
  let request_cid = request_value_identity(subject.request, budget)
  let origins = request_value_origins(subject.request, budget)
  bind_request_value_policy_facts(
    check, policy, environment, request_cid, origins,
  )
}

///|
fn request_value_policy_environment(
  check : SourceExecution,
  policy : @environment.SourceDataPolicy,
) -> @environment.WireEnvironment raise UnitBuildFailure {
  let subject = check.subject
  let environment = @environment.member_environment(
    @environment.contract_member(
      @environment.data_policy_envelope(
        @environment.source_view_data_policy(
          subject.response_policy.authoritative,
        ),
      ),
    ),
  )
  if !physical_equal(
      environment,
      @environment.member_environment(
        @environment.contract_member(@environment.data_policy_envelope(policy)),
      ),
    ) {
    raise ForeignOwner
  }
  environment
}

///|
fn bind_request_value_policy_facts(
  check : SourceExecution,
  policy : @environment.SourceDataPolicy,
  environment : @environment.WireEnvironment,
  request_cid : String,
  origins : Array[(String, RequestValuePolicyOrigin)],
) -> HostRequestValuePolicyEvidence {
  let subject = check.subject
  {
    environment,
    program_cid: @context.program_identity_definition_cid(subject.owner),
    parameters_cid: @context.program_identity_parameter_values_cid(
      subject.owner,
    ),
    stage: subject.stage,
    input: subject.input,
    source_view_cid: @sourceviews.selected_cid(subject.source),
    request_cid,
    origins,
    policy,
  }
}

///|
// Fail closed on absent, stale, foreign or duplicate evidence. An admitted
// policy Envelope cannot be transplanted to another value occurrence.
fn select_request_value_policy(
  identity : @context.ProgramSourceIdentity,
  stage : Int,
  input : Int,
  request : @sourceviews.AcquisitionRequest,
  response : SourceResponsePolicy,
  evidence : Array[HostRequestValuePolicyEvidence],
  budget : IdentityBudget,
) -> @environment.SourceDataPolicy? raise UnitBuildFailure {
  identity_charge(budget, evidence.length())
  let fields = match request {
    @sourceviews.Direct(_, value) =>
      @sourceviews.parameterized_request_field_count(value)
    @sourceviews.Keyed(_, value) =>
      @sourceviews.parameterized_keyed_request_field_count(value)
  }
  if fields == 0 {
    return None
  }
  let matching = []
  for item in evidence {
    if item.stage == stage && item.input == input {
      matching.push(item)
    }
  }
  guard matching.length() == 1 else { return None }
  let item = matching[0]
  let current_environment = @environment.member_environment(
    @environment.contract_member(
      @environment.data_policy_envelope(
        @environment.source_view_data_policy(response.authoritative),
      ),
    ),
  )
  if !physical_equal(item.environment, current_environment) {
    return None
  }
  for
    (expected, actual) in [
      (item.program_cid, @context.program_identity_definition_cid(identity)),
      (
        item.parameters_cid,
        @context.program_identity_parameter_values_cid(identity),
      ),
      (item.source_view_cid, @sourceviews.selected_cid(response.source)),
    ] {
    if identity_compare(expected, actual, budget) != 0 {
      return None
    }
  }
  let origins = request_value_origins(request, budget)
  if origins.length() != item.origins.length() {
    return None
  }
  identity_charge(budget, origins.length())
  for index in 0..<origins.length() {
    let (name, origin) = origins[index]
    let (previous_name, previous_origin) = item.origins[index]
    if identity_compare(name, previous_name, budget) != 0 {
      return None
    }
    match (origin, previous_origin) {
      (Literal, Literal) => ()
      (Parameter(name, origin), Parameter(previous_name, previous_origin)) =>
        if origin != previous_origin ||
          identity_compare(name, previous_name, budget) != 0 {
          return None
        }
      _ => return None
    }
  }
  if identity_compare(
      item.request_cid,
      request_value_identity(request, budget),
      budget,
    ) !=
    0 {
    return None
  }
  Some(item.policy)
}
