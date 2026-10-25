CREATE TABLE email_accounts (
 email TEXT PRIMARY KEY,
 user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE
);
ALTER TABLE api_devices ADD COLUMN expires_at TIMESTAMPTZ;
CREATE TABLE email_challenges (
 id TEXT PRIMARY KEY,
 token_hash TEXT NOT NULL,
 email TEXT NOT NULL,
 code_hash TEXT NOT NULL,
 mode TEXT NOT NULL CHECK (mode IN ('otp','link')),
 attempts INTEGER NOT NULL DEFAULT 0,
 expires_at TIMESTAMPTZ NOT NULL,
 used BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX email_challenges_expiry_idx ON email_challenges(expires_at);
CREATE TABLE auth_rate_limits (
 key TEXT PRIMARY KEY,
 count INTEGER NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL
);
