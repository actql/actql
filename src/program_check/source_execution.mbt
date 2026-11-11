///|
// These are separate obligations: admitting the Host's supported acquisition
// combination does not establish validity of the returned Carrier values.
pub enum SourceExecutionKind {
  HostCombination
  ReadAuthorization
  RequestEgress
  AcquisitionResources
  CarrierResponse
  KeyedRequest(KeyedExecution)
  KeyedEgress(KeyedExecution)
  KeyedResources(KeyedExecution)
  KeyedResponse(KeyedExecution)
}

///|
pub enum SourceExecutionPhase {
  BeforeProviderAccess
  BeforeSourceOutputUse
  BeforeAndDuringAcquisition
}

///|
pub enum SourceExecutionFailure {
  PreventProviderAccess
  RejectSourceOutput
  FailAcquisitionAtomically
}

///|
pub struct KeyedExecution {
  owner : @context.SourceProducerContext
  stage : Int
  index : Int
  join : @sourceviews.KeyedJoin
  bounds : @sourceviews.LookupBounds
  requirement : @sourceviews.LookupRequirement
  producer : @capacity.TargetMembership?
}

///|
fn keyed_execution_producer_matches(
  bounds : @sourceviews.LookupBounds,
  index : Int,
  join : @sourceviews.KeyedJoin,
  membership : @capacity.TargetMembership?,
) -> Bool {
  match
    (
      @sourceviews.keyed_rows_requirement_at(
        @sourceviews.lookup_bounds_rows(bounds),
        index,
      ),
      membership,
    ) {
    (Some(@sourceviews.CheckedEstimate(rows)), Some(membership)) =>
      physical_equal(rows, @capacity.target_membership_rows(membership))
    (Some(@sourceviews.RuntimeAdmission(original)), None) =>
      physical_equal(original, join)
    _ => false
  }
}

///|
pub struct SourceExecutionSubject {
  owner : @context.ProgramSourceIdentity
  stage : Int
  input : Int
  request : @sourceviews.AcquisitionRequest
  source : @sourceviews.ResolvedInput
  response_policy : SourceResponsePolicy
  response_policy_cid : String
  direct_policy : DirectSourcePolicy?
  request_value_policy : @environment.SourceDataPolicy?
  authority : SourceReadAuthority
}

///|
struct SourceExecution {
  subject : SourceExecutionSubject
  kind : SourceExecutionKind
  phase : SourceExecutionPhase
  failure : SourceExecutionFailure
  prerequisites : Array[SourceExecution]
}

