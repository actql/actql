// Shared physical review peer for the existing Native fixtures. Transport
// acknowledgments here are not Cloud commits, approval or Provider authority.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {nativeEffectCheckpointReplyFixture} from './native-effect-checkpoint-server.mjs';
import {nativeResolutionFixture} from './native-effect-resolution-fixture.mjs';

export function nativeEffectReviewFixture(authorization) {
  let resolutionRequests = 0;
  let reviewUploads = 0;
  let checkpointReportRequests = 0;
  let checkpointReportWire;
  const reviewUploadBodies = [];
  const handle = (request, response) => {
  if (request.method === 'POST' && request.url === '/fixture/effect-review-report') {
    if (request.headers.authorization !== authorization ||
        request.headers['content-type'] !== 'application/json') {
      response.writeHead(403); response.end(); return true;
    }
    const chunks=[]; let bytes=0;
    request.on('data',chunk=>{bytes+=chunk.length;if(bytes>65536)request.destroy();else chunks.push(chunk);});
    request.on('end',()=>{
      try {
        const wire=Buffer.concat(chunks).toString('utf8');
        checkpointReportWire ??= wire;
        if(wire!==checkpointReportWire){response.writeHead(409);response.end();return;}
        const reply=nativeEffectCheckpointReplyFixture(wire);
        checkpointReportRequests++;
        // Bare HTTP success cannot discharge the journal's report custody.
        // The next explicit retry obtains a fixture typed receipt, not a
        // production Cloud Owner commit or Effect approval.
        response.writeHead(200,{'content-type':'application/json'});
        response.end(checkpointReportRequests===1?'{}':reply);
      } catch {response.writeHead(422);response.end();}
    });
    return true;
  }
  if (request.method === 'POST' && request.url === '/fixture/effect-review') {
    if (request.headers.authorization !== authorization ||
        request.headers['content-type'] !== 'application/json' ||
        !/^sha256:[a-f0-9]{64}$/.test(request.headers['actql-dispatch-cid'] ?? '')) {
      response.writeHead(403); response.end(); return true;
    }
    const chunks=[]; let bytes=0;
    request.on('data',chunk=>{bytes+=chunk.length;if(bytes>65536)request.destroy();else chunks.push(chunk);});
    request.on('end',()=>{
      assert.equal(checkpointReportRequests,2,'Artifact upload preceded the original typed report receipt');
      const body=Buffer.concat(chunks).toString('utf8');
      reviewUploadBodies.push({dispatchCid:request.headers['actql-dispatch-cid'],
        byteLength:bytes,bodySha256:createHash('sha256').update(Buffer.concat(chunks)).digest('hex')});
      reviewUploads++;
      // First response is uncertain from the Site's perspective. The caller
      // retries its same owned bytes; no approval/report ACK is synthesized.
      response.writeHead(reviewUploads===1?503:204); response.end();
    });
    return true;
  }
  if (request.method === 'POST' && request.url === '/fixture/effect-resolution') {
    if (request.headers.authorization !== authorization) {
      response.writeHead(403); response.end(); return true;
    }
    const chunks=[];let bytes=0;
    request.on('data',chunk=>{bytes+=chunk.length;if(bytes>262144)request.destroy();else chunks.push(chunk);});
    request.on('end',()=>{
      try {
        const fixture=nativeResolutionFixture(Buffer.concat(chunks).toString('utf8'));
        resolutionRequests++;
        response.writeHead(200,{'content-type':'application/json'});
        response.end(JSON.stringify(fixture));
      } catch {response.writeHead(422);response.end();}
    });
    return true;
  }
    return false;
  };
  return Object.freeze({handle, facts: () => ({resolutionRequests, reviewUploads,
    checkpointReportRequests, checkpointReportWire, reviewUploadBodies})});
}
