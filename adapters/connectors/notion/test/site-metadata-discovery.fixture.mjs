// Actual existing installation Site issuer/Account/Common/SQLite and local TLS.
// The trusted installation/profile/key are explicit fixture originals. Response
// tickets remain doubles, not a preparation lifetime/egress/funding supplier.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {openRowSourceCredentialSite} from '../../../host-node/installed-row-source.mjs';
import {prepareNotionDatabaseMetadataTargets} from '../host/database-metadata-targets.mjs';
import {createNotionDatabaseDiscovery,NOTION_DATABASE_RETRIEVE_OPERATION as databaseOperation,
  NOTION_DATA_SOURCE_RETRIEVE_OPERATION as sourceOperation} from '../site/database-discovery.mjs';
import {metadataDiscoveryFixture,metadataDiscoveryLimits} from './installation-metadata-discovery.fixture.mjs';

export function siteMetadataDiscoveryFixture(t){
  return metadataDiscoveryFixture(t,{async publication(f,callback){
    const {root,state,profile,options,declaration,provider,origin,gate,resolveSecret,cert}=f;
    const targets=prepareNotionDatabaseMetadataTargets({moon:provider,declaration,origin,
      resource:'database:db',maxTargetBytes:metadataDiscoveryLimits.maxTargetBytes,maxResourceBytes:128});
    const siteProfile=Object.freeze({credentialPrivateKeyPath:join(root,'issuer-private.pem'),
      credentialAuthorityId:'notion-metadata-fixture',credentialKeyId:'key',journalRoot:join(root,'actual-site-journal'),
      resourceOrigin:origin,namespaceId:'original-notion-metadata',environment:'fixture',
      siteKey:'original-notion-site',siteGeneration:1});
    const sitePath=join(root,'actual-site.json'),siteWire=JSON.stringify(siteProfile);
    await writeFile(sitePath,siteWire,{mode:0o600});
    const siteCurrent=Object.freeze({async observe(){
      assert.equal(this,siteCurrent);assert.equal(await readFile(sitePath,'utf8'),siteWire);
    },assertCurrent(){assert.equal(this,siteCurrent);assert.equal(state.active,true);}});
    const site=await openRowSourceCredentialSite({profile:siteProfile,principalId:options.principalId,
      authorization:gate,connection:'notion:fixture',connectorRegistration:options.installation.registration,
      connectorRevision:options.installation.revision,runtimeBundleCid:options.runtimeBundleCid,
      commonMoon:options.moon,resolveSecret,ca:cert,grantLifetimeMs:120000,
      installationMetadata:{publicationRequest:options.publicationRequest,originals:{...options,profile},
        declaration,declarationSourceCid:provider.notionReadDatabaseDeclarationSourceCid(declaration),
        operations:[databaseOperation,sourceOperation],maxOperations:2,maxSecretBytes:128,
        maxIssuerKeyBytes:4096,maxCaBytes:4096,targetAuthority:targets.targetAuthority,siteCurrent}});
    t.after(()=>site.close());
    try{
      const request=target=>({target,metadataOccurrenceId:target===declaration?'database':'schema',
        useId:target===declaration?'original-database-use':'original-schema-use',
        expiresUnixMilliseconds:BigInt(Date.now()+60000),maxUses:1});
      const initial=await site.issueMetadataGrant(request(targets.databaseTarget));
      const credential=site.credential();f.journal=credential.journal;
      const current=async operation=>{
        await site.current(operation);state.current++;
        await state.onCurrent?.(operation,state.current);await site.current(operation);
      };
      const readerOptions={moon:provider,declaration,initialAuthorization:initial,credential,
        authorizationFor:({operation,index})=>{assert.equal(operation,databaseOperation);assert.equal(index,0);return initial;},
        sourceAuthorizationFor:async selected=>{
          const target=targets.selectSource(selected);
          await state.onSchema?.(selected);
          return site.issueMetadataGrant(request(target));
        },current,
        chargeResponse:body=>{const charge=Object.freeze({originalBody:body});state.charges.push(charge);return charge;},
        consumeObservation:charge=>{assert(state.charges.includes(charge));assert(!state.observations.includes(charge));state.observations.push(charge);},
        limits:metadataDiscoveryLimits,systemColumns:true,
        publication:{request:options.publicationRequest,originals:{...options,profile}}};
      return await callback({...f,site,sitePath,control:credential.control,
        journal:credential.journal,options:readerOptions,
        reader:changes=>createNotionDatabaseDiscovery({...readerOptions,...changes})});
    }finally{site.close();}
  }});
}
