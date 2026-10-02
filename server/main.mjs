import { resolve, join } from 'node:path'
import { readFileSync, existsSync } from 'node:fs'
import { Repository } from './storage.mjs'
import { processOrders } from './domain.mjs'
import { Feeds } from './providers.mjs'
import { handler } from './http.mjs'
import { PushDelivery } from './notifications.mjs'
export function loadConfig(path='.env.server') {
  if(!existsSync(path))return
  for(const line of readFileSync(path,'utf8').split(/\r?\n/)){
    const match=line.match(/^([A-Z][A-Z0-9_]*)=(.*)$/);if(!match)continue
    let value=match[2].trim();if((value.startsWith('"')&&value.endsWith('"'))||(value.startsWith("'")&&value.endsWith("'")))value=value.slice(1,-1)
    if(process.env[match[1]]===undefined)process.env[match[1]]=value
  }
}
if(import.meta.main){
  loadConfig()
  const directory=resolve(process.env.BORSA_SERVER_DATA??'.borsa-server')
  if(!existsSync(join(directory,'cert.pem')))throw new Error('Önce bun run server:setup çalıştır.')
  const repository=new Repository(join(directory,'account.sqlite')),feeds=new Feeds(),push=new PushDelivery()
  repository.update(s=>{s.health=s.health.filter(x=>x.id!=='notifications');s.health.push({id:'notifications',name:'Telefon bildirimleri',status:push.configured?'connected':'setup',message:push.configured?'APNs gönderimi açık; cihaz izni ve kaydı gerekli.':'Uygulama içi incelemeler açık. Uygulama kapalıyken bildirim için APNs anahtarı gerekli.',lastSuccessAt:null})})
  const server=Bun.serve({hostname:process.env.BORSA_SERVER_HOST??'0.0.0.0',port:Number(process.env.BORSA_SERVER_PORT??8787),maxRequestBodySize:16384,
    tls:{cert:Bun.file(join(directory,'cert.pem')),key:Bun.file(join(directory,'key.pem'))},fetch:handler(repository,{pairingPath:join(directory,'pairing.json')})})
  let stopped=false
  async function cycle(){
    if(stopped)return
    try{await feeds.cycle(repository);repository.update(s=>processOrders(s));await push.flush(repository)}catch{console.error('Veri/işlem döngüsü tamamlanamadı; hesap korunuyor.')}finally{if(!stopped)setTimeout(cycle,15000)}
  }
  cycle()
  console.log(`Borsa servisi TLS ile ${server.port} portunda çalışıyor. Eşleşme: bun run server:pair`)
  const stop=()=>{stopped=true;server.stop();setTimeout(()=>process.exit(0),100).unref()}
  process.on('SIGTERM',stop);process.on('SIGINT',stop)
}