///|
// Construct bindings from the selected request inventory, including unused
// inputs. No second Catalog, policy or source selector can be substituted.
// Mode and persistent resource-envelope emission remain separate obligations.
// Keyed bindings preserve the selected logical bounds and Host policy without
// claiming that a physical transport strategy has been admitted or executed.
fn prepare_source_execution(
  identity : @context.ProgramSourceIdentity,
  budget : IdentityBudget,
  request_value_policies? : Array[HostRequestValuePolicyEvidence] = [],
  original? : Array[SourceExecution]? = None,
) -> Array[SourceExecution] raise UnitBuildFailure {
  let producer = @context.preparation_sources(
    @context.operation_profiles_preparation(
      @context.program_sources_operations(
        @context.program_identity_sources(identity),
      ),
    ),
  )
  let requests = @context.source_rows_requests(
    @context.source_policy_rows(
      @context.source_capacity_context(
        @context.source_producer_capacity(producer),
      ),
    ),
  )
  let remaining = IdentityBudget::{ ..budget, }
  let result : Array[SourceExecution] = []
  let mut original_offset = 0
  let stages = @context.program_identity_stage_count(identity)
  identity_charge(remaining, stages)
  for stage in 0..<stages {
    guard @context.source_request_stage(requests, stage) is Some(selected) else {
      raise ForeignOwner
    }
    let count = @sourceviews.pipeline_requests_count(selected)
    identity_charge(remaining, count)
    let admissions : Map[
      Int,
      (SourceExecution, SourceExecution, SourceExecution),
    ] = Map([])
    for input in 0..<count {
      identity_charge(remaining, 6)
      let request = @sourceviews.pipeline_request_at(selected, input).unwrap()
      let source = match request {
        @sourceviews.Direct(mode, _) => @sourceviews.mode_input(mode)
        @sourceviews.Keyed(mode, _) => @sourceviews.keyed_mode_input(mode)
      }
      // A policy-only continuation retains the original response/authority
      // admission. It does not serialize/hash the same response policy again.
      let prior = original.map(checks => checks[original_offset].subject)
      let (response_policy, response_policy_cid) = match prior {
        Some(subject) => {
          guard physical_equal(subject.owner, identity) &&
            subject.stage == stage &&
            subject.input == input &&
            physical_equal(subject.source, source) else {
            raise ForeignOwner
          }
          (subject.response_policy, subject.response_policy_cid)
        }
        None => {
          let policy = prepare_source_response_policy(source)
          let writer = identity_writer(remaining)
          emit_source_response_policy(policy, writer) catch {
            e => raise Encoding(e)
          }
          (policy, identity_finish(remaining, writer))
        }
      }
      original_offset += 5
      let request_value_policy = select_request_value_policy(
        identity, stage, input, request, response_policy, request_value_policies,
        remaining,
      )
      let subject = SourceExecutionSubject::{
        owner: identity,
        stage,
        input,
        request,
        source,
        response_policy,
        response_policy_cid,
        request_value_policy,
        direct_policy: match request {
          @sourceviews.Direct(_, direct) =>
            Some(
              prepare_direct_source_policy(
                direct,
                response_policy,
                response_policy_cid,
                request_value_policy~,
              ),
            )
          @sourceviews.Keyed(_, _) => None
        },
        authority: match prior {
          Some(subject) => subject.authority
          None => prepare_source_authority(source)
        },
      }
      let host = SourceExecution::{
        subject,
        kind: HostCombination,
        phase: BeforeProviderAccess,
        failure: PreventProviderAccess,
        prerequisites: [],
      }
      result.push(host)
      let authorization = SourceExecution::{
        subject,
        kind: ReadAuthorization,
        phase: BeforeProviderAccess,
        failure: PreventProviderAccess,
        prerequisites: [host],
      }
      result.push(authorization)
      let egress = SourceExecution::{
        subject,
        kind: RequestEgress,
        phase: BeforeProviderAccess,
        failure: PreventProviderAccess,
        prerequisites: [authorization],
      }
      result.push(egress)
      let resources = SourceExecution::{
        subject,
        kind: AcquisitionResources,
        phase: BeforeAndDuringAcquisition,
        failure: FailAcquisitionAtomically,
        prerequisites: [host, authorization, egress],
      }
      result.push(resources)
      let response = SourceExecution::{
        subject,
        kind: CarrierResponse,
        phase: BeforeSourceOutputUse,
        failure: RejectSourceOutput,
        prerequisites: [host, resources],
      }
      result.push(response)
      admissions[input] = (host, resources, response)
    }
    guard @context.source_request_joins(requests, stage) is Some(joins) &&
      @context.source_capacity_stage(
        @context.source_producer_capacity(producer),
        stage,
      )
      is Some(bounds) else {
      raise ForeignOwner
    }
    let joins_count = @sourceviews.keyed_join_count(joins)
    if @sourceviews.lookup_bounds_count(bounds) != joins_count {
      raise ForeignOwner
    }
    identity_charge(remaining, joins_count)
    for index in 0..<joins_count {
      identity_charge(remaining, 4)
      let join = @sourceviews.keyed_join_at(joins, index).unwrap()
      guard admissions.get(@sourceviews.keyed_join_input(join))
        is Some((host, acquisition_resources, response)) &&
        @sourceviews.lookup_requirement_at(bounds, index) is Some(requirement) else {
        raise ForeignOwner
      }
      let membership = @context.source_producer_at(producer, stage, index)
      guard physical_equal(
          @sourceviews.lookup_requirement_join(requirement),
          join,
        ) &&
        keyed_execution_producer_matches(bounds, index, join, membership) else {
        raise ForeignOwner
      }
      guard host.subject.request is @sourceviews.Keyed(_, request) &&
        physical_equal(request, @sourceviews.keyed_join_request(join)) else {
        raise ForeignOwner
      }
      let binding = match original {
        Some(checks) => {
          guard checks[original_offset].kind is KeyedRequest(binding) &&
            physical_equal(binding.owner, producer) &&
            physical_equal(binding.join, join) &&
            binding.stage == stage &&
            binding.index == index else {
            raise ForeignOwner
          }
          binding
        }
        None =>
          KeyedExecution::{
            owner: producer,
            stage,
            index,
            join,
            bounds,
            requirement,
            producer: membership,
          }
      }
      original_offset += 4
      let request_check = SourceExecution::{
        subject: host.subject,
        kind: KeyedRequest(binding),
        phase: BeforeProviderAccess,
        failure: PreventProviderAccess,
        prerequisites: [host, acquisition_resources],
      }
      let keyed_egress = SourceExecution::{
        subject: host.subject,
        kind: KeyedEgress(binding),
        phase: BeforeProviderAccess,
        failure: PreventProviderAccess,
        prerequisites: [request_check],
      }
      let resources = SourceExecution::{
        subject: host.subject,
        kind: KeyedResources(binding),
        phase: BeforeAndDuringAcquisition,
        failure: FailAcquisitionAtomically,
        prerequisites: [request_check, keyed_egress],
      }
      result.push(request_check)
      result.push(keyed_egress)
      result.push(resources)
      result.push({
        subject: host.subject,
        kind: KeyedResponse(binding),
        phase: BeforeSourceOutputUse,
        failure: FailAcquisitionAtomically,
        prerequisites: [resources, response],
      })
    }
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}
