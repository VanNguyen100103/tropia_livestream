'use strict';

// Mock toàn bộ dependencies bên ngoài trước khi require service
jest.mock('../../src/repositories/auth.repository');
jest.mock('../../src/lib/redis',    () => ({ getRedis: jest.fn(), acquireLock: jest.fn() }));
jest.mock('../../src/lib/rabbitmq', () => ({ publish: jest.fn().mockResolvedValue(undefined) }));
jest.mock('../../src/middleware/security', () => ({ logSecurityEvent: jest.fn() }));

const bcrypt  = require('bcryptjs');
const crypto  = require('crypto');
const repo    = require('../../src/repositories/auth.repository');
const svc     = require('../../src/services/auth.service');
const { AuthError, ConflictError } = require('../../src/errors/AppError');

// ── Fixtures ─────────────────────────────────────────────────────────────────

const HASH = bcrypt.hashSync('Password1!', 1); // cost=1 để test nhanh

function makeUser(overrides = {}) {
  return {
    id:                    'uid-001',
    email:                 'user@tropia.vn',
    name:                  'Test User',
    role:                  'buyer',
    status:                'active',
    password_hash:         HASH,
    failed_login_attempts: 0,
    locked_until:          null,
    ...overrides,
  };
}

// ── register ─────────────────────────────────────────────────────────────────

describe('auth.service.register', () => {
  beforeEach(() => jest.clearAllMocks());

  it('tạo user thành công khi email chưa tồn tại', async () => {
    repo.emailExists.mockResolvedValue(false);
    repo.createProfile.mockResolvedValue(makeUser());

    const result = await svc.register({
      email: 'user@tropia.vn', password: 'Password1!',
      fullName: 'Test User', phone: null, role: 'buyer',
    });

    expect(repo.createProfile).toHaveBeenCalledTimes(1);
    expect(result.email).toBe('user@tropia.vn');
  });

  it('throw ConflictError khi email đã tồn tại', async () => {
    repo.emailExists.mockResolvedValue(true);

    await expect(svc.register({
      email: 'dup@tropia.vn', password: 'pass', fullName: 'X',
    })).rejects.toBeInstanceOf(ConflictError);

    expect(repo.createProfile).not.toHaveBeenCalled();
  });

  it('normalize email về lowercase', async () => {
    repo.emailExists.mockResolvedValue(false);
    repo.createProfile.mockResolvedValue(makeUser({ email: 'user@tropia.vn' }));

    await svc.register({ email: 'USER@TROPIA.VN', password: 'Password1!', fullName: 'X' });

    const callArg = repo.createProfile.mock.calls[0][0];
    expect(callArg.email).toBe('user@tropia.vn');
  });
});

// ── login ─────────────────────────────────────────────────────────────────────

describe('auth.service.login', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    repo.makeTokenPair.mockReturnValue({
      rawRefresh: 'raw-refresh-token',
      tokenHash:  'hash',
      expiresAt:  new Date(Date.now() + 86_400_000).toISOString(),
      family:     'fam-001',
    });
    repo.insertRefreshToken.mockResolvedValue(undefined);
    repo.clearLoginFailure.mockResolvedValue(undefined);
  });

  it('trả về tokens khi credentials đúng', async () => {
    repo.findProfileByEmail.mockResolvedValue(makeUser());

    const { tokens } = await svc.login('user@tropia.vn', 'Password1!', '127.0.0.1');

    expect(tokens.accessToken).toBeTruthy();
    expect(tokens.refreshToken).toBe('raw-refresh-token');
  });

  it('throw AuthError khi user không tồn tại', async () => {
    repo.findProfileByEmail.mockResolvedValue(null);

    await expect(svc.login('nobody@x.com', 'pass', '127.0.0.1'))
      .rejects.toBeInstanceOf(AuthError);
  });

  it('throw AuthError khi sai mật khẩu', async () => {
    repo.findProfileByEmail.mockResolvedValue(makeUser());
    repo.updateLoginFailure.mockResolvedValue(undefined);

    await expect(svc.login('user@tropia.vn', 'WrongPass!', '127.0.0.1'))
      .rejects.toBeInstanceOf(AuthError);

    expect(repo.updateLoginFailure).toHaveBeenCalledWith('uid-001', 1, null);
  });

  it('lock account sau 5 lần sai', async () => {
    repo.findProfileByEmail.mockResolvedValue(
      makeUser({ failed_login_attempts: 4 })
    );
    repo.updateLoginFailure.mockResolvedValue(undefined);

    await expect(svc.login('user@tropia.vn', 'Wrong!', '127.0.0.1'))
      .rejects.toBeInstanceOf(AuthError);

    // Lần thứ 5 → lockUntil phải được set
    const [, attempts, lockUntil] = repo.updateLoginFailure.mock.calls[0];
    expect(attempts).toBe(5);
    expect(lockUntil).not.toBeNull();
  });

  it('throw AuthError khi account đang bị lock', async () => {
    repo.findProfileByEmail.mockResolvedValue(
      makeUser({ locked_until: new Date(Date.now() + 60_000).toISOString() })
    );

    await expect(svc.login('user@tropia.vn', 'Password1!', '127.0.0.1'))
      .rejects.toBeInstanceOf(AuthError);
  });

  it('cho phép đăng nhập khi lock đã hết hạn', async () => {
    repo.findProfileByEmail.mockResolvedValue(
      makeUser({ locked_until: new Date(Date.now() - 1000).toISOString() })
    );

    const { tokens } = await svc.login('user@tropia.vn', 'Password1!', '127.0.0.1');
    expect(tokens.accessToken).toBeTruthy();
  });

  it('throw AuthError khi user status là deleted', async () => {
    repo.findProfileByEmail.mockResolvedValue(makeUser({ status: 'deleted' }));

    await expect(svc.login('user@tropia.vn', 'Password1!', '127.0.0.1'))
      .rejects.toBeInstanceOf(AuthError);
  });
});

