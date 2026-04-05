# Dispatch Paralelo de Agentes

## Cuando usar

Decision tree:
1. Multiples tareas independientes? → Si: evaluar paralelo
2. Dominios independientes (sin estado compartido)? → Si: dispatch paralelo
3. Resultado de una necesita input de otra? → Si: secuencial

## Patron

1. Identificar sub-tareas independientes
2. Asignar cada sub-tarea a un agente con contexto aislado
3. Ejecutar en paralelo (Future.wait / Promise.all)
4. Recolectar resultados
5. Sintetizar en respuesta unificada

## Protocolo de sintesis

Al recibir resultados de N agentes:
- Verificar que todos completaron (o manejaron fallos)
- Detectar conflictos entre resultados
- Priorizar por confianza/expertise del agente
- Consolidar en respuesta coherente
- Citar que agente/fuente produjo que hallazgo

## Reglas

- Cada agente recibe solo el contexto que necesita (no contexto completo)
- Timeout individual por agente (no esperar infinitamente)
- Si un agente falla, los demas continuan (aislamiento de fallos)
- Resultado parcial > sin resultado (degradacion graceful)

## Trade-offs

| Pro | Con |
|-----|-----|
| Latencia = max(agentes) no sum(agentes) | Mas tokens totales (~15x vs 1x) |
| Contextos limpios por agente | Overhead de coordinacion |
| Aislamiento de fallos | Complejidad de sintesis |
