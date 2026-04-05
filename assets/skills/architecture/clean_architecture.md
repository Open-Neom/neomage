# Clean Architecture — Dependency-Driven Design

## Purpose

Structure applications so business logic is independent of frameworks, databases, and UI. Changes in external layers don't break the core.

## Layer Structure

```
Entities (innermost) → Use Cases → Interface Adapters → Frameworks (outermost)
```

**Entities**: Business objects with enterprise-wide rules. No framework dependencies.

**Use Cases**: Application-specific business rules. Orchestrate entity interactions. Define input/output boundaries.

**Interface Adapters**: Convert data between use cases and external formats. Controllers, presenters, gateways.

**Frameworks & Drivers**: Database, web framework, UI framework. The outermost, most volatile layer.

## Dependency Rule

Dependencies point INWARD only. Inner layers know nothing about outer layers. Use interfaces (abstract classes in Dart) to invert dependencies.

## Flutter/Dart Implementation

```
lib/
├── domain/          # Entities + Use Cases + Repository interfaces
│   ├── entities/
│   ├── usecases/
│   └── repositories/  (abstract)
├── data/            # Repository implementations + Data sources
│   ├── repositories/
│   ├── datasources/
│   └── models/       (DTOs)
└── presentation/    # UI + State management
    ├── pages/
    ├── widgets/
    └── controllers/
```

## Key Practices

- Repository pattern: abstract in domain, implement in data
- DTOs map to entities at the data layer boundary
- Use cases are single-responsibility: one public method
- Dependency injection wires everything together (Sint.find pattern)
- Test use cases independently of UI and data sources
