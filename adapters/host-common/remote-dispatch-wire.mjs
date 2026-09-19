const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

const text = value => typeof value === 'string' && value.length > 0;

const checkedBody = (bodyText, maxBytes, code) => {
  if (!text(bodyText) || !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail(code);
  }
};

const admitted = (operation, code) => {
  try {
    return operation();
  } catch (error) {
    fail(code, error);
  }
};

export function admitRemoteDispatchJson(
  control,
  bodyText,
  claimedRequestCid,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitJson !== 'function' || !text(claimedRequestCid)) {
    fail('InvalidRemoteDispatchWire');
  }
  checkedBody(bodyText, maxBytes, 'InvalidRemoteDispatchWire');
  return admitted(
    () => control.admitJson(bodyText, claimedRequestCid),
    'InvalidRemoteDispatchWire',
  );
}

export function admitRemoteExecutionEvidenceJson(
  control,
  bodyText,
  claimedEvidenceCid,
  dispatch,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitExecutionEvidenceJson !== 'function' ||
      !text(claimedEvidenceCid) || dispatch === undefined) {
    fail('InvalidRemoteExecutionEvidenceWire');
  }
  checkedBody(bodyText, maxBytes, 'InvalidRemoteExecutionEvidenceWire');
  return admitted(
    () => control.admitExecutionEvidenceJson(
      bodyText,
      claimedEvidenceCid,
      dispatch,
    ),
    'InvalidRemoteExecutionEvidenceWire',
  );
}

export function admitRemoteManagedOutputSubjectJson(
  control,
  bodyText,
  claimedSubjectCid,
  dispatch,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitManagedOutputSubjectJson !== 'function' ||
      !text(claimedSubjectCid) || dispatch === undefined) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  checkedBody(bodyText, maxBytes, 'InvalidRemoteManagedOutputSubjectWire');
  return admitted(
    () => control.admitManagedOutputSubjectJson(
      bodyText,
      claimedSubjectCid,
      dispatch,
    ),
    'InvalidRemoteManagedOutputSubjectWire',
  );
}

export function admitRemoteManagedOutputMeasurementJson(
  control,
  bodyText,
  claimedMeasurementCid,
  maxBytes = 262_144,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitManagedOutputMeasurementJson !== 'function' ||
      !text(claimedMeasurementCid)) {
    fail('InvalidRemoteManagedOutputMeasurementWire');
  }
  checkedBody(
    bodyText,
    maxBytes,
    'InvalidRemoteManagedOutputMeasurementWire',
  );
  return admitted(
    () => control.admitManagedOutputMeasurementJson(
      bodyText,
      claimedMeasurementCid,
    ),
    'InvalidRemoteManagedOutputMeasurementWire',
  );
}
