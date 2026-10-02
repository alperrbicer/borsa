import { connect } from 'node:http2'
import { sign } from 'node:crypto'
import { readFileSync } from 'node:fs'
export function notificationPayload(decision) {
  return {aps:{alert:{title:`${decision.symbol} için inceleme`,body:'Yeni değerlendirme var. Süresi içinde uygulamadan inceleyebilirsin.'},sound:'default',category:'BORSA_REVIEW'},decisionId:decision.id}
}
export class PushError extends Error {
  constructor(status=0,reason='ConnectionFailed') { super(status ? `APNs HTTP ${status} (${reason})` : 'APNs bağlantısı başarısız.'); this.status=status; this.reason=reason }
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
      const client=connect(host);const timer=setTimeout(()=>{client.destroy();reject(new PushError(0,'Timeout'))},10000)
      client.on('error',()=>{clearTimeout(timer);client.destroy();reject(new PushError())})
      const stream=client.request({':method':'POST',':path':'/3/device/'+device,authorization:'bearer '+jwt,'apns-topic':e.APNS_TOPIC??'dev.prototype.borsa','apns-push-type':'alert','apns-priority':'10','apns-expiration':String(Math.floor(decision.expiresAt/1000)),'apns-collapse-id':decision.id})
      let status=0,body='';stream.on('response',headers=>{status=headers[':status']});stream.on('data',part=>{if(body.length<4096)body+=part.toString()})
      stream.on('error',()=>{clearTimeout(timer);client.destroy();reject(new PushError())})
      stream.on('end',()=>{
        clearTimeout(timer);client.close()
        let reason='Rejected';try{const value=JSON.parse(body).reason;if(typeof value==='string'&&/^[A-Za-z]{1,64}$/.test(value))reason=value}catch{}
        status===200?resolve(true):reject(new PushError(status,reason))
      })
      stream.end(JSON.stringify(notificationPayload(decision)))
    })
  }
  health(repo,status,message,successAt=null) {
    const old=repo.read().health.find(x=>x.id==='notifications')
    if(old?.status===status&&old?.message===message&&!successAt)return
    repo.update(s=>{
      s.health=s.health.filter(x=>x.id!=='notifications')
      s.health.push({id:'notifications',name:'Telefon bildirimleri',status,message,lastSuccessAt:successAt??old?.lastSuccessAt??null})
    })
  }
  async flush(repo){
    if(this.running)return
    if(!this.configured){this.health(repo,'setup','İncelemeler Asistan’da saklanıyor. Uygulama kapalıyken bildirim için APNs anahtarı gerekli.');return}
    this.running=true
    try{
      const devices=repo.db.query('SELECT token FROM devices').all()
      if(!devices.length){this.health(repo,'ready','APNs ayarlandı; telefonun bildirim kaydı bekleniyor. Henüz gönderim doğrulanmadı.');return}
      const pending=repo.read().decisions.filter(x=>x.state==='review'&&x.expiresAt>Date.now()).reverse()
      let attempts=0,successAt=null,failure=null
      for(const d of pending){
        for(const {token} of devices){
          if(d.expiresAt<=Date.now())break
          const id=d.id+'|'+token
          if(repo.db.query('SELECT id FROM delivery WHERE id=?').get(id))continue
          if(attempts>=10)break
          attempts++
          try {
            await this.send(token,d);successAt=Date.now()
            repo.db.query('INSERT OR IGNORE INTO delivery VALUES (?,?)').run(id,successAt)
          } catch(error) {
            failure=error instanceof PushError?error.message:'APNs anahtarı okunamadı veya bildirim gönderilemedi.'
            if(error instanceof PushError && error.status===410)repo.db.query('DELETE FROM devices WHERE token=?').run(token)
          }
        }
      }
      if(failure)this.health(repo,'error',failure+' İncelemeler Asistan’da duruyor; başarısız gönderimler yeniden denenecek.',successAt)
      else if(successAt)this.health(repo,'connected','Apple bildirim isteğini kabul etti. Telefonda gösterilmesi izin ve bağlantıya bağlı.',successAt)
      else if(!repo.read().health.some(x=>x.id==='notifications'&&['connected','error'].includes(x.status)))this.health(repo,'ready','Telefon kaydı hazır; henüz bir bildirimin Apple tarafından kabulü doğrulanmadı.')
    }finally{this.running=false}
  }
}
