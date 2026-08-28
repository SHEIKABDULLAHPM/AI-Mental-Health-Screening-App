# Synora Flutter application

Clean-architecture, feature-based Flutter client for MindEase.

> **Platform scaffolding:** this repository ships **with** the generated
> `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/` folders, plus
> `.metadata` and `.vscode/`. They were produced with the Flutter CLI so the
> app is immediately buildable. Regenerate them only if you rename the package:
>
> ```bash
> flutter create --org com.mindease --project-name mindease .
> ```
> The package name is `mindease` (must match `pubspec.yaml`); `flutter create`
> will **overwrite** `pubspec.yaml`/`lib/main.dart`, so run it before adding
> custom sources if scaffolding from scratch.

## Structure (feature-based clean architecture)

```
lib/
├── app.dart                  # root widget, themes, routing
├── main.dart                 # entry point
├── core/                     # cross-cutting concerns
│   ├── config/               # AppConfig (--dart-define)
│   ├── constants/
│   ├── error/                # failures + error mapper
│   ├── network/              # DioClient (auth interceptor)
│   ├── theme/                # colors, spacing, theme
│   └── utils/
├── features/
│   ├── auth/                 # login, session, profile
│   ├── screening/            # questionnaires, submit, results
│   ├── support/              # crisis resources, guidance
│   └── dashboard/            # post-login hub
│       ├── data/             # datasources, models, repositories (impl)
│       │   └── datasources remote / local
│       ├── domain/           # entities + repository contracts
│       └── presentation/     # state (controllers) + screens
└── shared/
    └── widgets/              # reusable UI
```

## Run

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
```

`10.0.2.2` is the Android emulator alias for the host machine (where Docker
publishes the backend on localhost).