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
  counts : @sourceviews.LookupCounts
  producer : @capacity.TargetMembership
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
      let response_policy = prepare_source_response_policy(source)
      let policy_writer = identity_writer(remaining)
      emit_source_response_policy(response_policy, policy_writer) catch {
        e => raise Encoding(e)
      }
      let response_policy_cid = identity_finish(remaining, policy_writer)
      let subject = SourceExecutionSubject::{
        owner: identity,
        stage,
        input,
        request,
        source,
        response_policy,
        response_policy_cid,
        authority: prepare_source_authority(source),
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
        @context.source_producer_at(producer, stage, index) is Some(membership) else {
        raise ForeignOwner
      }
      guard host.subject.request is @sourceviews.Keyed(_, request) &&
        physical_equal(request, @sourceviews.keyed_join_request(join)) else {
        raise ForeignOwner
      }
      let binding = KeyedExecution::{
        owner: producer,
        stage,
        index,
        join,
        bounds,
        counts: @sourceviews.lookup_bounds_at(bounds, index).unwrap(),
        producer: membership,
      }
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
