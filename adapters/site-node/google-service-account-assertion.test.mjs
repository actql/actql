import assert from 'node:assert/strict';
import {generateKeyPairSync, createPublicKey, verify, constants} from 'node:crypto';
import test from 'node:test';
import {prepareGoogleServiceAccountAssertion, googleServiceAccountAssertionRequest} from './google-service-account-assertion.mjs';

const {privateKey, publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
const limits=Object.freeze({maxScopes:4,maxScopeBytes:512,maxIdentityBytes:256,
  maxClaimBytes:2048,maxAssertionBytes:4096,maxRequestBytes:8192,maxKeyBits:4096});
const base=()=>({privateKey,clientEmail:'reader@fixture.iam.gserviceaccount.com',privateKeyId:'key-original',
  scopes:['https://www.googleapis.com/auth/calendar.readonly','https://mail.google.com/'],
  delegate:'ops@fixture.invalid',issuedAtUnixSeconds:1700000000,lifetimeSeconds:3600,limits});
const split=request=>{
  const assertion=new URLSearchParams(request.body).get('assertion');
  const [header,claims,signature]=assertion.split('.');
  return {header:JSON.parse(Buffer.from(header,'base64url')),claims:JSON.parse(Buffer.from(claims,'base64url')),
    signature:Buffer.from(signature,'base64url'),message:Buffer.from(`${header}.${claims}`),assertion};
};

test('Google assertion signs exact declared issuer subject scopes endpoint and expiry with native RS256',()=>{
  const original=prepareGoogleServiceAccountAssertion(base());const request=googleServiceAccountAssertionRequest(original);
  assert.equal(request.url,'https://oauth2.googleapis.com/token');assert.equal(request.method,'POST');
  assert.deepEqual(request.headers,[['content-type','application/x-www-form-urlencoded']]);
  assert.equal(new URLSearchParams(request.body).get('grant_type'),'urn:ietf:params:oauth:grant-type:jwt-bearer');
  assert.equal(request.requestBytes,Buffer.byteLength(request.body));assert.equal(request.issuedAtUnixSeconds,1700000000);
  assert.equal(request.expiresAtUnixSeconds,1700003600);
  const jwt=split(request);
  assert.deepEqual(jwt.header,{alg:'RS256',typ:'JWT',kid:'key-original'});
  assert.deepEqual(jwt.claims,{iss:'reader@fixture.iam.gserviceaccount.com',
    scope:'https://www.googleapis.com/auth/calendar.readonly https://mail.google.com/',
    aud:'https://oauth2.googleapis.com/token',exp:1700003600,iat:1700000000,sub:'ops@fixture.invalid'});
  assert(verify('sha256',jwt.message,{key:publicKey,padding:constants.RSA_PKCS1_PADDING},jwt.signature));
  const foreign=generateKeyPairSync('rsa',{modulusLength:2048}).publicKey;
  assert.equal(verify('sha256',jwt.message,{key:foreign,padding:constants.RSA_PKCS1_PADDING},jwt.signature),false);
  assert.equal(verify('sha256',Buffer.from(`${jwt.message}x`),{key:publicKey,padding:constants.RSA_PKCS1_PADDING},jwt.signature),false);
  assert.equal(Object.keys(original).length,0);assert.equal(JSON.stringify(original),'{}');
  assert(Object.isFrozen(original));assert(Object.isFrozen(request));
});

test('Google assertion optional key ID and delegate remain absent instead of synthesized null or default',()=>{
  const input=base();delete input.privateKeyId;delete input.delegate;
  const jwt=split(googleServiceAccountAssertionRequest(prepareGoogleServiceAccountAssertion(input)));
  assert.deepEqual(jwt.header,{alg:'RS256',typ:'JWT'});assert.equal(Object.hasOwn(jwt.claims,'sub'),false);
  assert.equal(Object.hasOwn(jwt.claims,'kid'),false);
});

test('Google assertion preserves original scope order and immutable prepared request after caller mutation',()=>{
  const input=base();const prepared=prepareGoogleServiceAccountAssertion(input);
  const request=googleServiceAccountAssertionRequest(prepared);input.scopes.reverse();input.delegate='changed@fixture.invalid';
  input.clientEmail='foreign@fixture.invalid';input.issuedAtUnixSeconds++;
  assert.deepEqual(googleServiceAccountAssertionRequest(prepared),request);
  const reversed=base();reversed.scopes.reverse();
  assert.equal(split(googleServiceAccountAssertionRequest(prepareGoogleServiceAccountAssertion(reversed))).claims.scope,
    'https://mail.google.com/ https://www.googleapis.com/auth/calendar.readonly');
});

test('Google assertion refuses copied serialized or foreign preparation instead of matching body values',()=>{
  const prepared=prepareGoogleServiceAccountAssertion(base());const body=googleServiceAccountAssertionRequest(prepared).body;
  for(const foreign of [{...prepared},JSON.parse(JSON.stringify(prepared)),Object.create(prepared),{body},null,undefined]){
    assert.throws(()=>googleServiceAccountAssertionRequest(foreign),{code:'ForeignGoogleAssertionPreparation'});
  }
});

test('Google assertion requires the native original RSA private key and honors caller key bound',()=>{
  const ec=generateKeyPairSync('ed25519').privateKey;
  const pss=generateKeyPairSync('rsa-pss',{modulusLength:2048}).privateKey;
  for(const key of [createPublicKey(privateKey),ec,pss,{},new Proxy(privateKey,{}),'fixture-private-text']){
    assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),privateKey:key}),{code:'InvalidGoogleAssertionKey'});
  }
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:{...limits,maxKeyBits:1024}}),{code:'InvalidGoogleAssertionKey'});
});

