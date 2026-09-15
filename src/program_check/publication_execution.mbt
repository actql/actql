///|
pub enum PublicationPhase {
  BeforeResultPublication
}

///|
pub enum PublicationFailure {
  PreventResultPublication
}

///|
// One owned execution binding, not parallel arrays to be zipped by a lowerer.
// Selection retains the exact order context and every conditional row-bound
// membership; those prerequisites do not become unconditional runtime facts.
struct PublicationExecution {
  selection : @context.PublicationRowLimit
  rows : @wire.LimitClaim
  bytes : @wire.LimitClaim
  proofs : Array[ReidentifiedStep]
  source_policy : PublicationSourcePolicy?
  phase : PublicationPhase
  failure : PublicationFailure
}

///|
fn prepare_publication_execution(
  unit : BuiltUnit,
  index : Int,
  budget : IdentityBudget,
  units? : Array[BuiltUnit]? = None,
  producers? : Array[BuiltUnit]? = None,
  conversion? : ProofConversion? = None,
) -> PublicationExecution raise UnitBuildFailure {
  guard unit.publication_rows.get(index) is Some(selection) else {
    raise ForeignOwner
  }
  let publication = @context.publication_row_limit_result(selection)
  let identity = @context.core_contract_identity(unit.contract_inventory)
  let selected_identity = @context.program_incoming_identity(
    @context.incoming_links_requirements(
      @context.publication_closure_owner(
        @context.publication_row_limit_owner(selection),
      ),
    ),
  )
  if !physical_equal(identity, selected_identity) {
    raise ForeignOwner
  }
  guard @context.program_identity_stage_at(identity, publication.stage)
    is Some(source) &&
    physical_equal(source, unit.source) else {
    raise ForeignOwner
  }
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, 1)
  let host = publication_host(
    @context.publication_row_limit_host(selection),
    remaining,
  )
  let proofs = publication_proofs(
    units.unwrap_or([unit]),
    selection,
    remaining,
    conversion~,
  )
  let rows = prepare_publication_row_artifact(
    unit,
    index,
    host,
    remaining,
    proofs=Some(proofs),
  )
  let bytes = prepare_publication_bytes(unit, index, remaining)
  let source_policy = prepare_publication_source_policy(
    unit,
    publication,
    remaining,
    producers~,
  )
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  {
    selection,
    rows,
    bytes,
    proofs,
    source_policy,
    phase: BeforeResultPublication,
    failure: PreventResultPublication,
  }
}
