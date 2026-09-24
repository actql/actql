///|
/// Witness closure for checked Result-publication limits. Other checked
/// operations can require additional witnesses before a Plan is complete.
pub struct ClientPublicationWitnesses {
  bodies : Array[String]
  cids : Array[String]
}

///|
pub(all) enum ClientPublicationWitnessIssue {
  InvalidLimits
  MissingPublication
  BudgetExceeded
  ConflictingWitness
  Encoding
} derive(Eq, Debug)

///|
pub(all) enum ClientPublicationWitnessAdmissionIssue {
  Issue(ClientPublicationWitnessIssue)
  MismatchedWitnesses
} derive(Eq, Debug)

///|
pub fn client_publication_witness_bodies(
  value : ClientPublicationWitnesses,
) -> Array[String] {
  value.bodies.copy()
}

///|
pub fn client_publication_witness_cids(
  value : ClientPublicationWitnesses,
) -> Array[String] {
  value.cids.copy()
}

///|
/// Enumerate the complete arithmetic witness closure retained by the common
/// capacity owner for every checked Unit Result row and byte limit. Order is
/// deterministic by Unit, Result port, scope, and owner witness order.
pub fn issue_prepared_client_publication_witnesses(
  value : PreparedClientProgram,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientPublicationWitnesses, ClientPublicationWitnessIssue] {
  if max_witnesses <= 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let program = @strategy.graph_program(value.graph)
  let bodies : Array[String] = []
  let cids : Array[String] = []
  for unit in 0..<@checked.unit_count(program) {
    guard @checked.unit_publication_count(program, unit) is Some(count) else {
      return Err(MissingPublication)
    }
    for index in 0..<count {
      guard @checked.unit_publication_at(program, unit, index)
        is Some(publication) else {
        return Err(MissingPublication)
      }
      for scope in [Rows, Bytes] {
        let claim = match scope {
          Rows => @checked.publication_rows(publication)
          Bytes => @checked.publication_bytes(publication)
        }
        let claims = @capacity.limit_claims(claim)
        for witness_index in 0..<@capacity.claim_count(claims) {
          guard @capacity.claim_at(claims, witness_index) is Some(witness) else {
            return Err(MissingPublication)
          }
          let cid = @capacity.cid(witness)
          let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
            _ => return Err(Encoding)
          }
          @capacity.emit(witness, writer) catch {
            _ => return Err(Encoding)
          }
          let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
          let mut existing = -1
          for previous in 0..<cids.length() {
            if cids[previous] == cid {
              existing = previous
            }
          }
          if existing >= 0 {
            if bodies[existing] != body {
              return Err(ConflictingWitness)
            }
          } else {
            if bodies.length() >= max_witnesses {
              return Err(BudgetExceeded)
            }
            cids.push(cid)
            bodies.push(body)
          }
        }
      }
    }
  }
  Ok({ bodies, cids, })
}

///|
/// Recheck saved Result-publication witness bytes against the checked owner.
/// This is not a complete bound-witness admission for an Executable Plan.
pub fn admit_prepared_client_publication_witnesses(
  value : PreparedClientProgram,
  saved : Array[String],
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientPublicationWitnesses, ClientPublicationWitnessAdmissionIssue] {
  let issued = match
    issue_prepared_client_publication_witnesses(
      value, max_witnesses, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Issue(issue))
  }
  if saved.length() != issued.bodies.length() {
    return Err(MismatchedWitnesses)
  }
  for index in 0..<saved.length() {
    if saved[index] != issued.bodies[index] {
      return Err(MismatchedWitnesses)
    }
  }
  Ok(issued)
}
