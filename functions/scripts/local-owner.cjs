'use strict';
// Solo emuladores locales; nunca asigna permisos en Firebase real.
const fs = require('node:fs');
const path = require('node:path');
const {randomBytes} = require('node:crypto');
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore} = require('firebase-admin/firestore');
initializeApp({projectId:'demo-cantones'});
(async()=>{
 const auth=getAuth(); const dir=path.resolve(__dirname,'../../.local');
 fs.mkdirSync(dir,{recursive:true}); const file=path.join(dir,'cuenta-dueno.json');
 const credentials=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')):
   {email:'dueno@cantones.local',password:randomBytes(18).toString('base64url')};
 let user;
 try {user=await auth.getUserByEmail(credentials.email);} catch(e) {
   if(e.code!=='auth/user-not-found') throw e;
   user=await auth.createUser({...credentials,uid:'cantones-owner',displayName:'Dueño local'});
 }
 await auth.setCustomUserClaims(user.uid,{...user.customClaims,owner:true});
 fs.writeFileSync(file,JSON.stringify(credentials,null,2),{mode:0o600});
 if(!(await getFirestore().doc('settings/business').get()).exists){
   const login=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local-emulator-key',{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...credentials,returnSecureToken:true})});
   const result=await login.json();if(!login.ok)throw Error(result.error?.message);
   const response=await fetch('http://127.0.0.1:5001/demo-cantones/us-central1/seedBusiness',{
    method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${result.idToken}`},body:JSON.stringify({data:{}})});
   const seeded=await response.json();if(!response.ok||seeded.error)throw Error(seeded.error?.message||'No se pudo cargar el catálogo');
 }
 console.log('Cuenta local preparada. Datos de acceso en .local/cuenta-dueno.json.');
 console.log('Los precios y existencias iniciales son cero; configurarlos en Dueño.');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
