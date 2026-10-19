import {installedSlackChannelsFixture} from './installed-slack-channels.fixture.mjs';

export async function installedSlackMessagesFixture(t,{account='allow',resource='messages'}={}){
  const f=await installedSlackChannelsFixture(t,{account,resource});
  // Eight actual exchanges: identity/list, then identity/history/replies for
  // each selected conversation. This explicit component bound is not normal
  // physical funding or proof of escaped raw/callback retirement.
  f.profile.limits={...f.profile.limits,maxPages:8};
  f.state.conversations=[{id:'C1',is_im:false,is_mpim:false},{id:'D1',is_im:true,is_mpim:false}];
  f.state.messages={C1:[{type:'message',ts:'1.000001',text:'parent',reply_count:1}],
    D1:[{type:'message',ts:'3.000000001',text:'direct'}]};
  f.state.replies={C1:[{type:'message',ts:'1.000001',thread_ts:'1.000001',text:'parent',reply_count:1},
    {type:'message',ts:'2.000001',thread_ts:'1.000001',text:'child'}],
  D1:[{type:'message',ts:'3.000000001',text:'direct'}]};
  f.state.beforeResponse=async(request,response)=>{
    const url=new URL(request.url,f.scope.resourceOrigin);let body;
    if(url.pathname==='/api/conversations.list')body={ok:true,channels:f.state.conversations,response_metadata:{next_cursor:null}};
    if(url.pathname==='/api/conversations.history')body={ok:true,messages:f.state.messages[url.searchParams.get('channel')],
      has_more:false,response_metadata:{next_cursor:null}};
    if(url.pathname==='/api/conversations.replies')body={ok:true,messages:f.state.replies[url.searchParams.get('channel')],
      has_more:false,response_metadata:{next_cursor:null}};
    if(body!==undefined){response.writeHead(200,{'content-type':'application/json'});response.end(JSON.stringify(body));}
    await f.state.afterResponse?.(request,response);
  };
  return f;
}

