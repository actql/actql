///|
pub struct RankingTransfer {
  input : RankingInput
  usage : Usage
}

///|
/// Transfers value-domain and score annotations, never a proof of current rank
/// contiguity, uniqueness or ordering. The consumer still validates those laws.
pub fn transfer_ranking_unary(
  previous : RankingInput,
  op : @relation.CheckedOperation,
  limits : Limits,
) -> Result[RankingTransfer, Issue] {
  try {
    let source = @relation.source(op)
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    guard @carrier.relation_rows(previous.carrier).bind(r => {
        @carrier.complete_schema(r)
      })
      is Some(schema) &&
      physical_equal(schema, @relation.input_schema(op)) else {
      fail(source, RankingInputMismatch)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    let mut tuples = previous.tuples
    let mut scores = previous.score_aliases
    match @relation.operation(op) {
      Filter
      | Sort
      | Take
      | AssertRows
      | DedupeRows
      | TopK
      | TopKBy
      | Lag
      | WatermarkRows => ()
      Derive => {
        spend(b, source, @relation.binding_count(op))
        let changed : Map[String, Bool] = Map([])
        for i in 0..<@relation.binding_count(op) {
          if @relation.binding_at(op, i).unwrap().name is Some(name) {
            changed[ranking_field_key(@row.Unqualified(name))] = true
          }
        }
        spend(
          b,
          source,
          previous.tuples.length() + previous.score_aliases.length(),
        )
        tuples = Map([])
        scores = Map([])
        for name, n in previous.tuples {
          if !changed.contains(name) {
            tuples[name] = n
          }
        }
        for name, _ in previous.score_aliases {
          if !changed.contains(name) {
            scores[name] = true
          }
        }
      }
      Select | Rename | Drop | Distinct =>
        if @relation.row_operation(op) is Some(DistinctRows) {
          ()
        } else {
          tuples = Map([])
          scores = Map([])
          let projection = @relation.projection(op)
          spend(b, source, projection.length())
          for p in projection {
            let old = ranking_field_key(p.input)
            let name = ranking_field_key(p.output)
            charge(b, source, @row.reference_name(p.input))
            charge(b, source, @row.reference_name(p.output))
            if previous.tuples.get(old) is Some(n) {
              tuples[name] = n
            }
            if previous.score_aliases.contains(old) {
              scores[name] = true
            }
          }
        }
      _ => {
        tuples = Map([])
        scores = Map([])
      }
    }
    let output = @relation.output_schema(op)
    spend(b, source, @row.field_count(output))
    Ok({
      input: {
        ..previous,
        carrier: @carrier.relation(@carrier.typed_rows(output)),
        tuples,
        score_aliases: scores,
      },
      usage: {
        work: limits.max_work - b.work,
        nodes: 0,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}
