///|
pub(all) enum ClientAllowedRunEvidenceIssue {
  Prepared(@publication.RunEvidenceValueIssue)
  Authorization(@publication.RunEvidenceValueIssue)
}

///|
fn emit_client_prepared_invocation_body(
  template_cid : String,
  plan_cid : String,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "compiled_plan_cid")
  @encode.string_value(writer, plan_cid)
  @encode.key(writer, "execution_context_cid")
  @encode.string_value(writer, execution_context_cid)
  @encode.key(writer, "expires_at")
  @encode.string_value(writer, expires_at)
  @encode.key(writer, "host_policy_cid")
  @encode.string_value(writer, host_policy_cid)
  @encode.key(writer, "invocation_template_cid")
  @encode.string_value(writer, template_cid)
  @encode.key(writer, "policy_decision")
  @encode.string_value(writer, "allow")
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-prepared-invocation/0.1")
  @encode.end_object(writer)
}

///|
fn emit_client_run_authorization_body(
  prepared_cid : String,
  execution_context_cid : String,
  host_policy_cid : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "decision")
  @encode.string_value(writer, "allowed")
  @encode.key(writer, "execution_context_cid")
  @encode.string_value(writer, execution_context_cid)
  @encode.key(writer, "host_policy_cid")
  @encode.string_value(writer, host_policy_cid)
  @encode.key(writer, "prepared_invocation_cid")
  @encode.string_value(writer, prepared_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-run-authorization/0.1")
  @encode.end_object(writer)
}

///|
/// Measure only the two initial bodies from the actual selected inputs. The
/// authorization link uses the template's admitted CID for its fixed ASCII
/// width before the Prepared Invocation CID exists. No evidence is issued.
pub fn measure_client_allowed_run_evidence_bodies(
  template : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  body_work? : ((Int) -> Bool)? = None,
) -> Result[
  (@encode.EncodingConstructionGeometry, @encode.EncodingConstructionGeometry),
  ClientAllowedRunEvidenceIssue,
] {
  let template_cid = @publication.run_evidence_value_identity(template)
  let prepared = try {
    match body_work {
      Some(work) =>
        @encode.work_construction_measuring_writer(
          max_wire_bytes, max_nodes, max_depth, work,
        )
      None =>
        @encode.construction_measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
    }
  } catch {
    _ => return Err(Prepared(RunEvidenceEncoding))
  }
  let prepared_geometry = try {
    emit_client_prepared_invocation_body(
      template_cid,
      @publication.publication_contract_identity(plan),
      execution_context_cid,
      host_policy_cid,
      expires_at,
      prepared,
    )
    @encode.finish_construction_measurement(prepared)
  } catch {
    _ => {
      @encode.cancel_writer(prepared)
      return Err(Prepared(RunEvidenceEncoding))
    }
  }
  let authorization = try {
    match body_work {
      Some(work) =>
        @encode.work_construction_measuring_writer(
          max_wire_bytes, max_nodes, max_depth, work,
        )
      None =>
        @encode.construction_measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
    }
  } catch {
    _ => return Err(Authorization(RunEvidenceEncoding))
  }
  try {
    emit_client_run_authorization_body(
      template_cid, execution_context_cid, host_policy_cid, authorization,
    )
    Ok(
      (
        prepared_geometry,
        @encode.finish_construction_measurement(authorization),
      ),
    )
  } catch {
    _ => {
      @encode.cancel_writer(authorization)
      Err(Authorization(RunEvidenceEncoding))
    }
  }
}

///|
/// The installing Host must authorize the caller before invoking this issuer.
/// These linked policy records never grant an Effect apply permit.
pub fn issue_client_allowed_run_evidence(
  template : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  execution_context_cid : String,
  host_policy_cid : String,
  expires_at : String,
  body_work? : ((Int) -> Bool)? = None,
) -> Result[
  (@publication.RunEvidenceValue, @publication.RunEvidenceValue),
  ClientAllowedRunEvidenceIssue,
] {
  let prepared_value = {
    let body = {
      let writer = try {
        match body_work {
          Some(work) => @encode.work_writer(100000, 10000, 100, work)
          None => @encode.writer(100000, 10000, 100)
        }
      } catch {
        _ => return Err(Prepared(RunEvidenceEncoding))
      }
      try {
        emit_client_prepared_invocation_body(
          @publication.run_evidence_value_identity(template),
          @publication.publication_contract_identity(plan),
          execution_context_cid,
          host_policy_cid,
          expires_at,
          writer,
        )
        @encode.finish(writer)
      } catch {
        _ => {
          @encode.cancel_writer(writer)
          return Err(Prepared(RunEvidenceEncoding))
        }
      }
    }
    match
      @publication.seal_run_evidence_value(
        "prepared_invocation", body, 100000, 10000, 100,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Prepared(issue))
    }
  }
  let authorization = {
    let body = {
      let writer = try {
        match body_work {
          Some(work) => @encode.work_writer(100000, 10000, 100, work)
          None => @encode.writer(100000, 10000, 100)
        }
      } catch {
        _ => return Err(Authorization(RunEvidenceEncoding))
      }
      try {
        emit_client_run_authorization_body(
          @publication.run_evidence_value_identity(prepared_value),
          execution_context_cid,
          host_policy_cid,
          writer,
        )
        @encode.finish(writer)
      } catch {
        _ => {
          @encode.cancel_writer(writer)
          return Err(Authorization(RunEvidenceEncoding))
        }
      }
    }
    match
      @publication.seal_run_evidence_value(
        "run_authorization", body, 100000, 10000, 100,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Authorization(issue))
    }
  }
  Ok((prepared_value, authorization))
}
