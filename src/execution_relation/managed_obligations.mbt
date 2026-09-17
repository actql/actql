///|
/// Logical identity domains retain their existing canonical preimages. These
/// tags select a requirement; they do not define or calculate a CID.
pub(all) enum ManagedIdentityDomain {
  LogicalRow
  OrderedRows
  LogicalRelation
} derive(Eq, Debug)

///|
pub(all) enum ManagedIdentitySubject {
  ReceivedValidationRows
  ReceivedNativeRows
  AcquisitionOutput
  TaskOutput
  NamedResult
} derive(Eq, Debug)

///|
pub(all) enum ManagedIdentityDeadline {
  BeforeCidOperation
  BeforePublication
  BeforeDiscard
} derive(Eq, Debug)

///|
pub(all) enum ManagedPublicationRequirement {
  ManagedUse
  LogicalContentAddressed
} derive(Eq, Debug)

///|
pub(all) enum ManagedConsumerRequirement {
  MaterialBinding
  LogicalContentIdentity
} derive(Eq, Debug)

///|
pub(all) enum ManagedIdentityNeed {
  UnestablishedRetained
  EstablishedBy(ManagedIdentityDeadline)
} derive(Eq, Debug)

///|
/// Runtime status of one logical identity domain. Source availability is
/// independent of whether the identity has already been established.
pub(all) enum ManagedIdentityStatus {
  UnestablishedSourceRetained
  UnestablishedSourceUnavailable
  EstablishedSourceRetained(String, String)
  EstablishedSourceUnavailable(String, String)
} derive(Eq, Debug)

///|
pub(all) struct ManagedIdentityRequirement {
  domain : ManagedIdentityDomain
  subject : ManagedIdentitySubject
  need : ManagedIdentityNeed
}

///|
struct ManagedObligations {
  owner : @lower.BoundPrepared
  identities : Array[ManagedIdentityRequirement]
  publication : ManagedPublicationRequirement
  consumer : ManagedConsumerRequirement
}

///|
pub(all) enum ManagedObligationIssue {
  InvalidLimits
  DuplicateIdentity(ManagedIdentityDomain, ManagedIdentitySubject)
  MissingRequiredIdentity
} derive(Eq, Debug)

///|
pub(all) enum ManagedIdentityEstablishmentIssue {
  UnknownIdentity
  InvalidIdentity
  SourceUnavailable
  IssuerUnavailable
  UnverifiedIdentity
  ConflictingIdentity
} derive(Eq, Debug)

///|
/// Host-owned derivation result. The caller supplies requirements already
/// derived from checked semantics, consumers, publication, and Host policy;
/// connector candidate code may inspect but never weaken this value.
pub fn prepare_managed_obligations(
  owner : @lower.BoundPrepared,
  identities : Array[ManagedIdentityRequirement],
  publication : ManagedPublicationRequirement,
  consumer : ManagedConsumerRequirement,
  max_entries : Int,
) -> Result[ManagedObligations, ManagedObligationIssue] {
  if max_entries < 0 || identities.length() > max_entries {
    return Err(InvalidLimits)
  }
  for index, identity in identities {
    for prior in 0..<index {
      if identities[prior].domain == identity.domain &&
        identities[prior].subject == identity.subject {
        return Err(DuplicateIdentity(identity.domain, identity.subject))
      }
    }
  }
  let required = identities.any(identity => identity.need is EstablishedBy(_))
  if (
      publication == LogicalContentAddressed ||
      consumer == LogicalContentIdentity
    ) &&
    !required {
    return Err(MissingRequiredIdentity)
  }
  Ok({ owner, identities: identities.copy(), publication, consumer, })
}

///|
/// Installed process-managed completion retains the exact task output source;
/// it does not silently request or establish a logical content identity.
pub fn process_managed_obligations(
  owner : @lower.BoundPrepared,
) -> ManagedObligations {
  prepare_managed_obligations(
    owner,
    [{ domain: OrderedRows, subject: TaskOutput, need: UnestablishedRetained, }],
    ManagedUse,
    MaterialBinding,
    1,
  ).unwrap()
}

///|
pub fn managed_obligations_owner(
  obligations : ManagedObligations,
) -> @lower.BoundPrepared {
  obligations.owner
}

///|
pub fn managed_obligations_identities(
  obligations : ManagedObligations,
) -> Array[ManagedIdentityRequirement] {
  obligations.identities.copy()
}

///|
pub fn managed_obligations_require_logical_identity(
  obligations : ManagedObligations,
) -> Bool {
  obligations.publication == LogicalContentAddressed ||
  obligations.consumer == LogicalContentIdentity ||
  obligations.identities.any(identity => identity.need is EstablishedBy(_))
}

///|
pub fn managed_obligations_retain_source(
  obligations : ManagedObligations,
) -> Bool {
  obligations.identities.any(identity => {
    identity.need is UnestablishedRetained ||
    identity.need is EstablishedBy(BeforeDiscard)
  })
}
