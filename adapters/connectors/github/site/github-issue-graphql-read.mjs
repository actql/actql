// GitHub's Issue read at the Site, bound to the published repository's
// global node ID. Every outer or nested page is a POST of a fixed read-only
// GraphQL document with typed variables; this driver never sends query text
// of its own and has no name-addressed fallback. The provider MoonBit decides
// every meaning (projection, identity, cursor, failure class); this driver
// sequences exchanges, takes the current read decision before every request,
// and stops on anything but a complete, exact page.
//
// Completion is never inferred: GraphQL `errors` (including a rate limit in
// an HTTP 200), incomplete data, a missing, repeated or non-advancing cursor,
// a page or row ceiling, a revoked decision or a transport failure stops the
// read with its accepted pages and the unfetched cursor kept. Raw header
// values are not retained. Nothing is retried.
import {checked} from '../../../host-common/runtime-result.mjs';
import {types} from 'node:util';
import {withHttpsCredentialRunResponseOriginal} from
  '../../../site-node/https-credential-resource.mjs';
import {invokeScopedCredentialOperation, invocationBindingsMatch} from
  '../../../host-common/owned-invocation-context.mjs';

export const GITHUB_GRAPHQL_READ_OPERATION = 'github:graphql:read';
export const GITHUB_GRAPHQL_PATH = '/graphql';

const fail = (code, details = {}) => {
  throw Object.assign(new Error(code), {code, ...details});
};
// Escaped results and failures retain this read's bounded original prefix.
// Ticket consumption and codec retirement do not release these aliases or ACK
// the Credential/RowRun owners. No public field exposes or manufactures them.
const retainedReads = new WeakMap();
const nativeArrayIsArray = Array.isArray;
const defineOwnData = Object.defineProperty;
const freeze = Object.freeze;
const count = value => Number.isSafeInteger(value) && value > 0;
const pairs = headers => [headers.map(entry => entry[0]),
  headers.map(entry => entry[1])];

// Refusal kinds of a 200 response and the stop each one is.
const refusalCodes = Object.freeze({
  RateLimited: 'GitHubRateLimited',
  RepositoryUnavailable: 'GitHubRepositoryUnavailable',
  ForeignRepository: 'GitHubRepositoryIdentityChanged',
  IdRepresentationChanged: 'GitHubRepositoryRepublishRequired',
  BindingChanged: 'GitHubRepositoryBindingChanged',
});

function checkLimits(limits) {
  if (!limits || !count(limits.maxPages) || limits.maxPages > 2147483647 || !count(limits.maxRows) ||
      !count(limits.maxBytes) || !count(limits.maxNodes) ||
      !count(limits.maxDepth) || !count(limits.perPage) ||
      limits.perPage > 100 || !count(limits.maxRequestBytes)) {
    fail('InvalidGitHubReadLimits');
  }
  return Object.freeze({...limits});
}

// Read the published repository's Issues. `repository` is the publication's
// `{nodeId, databaseId, nameWithOwner}`; `authorizationFor(index)` returns
// the credential authorization of the next request after rechecking the
// current read decision; `chargePage(body)` charges each received body before
// provider parsing or refusal. `consumePage(rows, page, {charge})` consumes
// that exact admission ticket before the next request.
export function readGitHubIssuesByNode(options) {
  return readGitHubRowsByNode(options, false);
}

// Same physical acquisition and original-prefix Owner; only the typed vendor
// codec family changes. This selects no new credential operation or grant.
export function readGitHubPullRequestsByNode(options) {
  return readGitHubRowsByNode(options, true);
}

// Comments traverse the two actual native subject families through the same
// original Credential/exchange/prefix Owner as the Issue and PullRequest reads.
export function readGitHubIssueCommentsByNode(options) {
  return readGitHubRowsByNode(options, false, true);
}

