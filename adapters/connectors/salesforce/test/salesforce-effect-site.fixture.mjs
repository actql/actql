import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {openSqliteCredentialJournal} from
  '../../../site-node/sqlite-credential-journal.mjs';
import {INSTALLED_SALESFORCE_SITE_VERSION, installSalesforceAuthorization,
  loadInstalledSalesforceSite} from '../host/installed-salesforce-site.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
// The execution request of each fixture write kind.
export const fixtureWrites = Object.freeze({
  create: {kind: 'create', fields: ['External_Key__c', 'Name']},
  update: {kind: 'update', fields: ['Name']},
  upsert: {kind: 'upsert', key: 'External_Key__c', fields: ['Name']},
  // A Result-backed create that omits a null label.
  createOmit: {kind: 'createFromResult', sources: [
    {target: 'External_Key__c', field: 'id', nullBehavior: 'reject'},
    {target: 'Name', field: 'id', nullBehavior: 'reject'},
    {target: 'Optional_Text__c', field: 'label', nullBehavior: 'omit'}]},
});

// The Host account configuration for the local orgs: Test_Record__c reads
// and Effects are allowed; nothing else is configured.
export function salesforceSiteAccountConfiguration(orgIds) {
  return canonicalJson({
    version: 'actql-execution-account-config/0.1',
    account_id: 'salesforce-test-account',
    entries: [{
      entry_id: 'test-records', outcome: 'allow', exclusions: [],
      principal: {all: true},
      connection: {any_of: orgIds.map(orgId => `salesforce:${orgId}`)},
      resource: {any_of: ['Test_Record__c']},
      operation: {any_of: ['effect', 'read']},
    }],
  });
}

// A JSON number spelled exactly as `text` in a reply, never through a JS
// number.
const rawNumber = Symbol('rawNumber');
export const numberText = text => Object.freeze({[rawNumber]: text});
const replyJson = value => {
  const texts = [];
  const json = JSON.stringify(value, (_key, item) =>
    item !== null && typeof item === 'object' && rawNumber in item
      ? `\u0000${texts.push(item[rawNumber]) - 1}\u0000` : item);
  return json.replace(/"\\u0000([0-9]+)\\u0000"/gu,
    (_match, index) => texts[Number(index)]);
};

// The stored Number(15,2) `Amount__c` by record, in the provider's own
// spellings (exponent form, trailing digits).
export const numberValues = Object.freeze({
  1: {Amount__c: numberText('1.2345678E7')},
  2: {Amount__c: null},
  3: {Amount__c: numberText('-9999999999999.9')},
});

// The stored `date` and `datetime` values by record, as Salesforce replies.
export const temporalValues = Object.freeze({
  1: {Due_Date__c: '2024-05-22', Due_At__c: '2012-07-12T17:49:01.123+0000'},
  2: {Due_Date__c: null, Due_At__c: null},
  3: {Due_Date__c: '1700-01-01', Due_At__c: '4000-12-31T00:00:00.000+0000'},
});

