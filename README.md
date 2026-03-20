# Database Utilities

A Flutter app for managing multiple Microsoft SQL Server database profiles from mobile or desktop through a small Windows API.

## How It Works

- The Flutter app runs on mobile, desktop, or web
- A Node API runs on the Windows machine that has SQL Server access
- The API stores saved server settings in MySQL
- The API executes `sqlcmd` for attach and detach requests
- The app opens behind a launch password in the format `OneNetDDMMMyyyy`
- Your phone calls the API over your local network

## Current Features

- Add and manage multiple SQL Server database profiles
- Store server name, database name, MDF path, optional LDF path, and auth mode
- Save and load server settings from MySQL
- Support both Windows Authentication and SQL Server login
- Send attach and detach requests through the API
- Show the last API result and SQL command preview
- Lock app launch with today’s password

## API Setup

1. Copy `.env.example` to `.env`
2. Update the values in `.env`
3. Make sure MySQL is running and the configured user can create databases/tables
4. Make sure `sqlcmd` is installed on the Windows machine and available in `PATH`
5. Install backend dependencies:

```bash
cd server
npm install
```

6. Start the API:

```bash
cd server
node server.js
```

7. The API will listen using the `HOST` and `PORT` values from `.env`

## .env Settings

```env
API_BASE_URL=http://10.0.2.2:3000
HOST=0.0.0.0
PORT=3000
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=your_mysql_password
MYSQL_DATABASE=database_utilities
```

- Use `API_BASE_URL=http://10.0.2.2:3000` for the Android emulator
- Use `API_BASE_URL=http://127.0.0.1:3000` for Flutter web or desktop on the same PC
- Use `API_BASE_URL=http://YOUR_WINDOWS_IP:3000` for a real phone, for example `http://192.168.5.254:3000`
- After changing `.env`, fully restart the Flutter app so the new value is loaded

## Launch Password

- The app asks for today’s password before opening
- Format: `OneNetDDMMMyyyy`
- Example for March 21, 2026: `OneNet21Mar2026`

## Flutter Run

```bash
flutter pub get
flutter run
```

## API Routes

- `GET /health`
- `GET /api/settings/profiles`
- `POST /api/settings/profiles`
- `DELETE /api/settings/profiles/:id`
- `POST /api/databases/attach`
- `POST /api/databases/detach`
