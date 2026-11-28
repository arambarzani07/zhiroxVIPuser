import { allowPasskeyChallenge } from "./passkey-policy.mjs";
const cases = [
  [
    "valid",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    true
  ],
  [
    "expiry boundary",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    301000,
    false
  ],
  [
    "future issuance",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    999,
    false
  ],
  [
    "overlong lifetime",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301001,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "replay",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": 1000
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "other market",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "33333333-3333-4333-8333-333333333333",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "other customer",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "44444444-4444-4444-8444-444444444444",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "wrong ceremony",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "authentication",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "wrong challenge",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
    },
    1001,
    false
  ],
  [
    "untrusted origin",
    {
      "origin": "https://evil.zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://evil.zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "origin mismatch",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://push.zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "wrong rp",
    {
      "origin": "https://zhirox.com",
      "rpId": "push.zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "second approved origin",
    {
      "origin": "https://push.zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://push.zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    true
  ],
  [
    "invalid challenge",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "short",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "short"
    },
    1001,
    false
  ],
  [
    "missing record",
    null,
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    false
  ],
  [
    "bad time",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "registration",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    null,
    false
  ],
  [
    "valid authentication",
    {
      "origin": "https://zhirox.com",
      "rpId": "zhirox.com",
      "ceremony": "authentication",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "issuedAt": 1000,
      "expiresAt": 301000,
      "consumedAt": null
    },
    {
      "origin": "https://zhirox.com",
      "ceremony": "authentication",
      "marketId": "11111111-1111-4111-8111-111111111111",
      "customerId": "22222222-2222-4222-8222-222222222222",
      "challenge": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    1001,
    true
  ]
];
for (const [name,record,context,now,expected] of cases) {
  Deno.test(name,()=>{if(allowPasskeyChallenge(record,context,now)!==expected)throw new Error(name);});
}
