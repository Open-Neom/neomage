# Documentacion de APIs

- La documentacion de API es el contrato entre proveedor y consumidor; precision es obligatoria
- OpenAPI/Swagger como fuente de verdad: genera docs, validacion, SDKs y mocks automaticamente
- Cada endpoint documenta: metodo, ruta, parametros (path, query, body), respuestas (200, 400, 401, 404, 500), ejemplos
- Los ejemplos deben ser ejecutables: curl, HTTPie, o SDK snippets que funcionen copy-paste
- Versionado explicito en URL o header; documentar cambios breaking con guia de migracion
- Errores tipados con codigos consistentes, mensaje descriptivo y link a documentacion
- Autenticacion documentada con flujo completo: obtener token, enviar token, refresh, errores

## Generacion automatizada
- OpenAPI spec → Swagger UI/Redoc para docs interactivas
- Spec → SDK clients (openapi-generator) para multiples lenguajes
- Spec → Mock servers para desarrollo paralelo frontend/backend
- Tests de contrato verifican que la implementacion cumple la spec

## Mejores practicas
- Agrupar endpoints por recurso/dominio, no por metodo HTTP
- Incluir rate limits, paginacion y filtrado en la guia general
- Changelog de API separado con fechas de deprecacion

## Anti-patrones
- Documentacion manual desincronizada del codigo
- Ejemplos con datos placeholder que no funcionan
- Errores genericos sin codigos ni mensajes utiles
