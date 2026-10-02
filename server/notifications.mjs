import { connect } from 'node:http2'
import { sign } from 'node:crypto'
import { readFileSync } from 'node:fs'
export function notificationPayload(decision) {
  return {aps:{alert:{title:`${decision.symbol} için inceleme`,body:'Yeni değerlendirme var. Süresi içinde uygulamadan inceleyebilirsin.'},sound:'default',category:'BORSA_REVIEW'},decisionId:decision.id}
}
export class PushDelivery {
  constructor(env=process.env){this.env=env;this.running=false}
  get configured(){return !!(this.env.APNS_KEY_PATH&&this.env.APNS_KEY_ID&&this.env.APNS_TEAM_ID)}
  async send(device,decision){
    const e=this.env, encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url')
    const data=encode({alg:'ES256',kid:e.APNS_KEY_ID})+'.'+encode({iss:e.APNS_TEAM_ID,iat:Math.floor(Date.now()/1000)})
    const jwt=data+'.'+sign('sha256',Buffer.from(data),{key:readFileSync(e.APNS_KEY_PATH),dsaEncoding:'ieee-p1363'}).toString('base64url')
    const host=e.APNS_ENV==='production'?'https://api.push.apple.com':'https://api.sandbox.push.apple.com'
    return await new Promise((resolve,reject)=>{
      const client=connect(host);const timer=setTimeout(()=>{client.destroy();reject(new Error('APNs zaman aşımı.'))},10000)
      client.on('error',()=>{clearTimeout(timer);client.destroy();reject(new Error('APNs bağlantısı başarısız.'))})
      const stream=client.request({':method':'POST',':path':'/3/device/'+device,authorization:'bearer '+jwt,'apns-topic':e.APNS_TOPIC??'dev.prototype.borsa','apns-push-type':'alert','apns-priority':'10','apns-expiration':String(Math.floor(decision.expiresAt/1000)),'apns-collapse-id':decision.id})
      let status=0;stream.on('response',headers=>{status=headers[':status']});stream.on('data',()=>{})
      stream.on('error',()=>{clearTimeout(timer);client.destroy();reject(new Error('APNs gönderimi başarısız.'))})
      stream.on('end',()=>{clearTimeout(timer);client.close();status===200?resolve(true):reject(new Error('APNs HTTP '+status))})
      stream.end(JSON.stringify(notificationPayload(decision)))
    })
  }
  async flush(repo){
    if(!this.configured||this.running)return;this.running=true
    try{
      for(const d of repo.read().decisions.filter(x=>x.state==='review'&&x.expiresAt>Date.now()).slice(0,10)){
        for(const {token} of repo.db.query('SELECT token FROM devices').all()){
          const id=d.id+'|'+token
          if(repo.db.query('SELECT id FROM delivery WHERE id=?').get(id))continue
          await this.send(token,d);repo.db.query('INSERT OR IGNORE INTO delivery VALUES (?,?)').run(id,Date.now())
        }
      }
    }finally{this.running=false}
  }
}