async function readGitHubRowsByNode({moon, repository,
  filters = {state: 'all', labels: []}, credential, callResource,
  authorizationFor, limits, chargePage, consumeObservation, consumePage, signal}, pullRequests, comments = false, managed) {
  const family = comments ? 'IssueComments' : pullRequests ? 'PullRequest' : 'Issue';
  const operations = moon && Object.freeze({
    request: moon[comments ? 'githubIssueCommentsReadNextRequestJson'
      : pullRequests ? 'githubPullRequestsRequestJson' : 'githubIssuesRequestJson'],
    begin: moon[comments ? 'githubIssueCommentsReadBegin' : `github${family}PageReadBegin`],
    next: moon[comments ? 'githubIssueCommentsReadNextRequestJson' : `github${family}PageReadNextRequestJson`],
    accept: moon[comments ? 'githubIssueCommentsReadAccept' : `github${family}PageReadAccept`],
    finish: moon[comments ? 'githubIssueCommentsReadPageJson' : `github${family}PageReadFinishJson`],
    close: moon[comments ? 'githubIssueCommentsReadClose' : `github${family}PageReadClose`],
  });
  if (!moon || Object.values(operations).some(value => typeof value !== 'function') ||
      typeof moon.githubGraphqlReadIssueJson !== 'function' ||
      typeof authorizationFor !== 'function' || !credential ||
      typeof callResource !== 'function' ||
      (chargePage !== undefined && typeof chargePage !== 'function') ||
      (consumeObservation !== undefined && typeof consumeObservation !== 'function') ||
      typeof repository?.nodeId !== 'string' ||
      !Number.isSafeInteger(repository.databaseId) ||
      typeof repository.nameWithOwner !== 'string') {
    fail('InvalidGitHubRead');
  }
  const owned = checkLimits(limits);
  const originalCredential = Object.freeze({...credential, retainRunResponseOriginal: true});
  const {control, journal} = originalCredential;
  const useProjection = control.useProjection;
  const grantIdentity = control.identity;
  const prefix = {responses: [], pages: [], credential: originalCredential,
    repository: Object.freeze({...repository}), limits: owned,
    chargePage, consumeObservation, consumePage, operations, moon};
  if (managed !== undefined) managed.prefix = prefix;
  const remember = value => {
    if (value !== null && ['object','function'].includes(typeof value)) {
      retainedReads.set(value,prefix);
      managed?.escaped.add(value);
    }
  };
  const invoke = (method,args) => managed === undefined ? Reflect.apply(method,moon,args)
    : Reflect.apply(managed.project,managed.context,[method,moon,args]);
  let prefixFailure;
  const checkPrefix = admitted => {
    if (prefixFailure !== undefined) throw prefixFailure;
    try {
      signal?.throwIfAborted();
      for (const entry of prefix.responses) {
        if (entry === admitted) continue;
        withHttpsCredentialRunResponseOriginal(entry.response, control, journal, facts => {
          if (facts !== entry.facts) fail('GitHubResponseOriginalChanged');
        });
      }
    } catch (cause) {
      prefixFailure = cause; remember(cause); throw cause;
    }
  };
  repository = prefix.repository;
  if (comments) {
    for (const name of ['maxSubjects', 'maxRows', 'maxBytes', 'maxNodes', 'maxDepth']) {
      if (!count(owned[name]) || owned[name] > 2147483647) fail('InvalidGitHubReadLimits');
    }
    if (chargePage !== undefined &&
        (consumeObservation === undefined || consumePage === undefined)) {
      fail('GitHubObservationNotAdmitted');
    }
  }
  let labels;
  if (!comments) {
    const inputLabels = filters.labels ?? [];
    const filterState = filters.state;
    const filterSince = filters.since;
    const states = pullRequests ? ['open', 'closed', 'merged', 'all'] : ['open', 'closed', 'all'];
    if (!states.includes(filterState) ||
        !nativeArrayIsArray(inputLabels) ||
        (filterSince !== undefined && (pullRequests || typeof filterSince !== 'string'))) {
      fail('InvalidGitHubReadFilters');
    }
    const labelCount = inputLabels.length;
    if (!Number.isInteger(labelCount) || labelCount < 0 || labelCount > 0xffffffff) {
      fail('InvalidGitHubReadFilters');
    }
    // Capture each original index once, without caller methods, iterators or
    // species. Validate the owned snapshot that every request will consume.
    labels = [];
    for (let index = 0; index < labelCount; index += 1) {
      defineOwnData(labels, index, {value: inputLabels[index],
        writable: true, enumerable: true, configurable: true});
    }
    for (let index = 0; index < labelCount; index += 1) {
      if (typeof labels[index] !== 'string') fail('InvalidGitHubReadFilters');
    }
    freeze(labels);
    filters = Object.freeze({state: filterState, since: filterSince, labels});
  }
  const headers = JSON.parse(invoke(moon.githubRequestHeadersJson,[]));
  const responseHeaders = JSON.parse(invoke(moon.githubResponseHeadersJson,[]));
  const accepted = [];
  const rows = [];
  const cursors = new Set();
  let after;
  let page = 1;
  let pending = true;
  let requests = 0;
  let lastBasis;
  const stopped = (code, details) => {
    const error = Object.assign(new Error(code), {code, stopped: true,
      acceptedPages: Object.freeze([...accepted]),
      unfetched: pending ? Object.freeze({after, page}) : undefined, ...details});
    remember(error);
    throw error;
  };
  const decoded = value => {
    try { return checked(value); }
    catch (cause) {
      const refusal = JSON.parse(invoke(moon.githubGraphqlReadIssueJson,[cause.cause]));
      stopped(refusalCodes[refusal.kind] ?? 'GitHubGraphQLRefused',
        {refusal, ...(refusal.kind === 'RateLimited' ? {basis: lastBasis} : {})});
    }
  };
  // All physical calls, including child connections, share the original
  // request ceiling, credential grant and current-read callback. No retry.
  const exchange = async body => {
    signal?.throwIfAborted();
    if (requests >= owned.maxPages) stopped('GitHubReadPageLimit');
    if (lastBasis?.remaining === 0) stopped('GitHubRateLimited', {basis: lastBasis});
    let response;
    let charge;
    try {
      const authorization = await authorizationFor(requests);
      checkPrefix();
      signal?.throwIfAborted();
      const expectedUseId = authorization.useId;
      const expectedGrantCid = Reflect.apply(grantIdentity, control, [authorization.grant]);
      requests += 1;
      response = await invokeScopedCredentialOperation({
        authorization, credential: originalCredential, callResource,
        operation: GITHUB_GRAPHQL_READ_OPERATION, method: 'POST',
        path: GITHUB_GRAPHQL_PATH, headers, body,
        responseHeaders, maxRequestBytes: owned.maxRequestBytes,
        maxResponseBytes: owned.maxBytes, signal,
      });
      const entry = {response, body, facts: undefined};
      prefix.responses.push(entry);
      const facts = withHttpsCredentialRunResponseOriginal(response, control, journal, value => {
        const use = Reflect.apply(useProjection, control, [value.use]);
        if (value.response !== response || value.method !== 'POST' ||
            value.path !== GITHUB_GRAPHQL_PATH ||
            value.requestBodyText !== body || value.requestBodyBytes !== Buffer.byteLength(body, 'utf8') ||
            use[0] !== response.useCid || use[1] !== expectedGrantCid ||
            use[2] !== expectedUseId ||
            prefix.responses.slice(0, -1).some(previous => previous.response === response) ||
            (prefix.responses.length > 1 && !invocationBindingsMatch(
              value.scope, prefix.responses[0].facts.scope, control))) {
          fail('GitHubResponseOriginalChanged');
        }
        return value;
      });
      entry.facts = facts;
      Object.freeze(entry);
      if (chargePage !== undefined) {
        // Before accounting, validate earlier responses that could have
        // changed during the physical call. The new body was just admitted.
        checkPrefix(entry);
        charge = await chargePage(response.body);
      }
    } catch (cause) {
      stopped(cause?.code ?? 'GitHubReadInterrupted', {cause});
    }
    const [names, values] = pairs(response.headers);
    lastBasis = JSON.parse(invoke(moon.githubRateLimitBasisJson,[names,values]));
    if (!response.accepted || response.statusCode !== 200) {
      const failure = JSON.parse(invoke(moon.githubClassifyFailureJson,[response.statusCode,names,values]));
      if (failure.kind === 'RateLimited') {
        stopped('GitHubRateLimited', {basis: failure.basis});
      }
      stopped('GitHubReadRejected', {failure});
    }
    return {response, charge};
  };
  try {
    if (comments) {
      const original = decoded(invoke(operations.begin,[repository.nodeId,
        repository.databaseId, repository.nameWithOwner, owned.maxBytes,
        owned.maxNodes, owned.maxDepth, owned.maxRows, owned.maxPages, owned.maxSubjects]));
      prefix.pages.push(original);
      try {
        for (;;) {
          const next = JSON.parse(decoded(invoke(operations.next,[original, owned.perPage])));
          if (next.body === null) { pending = false; break; }
          const {response, charge} = await exchange(next.body);
          // Fulfillment can run external microtasks before this continuation.
          // Check here, before any codec or consumer can observe changed bytes.
          try { checkPrefix(); }
          catch (cause) { stopped(cause?.code ?? 'GitHubReadInterrupted', {cause}); }
          decoded(invoke(operations.accept,[original, response.body]));
          const current = JSON.parse(decoded(invoke(operations.finish,[original]))).page;
          if (current === null) {
            if (consumeObservation !== undefined) {
              try {
                // The prefix was checked after exchange; the intervening
                // selected codec getters are synchronous and byte-only.
                await consumeObservation(charge);
                checkPrefix();
              } catch (cause) {
                stopped(cause?.code ?? 'GitHubObservationNotAdmitted', {cause});
              }
            }
          } else {
            if (rows.length + current.rows.length > owned.maxRows) stopped('GitHubReadRowLimit');
            if (consumePage !== undefined) {
              try {
                await consumePage(current.rows, page, Object.freeze({charge}));
                checkPrefix();
              } catch (cause) {
                stopped(cause?.code ?? 'GitHubPageNotAdmitted', {cause});
              }
            }
            rows.push(...current.rows);
            accepted.push(Object.freeze({page, useCid: response.useCid, rows: current.rows.length}));
            page += 1;
          }
        }
      } finally {
        // Managed decoder originals stay with this SAME Reader's retirement
        // duty. A stopped read-current fence must not replace the primary.
        if (managed === undefined) invoke(operations.close,[original]);
      }
    } else while (pending) {
      signal?.throwIfAborted();
      const arguments_ = [repository.nodeId, owned.perPage, after !== undefined,
        after ?? '', filters.state, labels];
      if (!pullRequests) arguments_.push(filters.since !== undefined, filters.since ?? '');
      const request = JSON.parse(invoke(operations.request,arguments_));
      if (request.refused) stopped('InvalidGitHubReadRequest',
        {refusal: request.refused});
      const {response, charge} = await exchange(request.body);
      try { checkPrefix(); }
      catch (cause) { stopped(cause?.code ?? 'GitHubReadInterrupted', {cause}); }
      const original = decoded(invoke(operations.begin,[response.body,
        owned.maxBytes, owned.maxNodes, owned.maxDepth, owned.perPage,
        owned.maxPages - requests + 1, repository.nodeId, repository.databaseId, repository.nameWithOwner]));
      prefix.pages.push(original);
      let current;
      let rowCharge = charge;
      try {
        for (;;) {
          const next = JSON.parse(decoded(invoke(operations.next,[original, owned.perPage])));
          if (next.body === null) break;
          // An accounted child body has its own admission ticket. Never hide it
          // as another row page or accept it without the original observation port.
          if (chargePage !== undefined && consumeObservation === undefined) {
            stopped('GitHubObservationNotAdmitted');
          }
          // The original RowRun allows one unconsumed physical-response ticket.
          // Consume each prefix as an observation before the next receive, while
          // the opaque decoder retains its original incomplete row graph. Exactly
          // the last actual ticket accompanies the completed logical page.
          if (consumeObservation !== undefined) {
            try {
              await consumeObservation(rowCharge);
              checkPrefix();
            }
            catch (cause) {
              stopped(cause?.code ?? 'GitHubObservationNotAdmitted', {cause});
            }
          }
          rowCharge = undefined;
          const child = await exchange(next.body);
          try { checkPrefix(); }
          catch (cause) { stopped(cause?.code ?? 'GitHubReadInterrupted', {cause}); }
          rowCharge = child.charge;
          decoded(invoke(operations.accept,[original, child.response.body]));
        }
        current = JSON.parse(decoded(invoke(operations.finish,[original])));
      } finally {
        // The managed cleanup owner closes this same original after stop;
        // ordinary read projection is deliberately unavailable then.
        if (managed === undefined) invoke(operations.close,[original]);
      }
      if (rows.length + current.rows.length > owned.maxRows) {
        stopped('GitHubReadRowLimit');
      }
      if (consumePage !== undefined) {
        try {
          // Finish/close only retire the selected codec's DATA aliases. The
          // preceding exchange or consumer check governs this callback entry.
          await consumePage(current.rows, page, Object.freeze({charge: rowCharge}));
          checkPrefix();
        }
        catch (cause) {
          stopped(cause?.code ?? 'GitHubPageNotAdmitted', {cause});
        }
      }
      rows.push(...current.rows);
      accepted.push(Object.freeze({page, useCid: response.useCid,
        rows: current.rows.length}));
      if (!current.hasNextPage) {
        pending = false;
        break;
      }
      // A cursor seen before (including the one just sent) never advances the
      // read: the provider would return a page already accepted.
      if (current.endCursor === after || cursors.has(current.endCursor)) {
        stopped('GitHubCursorCycle');
      }
      cursors.add(current.endCursor);
      after = current.endCursor;
      page += 1;
      // An accepted page with no remaining quota is kept; the read stops
      // before the next request instead of spending one it cannot make.
      if (lastBasis.remaining === 0) stopped('GitHubRateLimited', {basis: lastBasis});
    }
    // No uncontrolled callback or await follows the last original-prefix
    // check (including the post-consumer check). Publishing these frozen DATA
    // arrays does not require another hash of the same response bytes.
    const result = Object.freeze({rows: Object.freeze(rows),
      pages: Object.freeze(accepted), complete: true});
    remember(result);
    return result;
  } catch (cause) {
    remember(cause);
    throw cause;
  }
}

