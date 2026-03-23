const http = require('http');
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
const crypto = require('crypto');
const { spawn } = require('child_process');

loadEnv();

const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';
const MYSQL_HOST = process.env.MYSQL_HOST || '127.0.0.1';
const MYSQL_PORT = parseInt(process.env.MYSQL_PORT || '3306', 10);
const MYSQL_USER = process.env.MYSQL_USER || 'root';
const MYSQL_PASSWORD = process.env.MYSQL_PASSWORD || '';
const MYSQL_DATABASE = process.env.MYSQL_DATABASE || 'database_utilities';
const API_BASE_URL = process.env.API_BASE_URL || '';
const VALID_USER_TYPES = new Set(['admin', 'user']);

let pool;

function loadEnv() {
  const envPath = path.resolve(__dirname, '..', '.env');

  if (!fs.existsSync(envPath)) {
    return;
  }

  const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);

  for (const rawLine of lines) {
    const line = rawLine.trim();

    if (!line || line.startsWith('#')) {
      continue;
    }

    const separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 1).trim();

    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}

async function initializeStorage() {
  const bootstrapConnection = await mysql.createConnection({
    host: MYSQL_HOST,
    port: MYSQL_PORT,
    user: MYSQL_USER,
    password: MYSQL_PASSWORD,
  });

  await bootstrapConnection.query(
    `CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE.replace(/`/g, '')}\``,
  );
  await bootstrapConnection.end();

  pool = mysql.createPool({
    host: MYSQL_HOST,
    port: MYSQL_PORT,
    user: MYSQL_USER,
    password: MYSQL_PASSWORD,
    database: MYSQL_DATABASE,
    waitForConnections: true,
    connectionLimit: 10,
  });

  await pool.query(`
    CREATE TABLE IF NOT EXISTS database_profiles (
      id INT NOT NULL AUTO_INCREMENT,
      server VARCHAR(255) NOT NULL,
      database_name VARCHAR(255) NOT NULL,
      mdf_path TEXT NOT NULL,
      ldf_path TEXT NULL,
      authentication_mode VARCHAR(20) NOT NULL,
      username VARCHAR(255) NULL,
      password TEXT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_security_settings (
      id INT NOT NULL,
      default_user_type VARCHAR(20) NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(
    `INSERT INTO app_security_settings (id, default_user_type)
     VALUES (1, 'admin')
     ON DUPLICATE KEY UPDATE default_user_type = default_user_type`,
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_client_settings (
      id INT NOT NULL,
      company_name VARCHAR(255) NOT NULL,
      branch_name VARCHAR(255) NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(
    `INSERT INTO app_client_settings (id, company_name, branch_name)
     VALUES (1, 'Database Utilities', 'Main Branch')
     ON DUPLICATE KEY UPDATE company_name = company_name, branch_name = branch_name`,
  );

  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_users (
      id INT NOT NULL AUTO_INCREMENT,
      username VARCHAR(255) NOT NULL,
      password_hash TEXT NOT NULL,
      password_salt VARCHAR(255) NOT NULL,
      role VARCHAR(20) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_username (username)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS activity_logs (
      id INT NOT NULL AUTO_INCREMENT,
      actor_username VARCHAR(255) NOT NULL,
      actor_role VARCHAR(20) NOT NULL,
      action_name VARCHAR(255) NOT NULL,
      action_details TEXT NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  const [adminRows] = await pool.query(
    'SELECT id FROM app_users WHERE username = ? LIMIT 1',
    ['admin'],
  );

  if (adminRows.length === 0) {
    const { passwordHash, passwordSalt } = hashPassword(buildBootstrapPassword());
    await pool.query(
      `INSERT INTO app_users (username, password_hash, password_salt, role)
       VALUES (?, ?, ?, ?)`,
      ['admin', passwordHash, passwordSalt, 'admin'],
    );
  }
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  });
  res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';

    req.on('data', (chunk) => {
      body += chunk.toString();
      if (body.length > 1024 * 1024) {
        reject(new Error('Request body is too large.'));
      }
    });

    req.on('end', () => {
      if (!body) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(body));
      } catch (_) {
        reject(new Error('Invalid JSON body.'));
      }
    });

    req.on('error', reject);
  });
}

function escapeSqlString(value) {
  return String(value || '').replace(/'/g, "''");
}

function escapeSqlIdentifier(value) {
  return String(value || '').replace(/]/g, ']]');
}

function validateProfile(payload) {
  const missing = [];

  if (!payload.server) missing.push('server');
  if (!payload.databaseName) missing.push('databaseName');
  if (!payload.mdfPath) missing.push('mdfPath');
  if (!payload.authenticationMode) missing.push('authenticationMode');

  if (payload.authenticationMode === 'sqlServer') {
    if (!payload.username) missing.push('username');
    if (!payload.password) missing.push('password');
  }

  return missing;
}

function normalizeUserType(value) {
  return VALID_USER_TYPES.has(value) ? value : 'admin';
}

function buildBootstrapPassword() {
  const now = new Date();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const day = String(now.getDate()).padStart(2, '0');
  const month = months[now.getMonth()];
  const year = String(now.getFullYear());
  return `OneNet${day}${month}${year}`;
}

function hashPassword(password) {
  const passwordSalt = crypto.randomBytes(16).toString('hex');
  const passwordHash = crypto.scryptSync(password, passwordSalt, 64).toString('hex');
  return { passwordHash, passwordSalt };
}

function verifyPassword(password, passwordHash, passwordSalt) {
  const derivedHash = crypto.scryptSync(password, passwordSalt, 64).toString('hex');
  return crypto.timingSafeEqual(Buffer.from(derivedHash, 'hex'), Buffer.from(passwordHash, 'hex'));
}

async function logActivity({
  actorUsername = 'system',
  actorRole = 'system',
  actionName,
  actionDetails,
}) {
  await pool.query(
    `INSERT INTO activity_logs (actor_username, actor_role, action_name, action_details)
     VALUES (?, ?, ?, ?)`,
    [actorUsername, actorRole, actionName, actionDetails],
  );
}

function buildAttachQuery(payload) {
  const databaseName = escapeSqlIdentifier(payload.databaseName);
  const databaseString = escapeSqlString(payload.databaseName);
  const mdf = escapeSqlString(payload.mdfPath);

  if (payload.ldfPath && String(payload.ldfPath).trim()) {
    const ldf = escapeSqlString(payload.ldfPath);
    return `
IF DB_ID(N'${databaseString}') IS NOT NULL
BEGIN
    THROW 50000, 'Database already exists.', 1;
END
CREATE DATABASE [${databaseName}]
ON
(FILENAME = N'${mdf}'),
(FILENAME = N'${ldf}')
FOR ATTACH;
`;
  }

  return `
IF DB_ID(N'${databaseString}') IS NOT NULL
BEGIN
    THROW 50000, 'Database already exists.', 1;
END
CREATE DATABASE [${databaseName}]
ON
(FILENAME = N'${mdf}')
FOR ATTACH_REBUILD_LOG;
`;
}

function buildDetachQuery(payload) {
  const databaseName = escapeSqlIdentifier(payload.databaseName);
  const databaseString = escapeSqlString(payload.databaseName);

  return `
IF DB_ID(N'${databaseString}') IS NULL
BEGIN
    THROW 50000, 'Database not found.', 1;
END
ALTER DATABASE [${databaseName}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
EXEC master.dbo.sp_detach_db @dbname = N'${databaseString}';
  `;
}

function buildAttachmentStatusQuery(payload) {
  const databaseString = escapeSqlString(payload.databaseName);
  const mdfPath = escapeSqlString(String(payload.mdfPath || '').replace(/\//g, '\\'));
  const ldfPath = escapeSqlString(String(payload.ldfPath || '').replace(/\//g, '\\'));
  return `
SET NOCOUNT ON;
IF DB_ID(N'${databaseString}') IS NULL
BEGIN
    PRINT '__DETACHED__';
END
ELSE
BEGIN
    DECLARE @expectedMdf NVARCHAR(4000) = LOWER(N'${mdfPath}');
    DECLARE @expectedLdf NVARCHAR(4000) = LOWER(N'${ldfPath}');

    IF EXISTS (
        SELECT 1
        FROM sys.master_files
        WHERE database_id = DB_ID(N'${databaseString}')
          AND type_desc = 'ROWS'
          AND LOWER(physical_name) = @expectedMdf
    )
    AND (
        @expectedLdf = ''
        OR EXISTS (
            SELECT 1
            FROM sys.master_files
            WHERE database_id = DB_ID(N'${databaseString}')
              AND type_desc = 'LOG'
              AND LOWER(physical_name) = @expectedLdf
        )
    )
    BEGIN
        PRINT '__ATTACHED__';
    END
    ELSE
    BEGIN
        PRINT '__NAME_CONFLICT__';
    END
END
`;
}

function buildSqlcmdArgs(payload, query) {
  const normalizedQuery = query
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .join(' ');

  const args = ['-S', payload.server];

  if (payload.authenticationMode === 'windows') {
    args.push('-E');
  } else {
    args.push('-U', payload.username, '-P', payload.password);
  }

  args.push('-b', '-Q', normalizedQuery);

  const displayArgs = ['-S', payload.server];

  if (payload.authenticationMode === 'windows') {
    displayArgs.push('-E');
  } else {
    displayArgs.push('-U', payload.username, '-P', '********');
  }

  displayArgs.push('-b', '-Q', normalizedQuery);

  return {
    args,
    displayCommand: `sqlcmd ${displayArgs.join(' ')}`,
  };
}

function runSqlcmd(payload, query) {
  return new Promise((resolve) => {
    const { args, displayCommand } = buildSqlcmdArgs(payload, query);
    const child = spawn('sqlcmd', args, {
      windowsHide: true,
    });

    let stdoutText = '';
    let stderrText = '';

    child.stdout.on('data', (chunk) => {
      stdoutText += chunk.toString();
    });

    child.stderr.on('data', (chunk) => {
      stderrText += chunk.toString();
    });

    child.on('error', (error) => {
      resolve({
        success: false,
        message:
          `Could not start sqlcmd. Install SQL Server command-line tools and make sure sqlcmd is in PATH. Details: ${error.message}`,
        command: displayCommand,
      });
    });

    child.on('close', (code) => {
      const combined = [stdoutText.trim(), stderrText.trim()]
        .filter(Boolean)
        .join('\n');

      if (code === 0) {
        resolve({
          success: true,
          message: combined || 'Operation completed successfully.',
          command: displayCommand,
        });
        return;
      }

      resolve({
        success: false,
        message: combined || `SQL command failed with exit code ${code}.`,
        command: displayCommand,
      });
    });
  });
}

async function resolveAttachmentStatus(profile) {
  const result = await runSqlcmd(profile, buildAttachmentStatusQuery(profile));
  if (!result.success) {
    return 'unknown';
  }

  if (result.message.includes('__ATTACHED__')) {
    return 'attached';
  }

  if (result.message.includes('__DETACHED__')) {
    return 'detached';
  }

  if (result.message.includes('__NAME_CONFLICT__')) {
    return 'nameConflict';
  }

  return 'unknown';
}

async function listProfiles() {
  const [rows] = await pool.query(
    `SELECT id, server, database_name, mdf_path, ldf_path, authentication_mode, username, password
     FROM database_profiles
     ORDER BY id DESC`,
  );

  const profiles = rows.map((row) => ({
    id: row.id,
    server: row.server,
    databaseName: row.database_name,
    mdfPath: row.mdf_path,
    ldfPath: row.ldf_path || '',
    authenticationMode: row.authentication_mode,
    username: row.username || '',
    password: row.password || '',
  }));

  return Promise.all(
    profiles.map(async (profile) => ({
      ...profile,
      attachmentStatus: await resolveAttachmentStatus(profile),
    })),
  );
}

async function getSecurityPreference() {
  const [rows] = await pool.query(
    `SELECT default_user_type
     FROM app_security_settings
     WHERE id = 1
     LIMIT 1`,
  );

  return {
    defaultUserType: normalizeUserType(rows[0]?.default_user_type),
  };
}

async function saveSecurityPreference(payload) {
  const defaultUserType = String(payload.defaultUserType || payload.default_user_type || '').trim();
  if (!VALID_USER_TYPES.has(defaultUserType)) {
    throw new Error('Invalid user type. Allowed values: admin, user.');
  }

  await pool.query(
    `INSERT INTO app_security_settings (id, default_user_type)
     VALUES (1, ?)
     ON DUPLICATE KEY UPDATE default_user_type = VALUES(default_user_type)`,
    [defaultUserType],
  );
}

async function getClientSettings() {
  const [rows] = await pool.query(
    `SELECT company_name, branch_name
     FROM app_client_settings
     WHERE id = 1
     LIMIT 1`,
  );

  return {
    companyName: rows[0]?.company_name || 'Database Utilities',
    branchName: rows[0]?.branch_name || 'Main Branch',
  };
}

async function saveClientSettings(payload) {
  const companyName = String(payload.companyName || payload.company_name || '').trim();
  const branchName = String(payload.branchName || payload.branch_name || '').trim();

  if (!companyName || !branchName) {
    throw new Error('Company name and branch name are required.');
  }

  await pool.query(
    `INSERT INTO app_client_settings (id, company_name, branch_name)
     VALUES (1, ?, ?)
     ON DUPLICATE KEY UPDATE company_name = VALUES(company_name), branch_name = VALUES(branch_name)`,
    [companyName, branchName],
  );
}

async function listUsers() {
  const [rows] = await pool.query(
    `SELECT id, username, role, created_at, updated_at
     FROM app_users
     ORDER BY username ASC`,
  );

  return rows.map((row) => ({
    id: row.id,
    username: row.username,
    role: normalizeUserType(row.role),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }));
}

async function upsertUser(payload) {
  const username = String(payload.username || '').trim();
  const role = normalizeUserType(String(payload.role || '').trim());
  const password = String(payload.password || '');

  if (!username) {
    throw new Error('Username is required.');
  }

  if (payload.id) {
    const [rows] = await pool.query(
      'SELECT id, username FROM app_users WHERE id = ? LIMIT 1',
      [payload.id],
    );
    if (rows.length === 0) {
      throw new Error('User not found.');
    }

    await pool.query(
      'UPDATE app_users SET username = ?, role = ? WHERE id = ?',
      [username, role, payload.id],
    );

    if (password) {
      const { passwordHash, passwordSalt } = hashPassword(password);
      await pool.query(
        'UPDATE app_users SET password_hash = ?, password_salt = ? WHERE id = ?',
        [passwordHash, passwordSalt, payload.id],
      );
    }

    return 'User updated successfully.';
  }

  if (!password) {
    throw new Error('Password is required for a new user.');
  }

  const { passwordHash, passwordSalt } = hashPassword(password);
  await pool.query(
    `INSERT INTO app_users (username, password_hash, password_salt, role)
     VALUES (?, ?, ?, ?)`,
    [username, passwordHash, passwordSalt, role],
  );
  return 'User created successfully.';
}

async function deleteUser(id) {
  const [existingRows] = await pool.query(
    'SELECT username FROM app_users WHERE id = ? LIMIT 1',
    [id],
  );
  if (existingRows.length === 0) {
    return false;
  }
  if (existingRows[0].username === 'admin') {
    throw new Error('The default admin account cannot be deleted.');
  }

  const [result] = await pool.query('DELETE FROM app_users WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

async function updateUserPassword(payload) {
  const id = parseInt(payload.id, 10);
  const password = String(payload.password || '');
  if (!Number.isFinite(id)) {
    throw new Error('Invalid user id.');
  }
  if (!password) {
    throw new Error('Password is required.');
  }

  const { passwordHash, passwordSalt } = hashPassword(password);
  const [result] = await pool.query(
    'UPDATE app_users SET password_hash = ?, password_salt = ? WHERE id = ?',
    [passwordHash, passwordSalt, id],
  );
  if (result.affectedRows === 0) {
    throw new Error('User not found.');
  }
}

async function authenticateUser(payload) {
  const username = String(payload.username || '').trim();
  const password = String(payload.password || '');

  if (!username || !password) {
    throw new Error('Username and password are required.');
  }

  const [rows] = await pool.query(
    `SELECT id, username, password_hash, password_salt, role
     FROM app_users
     WHERE username = ?
     LIMIT 1`,
    [username],
  );

  if (rows.length === 0) {
    throw new Error('Invalid username or password.');
  }

  const user = rows[0];
  if (!verifyPassword(password, user.password_hash, user.password_salt)) {
    throw new Error('Invalid username or password.');
  }

  return {
    id: user.id,
    username: user.username,
    role: normalizeUserType(user.role),
  };
}

async function listActivityLogs(limit = 100) {
  const safeLimit = Math.min(Math.max(parseInt(limit, 10) || 100, 1), 500);
  const [rows] = await pool.query(
    `SELECT id, actor_username, actor_role, action_name, action_details, created_at
     FROM activity_logs
     ORDER BY id DESC
     LIMIT ?`,
    [safeLimit],
  );

  return rows.map((row) => ({
    id: row.id,
    actorUsername: row.actor_username,
    actorRole: row.actor_role,
    actionName: row.action_name,
    actionDetails: row.action_details,
    createdAt: row.created_at,
  }));
}

async function createActivityLog(payload) {
  await logActivity({
    actorUsername: String(payload.actorUsername || 'system'),
    actorRole: String(payload.actorRole || 'system'),
    actionName: String(payload.actionName || 'custom_event'),
    actionDetails: String(payload.actionDetails || ''),
  });
}

async function saveProfile(payload) {
  const values = [
    payload.server,
    payload.databaseName,
    payload.mdfPath,
    payload.ldfPath || '',
    payload.authenticationMode,
    payload.username || '',
    payload.password || '',
  ];

  if (payload.id) {
    await pool.query(
      `UPDATE database_profiles
       SET server = ?,
           database_name = ?,
           mdf_path = ?,
           ldf_path = ?,
           authentication_mode = ?,
           username = ?,
           password = ?
       WHERE id = ?`,
      [...values, payload.id],
    );
    return 'Settings updated successfully.';
  }

  await pool.query(
    `INSERT INTO database_profiles (
      server,
      database_name,
      mdf_path,
      ldf_path,
      authentication_mode,
      username,
      password
    ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
    values,
  );
  return 'Settings saved successfully.';
}

async function deleteProfile(id) {
  const [result] = await pool.query('DELETE FROM database_profiles WHERE id = ?', [id]);
  return result.affectedRows > 0;
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  if (req.method === 'GET' && req.url === '/health') {
    try {
      const profiles = await listProfiles();
      const primaryProfile = profiles[0] || null;
      const sqlDatabaseName = primaryProfile ? primaryProfile.databaseName : 'not configured';

      sendJson(res, 200, {
        success: true,
        message: `API server is running securely. Active database profile: ${sqlDatabaseName}.`,
        sqlDatabaseName,
        storage: 'configured',
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      sendJson(res, 500, {
        success: false,
        message: error.message || 'Could not build health status.',
      });
    }
    return;
  }

  if (req.method === 'GET' && req.url === '/api/settings/profiles') {
    try {
      const profiles = await listProfiles();
      sendJson(res, 200, {
        success: true,
        profiles,
      });
    } catch (error) {
      sendJson(res, 500, {
        success: false,
        message: error.message || 'Could not load profiles from MySQL.',
      });
    }
    return;
  }

  if (req.method === 'GET' && req.url === '/api/security/preferences') {
    try {
      const preference = await getSecurityPreference();
      sendJson(res, 200, {
        success: true,
        ...preference,
      });
    } catch (error) {
      sendJson(res, 500, {
        success: false,
        message: error.message || 'Could not load security preference.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/security/preferences') {
    try {
      const payload = await readJsonBody(req);
      await saveSecurityPreference(payload);
      sendJson(res, 200, {
        success: true,
        message: 'Security preference saved successfully.',
      });
    } catch (error) {
      sendJson(res, 400, {
        success: false,
        message: error.message || 'Could not save security preference.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/auth/login') {
    try {
      const payload = await readJsonBody(req);
      const user = await authenticateUser(payload);
      const clientSettings = await getClientSettings();
      await logActivity({
        actorUsername: user.username,
        actorRole: user.role,
        actionName: 'login',
        actionDetails: `User ${user.username} signed in successfully.`,
      });
      sendJson(res, 200, {
        success: true,
        user,
        clientSettings,
      });
    } catch (error) {
      sendJson(res, 401, {
        success: false,
        message: error.message || 'Authentication failed.',
      });
    }
    return;
  }

  if (req.method === 'GET' && req.url === '/api/client/settings') {
    try {
      const settings = await getClientSettings();
      sendJson(res, 200, {
        success: true,
        ...settings,
      });
    } catch (error) {
      sendJson(res, 500, {
        success: false,
        message: error.message || 'Could not load client settings.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/client/settings') {
    try {
      const payload = await readJsonBody(req);
      await saveClientSettings(payload);
      await logActivity({
        actorUsername: String(payload.actorUsername || 'admin'),
        actorRole: String(payload.actorRole || 'admin'),
        actionName: 'save_client_settings',
        actionDetails: `Updated company to "${payload.companyName}" and branch to "${payload.branchName}".`,
      });
      sendJson(res, 200, {
        success: true,
        message: 'Client settings saved successfully.',
      });
    } catch (error) {
      sendJson(res, 400, {
        success: false,
        message: error.message || 'Could not save client settings.',
      });
    }
    return;
  }

  if (req.method === 'GET' && req.url === '/api/security/users') {
    try {
      const users = await listUsers();
      sendJson(res, 200, {
        success: true,
        users,
      });
    } catch (error) {
      sendJson(res, 500, {
        success: false,
        message: error.message || 'Could not load users.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/security/users') {
    try {
      const payload = await readJsonBody(req);
      const message = await upsertUser(payload);
      await logActivity({
        actorUsername: String(payload.actorUsername || 'admin'),
        actorRole: String(payload.actorRole || 'admin'),
        actionName: payload.id ? 'update_user' : 'create_user',
        actionDetails: `${message} Username: ${payload.username}. Role: ${payload.role}.`,
      });
      sendJson(res, 200, {
        success: true,
        message,
      });
    } catch (error) {
      sendJson(res, 400, {
        success: false,
        message: error.message || 'Could not save user.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/security/users/password') {
    try {
      const payload = await readJsonBody(req);
      await updateUserPassword(payload);
      await logActivity({
        actorUsername: String(payload.actorUsername || 'admin'),
        actorRole: String(payload.actorRole || 'admin'),
        actionName: 'change_user_password',
        actionDetails: `Changed password for user id ${payload.id}.`,
      });
      sendJson(res, 200, {
        success: true,
        message: 'User password updated successfully.',
      });
    } catch (error) {
      sendJson(res, 400, {
        success: false,
        message: error.message || 'Could not change user password.',
      });
    }
    return;
  }

  if (req.method === 'DELETE' && req.url.startsWith('/api/security/users/')) {
    try {
      const requestUrl = new URL(req.url, 'http://localhost');
      const id = parseInt(requestUrl.pathname.split('/').pop(), 10);
      if (!Number.isFinite(id)) {
        sendJson(res, 400, {
          success: false,
          message: 'Invalid user id.',
        });
        return;
      }

      const removed = await deleteUser(id);
      if (removed) {
        await logActivity({
          actorUsername: String(requestUrl.searchParams.get('actorUsername') || 'admin'),
          actorRole: String(requestUrl.searchParams.get('actorRole') || 'admin'),
          actionName: 'delete_user',
          actionDetails: `Deleted user id ${id}.`,
        });
      }
      sendJson(res, removed ? 200 : 404, {
        success: removed,
        message: removed ? 'User deleted successfully.' : 'User not found.',
      });
    } catch (error) {
      sendJson(res, 400, {
        success: false,
        message: error.message || 'Could not delete user.',
      });
    }
    return;
  }

  if (req.method === 'GET' && req.url.startsWith('/api/activity-logs')) {
    try {
      const requestUrl = new URL(req.url, 'http://localhost');
      const logs = await listActivityLogs(requestUrl.searchParams.get('limit'));
      sendJson(res, 200, {
        success: true,
        logs,
      });
    } catch (error) {
      sendJson(res, 500, {
        success: false,
        message: error.message || 'Could not load activity logs.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/activity-logs') {
    try {
      const payload = await readJsonBody(req);
      await createActivityLog(payload);
      sendJson(res, 200, {
        success: true,
        message: 'Activity recorded successfully.',
      });
    } catch (error) {
      sendJson(res, 400, {
        success: false,
        message: error.message || 'Could not record activity.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/settings/profiles') {
    try {
      const payload = await readJsonBody(req);
      const missing = validateProfile(payload);

      if (missing.length > 0) {
        sendJson(res, 400, {
          success: false,
          message: `Missing required fields: ${missing.join(', ')}`,
        });
        return;
      }

      const message = await saveProfile(payload);
      await logActivity({
        actorUsername: String(payload.actorUsername || 'admin'),
        actorRole: String(payload.actorRole || 'admin'),
        actionName: payload.id ? 'update_profile' : 'create_profile',
        actionDetails: `${message} Database: ${payload.databaseName}.`,
      });
      sendJson(res, 200, {
        success: true,
        message,
      });
    } catch (error) {
      sendJson(res, 500, {
        success: false,
        message: error.message || 'Could not save profile to MySQL.',
      });
    }
    return;
  }

  if (req.method === 'DELETE' && req.url.startsWith('/api/settings/profiles/')) {
    try {
      const requestUrl = new URL(req.url, 'http://localhost');
      const id = parseInt(requestUrl.pathname.split('/').pop(), 10);
      if (!Number.isFinite(id)) {
        sendJson(res, 400, {
          success: false,
          message: 'Invalid profile id.',
        });
        return;
      }

      const removed = await deleteProfile(id);
      if (removed) {
        await logActivity({
          actorUsername: String(requestUrl.searchParams.get('actorUsername') || 'admin'),
          actorRole: String(requestUrl.searchParams.get('actorRole') || 'admin'),
          actionName: 'delete_profile',
          actionDetails: `Deleted profile id ${id}.`,
        });
      }
      sendJson(res, removed ? 200 : 404, {
        success: removed,
        message: removed ? 'Settings deleted successfully.' : 'Settings not found.',
      });
    } catch (error) {
      sendJson(res, 500, {
        success: false,
        message: error.message || 'Could not delete profile from MySQL.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/databases/attach') {
    try {
      const payload = await readJsonBody(req);
      const missing = validateProfile(payload);

      if (missing.length > 0) {
        sendJson(res, 400, {
          success: false,
          message: `Missing required fields: ${missing.join(', ')}`,
        });
        return;
      }

      const result = await runSqlcmd(payload, buildAttachQuery(payload));
      await logActivity({
        actorUsername: String(payload.actorUsername || 'system'),
        actorRole: String(payload.actorRole || 'system'),
        actionName: 'attach_database',
        actionDetails: `${payload.databaseName}: ${result.message}`,
      });
      sendJson(res, result.success ? 200 : 500, result);
    } catch (error) {
      sendJson(res, 400, {
        success: false,
        message: error.message || 'Unable to process request.',
      });
    }
    return;
  }

  if (req.method === 'POST' && req.url === '/api/databases/detach') {
    try {
      const payload = await readJsonBody(req);
      const missing = validateProfile(payload);

      if (missing.length > 0) {
        sendJson(res, 400, {
          success: false,
          message: `Missing required fields: ${missing.join(', ')}`,
        });
        return;
      }

      const result = await runSqlcmd(payload, buildDetachQuery(payload));
      await logActivity({
        actorUsername: String(payload.actorUsername || 'system'),
        actorRole: String(payload.actorRole || 'system'),
        actionName: 'detach_database',
        actionDetails: `${payload.databaseName}: ${result.message}`,
      });
      sendJson(res, result.success ? 200 : 500, result);
    } catch (error) {
      sendJson(res, 400, {
        success: false,
        message: error.message || 'Unable to process request.',
      });
    }
    return;
  }

  sendJson(res, 404, {
    success: false,
    message: 'Route not found.',
  });
});

function maskSecret(value) {
  if (!value) {
    return '(empty)';
  }

  return '*'.repeat(Math.max(value.length, 8));
}

function logStartupSettings() {
  console.log('================ API SERVER SETTINGS ================');
  console.log(`API_BASE_URL: ${API_BASE_URL || '(not set)'}`);
  console.log(`HOST: ${HOST}`);
  console.log(`PORT: ${PORT}`);
  console.log(`MYSQL_HOST: ${MYSQL_HOST}`);
  console.log(`MYSQL_PORT: ${MYSQL_PORT}`);
  console.log(`MYSQL_USER: ${MYSQL_USER}`);
  console.log(`MYSQL_PASSWORD: ${maskSecret(MYSQL_PASSWORD)}`);
  console.log(`MYSQL_DATABASE: ${MYSQL_DATABASE}`);
  console.log('====================================================');
}

initializeStorage()
  .then(() => {
    server.listen(PORT, HOST, () => {
      logStartupSettings();
      console.log(`Database Utilities API listening on http://${HOST}:${PORT}`);
      console.log(`MySQL storage ready on ${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}`);
    });
  })
  .catch((error) => {
    console.error('Failed to start API:', error.message);
    process.exit(1);
  });
