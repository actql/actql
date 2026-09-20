import {request as httpsRequest} from 'node:https';

const fail = (code, cause, details = {}) => {
  throw Object.assign(new Error(code, {cause}), {code, ...details});
};
const text = value => typeof value === 'string' && value.length > 0;

export function projectRemoteDispatchResponse(
  control,
  dispatch,
  admitted,
  {statusReply = false} = {},
) {
  const projection = control.responseProjection(admitted);
  const evidence = control.responseEvidence(admitted);
  const subject = control.responseSubject(admitted);
  const measurement = control.responseMeasurement(admitted);
  return Object.freeze({
    dispatchRequestCid: control.identity(dispatch),
    revision: projection[0],
    state: Object.freeze(projection.slice(1)),
    ...(statusReply ? {
      evidence,
      evidenceCid: evidence === undefined
        ? undefined
        : control.evidenceIdentity(evidence),
      evidenceWire: evidence === undefined
        ? undefined
        : control.evidenceJson(evidence),
      measurement,
      measurementCid: measurement === undefined
        ? undefined
        : control.managedOutputMeasurementIdentity(measurement),
      measurementWire: measurement === undefined
        ? undefined
        : control.managedOutputMeasurementJson(measurement),
      subject,
      subjectCid: subject === undefined
        ? undefined
        : control.managedOutputSubjectIdentity(subject),
      subjectWire: subject === undefined
        ? undefined
        : control.managedOutputSubjectJson(subject),
    } : {}),
  });
}

async function exchangeRemoteDispatch({
  origin,
  ca,
  cert,
  key,
  servername = 'localhost',
  control,
  dispatch,
  inputBindingBody,
  signal,
  maxResponseBytes = 16_384,
} = {}, operation = 'dispatch') {
  if (!text(origin) || ca === undefined || cert === undefined ||
      key === undefined || !text(servername) ||
      control === null || typeof control !== 'object' ||
      typeof control.requestJson !== 'function' ||
      typeof control.prepareInputBinding !== 'function' ||
      typeof control.pollJson !== 'function' ||
      typeof control.journalKey !== 'function' ||
      typeof control.identity !== 'function' ||
      typeof control.admitResponseJson !== 'function' ||
      typeof control.responseProjection !== 'function' ||
      typeof control.responseEvidence !== 'function' ||
      typeof control.responseSubject !== 'function' ||
      typeof control.responseMeasurement !== 'function' ||
      dispatch === undefined || !Number.isSafeInteger(maxResponseBytes) ||
      maxResponseBytes <= 0 ||
      (operation === 'dispatch' && typeof inputBindingBody !== 'string')) {
    fail('InvalidRemoteSiteClientConfiguration');
  }
  const body = operation === 'dispatch'
    ? control.pollJson(
      dispatch,
      control.prepareInputBinding(inputBindingBody),
    )
    : control.requestJson(dispatch);
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
        if (response.statusCode !== 200) {
          reject(Object.assign(new Error('RemoteSiteRejected'), {
            code: 'RemoteSiteRejected',
            status: response.statusCode,
          }));
          return;
        }
        const query = operation === 'query';
        let admitted;
        try {
          const bodyText = new TextDecoder('utf-8', {fatal: true}).decode(
            Buffer.concat(chunks, length),
          );
          admitted = control.admitResponseJson(bodyText, dispatch, query);
        } catch (error) {
          reject(Object.assign(new Error('InvalidRemoteSiteResponse', {
            cause: error,
          }), {code: 'InvalidRemoteSiteResponse'}));
          return;
        }
        resolve(projectRemoteDispatchResponse(
          control,
          dispatch,
          admitted,
          {statusReply: query},
        ));
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
