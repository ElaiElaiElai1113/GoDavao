# GoDavao

A Dynamic Ridesharing App for Davao City (Flutter + Supabase)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
- [Development](#development)
- [Deployment](#deployment)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Database Schema](#database-schema)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

GoDavao is a dynamic ridesharing system designed for Davao City, connecting passengers and drivers traveling along similar routes. Built with Flutter, Supabase, MapLibre GL, and OSRM, the system intelligently matches users through route-based heuristics and real-time updates.

This project was originally developed for academic purposes but is being improved for public and open-source use.

## Features

### Authentication & Roles
- Email/password login
- Passenger and Driver role detection
- User verification with valid ID upload
- Drivers upload vehicle photo + details
- Biometric authentication support (optional)

### Intelligent Routing & Maps
- Powered by MapLibre GL (no Mapbox tokens required)
- Color-coded routes:
  - Green = Main routes
  - Orange = Minor routes
- Route restrictions: pickup must be near a main route

### Passenger Features
- Select number of seats to book
- Real-time fare preview with full fare breakdown
- Track trip status in real-time
- View matched driver details (name, vehicle, route, ETA)

### Driver Features
- Add and manage routes
- Accept or decline ride requests
- Real-time passenger info
- Start/End ride with status timestamps

### Fare Calculation
Dynamic fare formula based on:
- Base fare (₱25)
- Distance rate (₱14 per km)
- Time rate (₱0.80 per minute)
- Booking fee (₱5)
- Minimum fare (₱70)
- Number of seats
- Carpool discount (2=6%, 3=12%, 4=20%, 5=25%)
- Night surcharge (+15% from 9 PM - 5 AM)
- Surge multiplier (0.7-2.0 based on demand/weather)
- Platform fee (15% of total)

**Booking Modes:**
- **Shared**: Regular shared ride with carpool discounts
- **Group Flat**: Group rate (+10% multiplier, bills 1 seat)
- **Pakyaw**: Full private ride (+20% multiplier, all seats)

**Distance-Proportional Shared Pricing:**
For shared rides with multiple passengers, fares are split proportionally based on each passenger's traveled distance. The total route fare is calculated first, then each passenger pays their fair share based on how much of the route they use.

Example: 10km route with ₱500 total fare
- Passenger A travels 10km → pays ₱333
- Passenger B travels 5km → pays ₱167

### Real-time Features
- Supabase Realtime subscriptions
- Instant updates for ride statuses and match events
- Local push notifications

## Tech Stack

### Frontend
- **Flutter** - Cross-platform UI framework
- **Dart** - Programming language
- **Provider** - State management
- **MapLibre GL** - Maps rendering

### Backend
- **Supabase** - PostgreSQL + Auth + Storage + Edge Functions
- **OSRM** - Open Source Routing Machine

### Development Tools
- **Docker** - Containerization
- **GitHub Actions** - CI/CD
- **Mocktail** - Testing framework
- **Logger** - Structured logging

## Getting Started

### Prerequisites
- Flutter SDK 3.7.2 or higher
- Dart SDK compatible with Flutter version
- Android Studio / VS Code (with Flutter extensions)
- For mobile: Android SDK (Android) or Xcode (iOS)
- Git

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/GoDavao.git
   cd GoDavao
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure environment variables**

   Create a `.env` file in the project root:
   ```env
   # Environment
   ENVIRONMENT=development

   # Supabase
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key

   # OSRM (optional - uses public server if not provided)
   OSRM_URL=https://router.project-osrm.org

   # Feature Flags
   ENABLE_DEBUG_TOOLS=true
   ENABLE_ANALYTICS=true
   LOG_LEVEL=debug
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

## Development

### Running the App

**Development Mode:**
```bash
flutter run
```

**Specific Device:**
```bash
flutter run -d chrome        # Web
flutter run -d macos         # macOS
flutter run -d windows       # Windows
flutter run -d android       # Android
flutter run -d ios           # iOS
```

**Release Build:**
```bash
flutter run --release
```

### Testing

**Run all tests:**
```bash
flutter test
```

**Run with coverage:**
```bash
flutter test --coverage
```

**Run integration tests:**
```bash
flutter test integration_test
```

**Run specific test file:**
```bash
flutter test test/unit/services/fare_service_test.dart
```

### Code Style

This project uses strict linting rules. To check your code:

```bash
flutter analyze
```

To auto-fix formatting:
```bash
dart format .
```

## Deployment

### Build for Production

**Android APK:**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Android App Bundle:**
```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

**iOS:**
```bash
flutter build ios --release
```

**Web:**
```bash
flutter build web --release
# Output: build/web/
```

### Docker Deployment

**Development:**
```bash
docker-compose up
```

**Production:**
```bash
docker-compose -f docker-compose.prod.yml up -d
```

**Build and test:**
```bash
docker-compose --profile test up
```

### CI/CD Pipeline

This project uses GitHub Actions for automated:
- Code analysis
- Unit and integration tests
- Android and iOS builds
- Security scanning

The pipeline runs on:
- Push to `main`, `develop`, `staging` branches
- Pull requests
- Manual trigger via workflow_dispatch

## Project Structure

```
lib/
├── common/                 # Shared utilities
│   ├── app_config.dart    # Environment configuration
│   ├── app_logger.dart    # Logging service
│   ├── error_handler.dart # Global error handling
│   ├── result.dart        # Result type for error handling
│   ├── secure_storage.dart # Secure key-value storage
│   └── validators.dart    # Input validation
├── core/                   # Core services
│   ├── fare_service.dart  # Fare calculation
│   ├── osrm_service.dart  # Routing service
│   └── weather_service.dart
├── features/               # Feature modules
│   ├── auth/              # Authentication
│   ├── rides/             # Ride management
│   ├── routes/            # Driver routes
│   ├── chat/              # Messaging
│   ├── payments/          # Payment processing
│   ├── ratings/           # User ratings
│   ├── safety/            # SOS, trusted contacts
│   └── ...
└── main.dart              # App entry point

test/
├── unit/                  # Unit tests
│   ├── common/           # Common utilities tests
│   └── services/         # Service tests
└── integration/           # Integration tests

.android/
.ios/
.web/
docker/
.github/
└── workflows/             # CI/CD configurations
```

## Architecture

### Design Patterns

- **Repository Pattern**: Data layer abstraction
- **Service Layer**: Business logic separation
- **Provider Pattern**: State management
- **Result Type**: Type-safe error handling

### Data Flow

```
UI Layer (Widgets)
    ↓
Provider (State Management)
    ↓
Service Layer (Business Logic)
    ↓
Repository Layer (Data Access)
    ↓
Supabase (Backend)
```

## Database Schema

| Table | Description |
|-------|-------------|
| `users` | User accounts and profiles |
| `vehicles` | Driver vehicle information |
| `driver_routes` | Driver route definitions |
| `ride_requests` | Passenger ride requests |
| `ride_matches` | Matched rides |
| `ride_status` | Ride status tracking |
| `ratings` | User ratings |
| `notifications` | Push notifications |

Full schema available in `/supabase/schema.sql`.

## Contributing

We welcome contributions! Please follow these guidelines:

### Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `flutter test`
5. Run analysis: `flutter analyze`
6. Format code: `dart format .`
7. Commit with conventional commits
8. Push and create a pull request

### Commit Convention

```
feat: add new feature
fix: bug fix
docs: documentation changes
style: formatting changes
refactor: code refactoring
test: adding/updating tests
chore: maintenance tasks
```

### Code Style

- Follow effective Dart guidelines
- Use strict type casting
- Prefer const constructors
- Document public APIs
- Write tests for new features

## License

This project is licensed under the MIT License.

You are free to use, modify, and distribute the project with attribution.

## About GoDavao

"Connecting Davao, one shared ride at a time."

Built with care by students from Ateneo de Davao University.

For questions or support, please open an issue on GitHub.
