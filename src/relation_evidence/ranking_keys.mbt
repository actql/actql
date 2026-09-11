///|
fn ranking_output_keys(
  source : @decode.Cursor,
  output : @carrier.Carrier,
  by : Array[@row.FieldName],
  candidate : @row.FieldName,
  tuples : Map[String, @carrier.Vectors],
  origin : KeyOrigin,
  producer : KeyProducer,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  try {
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, 1)
    let records = @carrier.relation_rows(output).unwrap()
    let fields : Array[KeyField] = []
    let seen : Map[String, Bool] = Map([])
    // Charge authored occurrences, even when a repeated by field is one column.
    spend(b, source, by.length() + 1)
    for name in by.iter().concat([candidate].iter()) {
      charge(b, source, name)
      let spelling = ranking_field_key(name)
      if seen.contains(spelling) {
        continue
      }
      seen[spelling] = true
      guard @carrier.lookup(records, name) is Present(field) else {
        fail(source, InputContractMismatch)
      }
      fields.push({
        name,
        contract: field.contract,
        positional_identity: tuples.get(spelling),
      })
    }
    let work = limits.max_work - b.work
    let name_bytes = limits.max_name_bytes - b.text
    let witnesses : Array[KeyedRelation] = [
      {
        origin,
        producer: Some(producer),
        records,
        declared_records: records,
        declared_fields: fields,
        fields,
        source,
        aliases: fields.map(f => [f]),
        usage: { fields: fields.length(), name_bytes, },
      },
    ]
    Ok({ keys: { records, witnesses, work, name_bytes, }, work, name_bytes, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn merged_ranking_keys(
  operation : CheckedRanking,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  ranking_output_keys(
    operation.options.source,
    operation.output,
    operation.options.by,
    operation.options.candidate,
    operation.tuples,
    RankingResult,
    RankingProducer(operation),
    limits,
  )
}

///|
pub fn text_rank_keys(
  operation : CheckedTextRank,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  ranking_output_keys(
    operation.options.source,
    operation.output,
    [@row.Unqualified("query_id")],
    @row.Unqualified("candidate_id"),
    Map([]),
    TextRankResult,
    TextRankProducer(operation),
    limits,
  )
}

///|
pub fn key_ranking_producer(key : KeyedRelation) -> CheckedRanking? {
  match key.producer {
    Some(RankingProducer(op)) => Some(op)
    _ => None
  }
}

///|
pub fn key_text_rank_producer(key : KeyedRelation) -> CheckedTextRank? {
  match key.producer {
    Some(TextRankProducer(op)) => Some(op)
    _ => None
  }
}
