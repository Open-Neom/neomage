# Producto de Inteligencia Artificial

- Un producto AI resuelve un problema real del usuario; la IA es el medio, no el fin
- Empezar con el problema, no con la tecnologia: "los usuarios necesitan X" > "usemos GPT para Y"
- El valor se mide por resultado del usuario, no por sofisticacion del modelo
- MVP AI: reglas + heuristicas como base, modelo AI como mejora incremental

## Arquitectura de producto AI
- Input pipeline: recibir, validar, preprocesar datos del usuario
- Modelo/Inference: LLM, ML model, o hibrido reglas+modelo
- Output processing: formatear, validar, post-procesar respuesta
- Feedback loop: capturar satisfaccion del usuario para mejorar iterativamente

## Decisiones clave
- Build vs buy: API externa (rapido, costoso) vs modelo propio (control, inversion)
- Latencia vs calidad: modelo grande (mejor, lento) vs modelo pequeno (rapido, suficiente)
- Costo por query: presupuesto de tokens, caching agresivo, tiered models por complejidad
- Evaluacion: metricas automaticas + evaluacion humana; A/B testing con usuarios reales

## Experiencia de usuario AI
- Establecer expectativas claras: que puede y que no puede hacer el AI
- Transparencia: mostrar confianza, fuentes, razonamiento
- Graceful degradation: respuesta util incluso cuando el modelo falla
- Human-in-the-loop: escalacion a humano cuando AI no tiene confianza suficiente

## Anti-patrones
- Lanzar sin evaluacion sistematica de calidad del modelo
- Prometer capacidades que el modelo no tiene de forma confiable
- Ignorar costos de inference en el modelo de negocio
