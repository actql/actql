///|
/// Original literal and delta imports over the same produced holders/Budget.
/// Yield before each original constructor; no producer is mutated or reissued.
fn advance_pipeline_core_imported(body : PipelineCoreBody) -> Unit raise Stop {
  let b = body.b
  let source = body.source
  let produced = body.produced_inputs
  match body.imported_step {
    LiteralInputs => {
      spend(b, source, produced.length())
      body.literal_inputs = Some(
        produced.map(input => input.bind(v => v.literals)),
      )
      body.imported_index = 0
      body.imported_step = LiteralDomain
    }
    LiteralDomain =>
      if body.imported_index < produced.length() {
        match body.literal_inputs.unwrap()[body.imported_index] {
          Some(domains) => {
            body.literal_read = Some(
              match
                @evidence.begin_literal_domains_read(source, domains, {
                  max_work: b.work,
                  max_name_bytes: b.text,
                }) {
                Ok(read) => read
                Err(issue) =>
                  raise Stop({
                    kind: KeyEvidence(issue.kind),
                    source,
                    path: issue.path.copy(),
                    span: issue.span,
                    range: None,
                  })
              },
            )
            body.imported_step = LiteralRead
          }
          None => body.imported_index += 1
        }
      } else {
        body.imported_step = LiteralSteps
      }
    LiteralRead => {
      let read = body.literal_read.unwrap()
      match @evidence.advance_literal_domains_read(read) {
        Pending => ()
        Complete => {
          let _ = literal_result(
            b,
            source,
            @evidence.take_literal_domains_read(read).unwrap(),
          )
          @evidence.clear_literal_domains_read(read)
          body.literal_read = None
          body.imported_index += 1
          body.imported_step = LiteralDomain
        }
        Failed => {
          let issue = @evidence.literal_domains_read_issue(read).unwrap()
          raise Stop({
            kind: KeyEvidence(issue.kind),
            source,
            path: issue.path.copy(),
            span: issue.span,
            range: None,
          })
        }
        _ => abort("original literal import was retired before its Core")
      }
    }
    LiteralSteps => {
      body.literal_steps = Some([])
      body.imported_step = DeltaStart
    }
    DeltaStart => {
      spend(b, source, produced.length())
      body.delta_inputs = Some([])
      body.imported_index = 0
      body.imported_step = DeltaInput
    }
    DeltaInput =>
      if body.imported_index < produced.length() {
        body.delta_pending = Some(empty_delta())
        if produced[body.imported_index] is Some(producer) {
          spend(b, source, producer.delta.fields.length())
          body.delta_iterator = Some(producer.delta.fields.iter())
          body.imported_step = DeltaField
        } else {
          body.imported_step = DeltaAppend
        }
      } else {
        body.imported_step = DeltaSteps
      }
    DeltaField => {
      let next = body.delta_iterator.unwrap().next()
      match next {
        Some((field, contract)) => {
          body.delta_field = next
          charge(b, source, field)
          body.carrier_read = Some(
            begin_carrier_preflight_read(
              b,
              source,
              @carrier.graph_carrier(@graph_contract.graph(contract)),
            ),
          )
          body.imported_step = DeltaCarrier
        }
        None => {
          body.delta_iterator = None
          body.imported_step = DeltaAppend
        }
      }
    }
    DeltaCarrier => {
      let read = body.carrier_read.unwrap()
      advance_carrier_preflight_read(read)
      match read.state {
        Pending => ()
        Complete => {
          clear_carrier_preflight_read(read)
          body.carrier_read = None
          body.imported_step = DeltaRegister
        }
        Rejected(issue) => raise Stop(issue)
        Cleared =>
          abort("original imported Carrier was retired before its Core")
      }
    }
    DeltaRegister => {
      let (field, contract) = body.delta_field.unwrap()
      // Explicit bindings may later extend only this new Map, never producer.
      body.delta_pending.unwrap().fields[field] = contract
      body.delta_field = None
      body.imported_step = DeltaField
    }
    DeltaAppend => {
      let current = body.delta_pending.unwrap()
      body.delta_inputs.unwrap().push(current)
      let actual = @shape.map_retained_extent(
        1L,
        current.fields.capacity().to_int64(),
        current.fields.length().to_int64(),
      ).unwrap()
      // Completed Maps are immutable during this original import loop. Retain
      // their actual storage sum once instead of rescanning them at each step.
      body.delta_completed_storage = @shape.add_collection_construction_extents(
        body.delta_completed_storage,
        @shape.add_collection_construction_extents(actual, {
          record_headers: 1L,
          reference_slots: 1L,
          scalar_words: 0L,
        }).unwrap(),
      ).unwrap()
      body.delta_pending = None
      body.imported_index += 1
      body.imported_step = DeltaInput
    }
    DeltaSteps => {
      body.delta_steps = Some([])
      body.phase = DeltaContracts
    }
  }
}
