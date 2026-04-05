# Fundamentos de Contexto — Anatomia y Mecanica

## Componentes del contexto

**System prompt**: Identidad, restricciones, guias de comportamiento. Se carga al inicio, persiste toda la sesion. Lenguaje claro y directo a la altitud correcta (ni rigido/fragil ni vago/ambiguo).

**Definiciones de herramientas**: Nombre, descripcion, parametros, formato de retorno. Guian el comportamiento del agente. Descripciones pobres = agente adivinando.

**Documentos recuperados**: Conocimiento especifico del dominio cargado en runtime via RAG. Patron just-in-time: mantener identificadores ligeros, cargar datos dinamicamente.

**Historial de mensajes**: Conversacion usuario-agente. En tareas largas domina el uso de contexto. Funciona como scratchpad de estado y progreso.

**Outputs de herramientas**: Resultados de acciones: archivos, busquedas, APIs. Pueden alcanzar 83.9% del uso total de contexto.

## Budget de atencion

Mecanismo de atencion: n tokens → n² relaciones. Budget finito que se agota con longitud.
- Modelos entrenados primariamente en secuencias cortas → menos capacidad para dependencias largas
- Position encoding interpolation permite contextos mas largos pero con precision reducida

## Principio de divulgacion progresiva

Cargar informacion solo cuando se necesite. Al inicio: nombres y descripciones de skills (suficiente para saber cuando activar). Contenido completo solo al activar para tarea especifica.

## Calidad > cantidad

"Context engineering = encontrar el set mas pequeno posible de tokens de alta senal que maximice la probabilidad de resultados deseados."

Factores de presion:
- Costo crece desproporcionalmente (no linealmente) con longitud
- Performance se degrada mas alla de ciertos umbrales
- Inputs largos siguen siendo costosos incluso con prefix caching

## Estrategias hibridas

Pre-cargar contexto estable (system prompts, reglas). Habilitar exploracion autonoma para contexto dinamico. Frontera depende de: dinamismo del contenido y caracteristicas de la tarea.

## Budget explicito de contexto

Asignar tokens por categoria: system prompt, herramientas, docs, historial, buffer reservado. Monitorear uso vs presupuesto. Triggers de optimizacion al 70-80% de capacidad.
