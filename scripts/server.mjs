#!/usr/bin/env bun
import { mkdirSync, existsSync, chmodSync, writeFileSync, readFileSync, copyFileSync, renameSync } from 'node:fs'
import { resolve, join } from 'node:path'
import { hostname } from 'node:os'
import { X509Certificate, randomInt, createHash } from 'node:crypto'
import { spawnSync } from 'node:child_process'
const root=resolve(import.meta.dir,'..'), dir=join(root,'.borsa-server'), command=process.argv[2]
mkdirSync(dir,{recursive:true,mode:0o700})
const localName=spawnSync('/usr/sbin/scutil',['--get','LocalHostName'],{encoding:'utf8'}).stdout?.trim()||hostname().split('.')[0]
if(command==='setup'){
  let existing
  try{existing=new X509Certificate(readFileSync(join(dir,'cert.pem')))}catch{}
  if(!existing?.keyUsage?.includes('1.3.6.1.5.5.7.3.1') || !existing.checkHost(localName+'.local') || Date.parse(existing.validTo)<=Date.now()){
    const result=spawnSync('openssl',['req','-x509','-newkey','rsa:2048','-sha256','-days','365','-nodes','-keyout',join(dir,'key.next.pem'),'-out',join(dir,'cert.next.pem'),'-subj','/CN='+localName+'.local','-addext','subjectAltName=DNS:'+localName+'.local,DNS:localhost,IP:127.0.0.1','-addext','extendedKeyUsage=serverAuth','-addext','keyUsage=critical,digitalSignature,keyEncipherment','-addext','basicConstraints=critical,CA:FALSE'],{stdio:'pipe'})
    if(result.status!==0)throw new Error('Yerel TLS sertifikası oluşturulamadı.')
    chmodSync(join(dir,'key.next.pem'),0o600)
    const stamp=Date.now()
    for(const name of ['cert.pem','key.pem'])if(existsSync(join(dir,name)))copyFileSync(join(dir,name),join(dir,name+'.previous-'+stamp))
    renameSync(join(dir,'key.next.pem'),join(dir,'key.pem'));renameSync(join(dir,'cert.next.pem'),join(dir,'cert.pem'))
    if(existing)console.log('Yerel sertifika yenilendi; eski sertifika saklandı. Servisi yeniden başlat ve sonraki cihaz kurulumunda yeni parmak izini kullan.')
  }
  if(!existsSync(join(root,'.env.server')))writeFileSync(join(root,'.env.server'),readFileSync(join(root,'.env.server.example')),{mode:0o600})
  const cert=new X509Certificate(readFileSync(join(dir,'cert.pem'))),pin=createHash('sha256').update(cert.raw).digest('hex')
  const publicConfig={url:'https://'+localName+'.local:8787',pin}
  writeFileSync(join(dir,'connection.json'),JSON.stringify(publicConfig,null,2)+'\n',{mode:0o600})
  // Public endpoint and certificate fingerprint only; no credential is bundled.
  writeFileSync(join(root,'Config/Server.local.xcconfig'),'BORSA_SERVER_HOST = '+localName+'.local\nBORSA_SERVER_PIN = '+pin+'\n')
  console.log('Yerel TLS, gizli ayar dosyası ve genel bağlantı ayarları hazır. URL: '+publicConfig.url)
}else if(command==='pair'){
  const code=String(randomInt(100000,1000000))
  writeFileSync(join(dir,'pairing.json'),JSON.stringify({digest:createHash('sha256').update(code).digest('hex'),expiresAt:Date.now()+180000}),{mode:0o600})
  console.log('3 dakika geçerli tek kullanımlık eşleşme kodu: '+code)
}else if(command==='status'){
  console.log(existsSync(join(dir,'connection.json'))?readFileSync(join(dir,'connection.json'),'utf8'):'Önce server:setup çalıştır.')
}else throw new Error('Kullanım: bun scripts/server.mjs setup|pair|status')
