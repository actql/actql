///|
/// Named claims required by the currently checked pure operation vocabulary.
/// A requirement is not evidence of checker or backend conformance.
pub(all) enum OperationProfile {
  RelA
  SGA
  PropertyGraph
  TEA
  VecA
  CalendarProfile
  TextRankProfile
} derive(Eq, Debug)

///|
pub fn operation_profile_id(profile : OperationProfile) -> String {
  match profile {
    RelA => "actql-rela/0.1"
    SGA => "actql-sga/0.1"
    PropertyGraph => "actql-property-graph/0.1"
    TEA => "actql-tea/0.1"
    VecA => "actql-veca/0.1"
    CalendarProfile => "actql-calendar/0.1"
    TextRankProfile => "actql-text-rank/0.1"
  }
}

///|
fn primary_operation_profile(operation : CheckedOperation) -> OperationProfile? {
  Some(
    match operation {
      Infer(_) => return None
      Unary(op) =>
        match @relation.operation(op) {
          Derive
          | Filter
          | Select
          | Rename
          | Drop
          | Sort
          | Take
          | Distinct
          | DedupeRows
          | JsonPick
          | Unnest
          | AssertRows
          | Unpivot
          | Group
          | Pivot
          | Analytic
          | TopK
          | TopKBy
          | Lag
          | WatermarkRows => RelA
        }
      Join(..)
      | Append(..)
      | Nest(..)
      | Set(..)
      | CrossJoin(..)
      | Values(_)
      | WindowGroup(_) => RelA
      IntervalJoin(..)
      | AsOfJoin(..)
      | Sequence(_)
      | TimeSeries(_)
      | Event(_) => TEA
      Calendar(_) => CalendarProfile
      Window(window) =>
        // The checked window accepts only Relation and Events. This is the
        // overloaded source spelling, not an inference from the output alone.
        if @window.input(window) is @carrier.Relation(_) {
          RelA
        } else {
          TEA
        }
      Projection(projection) =>
        match @projection.operation(projection) {
          NodeRows => PropertyGraph
          Events => TEA
          Vectors => VecA
        }
      PropertyGraphConstruction(..) => PropertyGraph
      GraphMatch(_) | Traverse(..) => PropertyGraph
      Vector(_) | Nearest(..) | Pool(_) | Ranking(_) => VecA
      TextRank(..) => TextRankProfile
    },
  )
}

///|
/// Constant-time reads without copying an operation body or constructing an
/// array. Calendar additionally requires TEA; text-rank does not imply VecA or
/// the complete text-time claim. Expression and acquisition demands are separate.
pub fn operation_profile_count(operation : CheckedOperation) -> Int {
  if operation is Infer(_) {
    0
  } else if operation is Calendar(_) {
    2
  } else {
    1
  }
}

///|
pub fn operation_profile_at(
  operation : CheckedOperation,
  index : Int,
) -> OperationProfile? {
  if index == 0 {
    primary_operation_profile(operation)
  } else if index == 1 && operation is Calendar(_) {
    Some(TEA)
  } else {
    None
  }
}