// The normal Source keeps its existing native protocol inside the SAME bound
// Reader. This constructor prepares original facts only; no credential call,
// parser, request issuer or replacement resource owner runs here.
export function prepareGitHubSourceReadSequence(options) {
  let {moon,site,repository,preparedRead,originalAuthorization,limits,responseCapacity,retireProjection}=options;
  options=undefined;
  let resource=preparedRead?.resource,nonce=preparedRead?.nonce;
  const comments=resource==='issue_comments',pullRequests=resource==='pull_requests';
  if (!['issues','pull_requests','issue_comments'].includes(resource) ||
      typeof nonce!=='string'||!nonce||typeof responseCapacity!=='function'||
      typeof retireProjection!=='function'||types.isProxy(retireProjection)) fail('InvalidGitHubSourceRead');
  let grant=originalAuthorization?.grant,scope=originalAuthorization?.scope;
  if (grant===undefined||scope?.operation!==GITHUB_GRAPHQL_READ_OPERATION ||
      scope.runInvocationCid!==preparedRead.runInvocationCid ||
      scope.dispatchRequestCid!==preparedRead.dispatchRequestCid) fail('ForeignGitHubSourceRead');
  let credential=site.credential,managed={prefix:undefined,escaped:new Set(),context:undefined,project:undefined};
  let pending=false,started=false,retired=false,largest=0,responses=0,capacity;
  const sequence=Object.freeze({
    responseCapacity(bytes) {
      if(this!==sequence||!pending||retired||!Number.isSafeInteger(bytes)||bytes<0||bytes>limits.maxBytes||responses>=limits.maxPages)
        fail('InvalidGitHubSourceResponseExtent');
      // Every original response remains in this reader's prefix, including
      // equal-sized pages. Quote it before decoding, together with the next
      // request; a peak byte size alone cannot describe the held prefix.
      largest=Math.max(largest,bytes);responses++;
      capacity=responseCapacity(largest,responses);
      return capacity;
    },
    async read(context,initialAuthorization) {
      if(this!==sequence||started||retired)fail('GitHubSourceReadAlreadyStarted');
      started=true;pending=true;
      try {
        if(initialAuthorization?.grant!==grant||initialAuthorization.scope!==scope ||
            initialAuthorization.useId!==`${nonce}-read-0`)fail('ForeignGitHubSourceRead');
        managed.context=context;managed.project=githubReadMethod(context,'project');
        const consumePage=githubReadMethod(context,'consumePage');
        const consumeObservation=githubReadMethod(context,'consumeObservation');
        await readGitHubRowsByNode({moon,repository,filters:{state:'all',labels:[]},credential,
          limits,signal:preparedRead.signal,
          authorizationFor:index=>Object.freeze({...initialAuthorization,useId:`${nonce}-read-${index}`}),
          callResource:input=>readGitHubSourceChild(context,originalAuthorization,input),
          // The bound Reader already charges the actual response exactly once.
          // The existing codec still decides whether it is an observation or
          // a complete row page; no original ticket is synthesized here.
          consumeObservation:()=>Reflect.apply(consumeObservation,context,[]),
          consumePage:rows=>Reflect.apply(consumePage,context,[rows]),
        },pullRequests,comments,managed);
      } finally {pending=false;}
    },
    retire() {
      if(this!==sequence)fail('ForeignGitHubSourceRead');
      if(pending)return false;
      if(retired)return true;
      const prefix=managed.prefix;
      if(prefix!==undefined){
        // This is the original constructor-supplied synchronous projector,
        // not context.project's read-current fence. Its existing borrower
        // retains invalid async results; a failure leaves this SAME page for
        // cleanup retry. No new registry, issuer or physical ACK is created.
        while(prefix.pages.length!==0){
          const original=prefix.pages[prefix.pages.length-1];
          const result=Reflect.apply(retireProjection,undefined,[prefix.operations.close,prefix.moon,[original]]);
          if(result!==undefined)fail('InvalidGitHubDecoderRetirement');
          prefix.pages.pop();
        }
        prefix.responses.length=0;
        for(const name of Object.keys(prefix))prefix[name]=undefined;
      }
      for(const value of managed.escaped)if(retainedReads.get(value)===prefix)retainedReads.delete(value);
      managed.escaped.clear();managed.context=managed.project=managed.prefix=undefined;
      moon=site=repository=preparedRead=originalAuthorization=limits=responseCapacity=retireProjection=credential=capacity=undefined;
      grant=scope=resource=nonce=undefined;
      managed=undefined;retired=true;
      return true;
    },
  });
  return sequence;
}

