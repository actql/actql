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
      @checking.fail(source, InvalidLimits)
    }
    guard @carrier.relation_rows(previous.carrier).bind(r => {
        @carrier.complete_schema(r)
      })
      is Some(schema) &&
      physical_equal(schema, @relation.input_schema(op)) else {
      @checking.fail(source, RankingInputMismatch)
    }
    let b : @checking.Budget = {
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
        @checking.spend(b, source, @relation.binding_count(op))
        let slots : Array[(Int?, Bool)] = []
        let assigned : Map[String, (Int?, Bool)] = Map([])
        for i in 0..<@relation.binding_count(op) {
          let binding = @relation.binding_copy_at(op, i).unwrap()
          let annotation = match binding.input {
            Some(InputField(field)) => {
              @checking.charge(b, source, @row.reference_name(field))
              let name = ranking_field_key(field)
              (previous.tuples.get(name), previous.score_aliases.contains(name))
            }
            Some(PriorSlot(slot)) => slots[slot]
            None => (None, false)
          }
          slots.push(annotation)
          if binding.output is Some(name) {
            @checking.charge(b, source, name)
            assigned[ranking_field_key(@row.Unqualified(name))] = annotation
          }
        }
        tuples = Map([])
        scores = Map([])
        let output = @relation.output_schema(op)
        @checking.spend(b, source, @row.field_count(output))
        for i in 0..<@row.field_count(output) {
          let field = @row.field_at(output, i).unwrap().name
          @checking.charge(b, source, @row.reference_name(field))
          let name = ranking_field_key(field)
          let (tuple, score) = assigned
            .get(name)
            .unwrap_or(
              (previous.tuples.get(name), previous.score_aliases.contains(name)),
            )
          if tuple is Some(n) {
            tuples[name] = n
          }
          if score {
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
          @checking.spend(b, source, projection.length())
          for p in projection {
            let old = ranking_field_key(p.input)
            let name = ranking_field_key(p.output)
            @checking.charge(b, source, @row.reference_name(p.input))
            @checking.charge(b, source, @row.reference_name(p.output))
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
    @checking.spend(b, source, @row.field_count(output))
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
    @checking.Stop(e) => Err(e)
  }
}
