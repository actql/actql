///|
pub(all) enum Metric {
  Cosine
  Dot
  L2
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  Decode(@decode.IssueKind)
  // Original vector operation requirement; its closed facts have an existing
  // public diagnostic projection. Sibling branch/alternative errors retain
  // their typed facts without widening that disclosure boundary.
  WrongCarrier(@carrier.Kind, @carrier.Kind)
  WrongRelationCarrier(@carrier.Kind, @carrier.Kind)
  WrongCarrierAlternatives(@carrier.Kind, @carrier.Kind, @carrier.Kind)
  WrongPoolCarrier(@carrier.Kind, @carrier.Kind)
  IncompletePoolInput
  InvalidQuery
  UnknownParameter(String)
  IncompatibleParameter(String)
  DimensionMismatch(Double, Double)
  OutputCollision(String)
  UnknownOutputFields
  InvalidRole(@carrier.Issue)
  MissingNearestRole(String)
  ConflictingNearestRole(String)
  IncompleteNearestInput
  DuplicatePoolField(@row.FieldName)
  UnsupportedPoolMemberIdentity(@row.FieldName)
  MissingEligiblePoolKey
  IncompleteRankingInput
  InvalidRankingField(@row.FieldName)
  RankingDomainMismatch(@row.FieldName)
  MissingScoreContract
  ScoreContractMismatch
  RankingInputMismatch
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub(all) struct Limits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
} derive(Eq, Debug)