export async function openSalesforceEffectSiteFixture(t, {
  commonMoon, salesforceMoon, runInvocationCid, dispatchRequestCid,
  orgId = '00D000000000001EAA',
  loseWriteReplyOnce = false,
  rateLimitWriteOnce = false,
  collectionPartial = true,
  writeOperation = 'update',
  authorization,
  // Further listed objects, each with a minimal describe, for orgs that list
  // more than the tested object.
  extraObjects = [],
  // Whether Test_Record__c's describe reports Id as sortable, and the order
  // in which the stored records are returned without ORDER BY.
  idSortable = false,
  storedOrder = [1, 2, 3],
  // A nullable, writable Optional_Text__c on Test_Record__c.
  optionalText: initialOptionalText = false,
  // A nullable, writable Salesforce `date` Due_Date__c and `datetime`
  // Due_At__c on Test_Record__c. Stored records and target reads carry them
  // in Salesforce's own spelling (the datetime in UTC as `+0000`).
  temporalFields = false,
  // The body fields every single-record PATCH must carry exactly.
  patchFields = ['Name'],
  // A nullable, writable Number(15,2) `Amount__c` on Test_Record__c, and a
  // Number(16,2) `Wide_Amount__c` that is not declared. Stored records and
  // target reads carry `numberValues`.
  numberFields = false,
  // The Host's logical connection id the Site declares under.
  connectorId = 'crm-main',
  // An HTTP status selected query requests answer with instead of rows.
  queryFailureStatus,
  // Restrict the injected query failure to this 1-based request, if set.
  queryFailureOnRequest,
  // Records a query answers instead of the three stored ones.
  storedRecords,
  // Bounded locator pages and exact reply faults for public Read acceptance.
  queryPageSize,
  queryResponse = body => body,
  // Resource-specific records for distinguishing two checked source views.
  recordsByResource,
  // Further writable objects shaped like Test_Record__c.
  writableObjects: extraWritable = [],
  // The 1-based sequence numbers of record writes the org rejects with a
  // field error.
  rejectWrites = [],
  // Exact replies by 1-based record write sequence: {status, body} with a
  // JSON body (or `raw` text), sent instead of the org's answer. With
  // `statefulRecords`, `applied: true` applies the write before the reply.
  writeReplies = {},
  // A stateful org: the stored records (`storedRecords`, or the three
  // defaults) are the org's records. A query and a target read answer their
  // current values, a target read of a missing record is 404, and an
  // applied write changes them. Rejected writes change nothing.
  statefulRecords = false,
  // With `statefulRecords`: 1-based single-record write sequences whose
  // update is applied and whose reply is then lost.
  loseReplyAfterApply = [],
  // With `statefulRecords`: per-row Collections outcomes, in request order,
  // each {apply, result}. `apply` says whether the org saved the row;
  // `result` is that row's reply entry, or undefined to leave it out of the
  // reply. The saved rows stay saved whatever the reply says.
  collectionOutcomes,
  // Called after each query reply is sent, with the org's records.
  onQuery,
  // With `statefulRecords`: 1-based single-record write sequences the org
  // reads and then holds open, neither applying nor answering them;
  // `onHeldWrite(sequence)` is called once each is held.
  holdWrites = [],
  onHeldWrite,
  // Reuse this directory's `ca.crt`, `ca.key`, `resource.crt` and
  // `resource.key` instead of issuing new ones (for state that names this
  // org's TLS identity), and listen on this fixed local port.
  certificateDirectory,
  port = 0,
  // The validity of newly issued certificates.
  certificateDays = 1,
}) {
  const writable = ['Test_Record__c', ...extraWritable];
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-site-'));
  const openssl = (...args) => execFileSync('openssl', args,
    {cwd: root, stdio: 'ignore'});
  const certificates = certificateDirectory ?? root;
  if (certificateDirectory === undefined) {
    const days = String(certificateDays);
    openssl('genrsa', '-out', 'ca.key', '2048');
    openssl('req', '-x509', '-new', '-key', 'ca.key', '-out',
      'ca.crt', '-subj', '/CN=ActQL Effect Test CA', '-days', days);
    openssl('genrsa', '-out', 'resource.key', '2048');
    openssl('req', '-new', '-key', 'resource.key', '-out',
      'resource.csr', '-subj', '/CN=localhost');
    await writeFile(join(root, 'resource.ext'),
      'subjectAltName=DNS:localhost,IP:127.0.0.1\n');
    openssl('x509', '-req', '-in', 'resource.csr', '-CA', 'ca.crt',
      '-CAkey', 'ca.key', '-CAcreateserial', '-out', 'resource.crt',
      '-days', days, '-extfile', 'resource.ext');
  }
  const [ca, cert, key] = await Promise.all([
    readFile(join(certificates, 'ca.crt')),
    readFile(join(certificates, 'resource.crt')),
    readFile(join(certificates, 'resource.key')),
  ]);
  const seen = [];
  const orgRecords = () => state === undefined ? undefined
    : [...state.values()].map(record => ({...record}))
      .sort((a, b) => a.Id < b.Id ? -1 : 1);
  let optionalText = initialOptionalText;
  let loseReply = loseWriteReplyOnce;
  let rateLimitReply = rateLimitWriteOnce;
  let observedName = 'before';
  // Target names of single objects, over the org-wide name.
  const observedNames = new Map();
  let nameUpdateable = true;
  let describeStatus = 200;
  // The stateful org's records by Id.
  const defaultRecords = () => storedOrder.map(index => ({
    Id: `a0000000000000${index}`,
    Name: `record-${index}`, External_Key__c: `key-${index}`,
    ...(temporalFields ? temporalValues[index] : {}),
    ...(numberFields ? numberValues[index] : {})}));
  const state = statefulRecords ? new Map((storedRecords ?? defaultRecords())
    .map(record => [record.Id, {...record}])) : undefined;
  const singleWriteSequence = () => seen.filter(item =>
    item.method === 'POST' || (item.method === 'PATCH' && item.path !==
      '/services/data/v62.0/composite/sobjects')).length;
  let nameCreateable = true;
  const queryPages = new Map();
  const server = createServer({cert, key}, (request, response) => {
    const observed = {method: request.method, path: request.url,
      authorization: request.headers.authorization};
    seen.push(observed);
    if (request.headers.authorization !== 'Bearer test-only-secret') {
      response.writeHead(401).end();
      return;
    }
    const prefix = '/services/data/v62.0/';
    if (request.method === 'GET' && request.url?.startsWith(`${prefix}query/01gFIXTURE`)) {
      const offset = Number(request.url.slice(`${prefix}query/01gFIXTURE`.length));
      const records = queryPages.get(offset);
      if (records === undefined) { response.writeHead(404).end(); return; }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(replyJson(queryResponse(records)));
      return;
    }
    if (queryFailureStatus !== undefined && request.method === 'GET' &&
        request.url?.startsWith(`${prefix}query?q=`) &&
        (queryFailureOnRequest === undefined ||
          seen.filter(item => item.method === 'GET' &&
            item.path?.startsWith(`${prefix}query?q=`)).length ===
          queryFailureOnRequest)) {
      response.writeHead(queryFailureStatus, {'content-type': 'application/json'});
      response.end('[{"errorCode":"SERVER_UNAVAILABLE"}]');
      return;
    }
    if (request.method === 'GET' && request.url?.startsWith(`${prefix}query?q=`)) {
      // Three stored records answer a bounded preview query, or a whole
      // acquisition query without a limit.
      const soql = decodeURIComponent(request.url.slice(
        `${prefix}query?q=`.length));
      const match =
        /^SELECT ([A-Za-z_,]+) FROM ([A-Za-z_][A-Za-z_0-9]*)( ORDER BY Id)?(?: LIMIT ([0-9]+))?$/u
          .exec(soql);
      if (match === null || !writable.includes(match[2])) {
        response.writeHead(400, {'content-type': 'application/json'});
        response.end('[{"errorCode":"MALFORMED_QUERY"}]');
        return;
      }
      const stored = state !== undefined ? (match[3] === undefined
        ? [...state.values()]
        : [...state.values()].sort((a, b) => a.Id < b.Id ? -1 : 1))
        : recordsByResource?.[match[2]] ?? storedRecords ??
          (match[3] === undefined ? storedOrder
        : [...storedOrder].sort()).map(index => ({
        Id: `a0000000000000${index}`,
        Name: `record-${index}`, External_Key__c: `key-${index}`,
        ...(temporalFields ? temporalValues[index] : {}),
        ...(numberFields ? numberValues[index] : {})}));
      const records = stored.slice(0, match[4] === undefined
        ? stored.length : Number(match[4])).map(record =>
        Object.fromEntries([['attributes', {type: match[2]}],
          ...match[1].split(',').map(name => [name, record[name] ?? null])]));
      response.writeHead(200, {'content-type': 'application/json'});
      const size = queryPageSize ?? records.length;
      const page = offset => {
        const end = Math.min(records.length, offset + size);
        return {totalSize: records.length, done: end === records.length,
          ...(end < records.length ? {nextRecordsUrl: `${prefix}query/01gFIXTURE${end}`} : {}),
          records: records.slice(offset, end)};
      };
      if (size > 0) for (let offset = size; offset < records.length; offset += size) {
        queryPages.set(offset, page(offset));
      }
      response.end(replyJson(queryResponse(page(0))), () => onQuery?.(orgRecords()));
      return;
    }
    if (request.method === 'GET' && request.url ===
        `${prefix}sobjects/`) {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({sobjects: [
        ...extraObjects.map(name => ({name, queryable: true,
          createable: false, updateable: false})),
        ...writable.map(name => ({name, queryable: true, createable: true,
          updateable: true}))]}));
      return;
    }
    const extra = extraObjects.find(name => request.method === 'GET' &&
      request.url === `${prefix}sobjects/${name}/describe`);
    if (extra !== undefined) {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({name: extra, queryable: true,
        createable: false, updateable: false,
        fields: [{name: 'Id', type: 'id', nillable: false}]}));
      return;
    }
    const described = writable.find(name => request.method === 'GET' &&
      request.url === `${prefix}sobjects/${name}/describe`);
    if (described !== undefined) {
      if (describeStatus !== 200) {
        response.writeHead(describeStatus, {'content-type': 'application/json'});
        response.end(JSON.stringify([{errorCode: 'SERVER_UNAVAILABLE'}]));
        return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify({name: described, queryable: true,
        createable: true, updateable: true, fields: [
          {name: 'Id', type: 'id', nillable: false, sortable: idSortable},
          {name: 'Name', type: 'string', nillable: false,
            defaultedOnCreate: false, createable: nameCreateable,
            updateable: nameUpdateable},
          {name: 'External_Key__c', type: 'string', externalId: true,
            unique: true, caseSensitive: true, nillable: false,
            defaultedOnCreate: false, createable: true,
            updateable: true},
          ...(optionalText ? [{name: 'Optional_Text__c', type: 'string',
            nillable: true, defaultedOnCreate: false, createable: true,
            updateable: true}] : []),
          ...(numberFields ? [
            {name: 'Amount__c', type: 'double', precision: 15, scale: 2,
              nillable: true, defaultedOnCreate: false, createable: true,
              updateable: true},
            {name: 'Wide_Amount__c', type: 'double', precision: 16,
              scale: 2, nillable: true, defaultedOnCreate: false,
              createable: true, updateable: true},
          ] : []),
          ...(temporalFields ? [
            {name: 'Due_Date__c', type: 'date', nillable: true,
              defaultedOnCreate: false, createable: true, updateable: true},
            {name: 'Due_At__c', type: 'datetime', nillable: true,
              defaultedOnCreate: false, createable: true, updateable: true},
          ] : []),
        ]}));
      return;
    }
    const record = writable.find(name => request.url?.startsWith(
      `${prefix}sobjects/${name}/`));
    // The write this request makes, applied to the stateful org.
    let apply = () => {};
    const rejected = () => {
      const sequence = seen.filter(item => item.method === 'POST' ||
        (item.method === 'PATCH' && item.path !==
          `${prefix}composite/sobjects`)).length;
      const reply = writeReplies[sequence];
      if (reply !== undefined) {
        if (reply.applied === true) apply();
        response.writeHead(reply.status, {'content-type': 'application/json'});
        response.end(reply.raw ?? JSON.stringify(reply.body));
        return true;
      }
      if (!rejectWrites.includes(sequence)) return false;
      response.writeHead(400, {'content-type': 'application/json'});
      response.end(JSON.stringify([{message: 'Rejected field',
        errorCode: 'INVALID_FIELD', fields: ['Name']}]));
      return true;
    };
    if (request.method === 'GET' && record !== undefined) {
      const target = decodeURIComponent(request.url.slice(
        `${prefix}sobjects/${record}/`.length).split('/').at(-1));
      if (state !== undefined && record === 'Test_Record__c') {
        const current = state.get(target);
        if (current === undefined) {
          response.writeHead(404, {'content-type': 'application/json'});
          response.end(JSON.stringify([{message: 'Not found',
            errorCode: 'NOT_FOUND'}]));
          return;
        }
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(replyJson(current));
        return;
      }
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(replyJson({Id: target,
        Name: observedNames.get(record) ?? observedName,
        External_Key__c: target,
        ...(temporalFields ? temporalValues[1] : {}),
        ...(numberFields ? numberValues[1] : {})}));
      return;
    }
    if (request.method === 'POST' && record !== undefined &&
        request.url === `${prefix}sobjects/${record}/`) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        const {Optional_Text__c: optional, ...required} =
          JSON.parse(observed.body);
        assert.deepEqual(required, {External_Key__c: required.Name,
          Name: required.Name});
        assert.ok(optional === undefined || optionalText);
        if (loseReply) {
          loseReply = false;
          request.socket.destroy();
          return;
        }
        if (rateLimitReply) {
          rateLimitReply = false;
          // 429 is not a documented REST write rejection: the outcome
          // stays unknown.
          response.writeHead(429, {'content-type': 'application/json'});
          response.end(JSON.stringify([{message: 'Request limit exceeded',
            errorCode: 'REQUEST_LIMIT_EXCEEDED'}]));
          return;
        }
        if (rejected()) return;
        const sequence = seen.filter(item => item.method === 'POST').length;
        response.writeHead(201, {'content-type': 'application/json'});
        response.end(JSON.stringify({id: `a0012345678901${sequence}`,
          success: true, errors: []}));
      });
      return;
    }
    if (request.method === 'PATCH' && record !== undefined) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        assert.deepEqual(Object.keys(JSON.parse(observed.body)), patchFields);
        const target = decodeURIComponent(request.url.split('/').at(-1));
        if (state !== undefined && record === 'Test_Record__c') {
          apply = () => {
            const current = state.get(target);
            if (current !== undefined) {
              Object.assign(current, JSON.parse(observed.body));
            }
          };
          if (holdWrites.includes(singleWriteSequence())) {
            onHeldWrite?.(singleWriteSequence());
            return;
          }
          if (loseReplyAfterApply.includes(singleWriteSequence())) {
            apply();
            request.socket.destroy();
            return;
          }
        }
        if (loseReply) {
          loseReply = false;
          request.socket.destroy();
          return;
        }
        if (rateLimitReply) {
          rateLimitReply = false;
          // 429 is not a documented REST write rejection: the outcome
          // stays unknown.
          response.writeHead(429, {'content-type': 'application/json'});
          response.end(JSON.stringify([{message: 'Request limit exceeded',
            errorCode: 'REQUEST_LIMIT_EXCEEDED'}]));
          return;
        }
        if (rejected()) return;
        apply();
        if (writeOperation === 'upsert') {
          const sequence = seen.filter(item => item.method === 'PATCH').length;
          response.writeHead(200, {'content-type': 'application/json'});
          response.end(JSON.stringify({id: `a0012345678901${sequence}`,
            success: true, errors: [], created: false}));
        } else {
          response.writeHead(204).end();
        }
      });
      return;
    }
    if (request.method === 'PATCH' && request.url ===
        `${prefix}composite/sobjects`) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.on('end', () => {
        observed.body = Buffer.concat(chunks).toString('utf8');
        const batch = JSON.parse(observed.body);
        assert.equal(batch.allOrNone, false);
        if (state !== undefined && collectionOutcomes !== undefined) {
          assert.equal(batch.records.length, collectionOutcomes.length);
          const results = [];
          for (const [index, row] of batch.records.entries()) {
            const outcome = collectionOutcomes[index];
            const {attributes: _type, Id: id, ...fields} = row;
            if (outcome.apply) Object.assign(state.get(id), fields);
            if (outcome.result !== undefined) results.push(outcome.result);
          }
          response.writeHead(200, {'content-type': 'application/json'});
          response.end(JSON.stringify(results));
          return;
        }
        assert.equal(batch.records.length, 2);
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify(batch.records.map((_, index) =>
          collectionPartial && index === 0
            ? {id: null, success: false, errors: [
              {statusCode: 'INVALID_FIELD', message: 'Rejected field',
                fields: ['Name']}]}
            : {id: `00100000000000${index + 1}`, success: true,
              errors: []})));
      });
      return;
    }
    response.writeHead(404).end();
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  const origin = `https://127.0.0.1:${server.address().port}`;
  // The Site is installed from a Host profile and the Host's account gate;
  // the test supplies only the local org and its secret.
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  await writeFile(join(root, 'org-ca.crt'), ca);
  const profilePath = join(root, 'salesforce-site.json');
  await writeFile(profilePath, JSON.stringify({
    version: INSTALLED_SALESFORCE_SITE_VERSION, apiVersion: 'v62.0',
    cliAlias: 'actql-test', cliUsername: 'user@example.test',
    connectionRevision: 'connection-revision-a',
    credentialAuthorityId: 'credential-authority-a',
    credentialKeyId: 'credential-key-a',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    environment: 'test', instanceOrigin: origin,
    journalRoot: join(root, 'journal'), orgId, siteGeneration: 4,
    siteKey: 'site-a', namespaceId: 'namespace-a', caPath: join(root, 'org-ca.crt'),
  }));
  const hostAuthorization = authorization ??
    await installSalesforceAuthorization({
      accountConfiguration: salesforceSiteAccountConfiguration([orgId]),
      principalId: 'principal-a', root});
  const installed = await loadInstalledSalesforceSite(profilePath, {
    commonMoon, salesforceMoon, authorization: hostAuthorization,
    runtimeBundleCid: cid('a'), resolveSecret: async () => 'test-only-secret',
    now: () => 1_999_999_999_999, grantLifetimeMs: 1});
  const journal = installed.credential.journal;
  t.after(async () => {
    installed.close();
    await new Promise(resolve => server.close(resolve));
    await rm(root, {recursive: true, force: true});
  });
  const control = installed.credential.control;
  const dispatch = {runInvocationCid, taskAttempt: 2, dispatchRequestCid};
  // Record grants follow the Host gate's own dispatch for this org's
  // Test_Record__c; the gate still decides each commit separately.
  const recordGrant = async (operation, boundary, operationClass) => {
    const decision = await hostAuthorization.authorize(boundary, {
      connection: installed.connection, resource: 'Test_Record__c',
      operation: operationClass}, {subjectCid: runInvocationCid});
    return installed.issueGrant({operation, decision,
      resource: 'Test_Record__c', ...dispatch, maxUses: 32,
      subjectCid: runInvocationCid});
  };
  const observe = await recordGrant('salesforce:record:observe',
    'acquisition', 'read');
  const write = await recordGrant(`salesforce:record:${writeOperation}`,
    'effect_commit', 'effect');
  const credential = installed.credential;
  let catalogSequence = 0;
  const catalogLimits = {
    list: {maxBytes: 10000, maxNodes: 1000, maxDepth: 20,
      maxResources: 20, maxSelected: 20, maxNameUnits: 1000},
    describe: {maxBytes: 10000, maxNodes: 1000, maxDepth: 20,
      maxFields: 20, maxNameUnits: 1000},
    maxObservationBytes: 10000,
  };
  const refreshCatalog = async ({signal} = {}) => {
    const sequence = catalogSequence++;
    return await installed.refreshCatalog({...dispatch,
      occurrence: sequence === 0 ? 'catalog-sync-a' :
        `catalog-sync-${sequence}`,
      retainResponses: sequence === 0,
      maxRetainedBytes: sequence === 0 ? 30000 : 0,
      // One dispatch's metadata grants serve every refresh of the Run.
      limits: catalogLimits, grantUses: 32, signal});
  };
  const catalog = await refreshCatalog();
  assert.equal(catalog.status, 'complete');
  // The Site's static declaration for its writable Resource: the explicit
  // publication step that gates its write capability.
  const declared = await installed.declareCatalog({connectorId,
    resources: ['Test_Record__c']});
  const recoveryGrant = authorization => Object.freeze({
    cid: control.identity(authorization.grant),
    wire: control.json(authorization.grant),
  });
  const recoveryConnection = Object.freeze({
    origin, orgId,
    caBase64: ca.toString('base64'),
    journalRoot: join(root, 'journal'),
    authorityPublicKey: authority.publicKey.export({
      type: 'spki', format: 'pem',
    }),
    list: recoveryGrant(catalog.grants.list),
    describe: recoveryGrant(catalog.grants.describe),
    observe: recoveryGrant(observe),
    write: recoveryGrant(write),
  });
  return {seen, journal, orgId, origin, catalog, observe, write, credential,
    refreshCatalog, recoveryConnection, declared,
    declaration: declared.declaration,
    // The execution Mapping of one write under this Site's declaration.
    executionMapping: (write, declaration = declared.declaration) =>
      installed.prepareExecutionMapping({declaration,
        resource: 'Test_Record__c', write}),
    refreshDeclaration: () => installed.declareCatalog({
      connectorId, resources: ['Test_Record__c']}),
    // Every object's target name, or only `resource`'s.
    setTargetName(name, resource) {
      if (resource === undefined) observedName = name;
      else observedNames.set(resource, name);
    },
    setNameUpdateable(value) { nameUpdateable = value; },
    setDescribeStatus(value) { describeStatus = value; },
    setNameCreateable(value) { nameCreateable = value; },
    setOptionalText(value) { optionalText = value; },
    // The stateful org's current records, and a change to one of them made
    // outside ActQL.
    records: () => orgRecords(),
    setRecord(id, fields) { Object.assign(state.get(id), fields); },
    deleteRecord(id) { state.delete(id); }};
}

// The real SQLite credential journal whose close fails the first `failures`
// times, counting every close attempt.
export function closeFailingJournal(failures) {
  const calls = {close: 0};
  const open = (root, options) => {
    const real = openSqliteCredentialJournal(root, options);
    return Object.freeze({...real, close() {
      calls.close++;
      if (calls.close <= failures) {
        throw Object.assign(new Error('InjectedJournalCloseFailure'),
          {code: 'InjectedJournalCloseFailure'});
      }
      return real.close();
    }});
  };
  return {open, calls};
}
