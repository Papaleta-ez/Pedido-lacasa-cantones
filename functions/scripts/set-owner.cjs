// Run with Application Default Credentials from a trusted administrator terminal.
const {initializeApp,applicationDefault}=require('firebase-admin/app');const {getAuth}=require('firebase-admin/auth');
const [projectId,uid]=process.argv.slice(2);if(!projectId||!uid){console.error('Uso: node scripts/set-owner.cjs PROJECT_ID OWNER_UID');process.exit(1);}
initializeApp({credential:applicationDefault(),projectId});
getAuth().getUser(uid).then(user=>getAuth().setCustomUserClaims(uid,{...user.customClaims,owner:true})).then(()=>console.log('Claim owner asignado. Volvé a iniciar sesión.')).catch(e=>{console.error(e.message);process.exitCode=1;});
