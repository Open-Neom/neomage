# Patrones de Agentes Autonomos

## Loop principal

Think (razonar) → Decide (planificar) → Act (ejecutar) → Observe (resultado) → repetir

Condicion de salida: sin mas tool calls = tarea completa. Max iterations como safety net.

## Diseno de herramientas

- Descripcion = prompt. Descripciones pobres = agente adivinando
- Principio de consolidacion: si un humano no puede decidir que tool usar, el agente tampoco
- Esquema claro: nombre, descripcion con contexto de uso, parametros tipados, formato de retorno
- Granularidad apropiada: ni demasiado finas ni demasiado gruesas

## Niveles de permisos

| Nivel | Cuando |
|-------|--------|
| AUTO | Operaciones de solo lectura (leer archivo, buscar) |
| ASK_ONCE | Escritura (crear/editar archivos) |
| ASK_EACH | Operaciones de sistema (ejecutar comandos) |
| NEVER | Operaciones peligrosas (sudo, delete masivo) |

## Patrones de seguridad

- Sandbox: validar paths dentro del workspace, lista blanca de comandos
- Audit logging habilitado
- Timeout en operaciones (30s default)
- Rollback disponible

## Gestion de contexto

- Inyeccion just-in-time (archivos, URLs, diagnosticos solo cuando se necesitan)
- Checkpoints: guardar estado (historial, contexto, workspace state) para resume en tareas largas
- Capturar git ref + dirty state para reproducibilidad

## Multi-modelo

Diferentes modelos para diferentes propositos:
- Rapido para planificacion
- Poderoso para razonamiento complejo
- Especializado para generacion de codigo

## Checklist de diseno

- Descomposicion clara de tareas
- Granularidad apropiada de herramientas
- Manejo de errores en cada paso
- Visibilidad de progreso al usuario
- Permisos implementados
- Undo/rollback disponible