// Same Site grant, scope and immutable native operation request. The original
// invocation packet itself is the occurrence key; labels/counters are not a
// substitute for the bound Reader's checked child authorization.
function readGitHubSourceChild(context,originalAuthorization,input) {
  const grant=githubReadField(originalAuthorization,'grant'),scope=githubReadField(originalAuthorization,'scope');
  const supplied=githubReadField(input,'scope');
  if(githubReadField(input,'grant')!==grant||supplied===null||typeof supplied!=='object'||types.isProxy(supplied) ||
      Reflect.ownKeys(supplied).length!==Reflect.ownKeys(scope).length ||
      Reflect.ownKeys(scope).some(name=>githubReadField(supplied,name)!==githubReadField(scope,name)))fail('ForeignGitHubSourceReadChild');
  const operations=githubReadField(input,'operations');
  if(!(operations instanceof Map)||types.isProxy(operations)||operations.size!==1||!operations.has(GITHUB_GRAPHQL_READ_OPERATION))
    fail('InvalidGitHubSourceReadChild');
  const request=operations.get(GITHUB_GRAPHQL_READ_OPERATION);
  if(githubReadField(request,'method')!=='POST'||githubReadField(request,'path')!==GITHUB_GRAPHQL_PATH||
      typeof githubReadField(request,'body')!=='string' ||
      Object.hasOwn(request,'bodyBytes'))fail('InvalidGitHubSourceReadChild');
  const authorization=Object.freeze({grant,scope,useId:githubReadField(input,'useId')});
  return Reflect.apply(githubReadMethod(context,'readChild'),context,[{operation:GITHUB_GRAPHQL_READ_OPERATION,prepare(){
    return Object.freeze({original:input,originalAuthorization,authorization,request,project:response=>response});
  }}]);
}

function githubReadField(value,name) {
  if(value===null||typeof value!=='object'||types.isProxy(value))fail('InvalidGitHubSourceRead');
  const field=Object.getOwnPropertyDescriptor(value,name);
  if(!field||!Object.hasOwn(field,'value'))fail('InvalidGitHubSourceRead');
  return field.value;
}
function githubReadMethod(value,name) {
  const method=githubReadField(value,name);
  if(typeof method!=='function'||types.isProxy(method))fail('InvalidGitHubSourceRead');
  return method;
}
