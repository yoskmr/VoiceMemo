import { SignJWT, jwtVerify, errors as joseErrors } from "jose";

// --- Constants ---

const ISSUER = "soyoka-api";
const ALGORITHM = "HS256";
const EXPIRATION_HOURS = 24;

// --- Token Generation ---

export interface GenerateTokenResult {
  token: string;
  expiresAt: Date;
}

/**
 * デバイスID に対して HS256 署名付き JWT トークンを生成する
 * 有効期限は 24 時間
 */
export async function generateToken(
  deviceId: string,
  secret: string,
): Promise<GenerateTokenResult> {
  const secretKey = new TextEncoder().encode(secret);
  const expiresAt = new Date(Date.now() + EXPIRATION_HOURS * 60 * 60 * 1000);

  const token = await new SignJWT({ device_id: deviceId })
    .setProtectedHeader({ alg: ALGORITHM })
    .setIssuedAt()
    .setIssuer(ISSUER)
    .setSubject(deviceId)
    .setExpirationTime(expiresAt)
    .sign(secretKey);

  return { token, expiresAt };
}

// --- Token Verification ---

export interface VerifyTokenResult {
  deviceId: string;
}

/**
 * JWT トークンを検証し、埋め込まれた deviceId を返す
 * 検証失敗時は Error をスローする
 */
export async function verifyToken(
  token: string,
  secret: string,
): Promise<VerifyTokenResult> {
  const secretKey = new TextEncoder().encode(secret);

  const { payload } = await jwtVerify(token, secretKey, {
    issuer: ISSUER,
    algorithms: [ALGORITHM],
  });

  const deviceId = payload.sub;
  if (deviceId === undefined) {
    throw new Error("Token missing subject claim");
  }

  return { deviceId };
}

// --- Error Type Re-export ---

export const JWTExpiredError = joseErrors.JWTExpired;
export const JWTClaimValidationFailed = joseErrors.JWTClaimValidationFailed;
export const JWSSignatureVerificationFailed = joseErrors.JWSSignatureVerificationFailed;
