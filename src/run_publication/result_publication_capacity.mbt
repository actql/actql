///|
/// The occurrence Result export and its physical capacity projection share
/// this issuer. This string is not an authority token.
pub fn result_export_issuer_id() -> String {
  "actql-common-host"
}

///|
/// Pure byte ceilings in artifact/derivation/ordering/durable-binding order.
/// Reuse the exact issuance emitters and the registered identity field; do not
/// create a PublicationContract or invent evidence for an unexecuted Result.
/// Unknown identities have fixed CID width. Counts use the largest Int accepted
/// by these issuers. Result field names are bounded by the separately admitted
/// schema bytes, including escaping. Failure retains the original wire ceiling.
pub fn result_publication_contract_byte_bounds(
  input_relation_cids : Array[String],
  max_schema_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Array[Int] {
  if max_schema_bytes < 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return []
  }
  let cid = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let digest = "0000000000000000000000000000000000000000000000000000000000000000"
  let result : Array[Int] = []
  for
    kind in [
      "result_artifact", "derivation_evidence", "ordering_evidence", "durable_result_binding",
    ] {
    let bound = (fn() -> Int {
      try {
        let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
        match kind {
          "result_artifact" =>
            emit_complete_result_artifact_body(
              cid, cid, cid, cid, cid, 2147483647, cid, cid, cid, writer,
            )
          "derivation_evidence" =>
            emit_derivation_evidence_body(
              cid,
              cid,
              cid,
              cid,
              input_relation_cids,
              cid,
              cid,
              result_export_issuer_id(),
              cid,
              writer,
            )
          "ordering_evidence" => emit_ordering_evidence_body(cid, cid, writer)
          _ =>
            emit_durable_result_binding_body(
              2147483647,
              cid,
              cid,
              cid,
              cid,
              cid,
              cid,
              digest,
              [],
              cid,
              cid,
              2147483647,
              cid,
              cid,
              writer,
            )
        }
        let body_wire = @encode.finish(writer)
        guard parse_contract_wire(
            body_wire, max_wire_bytes, max_nodes, max_depth,
          )
          is Ok(body) &&
          contract_spec(kind) is Some(spec) &&
          @json.object_with_string_field(body, spec.identity, cid)
          is Some(complete) else {
          return max_wire_bytes
        }
        let wire = @json.stringify_value(
          complete, max_wire_bytes, max_nodes, max_depth,
        )
        let size = @utf8.encode(wire).length()
        if kind == "durable_result_binding" {
          // Empty name array already occupies two bytes. The whole schema
          // bounds every encoded name plus separators, conservatively +2.
          if size > max_wire_bytes - 2 ||
            max_schema_bytes > max_wire_bytes - size - 2 {
            max_wire_bytes
          } else {
            size + max_schema_bytes + 2
          }
        } else {
          size
        }
      } catch {
        _ => max_wire_bytes
      }
    })()
    result.push(bound)
  }
  result
}
