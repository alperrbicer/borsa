import { CATALOG, acceptQuote, hash, integer, requireValue } from './domain.mjs'
import { addNews, evaluateNews } from './analysis.mjs'
export async function readURL(url, options={}, fetcher=fetch) {
  const response=await fetcher(url,{...options,redirect:'error',signal:AbortSignal.timeout(12_000)})
  if (!response.ok) throw new Error(`HTTP ${response.status}: veri erişimi başarısız.`)
  if (Number(response.headers.get('content-length')??0)>2_000_000) throw new Error('Sağlayıcı yanıtı boyut sınırını aştı.')
  const reader=response.body.getReader(); const parts=[]; let size=0
  for (;;) { const {done,value}=await reader.read(); if(done)break;size+=value.length;if(size>2_000_000){await reader.cancel();throw new Error('Sağlayıcı yanıtı boyut sınırını aştı.')} parts.push(value) }
  return new TextDecoder().decode(Buffer.concat(parts))
}
export const jsonURL=async (...args)=>JSON.parse(await readURL(...args))
export function normalizeAlpaca(symbol, row, feed, clock, now=Date.now()) {
  const q=row.latestQuote, bid=Math.round(Number(q?.bp)*10000), ask=Math.round(Number(q?.ap)*10000)
  requireValue(integer(bid,1,1_000_000_000)&&integer(ask,bid,1_000_000_000),'Alpaca kotasyonu geçersiz.')
  const clockTime=Date.parse(clock?.timestamp), open=clock?.is_open===true && Math.abs(now-clockTime)<45_000
  return {symbol,currency:'USD',providerId:'alpaca',priceUnits:Math.round((bid+ask)/2),bidUnits:bid,askUnits:ask,
    bidSize:Number(q.bs),askSize:Number(q.as),timestamp:Date.parse(q.t),receivedAt:now,
    previousCloseUnits:Math.round(Number(row.prevDailyBar?.c??0)*10000),source:`Alpaca ${feed.toUpperCase()} · kotasyon ortası`,
    delaySeconds:feed==='delayed_sip'?900:0,quality:feed==='delayed_sip'?'delayed':'realtime',sessionOpen:open}
}
export const plain = value => String(value??'').replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,'$1').replace(/<[^>]*>/g,' ').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;|&apos;/g,"'").replace(/\s+/g,' ').trim()
export function parseRSS(xml, {source,market,url}, now=Date.now()) {
  const field=(text,name)=>plain(text.match(new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${name}>`,'i'))?.[1])
  const chunks=xml.match(/<(item|entry)(?:\s[^>]*)?>[\s\S]*?<\/\1>/gi)??[]
  return chunks.slice(0,50).map(chunk=>{
    let link=field(chunk,'link')||chunk.match(/<link\b[^>]*href="([^"]+)"/i)?.[1]||''
    if (link.startsWith('http://www.tcmb.gov.tr/')) link=link.replace('http:','https:')
    const rawDate=field(chunk,'pubDate')||field(chunk,'published')||field(chunk,'dc:date')
    const tr=rawDate.match(/^(\d{1,2}) (Oca|Şub|Mar|Nis|May|Haz|Tem|Ağu|Eyl|Eki|Kas|Ara) (\d{4}) (\d{2}:\d{2}:\d{2})$/)
    const publishedAt=tr?Date.parse(`${tr[3]}-${String(['Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'].indexOf(tr[2])+1).padStart(2,'0')}-${tr[1].padStart(2,'0')}T${tr[4]}+03:00`):Date.parse(rawDate)
    return {id:hash(source+'|'+link),title:field(chunk,'title'),summary:field(chunk,'description')||field(chunk,'summary'),source,url:link,symbols:[],market,scope:'macro',sourceTier:'official',publishedAt,receivedAt:now}
  }).filter(x=>x.title&&/^https:\/\//.test(x.url)&&Number.isFinite(x.publishedAt))
}
export function normalizeLicensed(envelope, now=Date.now()) {
  requireValue(envelope?.version===1 && typeof envelope.source==='string' && envelope.source.trim().length>0 && envelope.source.length<=200 && Array.isArray(envelope.quotes) && envelope.quotes.length>0,'Lisanslı akış sözleşmesi geçersiz.')
  return envelope.quotes.slice(0,100).map(q=>{
    requireValue(CATALOG.some(x=>x.symbol===q.symbol)&&Number.isFinite(q.timestamp)&&typeof q.sessionOpen==='boolean','Lisanslı akış zamanı/seansı geçersiz.')
    requireValue(['realtime','delayed','eod'].includes(q.quality)&&integer(q.delaySeconds,0,172800),'Lisanslı akış gecikmesi belirtilmeli.')
    return {...q,source:envelope.source,providerId:'licensed',receivedAt:now}
  })
}
export class Feeds {
  constructor(env=process.env,fetcher=fetch) { this.env=env;this.fetcher=fetcher;this.lastNews=0;this.lastBIST=0;this.running=false }
  async cycle(repository,now=Date.now()) {
    if(this.running)return
    this.running=true
    const e=this.env, updates=[], stories=[], health=[]
    const run=async(id,name,task)=>{
      const quoteStart=updates.length, newsStart=stories.length
      try {const message=await task();health.push({id,name,status:'connected',message:message??'Bağlantı çalışıyor.',lastSuccessAt:now})}
      catch(error){updates.splice(quoteStart);stories.splice(newsStart);health.push({id,name,status:'error',message:error.message?.startsWith('HTTP')?error.message:'Veri alınamadı veya sağlayıcı yanıtı doğrulanamadı.',lastSuccessAt:null})}
    }
    try {
      if(e.ALPACA_KEY_ID&&e.ALPACA_SECRET_KEY) {
        await run('alpaca','ABD fiyatları',async()=>{
          const feed=e.ALPACA_FEED??'iex'; requireValue(['iex','sip','delayed_sip'].includes(feed),'Geçersiz feed.')
          const headers={'APCA-API-KEY-ID':e.ALPACA_KEY_ID,'APCA-API-SECRET-KEY':e.ALPACA_SECRET_KEY}
          const symbols=CATALOG.filter(x=>x.market==='US').map(x=>x.symbol).join(',')
          const [rows,clock]=await Promise.all([jsonURL('https://data.alpaca.markets/v2/stocks/snapshots?symbols='+symbols+'&feed='+feed,{headers},this.fetcher),jsonURL('https://paper-api.alpaca.markets/v2/clock',{headers},this.fetcher)])
          for(const symbol of symbols.split(',')) if(rows[symbol]) updates.push(normalizeAlpaca(symbol,rows[symbol],feed,clock,now))
          requireValue(updates.some(q=>q.providerId==='alpaca'),'Alpaca fiyat döndürmedi.')
          return feed==='iex'?'IEX kapsamı; tüm ABD piyasasının birleşik hacmi değildir.':feed==='sip'?'SIP birleşik ABD akışı.':'15 dakika gecikmeli; otomatik gerçekleşme kapalı.'
        })
      } else health.push({id:'alpaca',name:'ABD fiyatları',status:'setup',message:'Ücretsiz IEX veya ücretli SIP için Alpaca API anahtarı gerekli.',lastSuccessAt:null})
      if(e.LICENSED_FEED_URL&&e.LICENSED_FEED_TOKEN) {
        await run('licensed','Lisanslı BIST akışı',async()=>{
          requireValue(new URL(e.LICENSED_FEED_URL).protocol==='https:','Lisanslı veri için HTTPS gerekli.')
          const body=await jsonURL(e.LICENSED_FEED_URL,{headers:{Authorization:'Bearer '+e.LICENSED_FEED_TOKEN}},this.fetcher)
          updates.push(...normalizeLicensed(body,now))
          if(Array.isArray(body.news))stories.push(...body.news.slice(0,100).filter(n=>n&&typeof n==='object').map(n=>({...n,source:body.source,sourceTier:'licensed',scope:n.scope==='company'?'company':'macro',market:n.market==='US'?'US':'BIST'})))
          return 'Yetkili fiyat/haber akışı sözleşmesi v1; sağlayıcı kapsamı uygulanıyor.'
        })
      } else health.push({id:'licensed',name:'BIST gün içi',status:'setup',message:'Yetkili sağlayıcı API erişimi/lisansı gerekli. Matriks sözleşmesine göre bağlanır.',lastSuccessAt:null})
      if(e.TWELVE_DATA_KEY && now-this.lastBIST>60*60_000) {
        this.lastBIST=now
        await run('twelve','BIST gün sonu',async()=>{
          for(const item of CATALOG.filter(x=>x.market==='BIST')) {
            const row=await jsonURL('https://api.twelvedata.com/quote?symbol='+item.symbol+'&exchange=BIST&apikey='+encodeURIComponent(e.TWELVE_DATA_KEY),{},this.fetcher)
            requireValue(row.status!=='error' && row.currency==='TRY' && row.symbol===item.symbol,'Twelve Data kapsamı doğrulanamadı.')
            updates.push({symbol:item.symbol,currency:'TRY',providerId:'twelve',priceUnits:Math.round(Number(row.close)*10000),bidUnits:null,askUnits:null,bidSize:0,askSize:0,
              timestamp:Number(row.timestamp)*1000,receivedAt:now,previousCloseUnits:Math.round(Number(row.previous_close)*10000),source:'Twelve Data · BIST gün sonu',quality:'eod',delaySeconds:86400,sessionOpen:false})
          }
          return 'Gün sonu; gün içi sanal gerçekleşme kapalı.'
        })
      } else if(!e.TWELVE_DATA_KEY) health.push({id:'twelve',name:'BIST gün sonu',status:'setup',message:'İsteğe bağlı Twelve Data Grow erişimi gerekli.',lastSuccessAt:null})
      if(now-this.lastNews>120_000) {
        this.lastNews=now
        const feeds=[{source:'Federal Reserve',market:'US',url:'https://www.federalreserve.gov/feeds/press_all.xml'},
          {source:'TCMB',market:'BIST',url:'https://www.tcmb.gov.tr/wps/wcm/connect/TR/TCMB%2BTR/Bottom%2BMenu/Diger/RSS/Basin%2BDuyurulari'}]
        for(const feed of feeds) await run(feed.source,'Haber · '+feed.source,async()=>{const rows=parseRSS(await readURL(feed.url,{},this.fetcher),feed,now);requireValue(rows.length>0,'RSS boş veya biçimi değişti.');stories.push(...rows);return `${rows.length} resmî duyuru alındı.`})
        if(e.ALPACA_KEY_ID&&e.ALPACA_SECRET_KEY) await run('alpaca-news','Şirket haberleri',async()=>{
          const result=await jsonURL('https://data.alpaca.markets/v1beta1/news?limit=50&include_content=false&symbols='+CATALOG.filter(x=>x.market==='US').map(x=>x.symbol).join(','),{headers:{'APCA-API-KEY-ID':e.ALPACA_KEY_ID,'APCA-API-SECRET-KEY':e.ALPACA_SECRET_KEY}},this.fetcher)
          requireValue(Array.isArray(result.news),'Haber yanıtı geçersiz.')
          stories.push(...result.news.map(n=>({id:'alpaca-'+n.id,title:n.headline,summary:plain(n.summary),source:n.source??'Alpaca Haber',sourceTier:'licensed',url:n.url,symbols:n.symbols,market:'US',scope:'company',publishedAt:Date.parse(n.created_at),receivedAt:now})))
          return 'Haber yetkisi hesaba bağlı; gözlenen gecikme haberde gösterilir.'
        })
      }
      if(!e.ALPACA_KEY_ID||!e.ALPACA_SECRET_KEY) health.push({id:'alpaca-news',name:'Şirket haberleri',status:'setup',message:'Alpaca hesabının haber yetkisi gerekli; ücretsiz resmî makro haberler ayrı akıyor.',lastSuccessAt:null})
      repository.update(state=>{
        for(const q of updates) {try{acceptQuote(state,q,now);state.health=state.health.filter(x=>x.id!=='invalid-'+q.symbol)}catch{if(state.quotes[q.symbol])state.quotes[q.symbol].sessionOpen=false;health.push({id:'invalid-'+q.symbol,name:q.symbol,status:'error',message:'Geçersiz sağlayıcı verisi reddedildi.',lastSuccessAt:null})}}
        for(const h of health.filter(x=>x.status!=='connected'))for(const q of Object.values(state.quotes))if(q.providerId===h.id)q.sessionOpen=false
        for(const item of health) {const old=state.health.find(x=>x.id===item.id);if(old){const previous=old.lastSuccessAt;Object.assign(old,item);if(!item.lastSuccessAt)old.lastSuccessAt=previous}else state.health.push(item)}
        addNews(state,stories,now);evaluateNews(state,now);state.lastCycleAt=now
      })
    } finally {this.running=false}
  }
}
