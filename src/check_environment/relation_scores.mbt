///|
let relation_scores_component_key : String = "relation_scores"

///|
priv struct RelationScoreFacts {
  envelope : ContractEnvelope
  source : @decode.Cursor
}

///|
/// Field-scoped conditional assertions owned by the original SourceView.
/// No local snapshot, operation argument or same-named foreign member can
/// substitute this admitted Catalog/schema/facts binding.
struct SourceRelationScores {
  reference : CatalogReference
  schema : CarrierSchema
  facts : RelationScoreFacts
}

///|
fn read_relation_score_facts(
  envelope : ContractEnvelope,
  max_work : Int,
  max_depth : Int,
  meter? : CarrierSchemaMeter? = None,
) -> (RelationScoreFacts?, Int) raise CarrierStop {
  let root = envelope.body
  let object = @decode.open_object(root).unwrap_or_else(() => {
    carrier_fail(InvalidBody, root)
  })
  guard @decode.lookup(object, relation_scores_component_key) is Some(source) else {
    return (None, 0)
  }
  // Reuse the ScoreContract reader; keep its bounded scan and original cursors.
  let budget : @score_checks.Budget = {
    limits: {
      max_work,
      max_nodes: max_work,
      max_depth,
      max_text_bytes: max_work,
    },
    work: max_work,
    nodes: max_work,
    text: max_work,
  }
  try {
    @score_checks.scan(budget, source)
    let _ = @score_checks.decoded(@decode.open_object(source))
    let count = @decode.object_length(source).unwrap()
    @score_checks.spend(budget, source, count)
    for index in 0..<count {
      let (name, at) = @decode.field_at(source, index).unwrap()
      if name.is_empty() {
        @score_checks.fail(at, InvalidBody)
      }
      let _ = @score_checks.read_score_contract(at)
    }
    if meter is Some(meter) {
      meter.work += max_work - budget.work
    }
    (Some({ envelope, source, }), max_work - budget.work)
  } catch {
    @score_checks.Stop(issue) => {
      if meter is Some(meter) {
        meter.work += max_work - budget.work
      }
      carrier_fail(
        if issue.kind is BudgetExceeded {
          WorkLimit
        } else {
          InvalidBody
        },
        source,
      )
    }
  }
}

///|
fn bind_source_relation_scores(
  reference : CatalogReference,
  schema : CarrierSchema,
  facts : RelationScoreFacts,
  max_work : Int,
  meter? : CarrierSchemaMeter? = None,
) -> (SourceRelationScores, Int) raise CarrierStop {
  if !physical_equal(reference.contract, facts.envelope) {
    carrier_fail(InvalidBody, reference.source)
  }
  let rows = @carrier.relation_rows(schema.carrier).unwrap_or_else(() => {
    carrier_fail(CarrierMismatch, reference.source)
  })
  let count = @decode.object_length(facts.source).unwrap()
  let budget : RelationKeyBudget = { key_work: max_work, meter, }
  relation_key_charge(budget, facts.source, count)
  for index in 0..<count {
    let (name, at) = @decode.field_at(facts.source, index).unwrap()
    relation_key_charge(budget, at, name.length())
    guard @carrier.lookup(rows, @row.Unqualified(name)) is Present(field) &&
      field.presence == @row.Required &&
      field.contract is Some({ nullable: false, shape: Number, }) else {
      carrier_fail(InvalidBody, at)
    }
  }
  ({ reference, schema, facts, }, max_work - budget.key_work)
}

///|
pub fn source_view_relation_scores(
  view : SourceViewCarrier,
) -> SourceRelationScores? {
  view.relation_scores
}

///|
pub fn source_relation_scores_source(
  scores : SourceRelationScores,
) -> @decode.Cursor {
  scores.facts.source
}

///|
pub fn source_relation_scores_schema(
  scores : SourceRelationScores,
) -> CarrierSchema {
  scores.schema
}

///|
pub fn source_relation_scores_reference(
  scores : SourceRelationScores,
) -> CatalogReference {
  scores.reference
}
