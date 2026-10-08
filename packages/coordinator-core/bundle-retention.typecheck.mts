import {bundleRetention, type BundleDistribution, type BundleHoldScope,
  type BundleHoldBinding, type BundleCustodyRequest, type BundleCustodyResponse,
  type BundleCustodyOperation, type BundleCustodyObservation,
  type BundleHoldScopeInput} from '@actql/coordinator-core';

const members: readonly string[] = ['sha256:bundle'];
const distribution: BundleDistribution = bundleRetention.prepareDistribution(members);
const input: Readonly<BundleHoldScopeInput> = {distribution,
  coordinatorAuthority: 'coordinator-a', workspaceId: 'workspace-a',
  authorityScopeCid: 'sha256:scope', environment: 'production',
  setRevisionCid: 'sha256:set', runtimeBundleCid: 'sha256:bundle',
  siteKey: 'site-a', siteGeneration: 7, attemptId: 'hold-a'};
const scope: BundleHoldScope = bundleRetention.prepareHoldScope(input);
const context: BundleCustodyRequest = bundleRetention.prepareCustodyContextQuery(distribution, scope);
const response: BundleCustodyResponse = bundleRetention.admitCustodyResponseJson(context, '', '');
const binding: BundleHoldBinding = bundleRetention.custodyResponseBinding(response);
const restored: BundleHoldBinding = bundleRetention.admitHoldBindingJson(distribution,
  bundleRetention.holdBindingJson(binding), bundleRetention.holdBindingIdentity(binding));
const request: BundleCustodyRequest = bundleRetention.prepareCustodyRequest(distribution, restored, 'retain');
const operation: BundleCustodyOperation = bundleRetention.custodyRequestOperation(request);
const observation: BundleCustodyObservation | '' = bundleRetention.custodyResponseObservation(response);
const optionalBinding: BundleHoldBinding | undefined = bundleRetention.custodyRequestBinding(context);
const optionalCatalog: string | undefined = bundleRetention.custodyResponseCatalog(response);
const optionalRevision: number | undefined = bundleRetention.custodyResponseRevision(response);
void [operation, observation, optionalBinding, optionalCatalog, optionalRevision];

// @ts-expect-error Only the owner can construct an opaque distribution.
const forgedDistribution: BundleDistribution = {};
// @ts-expect-error Scope and binding are different opaque owner values.
const forgedBinding: BundleHoldBinding = scope;
// @ts-expect-error Request and response are different opaque owner values.
const forgedResponse: BundleCustodyResponse = request;
// @ts-expect-error A scope does not carry the returned original binding.
bundleRetention.prepareCustodyRequest(distribution, scope, 'retain');
// @ts-expect-error The portable client exposes no installation verb.
bundleRetention.prepareCustodyRequest(distribution, binding, 'install');
// @ts-expect-error Response admission requires its original request.
bundleRetention.admitCustodyResponseJson(binding, '', '');
// @ts-expect-error The public namespace is frozen.
bundleRetention.prepareDistribution = () => distribution;
// @ts-expect-error The client cannot mutate the physical Store.
bundleRetention.prepareHoldRetain({});
void [forgedDistribution, forgedBinding, forgedResponse];
