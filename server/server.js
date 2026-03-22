const http = require('http');
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
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

async function listProfiles() {
  const [rows] = await pool.query(
    `SELECT id, server, database_name, mdf_path, ldf_path, authentication_mode, username, password
     FROM database_profiles
     ORDER BY id DESC`,
  );

  return rows.map((row) => ({
    id: row.id,
    server: row.server,
    databaseName: row.database_name,
    mdfPath: row.mdf_path,
    ldfPath: row.ldf_path || '',
    authenticationMode: row.authentication_mode,
    username: row.username || '',
    password: row.password || '',
  }));
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
      const apiHost = req.headers.host || `${HOST}:${PORT}`;
      const publicApiAddress = API_BASE_URL && API_BASE_URL.trim().length > 0
        ? API_BASE_URL.trim()
        : `http://${apiHost}`;
      const forwardedFor = req.headers['x-forwarded-for'];
      const remoteAddress =
        (Array.isArray(forwardedFor) ? forwardedFor[0] : forwardedFor?.split(',')[0]?.trim()) ||
        req.socket.remoteAddress ||
        'unknown';
      const sqlServerName = primaryProfile ? primaryProfile.server : 'not configured';
      const sqlDatabaseName = primaryProfile ? primaryProfile.databaseName : 'not configured';
      const sqlServerPort = primaryProfile && String(primaryProfile.server).includes(',')
        ? String(primaryProfile.server).split(',').pop().trim()
        : 'default';

      sendJson(res, 200, {
        success: true,
        message: `API server ${publicApiAddress} is running. Client remote address: ${remoteAddress}. SQL Server: ${sqlServerName}. SQL port: ${sqlServerPort}. Database: ${sqlDatabaseName}.`,
        apiServerAddress: apiHost,
        publicApiAddress,
        clientRemoteAddress: remoteAddress,
        sqlServerName,
        sqlServerPort,
        sqlDatabaseName,
        storage: `mysql://${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}`,
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
      const id = parseInt(req.url.split('/').pop(), 10);
      if (!Number.isFinite(id)) {
        sendJson(res, 400, {
          success: false,
          message: 'Invalid profile id.',
        });
        return;
      }

      const removed = await deleteProfile(id);
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
