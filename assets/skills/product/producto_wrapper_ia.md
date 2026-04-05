# Producto Wrapper de IA

- Un wrapper AI agrega valor sobre una API base (OpenAI, Anthropic) con UX, contexto o workflow especifico
- El valor no esta en acceso al modelo (commodity); esta en la experiencia, datos y workflow del usuario
- Defensibilidad: datos propietarios > fine-tuning > UX diferenciada > acceso a API (de mas a menos defensible)

## Capas de valor
- **Capa 1 — UX**: interfaz optimizada para el caso de uso (chat legal no es chat general)
- **Capa 2 — Contexto**: datos del usuario, historial, preferencias inyectados en cada query
- **Capa 3 — Workflow**: automatizaciones, integraciones, pipelines multi-paso
- **Capa 4 — Datos**: conocimiento propietario, modelos fine-tuned, evaluaciones acumuladas

## Modelo de negocio
- Pricing por valor entregado, no por token consumido (el usuario no entiende tokens)
- Tiers basados en features/uso: free tier para activacion, paid para retorno de valor
- Margen: costo API + compute + storage debe ser <40% del precio para sostenibilidad
- Metricas: CAC, LTV, gross margin por usuario, costo por query promedio

## Ventajas competitivas sostenibles
- Datos de usuario acumulados que mejoran el producto (flywheel)
- Integraciones profundas con herramientas del workflow del usuario
- Evaluaciones y fine-tuning basados en feedback real
- Comunidad y contenido generado por usuarios

## Anti-patrones
- Depender 100% de un solo proveedor de modelo (riesgo de pricing/API changes)
- No cachear respuestas similares (costos innecesarios)
- Cobrar solo por acceso sin agregar valor diferencial
