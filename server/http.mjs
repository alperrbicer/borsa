import { randomBytes, timingSafeEqual } from 'node:crypto'
import { readFileSync, unlinkSync } from 'node:fs'
import { DomainError, snapshot, placeOrder, cancelOrder, changeSettings, instrument, hash } from './domain.mjs'
import { reviewDecision, previewDecision } from './analysis.mjs'
const json=(value,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}})
export function handler(repository,{pairingPath,now=()=>Date.now()}={}) {
  let failures=0, lockedUntil=0
  return async request=>{
    try {
      const url=new URL(request.url), path=url.pathname
      if(request.headers.get('origin'))throw new DomainError('Tarayıcı erişimi desteklenmiyor.',403)
      if(path==='/health'&&request.method==='GET')return json({ok:true,version:1})
      const body=async()=>{
        if(Number(request.headers.get('content-length')??0)>16384)throw new DomainError('İstek çok büyük.',413)
        const reader=request.body?.getReader();if(!reader)throw new DomainError('İstek gövdesi gerekli.',400)
        let bytes=0,parts=[]
        for(;;){const r=await reader.read();if(r.done)break;bytes+=r.value.length;if(bytes>16384){await reader.cancel();throw new DomainError('İstek çok büyük.',413)}parts.push(r.value)}
        try{const value=JSON.parse(Buffer.concat(parts).toString());if(!value||typeof value!=='object'||Array.isArray(value))throw new Error();return value}catch{throw new DomainError('Geçersiz JSON.',400)}
      }
      if(path==='/pair'&&request.method==='POST') {
        if(lockedUntil>now())throw new DomainError('Çok fazla deneme. Bir dakika sonra tekrar dene.',429)
        const input=await body();let pairing
        try{pairing=JSON.parse(readFileSync(pairingPath,'utf8'))}catch{throw new DomainError('Yeni bir eşleşme kodu oluştur.',401)}
        const expected=Buffer.from(pairing.digest??''), actual=Buffer.from(hash(String(input.code??'')))
        if(pairing.expiresAt<now()||expected.length!==actual.length||!timingSafeEqual(expected,actual)) {
          if(++failures>=5){lockedUntil=now()+60_000;failures=0}throw new DomainError('Eşleşme kodu geçersiz veya süresi doldu.',401)
        }
        unlinkSync(pairingPath);failures=0
        const token=randomBytes(32).toString('hex');repository.addToken(token)
        return json({token})
      }
      const bearer=request.headers.get('authorization')?.match(/^Bearer ([a-zA-Z0-9]+)$/)?.[1]
      if(!repository.authorize(bearer))throw new DomainError('Sunucuyla eşleşmen gerekiyor.',401)
      if(path==='/snapshot'&&request.method==='GET')return json(snapshot(repository.read(),now()))
      if(path==='/backup'&&request.method==='GET')return json(repository.read())
      if(path==='/orders'&&request.method==='POST'){const input=await body();repository.update(s=>placeOrder(s,input,now()));return json(snapshot(repository.read(),now()))}
      const cancel=path.match(/^\/orders\/([a-zA-Z0-9-]+)\/cancel$/)
      if(cancel&&request.method==='POST'){repository.update(s=>cancelOrder(s,cancel[1]));return json(snapshot(repository.read(),now()))}
      const review=path.match(/^\/decisions\/([a-zA-Z0-9-]+)\/review$/)
      if(review&&request.method==='POST'){const input=await body();if(input.choice!=='reject'&&!input.confirmation)throw new DomainError('Önce emir önizlemesini onayla.');repository.update(s=>reviewDecision(s,review[1],input.choice,now(),input.confirmation));return json(snapshot(repository.read(),now()))}
      const preview=path.match(/^\/decisions\/([a-zA-Z0-9-]+)\/preview$/)
      if(preview&&request.method==='POST'){const input=await body();return json(previewDecision(repository.read(),preview[1],input.choice,now()))}
      if(path==='/settings'&&request.method==='PATCH'){const input=await body();repository.update(s=>changeSettings(s,input));return json(snapshot(repository.read(),now()))}
      if(path==='/watchlist'&&request.method==='PUT'){
        const input=await body();if(!Array.isArray(input.symbols)||input.symbols.length>30||input.symbols.some(x=>!instrument(x)))throw new DomainError('Geçersiz takip listesi.')
        repository.update(s=>{s.watchlist=[...new Set(input.symbols)]});return json(snapshot(repository.read(),now()))
      }
      if(path==='/device'&&request.method==='POST'){
        const input=await body();if(!/^[0-9a-f]{64,200}$/.test(input.token??''))throw new DomainError('Geçersiz bildirim kaydı.')
        repository.db.query('INSERT INTO devices VALUES (?,?) ON CONFLICT(token) DO UPDATE SET updated=excluded.updated').run(input.token,now());return json({ok:true})
      }
      throw new DomainError('İşlem bulunamadı.',404)
    }catch(error){return json({error:error instanceof DomainError?error.message:'İşlem kaydedilemedi. Mevcut hesap korunuyor.'},error instanceof DomainError?error.status:500)}
  }
}
