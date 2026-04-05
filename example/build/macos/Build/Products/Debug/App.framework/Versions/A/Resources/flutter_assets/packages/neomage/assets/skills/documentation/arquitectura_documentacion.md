# Arquitectura de Documentacion

- La documentacion es producto: necesita dueno, roadmap, metricas de calidad y ciclo de mantenimiento
- Estructura por audiencia: guias de usuario, referencia API, tutoriales, explicaciones conceptuales (modelo Diataxis)
- Tutoriales: aprendizaje guiado paso a paso. How-to: resolucion de tareas especificas. Referencia: datos exactos. Explicacion: comprension profunda
- Cada documento tiene un solo proposito; mezclar tutorial con referencia confunde a ambas audiencias
- La documentacion vive junto al codigo (docs-as-code): versionada, revisada, desplegada automaticamente
- Templates reducen friccion para contribuir: ADR, RFC, runbook, postmortem, changelog
- Busqueda efectiva es critica: indexar titulos, headers, contenido; filtrar por version y audiencia
- Medir salud: cobertura (% de APIs documentadas), frescura (edad promedio), uso (paginas mas visitadas)

## Proceso de mantenimiento
- Docs review en cada PR que cambie comportamiento
- Auditoria trimestral de contenido obsoleto
- Feedback loop visible: boton "fue util?" en cada pagina

## Anti-patrones
- Documentacion sin fecha ni version (no se sabe si es actual)
- Wiki desorganizada sin estructura ni busqueda
- Documentar implementacion en vez de comportamiento y proposito
