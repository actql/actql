///|
struct ResultPublication {
  pipeline : CheckedPipeline
  target : Target
  projection : @relation.CheckedOperation
  authored : @decode.Cursor?
  decision : @publication.Decision[LogicalOrder]
}

///|
struct PublishedInput {
  input : ProducedInput
  publication : ResultPublication
  usage : Usage
}

///|
/// Resolve publication from actual producer facts and a no-alias Result
/// projection. Source Program membership and runtime completion remain separate.
pub fn publish_produced_input(
  pipeline : CheckedPipeline,
  target : Target,
  projection : @relation.CheckedOperation,
  authored : @decode.Cursor?,
  limits : Limits,
) -> Result[PublishedInput, Issue] {
  let source = @relation.source(projection)
  try {
    let projected = match
      project_produced_input(pipeline, target, projection, limits) {
      Ok(v) => v
      Err(e) => raise Stop(e)
    }
    let used = projected.usage
    let b : Budget = {
      limits,
      work: limits.max_work - used.work,
      text: limits.max_text_bytes - used.text_bytes,
      nodes: limits.max_nodes - used.nodes,
      tokens: 0,
    }
    let fields = @relation.projection(projection)
    spend(b, source, fields.length())
    let selected : Array[String] = []
    for field in fields {
      if field.input != field.output {
        fail(source, InvalidBody)
      }
      let name = @schema.reference_name(field.output)
      charge(b, source, name)
      selected.push(name)
    }
    let schema = @relation.input_schema(projection)
    let terms : Array[@publication.AuthoredTerm]? = match authored {
      None => None
      Some(root) => {
        let n = match @decode.array_length(root) {
          Some(n) if n > 0 => n
          _ => fail(root, InvalidBody)
        }
        if limits.max_depth < 2 || b.nodes == 0 {
          fail(root, BudgetExceeded)
        }
        b.nodes -= 1
        spend(b, root, 1)
        spend(b, root, n)
        let out = []
        for i in 0..<n {
          let item = @decode.element_at(root, i).unwrap()
          let count = match @decode.object_length(item) {
            Some(n) if n == 1 || n == 3 => n
            _ => fail(item, InvalidBody)
          }
          if count + 1 > b.nodes {
            fail(item, BudgetExceeded)
          }
          b.nodes -= count + 1
          let term = match @order.read(item) {
            Ok(v) => v
            Err(e) => fail(e.source, InvalidBody)
          }
          spend(b, item, term.work)
          charge(b, term.field_source, term.field)
          let field = match @schema.lookup_reference(schema, term.field) {
            Some(f) => f
            None => fail(term.field_source, UnknownName(term.field))
          }
          if !@order.author_orderable(field.contract) {
            fail(term.field_source, InvalidBody)
          }
          out.push(@publication.AuthoredTerm::{
            field: term.field,
            direction: term.direction,
            nulls: term.nulls,
            source: item,
          })
        }
        Some(out)
      }
    }
    let decision = match
      @publication.decide(
        source,
        schema,
        @relation.output_schema(projection),
        selected,
        terms,
        candidate_keys(pipeline, target),
        logical_order(pipeline, target),
        max_work=b.work,
        max_text_bytes=b.text,
      ) {
      Ok(v) => v
      Err(e) =>
        fail(
          e.source,
          match e.kind {
            @publication.InvalidLimits => InvalidLimits
            @publication.InvalidInput => InvalidBody
            @publication.BudgetExceeded => BudgetExceeded
            @publication.UnresolvedOrder => UnresolvedOrder
          },
        )
    }
    b.work -= decision.work
    b.text -= decision.text_bytes
    let publication = { pipeline, target, projection, authored, decision, }
    let order : LogicalOrder = {
      origin: target,
      producer: None,
      imported: None,
      predecessor: None,
      completion: None,
      key_order: None,
      dependencies: [],
      publication: Some(publication),
    }
    Ok({
      input: { ..projected.input, order: Some(order), },
      publication,
      usage: {
        work: limits.max_work - b.work,
        text_bytes: limits.max_text_bytes - b.text,
        nodes: limits.max_nodes - b.nodes,
        tokens: 0,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn published_input(value : PublishedInput) -> ProducedInput {
  value.input
}

///|
pub fn published_input_usage(value : PublishedInput) -> Usage {
  value.usage
}

///|
pub fn input_publication(value : PublishedInput) -> ResultPublication {
  value.publication
}

///|
pub fn order_publication(value : LogicalOrder) -> ResultPublication? {
  value.publication
}

///|
pub fn publication_pipeline(value : ResultPublication) -> CheckedPipeline {
  value.pipeline
}

///|
pub fn publication_target(value : ResultPublication) -> Target {
  value.target
}

///|
pub fn publication_projection(
  value : ResultPublication,
) -> @relation.CheckedOperation {
  value.projection
}

///|
pub fn publication_order_source(value : ResultPublication) -> @decode.Cursor? {
  value.authored
}

///|
pub fn publication_strategy(value : ResultPublication) -> @publication.Strategy {
  value.decision.strategy
}

///|
pub fn publication_term_count(value : ResultPublication) -> Int {
  value.decision.terms.length()
}

///|
pub fn publication_term_at(
  value : ResultPublication,
  index : Int,
) -> @publication.Term? {
  value.decision.terms.get(index)
}

///|
pub fn publication_prior_order(value : ResultPublication) -> LogicalOrder? {
  value.decision.inherited
}

///|
pub fn publication_key(value : ResultPublication) -> @evidence.KeyedRelation? {
  value.decision.key
}
