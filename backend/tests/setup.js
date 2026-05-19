'use strict';

// Env vars tối thiểu để config/auth.js không throw
process.env.JWT_ACCESS_SECRET  = 'test-access-secret-min-32-chars-long!!';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-min-32-chars-long!';
process.env.JWT_ACCESS_EXPIRES_IN  = '15m';
process.env.JWT_REFRESH_EXPIRES_IN = '7d';
process.env.NODE_ENV = 'test';
process.env.PORT     = '0';  // random port để integration tests không conflict

// Supabase stub (không cần kết nối thật)
process.env.SUPABASE_URL         = 'https://test.supabase.co';
process.env.SUPABASE_SERVICE_KEY = 'test-service-key';

// Google OAuth stub
process.env.GOOGLE_CLIENT_ID     = 'test-google-client-id';
process.env.GOOGLE_CLIENT_SECRET = 'test-google-client-secret';
