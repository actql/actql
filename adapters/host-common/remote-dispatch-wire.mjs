const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

const text = value => typeof value === 'string' && value.length > 0;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

export function admitRemoteDispatchJson(
  control,
  bodyText,
  claimedRequestCid,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admit !== 'function' ||
      typeof control.requestJson !== 'function' ||
      !text(bodyText) || !text(claimedRequestCid) ||
      !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail('InvalidRemoteDispatchWire');
  }
  let body;
  try { body = JSON.parse(bodyText); }
  catch (error) { fail('InvalidRemoteDispatchWire', error); }
  if (body === null || typeof body !== 'object' || Array.isArray(body) ||
      body.version !== 'actql-remote-dispatch-request/0.2') {
    fail('InvalidRemoteDispatchWire');
  }
  let request;
  try {
    request = control.admit(Object.freeze({
      coordinatorAuthority: body.coordinator_authority,
      runDefinitionCid: body.run_definition_cid,
      taskKey: body.task_key,
      taskAttempt: body.task_attempt,
      dispatchId: body.dispatch_id,
      dispatchRequestCid: claimedRequestCid,
      siteKey: body.site_key,
      siteGeneration: body.site_generation,
      runtimeBundleCid: body.runtime_bundle_cid,
      connectorRegistration: body.connector_registration,
      connectorRevision: body.connector_revision,
      strategyRevision: body.strategy_revision,
      inputBindingCid: body.input_binding_cid,
      obligationsCid: body.obligations_cid,
      budgetCid: body.budget_cid,
      evidenceIssuerCapabilityCid: body.evidence_issuer_capability_cid,
      grantCid: body.grant_cid,
    }));
  } catch (error) {
    fail('InvalidRemoteDispatchWire', error);
  }
  if (control.requestJson(request) !== bodyText) {
    fail('NonCanonicalRemoteDispatchWire');
  }
  return request;
}

export function admitRemoteExecutionEvidenceJson(
  control,
  bodyText,
  claimedEvidenceCid,
  dispatch,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitExecutionEvidence !== 'function' ||
      typeof control.evidenceJson !== 'function' ||
      typeof control.evidenceMatchesDispatch !== 'function' ||
      !text(bodyText) || !text(claimedEvidenceCid) || dispatch === undefined ||
      !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail('InvalidRemoteExecutionEvidenceWire');
  }
  let body;
  try { body = JSON.parse(bodyText); }
  catch (error) { fail('InvalidRemoteExecutionEvidenceWire', error); }
  if (body === null || typeof body !== 'object' || Array.isArray(body) ||
      body.version !== 'actql-remote-execution-evidence/0.1') {
    fail('InvalidRemoteExecutionEvidenceWire');
  }
  let evidence;
  try {
    evidence = control.admitExecutionEvidence(Object.freeze({
      connectorRegistration: body.connector_registration,
      connectorRevision: body.connector_revision,
      dispatchRequestCid: body.dispatch_request_cid,
      evidenceKind: body.evidence_kind,
      evidenceSubjectCid: body.evidence_subject_cid,
      holdingEvidenceCid: body.holding_evidence_cid,
      issuerCapabilityCid: body.issuer_capability_cid,
      materialGeneration: body.material_generation,
      obligationsCid: body.obligations_cid,
      runtimeBundleCid: body.runtime_bundle_cid,
      siteGeneration: body.site_generation,
      siteKey: body.site_key,
      strategyRevision: body.strategy_revision,
      evidenceCid: claimedEvidenceCid,
    }));
  } catch (error) {
    fail('InvalidRemoteExecutionEvidenceWire', error);
  }
  if (control.evidenceJson(evidence) !== bodyText ||
      !control.evidenceMatchesDispatch(evidence, dispatch)) {
    fail('NonCanonicalRemoteExecutionEvidenceWire');
  }
  return evidence;
}

