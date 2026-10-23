///|
// Private to one artifact construction. This retains the already-checked
// metadata, not an execution grant or a physical publication acknowledgement.
priv struct PreparedPublicationRowBody {
  host : @host.Witness
  candidates : Array[(String, @wire.WireWitness?)]
  subject : String
  maximum : Int64
}

///|
fn publication_result_subject(definition_cid : String, name : String) -> String {
  let escaped = name.replace(old="~", new="~0").replace(old="/", new="~1")
  "unit:" + definition_cid + "#/results/" + escaped + "/rows"
}

///|
// Prepare the original candidate membership, ordering and subject once.
// The Unit owns both its definition identity and the selected Result limit.
fn prepare_publication_row_body(
  unit : BuiltUnit,
  index : Int,
  host : @host.Witness,
  budget : IdentityBudget,
  proofs? : Array[ReidentifiedStep]? = None,
  on_body_preparation? : (() -> Unit)? = None,
) -> PreparedPublicationRowBody raise UnitBuildFailure {
  guard unit.publication_rows.get(index) is Some(selected) else {
    raise ForeignOwner
  }
  if !physical_equal(
      @host.ceiling(host),
      @context.publication_row_limit_host(selected),
    ) {
    raise ForeignOwner
  }
  if on_body_preparation is Some(observe) {
    observe()
  }
  let publication = @context.publication_row_limit_result(selected)
  let count = @context.publication_row_limit_program_count(selected)
  let proofs = match proofs {
    Some(v) => v
    None => publication_proofs([unit], selected, budget)
  }
  if proofs.length() != count {
    raise ForeignOwner
  }
  identity_charge(budget, count)
  identity_charge(budget, 1)
  // CIDs order wire candidates, not source occurrences. Repeated proof uses
  // remain retained in the owning closure even when their wire body is shared.
  let candidates : Array[(String, @wire.WireWitness?)] = [
    (@host.cid(host), None),
  ]
  for i in 0..<count {
    let candidate = @context.publication_row_limit_program_at(selected, i).unwrap()
    let bound = require_step_target_rows(
      @capacity.target_membership_rows(candidate.membership),
    )
    if !physical_equal(bound, proofs[i].original) {
      raise ForeignOwner
    }
    let witness = @wire.program_proof_witness(proofs[i].proof)
    candidates.push((@wire.cid(witness), Some(witness)))
  }
  identity_sort(candidates, budget)
  let name = @publication.name(@publication.port_result(publication.port))
  identity_charge(budget, name.length())
  identity_charge(budget, name.length())
  identity_charge(budget, name.length())
  identity_charge(budget, unit.definition_cid.length())
  // JSON Pointer escaping makes arbitrary authored Result names unambiguous.
  // No process-local stage/step index is part of this protected subject.
  let subject = publication_result_subject(unit.definition_cid, name)
  {
    host,
    candidates,
    subject,
    maximum: @context.publication_row_limit_maximum(selected),
  }
}

///|
// Serialization passes consume the same private immutable preparation. They
// still meter each actual traversal and use their own bounded Writer.
fn emit_prepared_publication_row_body(
  body : PreparedPublicationRowBody,
  writer : @encode.Writer,
  budget : IdentityBudget,
  cid? : String? = None,
) -> Unit raise UnitBuildFailure {
  identity_charge(budget, body.candidates.length())
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "author_guard_binding")
    @encode.string_value(writer, "absent")
    @encode.key(writer, "breach")
    @encode.string_value(writer, "fail")
    @encode.key(writer, "candidates")
    @encode.begin_array(writer)
    let mut previous = ""
    for (cid, witness) in body.candidates {
      if cid == previous {
        continue
      }
      previous = cid
      match witness {
        None => @host.emit(body.host, writer)
        Some(value) => @wire.emit(value, writer)
      }
    }
    @encode.end_array(writer)
    @encode.key(writer, "effective_max")
    @encode.number_value(writer, body.maximum.to_double())
    @encode.key(writer, "enforcement")
    @encode.string_value(writer, "engine_atomic")
    if cid is Some(value) {
      @encode.key(writer, "resolved_limit_cid")
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "subject_ref")
    @encode.string_value(writer, body.subject)
    @encode.key(writer, "unit")
    @encode.string_value(writer, "rows")
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-resolved-limit/0.1")
    @encode.end_object(writer)
  } catch {
    e => raise Encoding(e)
  }
}
