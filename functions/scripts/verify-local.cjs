const assert=require('node:assert/strict');
const fs=require('node:fs');
process.env.FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099';process.env.FIRESTORE_EMULATOR_HOST='127.0.0.1:8080';
const {initializeApp}=require('firebase-admin/app');const {getAuth}=require('firebase-admin/auth');const {getFirestore}=require('firebase-admin/firestore');initializeApp({projectId:'demo-cantones'});
async function auth(method,data){const r=await fetch(`http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:${method}?key=local-emulator-key`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...data,returnSecureToken:true})});const v=await r.json();assert.equal(r.status,200,JSON.stringify(v));return v;}
async function call(method,token,data){const r=await fetch(`http://127.0.0.1:5001/demo-cantones/us-central1/${method}`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify({data})});const v=await r.json();assert.equal(r.status,200,JSON.stringify(v));assert.ok(!v.error);return v;}
(async()=>{const creds=JSON.parse(fs.readFileSync('.local/cuenta-dueno.json','utf8'));const owner=await auth('signInWithPassword',creds);const device=await auth('signUp',{});try{
 await call('registerDevice',device.idToken,{mode:'mesero',name:'Prueba automática local'});
 let doc=await getFirestore().doc(`devices/${device.localId}`).get();assert.equal(doc.data().active,false);
 await call('authorizeDevice',owner.idToken,{uid:device.localId,role:'mesero',active:true});
 doc=await getFirestore().doc(`devices/${device.localId}`).get();assert.equal(doc.data().active,true);
 assert.ok((await getFirestore().doc('settings/business').get()).exists);
 console.log('OK: acceso dueño, registro terminal, autorización y catálogo por HTTP local real.');
}finally{await getFirestore().doc(`devices/${device.localId}`).delete();await getAuth().deleteUser(device.localId);}})().catch(e=>{console.error(e.message);process.exitCode=1;});
