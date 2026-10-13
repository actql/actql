///|
pub struct ScoreContract {
  domain : String
  normalization : String
  minimum : Double
  maximum : Double
}

///|
pub fn score_contract_domain(value : ScoreContract) -> String {
  value.domain
}

///|
pub fn score_contract_normalization(value : ScoreContract) -> String {
  value.normalization
}

///|
pub fn score_contract_minimum(value : ScoreContract) -> Double {
  value.minimum
}

///|
pub fn score_contract_maximum(value : ScoreContract) -> Double {
  value.maximum
}

///|
pub fn read_score_contract(
  at : @decode.Cursor,
) -> ScoreContract raise Stop {
  let root = decoded(
    @decode.closed_object(at, [
      "domain", "range", "normalization", "higher_is_better",
    ]),
  )
  let domain = score_contract_name(
    decoded(@decode.required(root, "domain")),
  )
  let normalization = score_contract_name(
    decoded(@decode.required(root, "normalization")),
  )
  if @decode.lookup(root, "higher_is_better") is Some(at) {
    if !decoded(@decode.boolean(at)) {
      fail(at, InvalidBody)
    }
  }
  let range_at = decoded(@decode.required(root, "range"))
  let items = decoded(@decode.elements(range_at))
  if items.length() != 2 {
    fail(range_at, InvalidBody)
  }
  let minimum = decoded(@decode.finite_number(items[0]))
  let maximum = decoded(@decode.finite_number(items[1]))
  if minimum > maximum {
    fail(range_at, InvalidBody)
  }
  { domain, normalization, minimum, maximum, }
}

///|
fn score_contract_name(at : @decode.Cursor) -> String raise Stop {
  let name = decoded(@decode.text(at))
  if name.is_empty() { fail(at, InvalidBody) }
  name
}
