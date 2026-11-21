import type {remoteSiteControl} from './remote-site-control.mjs';

type SiteControl = ReturnType<typeof remoteSiteControl>;

const fail: (code: string, cause?: unknown) => never = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;

const checkedBody: (bodyText: unknown, maxBytes: number, code: string) => asserts bodyText is string =
  (bodyText, maxBytes, code) => {
  if (!text(bodyText) || !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail(code);
  }
};

const admitted = <Value,>(operation: () => Value, code: string): Value => {
  try {
    return operation();
  } catch (error) {
    fail(code, error);
  }
};

export function admitRemoteDispatchJson(
  control: Pick<SiteControl, 'admitJson'>,
  bodyText: unknown,
  claimedRequestCid: unknown,
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
  control: Pick<SiteControl, 'admitExecutionEvidenceJson'>,
  bodyText: unknown,
  claimedEvidenceCid: unknown,
  dispatch: unknown,
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
  control: Pick<SiteControl, 'admitManagedOutputSubjectJson'>,
  bodyText: unknown,
  claimedSubjectCid: unknown,
  dispatch: unknown,
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
  control: Pick<SiteControl, 'admitManagedOutputMeasurementJson'>,
  bodyText: unknown,
  claimedMeasurementCid: unknown,
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
