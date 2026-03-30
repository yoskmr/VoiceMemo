import { describe, it, expect } from "vitest";
import { SignJWT } from "jose";
import {
  generateToken,
  verifyToken,
  JWTExpiredError,
  JWSSignatureVerificationFailed,
} from "../../src/services/token.js";

const TEST_SECRET = "test-secret-key-for-unit-tests-only";
const TEST_DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000";

describe("token service", () => {
  describe("generateToken", () => {
    it("有効な JWT を生成できる", async () => {
      const result = await generateToken(TEST_DEVICE_ID, TEST_SECRET);

      expect(result.token).toBeDefined();
      expect(typeof result.token).toBe("string");
      expect(result.token.split(".")).toHaveLength(3); // JWT は 3 パートで構成される
      expect(result.expiresAt).toBeInstanceOf(Date);
      expect(result.expiresAt.getTime()).toBeGreaterThan(Date.now());
    });

    it("生成したトークンを検証できる", async () => {
      const { token } = await generateToken(TEST_DEVICE_ID, TEST_SECRET);
      const verified = await verifyToken(token, TEST_SECRET);

      expect(verified.deviceId).toBe(TEST_DEVICE_ID);
    });

    it("有効期限が約 24 時間後に設定される", async () => {
      const before = Date.now();
      const result = await generateToken(TEST_DEVICE_ID, TEST_SECRET);
      const after = Date.now();

      const expectedMin = before + 24 * 60 * 60 * 1000;
      const expectedMax = after + 24 * 60 * 60 * 1000;

      expect(result.expiresAt.getTime()).toBeGreaterThanOrEqual(expectedMin);
      expect(result.expiresAt.getTime()).toBeLessThanOrEqual(expectedMax);
    });
  });

  describe("verifyToken", () => {
    it("有効なトークンから deviceId を取得できる", async () => {
      const { token } = await generateToken(TEST_DEVICE_ID, TEST_SECRET);
      const result = await verifyToken(token, TEST_SECRET);

      expect(result.deviceId).toBe(TEST_DEVICE_ID);
    });

    it("期限切れ JWT を拒否する", async () => {
      // 過去の有効期限でトークンを手動生成
      const secretKey = new TextEncoder().encode(TEST_SECRET);
      const expiredToken = await new SignJWT({ device_id: TEST_DEVICE_ID })
        .setProtectedHeader({ alg: "HS256" })
        .setIssuedAt(Math.floor(Date.now() / 1000) - 7200) // 2 時間前に発行
        .setIssuer("soyoka-api")
        .setSubject(TEST_DEVICE_ID)
        .setExpirationTime(Math.floor(Date.now() / 1000) - 3600) // 1 時間前に期限切れ
        .sign(secretKey);

      await expect(verifyToken(expiredToken, TEST_SECRET)).rejects.toThrow(
        JWTExpiredError,
      );
    });

    it("不正な署名の JWT を拒否する", async () => {
      const { token } = await generateToken(TEST_DEVICE_ID, TEST_SECRET);
      const differentSecret = "completely-different-secret-key";

      await expect(verifyToken(token, differentSecret)).rejects.toThrow(
        JWSSignatureVerificationFailed,
      );
    });

    it("不正な issuer の JWT を拒否する", async () => {
      const secretKey = new TextEncoder().encode(TEST_SECRET);
      const badIssuerToken = await new SignJWT({ device_id: TEST_DEVICE_ID })
        .setProtectedHeader({ alg: "HS256" })
        .setIssuedAt()
        .setIssuer("wrong-issuer")
        .setSubject(TEST_DEVICE_ID)
        .setExpirationTime("24h")
        .sign(secretKey);

      await expect(verifyToken(badIssuerToken, TEST_SECRET)).rejects.toThrow();
    });
  });
});