test('Google assertion does not accept alternate audience algorithm endpoint or undeclared option',()=>{
  for(const extra of [{aud:'https://foreign.invalid/token'},{alg:'none'},{tokenUri:'https://foreign.invalid/token'},
    {expiresAtUnixSeconds:1700004000},{unknown:true}]){
    assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),...extra}),{code:'InvalidGoogleAssertionPreparation'});
  }
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:{...limits,unknown:1}}),{code:'InvalidGoogleAssertionLimits'});
});

test('Google assertion rejects malformed original identities without replacement or inferred delegation',()=>{
  for(const input of [{clientEmail:''},{clientEmail:'not-email'},{clientEmail:'x\ny@fixture.invalid'},
    {clientEmail:'a\ud800@fixture.invalid'},{privateKeyId:null},{privateKeyId:''},{delegate:null},{delegate:''},{delegate:'missing-at'}]){
    assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),...input}),{code:'InvalidGoogleAssertionIdentity'});
  }
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:{...limits,maxIdentityBytes:2}}),{code:'InvalidGoogleAssertionIdentity'});
});

test('Google assertion checks explicit seconds and one-hour protocol maximum with no clock rounding',()=>{
  for(const input of [{issuedAtUnixSeconds:-1},{issuedAtUnixSeconds:1.5},{issuedAtUnixSeconds:NaN},
    {issuedAtUnixSeconds:undefined},{issuedAtUnixSeconds:Number.MAX_SAFE_INTEGER},{lifetimeSeconds:0},
    {lifetimeSeconds:3601},{lifetimeSeconds:1.5},{lifetimeSeconds:undefined}]){
    assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),...input}),{code:'InvalidGoogleAssertionLifetime'});
  }
  const request=googleServiceAccountAssertionRequest(prepareGoogleServiceAccountAssertion({...base(),lifetimeSeconds:1}));
  assert.equal(request.expiresAtUnixSeconds,1700000001);
});

test('Google assertion scopes are exact explicit tokens with duplicate count and total-byte bounds',()=>{
  for(const scopes of [[],[''],['read write'],['a','a'],[null],['bad"scope'],['bad\\scope']]){
    assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),scopes}),{code:'InvalidGoogleAssertionScopes'});
  }
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:{...limits,maxScopes:1}}),{code:'InvalidGoogleAssertionScopes'});
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:{...limits,maxScopeBytes:10}}),{code:'GoogleAssertionScopeLimit'});
});

test('Google assertion separately bounds original claims signed assertion and complete form request',()=>{
  for(const [key,code] of [['maxClaimBytes','GoogleAssertionClaimLimit'],['maxAssertionBytes','GoogleAssertionSizeLimit'],
    ['maxRequestBytes','GoogleAssertionRequestLimit']]){
    assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:{...limits,[key]:10}}),{code});
  }
  for(const key of Object.keys(limits))for(const invalid of [undefined,null,0,-1,1.5,2147483648]){
    assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:{...limits,[key]:invalid}}),{code:'InvalidGoogleAssertionLimits'});
  }
});

test('Google assertion snapshots original option scope and limit getters once without parser or I/O callbacks',()=>{
  const input=base();const counts=new Map(),options={},bound={};
  for(const [key,value] of Object.entries(limits))Object.defineProperty(bound,key,{enumerable:true,get(){counts.set(key,(counts.get(key)??0)+1);return value;}});
  for(const [key,value] of Object.entries({...input,limits:bound}))Object.defineProperty(options,key,{enumerable:true,get(){counts.set(key,(counts.get(key)??0)+1);return value;}});
  const value=prepareGoogleServiceAccountAssertion(options);assert.equal(split(googleServiceAccountAssertionRequest(value)).claims.sub,'ops@fixture.invalid');
  for(const [key,count] of counts)assert.equal(count,1,key);
});

test('Google assertion never acquires delegation or key ID from an inherited optional property',()=>{
  const own=base();delete own.delegate;delete own.privateKeyId;
  const input=Object.assign(Object.create({delegate:'foreign@fixture.invalid',privateKeyId:'foreign-key'}),own);
  const jwt=split(googleServiceAccountAssertionRequest(prepareGoogleServiceAccountAssertion(input)));
  assert.equal(Object.hasOwn(jwt.claims,'sub'),false);assert.equal(Object.hasOwn(jwt.header,'kid'),false);
});

test('Google assertion requires own original required materials and all explicit limit properties',()=>{
  assert.throws(()=>prepareGoogleServiceAccountAssertion(Object.create(base())),{code:'InvalidGoogleAssertionPreparation'});
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:Object.create(limits)}),{code:'InvalidGoogleAssertionLimits'});
});

test('Google assertion rejects Proxy key options limits and scopes before invoking any trap',()=>{
  let calls=0;const traps={get(){calls++;throw new Error('untrusted get');},
    ownKeys(){calls++;throw new Error('untrusted keys');},getOwnPropertyDescriptor(){calls++;throw new Error('untrusted descriptor');}};
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),privateKey:new Proxy(privateKey,traps)}),{code:'InvalidGoogleAssertionKey'});
  assert.throws(()=>prepareGoogleServiceAccountAssertion(new Proxy(base(),traps)),{code:'InvalidGoogleAssertionPreparation'});
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),limits:new Proxy(limits,traps)}),{code:'InvalidGoogleAssertionLimits'});
  assert.throws(()=>prepareGoogleServiceAccountAssertion({...base(),scopes:new Proxy(base().scopes,traps)}),{code:'InvalidGoogleAssertionScopes'});
  assert.equal(calls,0);
});