export function admitRemoteManagedOutputSubjectJson(
  control,
  bodyText,
  claimedSubjectCid,
  dispatch,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitManagedOutputSubject !== 'function' ||
      typeof control.managedOutputSubjectJson !== 'function' ||
      typeof control.managedOutputSubjectProjection !== 'function' ||
      typeof control.identity !== 'function' || !text(bodyText) ||
      !text(claimedSubjectCid) || dispatch === undefined ||
      !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  let body;
  try { body = JSON.parse(bodyText); }
  catch (error) { fail('InvalidRemoteManagedOutputSubjectWire', error); }
  const keys = [
    'dispatch_request_cid',
    'holding_evidence_cid',
    'logical_view_cid',
    'managed_profile_cid',
    'material_generation',
    'measurement_evidence_cid',
    'physical_manifest_cid',
    'representation_codec_cid',
    'result_schema_cid',
    'retained_bytes',
    'row_count',
    'version',
  ];
  if (!exactKeys(body, keys) ||
      body.version !== 'actql-remote-managed-output-subject/0.2' ||
      !/^(0|[1-9][0-9]*)$/.test(body.retained_bytes) ||
      !Number.isSafeInteger(body.row_count) || body.row_count < 0) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  let retainedBytes;
  try { retainedBytes = BigInt(body.retained_bytes); }
  catch (error) { fail('InvalidRemoteManagedOutputSubjectWire', error); }
  if (retainedBytes > 9_223_372_036_854_775_807n) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  let subject;
  try {
    subject = control.admitManagedOutputSubject(Object.freeze({
      dispatchRequestCid: body.dispatch_request_cid,
      materialGeneration: body.material_generation,
      holdingEvidenceCid: body.holding_evidence_cid,
      managedProfileCid: body.managed_profile_cid,
      resultSchemaCid: body.result_schema_cid,
      logicalViewCid: body.logical_view_cid,
      representationCodecCid: body.representation_codec_cid,
      physicalManifestCid: body.physical_manifest_cid,
      measurementEvidenceCid: body.measurement_evidence_cid,
      rowCount: body.row_count,
      retainedBytes,
      subjectCid: claimedSubjectCid,
    }));
  } catch (error) {
    fail('InvalidRemoteManagedOutputSubjectWire', error);
  }
  const projection = control.managedOutputSubjectProjection(subject);
  if (control.managedOutputSubjectJson(subject) !== bodyText ||
      !Array.isArray(projection) || projection.length !== 12 ||
      projection[0] !== control.identity(dispatch) ||
      projection[11] !== claimedSubjectCid) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  return subject;
}

export function admitRemoteManagedOutputMeasurementJson(
  control,
  bodyText,
  claimedMeasurementCid,
  maxBytes = 262_144,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitManagedOutputMeasurement !== 'function' ||
      typeof control.managedOutputMeasurementJson !== 'function' ||
      typeof control.managedOutputMeasurementProjection !== 'function' ||
      !text(bodyText) || !text(claimedMeasurementCid) ||
      !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail('InvalidRemoteManagedOutputMeasurementWire');
  }
  let body;
  try { body = JSON.parse(bodyText); }
  catch (error) {
    fail('InvalidRemoteManagedOutputMeasurementWire', error);
  }
  if (!exactKeys(body, [
    'admission_nodes',
    'admission_text_bytes',
    'admission_work',
    'columns',
    'row_count',
    'version',
  ]) || body.version !== 'actql-remote-managed-output-measurement/0.1' ||
      !Number.isSafeInteger(body.row_count) || body.row_count < 0 ||
      !Number.isSafeInteger(body.admission_nodes) ||
      body.admission_nodes < 0 ||
      !Number.isSafeInteger(body.admission_text_bytes) ||
      body.admission_text_bytes < 0 ||
      !Number.isSafeInteger(body.admission_work) || body.admission_work < 0 ||
      !Array.isArray(body.columns) || body.columns.length > 4096) {
    fail('InvalidRemoteManagedOutputMeasurementWire');
  }
  const columns = body.columns.map(column => {
    if (!exactKeys(column, [
      'admitted_depth',
      'bytes',
      'max_value_bytes',
      'nodes',
      'null_rows',
      'rows',
    ]) || Object.values(column).some(value =>
      !Number.isSafeInteger(value) || value < 0)) {
      fail('InvalidRemoteManagedOutputMeasurementWire');
    }
    return column;
  });
  let measurement;
  try {
    measurement = control.admitManagedOutputMeasurement(Object.freeze({
      rowCount: body.row_count,
      admissionNodes: body.admission_nodes,
      admissionTextBytes: body.admission_text_bytes,
      admissionWork: body.admission_work,
      columnRows: columns.map(column => column.rows),
      columnBytes: columns.map(column => column.bytes),
      columnNodes: columns.map(column => column.nodes),
      columnMaxValueBytes: columns.map(column => column.max_value_bytes),
      columnNullRows: columns.map(column => column.null_rows),
      columnAdmittedDepths: columns.map(column => column.admitted_depth),
      measurementCid: claimedMeasurementCid,
    }));
  } catch (error) {
    fail('InvalidRemoteManagedOutputMeasurementWire', error);
  }
  const projection = control.managedOutputMeasurementProjection(measurement);
  if (control.managedOutputMeasurementJson(measurement) !== bodyText ||
      !Array.isArray(projection) || projection.length !== 7 ||
      !Array.isArray(projection[0]) || projection[0].length !== 4) {
    fail('InvalidRemoteManagedOutputMeasurementWire');
  }
  return measurement;
}
