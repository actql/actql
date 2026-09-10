///|
/// Independent evidence axes bound to one immutable Relation contract.
struct RelationEvidence {
  keys : @evidence.KeySet
  ranking : @vector.RankingInput
}

///|
/// Combines retained witnesses without discharging their validation obligations.
/// Matching requires the same row-knowledge or complete-schema handle, not
/// structural equality with an independently created contract. This is O(1);
/// the pipeline still charges input admission and key traversal to its budget.
pub fn combine_relation_evidence(
  source : @decode.Cursor,
  keys : @evidence.KeySet,
  ranking : @vector.RankingInput,
) -> Result[RelationEvidence, Issue] {
  try {
    let input = @vector.ranking_input_carrier(ranking)
    let records = match @carrier.relation_rows(input) {
      Some(records) => records
      None => fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let key_records = @evidence.key_set_records(keys)
    let same = if physical_equal(records, key_records) {
      true
    } else {
      match
        (
          @carrier.complete_schema(records),
          @carrier.complete_schema(key_records),
        ) {
        (Some(a), Some(b)) => physical_equal(a, b)
        _ => false
      }
    }
    if !same {
      fail(source, KeyEvidence(InputContractMismatch))
    }
    Ok({ keys, ranking, })
  } catch {
    Stop(issue) => Err(issue)
  }
}