// ── refresh ───────────────────────────────────────────────────────────────────

describe('auth.service.refresh', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    repo.makeTokenPair.mockReturnValue({
      rawRefresh: 'new-refresh',
      tokenHash:  'new-hash',
      expiresAt:  new Date(Date.now() + 86_400_000).toISOString(),
      family:     'fam-001',
    });
    repo.insertRefreshToken.mockResolvedValue(undefined);
    repo.revokeTokenByHash.mockResolvedValue(undefined);
  });

  it('throw AuthError khi không có token', async () => {
    await expect(svc.refresh(null)).rejects.toBeInstanceOf(AuthError);
    await expect(svc.refresh('')).rejects.toBeInstanceOf(AuthError);
  });

  it('throw AuthError khi token không tồn tại trong DB', async () => {
    repo.findRefreshToken.mockResolvedValue(null);

    await expect(svc.refresh('fake-token')).rejects.toBeInstanceOf(AuthError);
  });

  it('throw AuthError và revoke family khi token đã bị dùng (reuse attack)', async () => {
    repo.findRefreshToken.mockResolvedValue({
      user_id: 'uid-001', family: 'fam-001',
      revoked: true,
      expires_at: new Date(Date.now() + 86_400_000).toISOString(),
    });
    repo.revokeTokenFamily.mockResolvedValue(undefined);

    await expect(svc.refresh('reused-token')).rejects.toBeInstanceOf(AuthError);
    expect(repo.revokeTokenFamily).toHaveBeenCalledWith('fam-001');
  });

  it('rotate token thành công', async () => {
    repo.findRefreshToken.mockResolvedValue({
      user_id: 'uid-001', family: 'fam-001',
      revoked: false,
      expires_at: new Date(Date.now() + 86_400_000).toISOString(),
    });
    repo.findProfileById.mockResolvedValue(makeUser());

    const { tokens } = await svc.refresh('valid-raw-token');
    expect(tokens.refreshToken).toBe('new-refresh');
    expect(repo.revokeTokenByHash).toHaveBeenCalled();
  });
});

// ── forgotPassword / resetPassword ────────────────────────────────────────────

describe('auth.service.forgotPassword', () => {
  beforeEach(() => jest.clearAllMocks());

  it('không throw dù email không tồn tại (anti-enumeration)', async () => {
    repo.findProfileByEmail.mockResolvedValue(null);
    await expect(svc.forgotPassword('ghost@x.com')).resolves.toBeUndefined();
    expect(repo.setPasswordResetToken).not.toHaveBeenCalled();
  });

  it('lưu token khi user tồn tại', async () => {
    repo.findProfileByEmail.mockResolvedValue(makeUser());
    repo.setPasswordResetToken.mockResolvedValue(undefined);

    await svc.forgotPassword('user@tropia.vn');

    expect(repo.setPasswordResetToken).toHaveBeenCalledTimes(1);
    const [uid, hash, expiresAt] = repo.setPasswordResetToken.mock.calls[0];
    expect(uid).toBe('uid-001');
    expect(typeof hash).toBe('string');
    expect(new Date(expiresAt) > new Date()).toBe(true);
  });
});

describe('auth.service.resetPassword', () => {
  beforeEach(() => jest.clearAllMocks());

  it('throw AuthError khi token rỗng', async () => {
    await expect(svc.resetPassword('', 'NewPass1!'))
      .rejects.toBeInstanceOf(AuthError);
  });

  it('throw AuthError khi token không tìm thấy', async () => {
    repo.findProfileByResetToken.mockResolvedValue(null);
    await expect(svc.resetPassword('bad-token', 'NewPass1!'))
      .rejects.toBeInstanceOf(AuthError);
  });

  it('throw AuthError khi token hết hạn', async () => {
    repo.findProfileByResetToken.mockResolvedValue(
      makeUser({ password_reset_expires: new Date(Date.now() - 1000).toISOString() })
    );

    await expect(svc.resetPassword('expired-token', 'NewPass1!'))
      .rejects.toBeInstanceOf(AuthError);
  });

  it('đặt lại mật khẩu và revoke tất cả refresh tokens', async () => {
    repo.findProfileByResetToken.mockResolvedValue(
      makeUser({ password_reset_expires: new Date(Date.now() + 3_600_000).toISOString() })
    );
    repo.clearPasswordResetToken.mockResolvedValue(undefined);
    repo.revokeAllUserTokens.mockResolvedValue(undefined);

    await svc.resetPassword('valid-raw-token', 'NewPass1!');

    expect(repo.clearPasswordResetToken).toHaveBeenCalledWith('uid-001', expect.any(String));
    expect(repo.revokeAllUserTokens).toHaveBeenCalledWith('uid-001');
  });
});
