export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export async function authorizeDaftarSyncRequest(input: {
  authorizationHeader: string | null;
  providedSecret: string;
  serviceCredential: string;
  expectedSecretHash: string;
}): Promise<boolean> {
  const bearer = (input.authorizationHeader ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();

  const internalServiceAuthorized =
    bearer.length > 0 &&
    input.serviceCredential.length > 0 &&
    constantTimeEqual(
      await sha256Hex(bearer),
      await sha256Hex(input.serviceCredential),
    );

  const dedicatedSecretAuthorized =
    input.providedSecret.length > 0 &&
    constantTimeEqual(
      await sha256Hex(input.providedSecret),
      input.expectedSecretHash,
    );

  return internalServiceAuthorized || dedicatedSecretAuthorized;
}
