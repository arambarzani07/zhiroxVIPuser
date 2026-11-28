// Pre-verification policy only. Not a signature verifier or authorization grant.
// All context identities and timestamps must be obtained server-side.
// Atomically consume the challenge before calling the vetted WebAuthn verifier.
export function allowPasskeyChallenge(record,context,now){
  const allowedOrigins=['https://zhirox.com','https://push.zhirox.com'];
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const challengePattern=/^[A-Za-z0-9_-]{43,128}$/;
  if(!record||!context||!Number.isSafeInteger(now))return false;
  if(!allowedOrigins.includes(context.origin)||record.origin!==context.origin||record.rpId!=='zhirox.com')return false;
  if(!['registration','authentication'].includes(context.ceremony)||record.ceremony!==context.ceremony)return false;
  if(!uuid.test(context.marketId)||!uuid.test(context.customerId)||record.marketId!==context.marketId||record.customerId!==context.customerId)return false;
  if(!challengePattern.test(record.challenge)||record.challenge!==context.challenge)return false;
  if(record.consumedAt!==null||!Number.isSafeInteger(record.issuedAt)||!Number.isSafeInteger(record.expiresAt))return false;
  return record.issuedAt<=now&&now<record.expiresAt&&record.expiresAt-record.issuedAt<=300000;
}
