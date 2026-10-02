// Local integration fixture only. Never imported by the application or production service.
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { createHash, X509Certificate } from 'node:crypto'
import { Repository } from '../../server/storage.mjs'
import { hash, acceptQuote, placeOrder, processOrders } from '../../server/domain.mjs'
import { addNews, evaluateNews } from '../../server/analysis.mjs'
import { handler } from '../../server/http.mjs'
if(process.env.BORSA_TEST_FIXTURE!=='1')throw new Error('This entry point is for isolated integration tests only.')
const directory=process.argv[2],repo=new Repository(join(directory,'fixture.sqlite')),now=Date.now()-5000
repo.update(s=>{
  const q={symbol:'AAPL',currency:'USD',source:'TEST FIXTURE ONLY',priceUnits:1_000_000,bidUnits:1_000_000,askUnits:1_000_000,bidSize:10,askSize:10,previousCloseUnits:990_000,timestamp:now,sessionOpen:true,quality:'realtime',delaySeconds:0}
  acceptQuote(s,q,now)
  placeOrder(s,{id:'fixture-order-0000001',symbol:'AAPL',side:'buy',quantity:2,limitUnits:1_010_000},now)
  acceptQuote(s,{...q,timestamp:now+1000},now+1000);processOrders(s,now+1000)
  addNews(s,[{id:'fixture-news',title:'Apple raises guidance',summary:'Test fixture only.',source:'TEST FIXTURE ONLY',url:'https://example.test/news',symbols:['AAPL'],market:'US',scope:'company',sourceTier:'licensed',publishedAt:now+2000}],now+2000)
  evaluateNews(s,now+2000);s.lastCycleAt=now+2000
})
const pairingPath=join(directory,'pairing.json')
writeFileSync(pairingPath,JSON.stringify({digest:hash('654321'),expiresAt:Date.now()+180000}))
const app=handler(repo,{pairingPath})
const server=Bun.serve({hostname:'127.0.0.1',port:0,tls:{cert:Bun.file(join(directory,'cert.pem')),key:Bun.file(join(directory,'key.pem'))},fetch:request=>{
  if(new URL(request.url).pathname==='/redirect')return new Response(null,{status:302,headers:{Location:'/health'}})
  return app(request)
}})
const cert=new X509Certificate(readFileSync(join(directory,'cert.pem')))
writeFileSync(join(directory,'ready.json'),JSON.stringify({url:`https://localhost:${server.port}`,pin:createHash('sha256').update(cert.raw).digest('hex')}))
process.on('SIGTERM',()=>{server.stop(true);repo.close();process.exit(0)})
