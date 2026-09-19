import {request as httpsRequest} from 'node:https';
import {
  admitRemoteExecutionEvidenceJson,
  admitRemoteManagedOutputMeasurementJson,
  admitRemoteManagedOutputSubjectJson,
} from
  '../host-common/remote-dispatch-wire.mjs';

const fail = (code, cause, details = {}) => {
  throw Object.assign(new Error(code, {cause}), {code, ...details});
};
const text = value => typeof value === 'string' && value.length > 0;

async function exchangeRemoteDispatch({
  origin,
  ca,
  cert,
  key,
  servername = 'localhost',
  control,
  dispatch,
  signal,
  maxResponseBytes = 16_384,
} = {}, operation = 'dispatch') {
  if (!text(origin) || ca === undefined || cert === undefined ||
      key === undefined || !text(servername) ||
      control === null || typeof control !== 'object' ||
      typeof control.requestJson !== 'function' ||
      typeof control.journalKey !== 'function' ||
      typeof control.identity !== 'function' ||
      dispatch === undefined || !Number.isSafeInteger(maxResponseBytes) ||
      maxResponseBytes <= 0) {
    fail('InvalidRemoteSiteClientConfiguration');
  }
  const body = control.requestJson(dispatch);
  const bodyBytes = Buffer.from(body, 'utf8');
  const parts = control.journalKey(dispatch);
  const suffix = operation === 'query'
    ? '/query'
    : operation === 'cancel' ? '/cancel' : '';
  const path = `/v1/sites/${encodeURIComponent(parts[1])}/generations/` +
    `${parts[2]}/dispatches${suffix}`;
  return await new Promise((resolve, reject) => {
    const request = httpsRequest(new URL(path, origin), {
      method: 'POST',
      ca,
      cert,
      key,
      servername,
      minVersion: 'TLSv1.3',
      signal,
      headers: {
        'content-type': 'application/json',
        'content-length': String(bodyBytes.byteLength),
        'actql-dispatch-cid': control.identity(dispatch),
      },
    }, response => {
      const chunks = [];
      let length = 0;
      response.on('data', chunk => {
        length += chunk.byteLength;
        if (length > maxResponseBytes) {
          response.destroy(Object.assign(
            new Error('RemoteSiteResponseTooLarge'),
            {code: 'RemoteSiteResponseTooLarge'},
          ));
          return;
        }
        chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => {
        let payload;
        try { payload = JSON.parse(Buffer.concat(chunks, length)); }
        catch (error) {
          reject(Object.assign(new Error('InvalidRemoteSiteResponse', {
            cause: error,
          }), {code: 'InvalidRemoteSiteResponse'}));
          return;
        }
        if (response.statusCode !== 200) {
          reject(Object.assign(new Error('RemoteSiteRejected'), {
            code: 'RemoteSiteRejected',
            status: response.statusCode,
          }));
          return;
        }
        const query = operation === 'query';
        const expectedVersion = query
          ? 'actql-remote-dispatch-status/0.1'
          : 'actql-remote-dispatch-response/0.1';
        const wireRecord = value => value !== null &&
          typeof value === 'object' && typeof value.cid === 'string' &&
          typeof value.wire === 'string';
        const evidenceValid = !query ||
          (payload?.evidence === null && payload?.subject === null &&
            payload?.measurement === null) ||
          (wireRecord(payload?.evidence) && wireRecord(payload?.subject) &&
            wireRecord(payload?.measurement));
        if (payload?.version !== expectedVersion ||
            payload.dispatch_request_cid !== control.identity(dispatch) ||
            !Number.isSafeInteger(payload.revision) ||
            !Array.isArray(payload.state) || payload.state.length !== 5 ||
            !evidenceValid) {
          reject(Object.assign(new Error('InvalidRemoteSiteResponse'), {
            code: 'InvalidRemoteSiteResponse',
          }));
          return;
        }
        let evidence;
        let measurement;
        let subject;
        if (query && payload.evidence !== null) {
          try {
            evidence = admitRemoteExecutionEvidenceJson(
              control,
              payload.evidence.wire,
              payload.evidence.cid,
              dispatch,
              maxResponseBytes,
            );
            subject = admitRemoteManagedOutputSubjectJson(
              control,
              payload.subject.wire,
              payload.subject.cid,
              dispatch,
              maxResponseBytes,
            );
            measurement = admitRemoteManagedOutputMeasurementJson(
              control,
              payload.measurement.wire,
              payload.measurement.cid,
              maxResponseBytes,
            );
            if (!control.managedOutputSubjectMatchesEvidence(
              subject,
              evidence,
              dispatch,
            ) || !control.managedOutputSubjectMatchesMeasurement(
              subject,
              measurement,
            )) {
              throw Object.assign(new Error('Remote evidence mismatch'), {
                code: 'RemoteManagedOutputEvidenceMismatch',
              });
            }
          } catch (error) {
            reject(Object.assign(new Error('InvalidRemoteSiteResponse', {
              cause: error,
            }), {code: 'InvalidRemoteSiteResponse'}));
            return;
          }
        }
        resolve(Object.freeze({
          dispatchRequestCid: payload.dispatch_request_cid,
          revision: payload.revision,
          state: Object.freeze([...payload.state]),
          ...(query ? {
            evidence,
            evidenceCid: payload.evidence?.cid,
            evidenceWire: payload.evidence?.wire,
            measurement,
            measurementCid: payload.measurement?.cid,
            measurementWire: payload.measurement?.wire,
            subject,
            subjectCid: payload.subject?.cid,
            subjectWire: payload.subject?.wire,
          } : {}),
        }));
      });
    });
    request.on('error', reject);
    request.end(bodyBytes);
  });
}

export function sendRemoteDispatch(options) {
  return exchangeRemoteDispatch(options, 'dispatch');
}

export function queryRemoteDispatch(options) {
  return exchangeRemoteDispatch(options, 'query');
}

export function cancelRemoteDispatch(options) {
  return exchangeRemoteDispatch(options, 'cancel');
}
