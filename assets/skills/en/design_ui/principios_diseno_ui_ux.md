# Principios de Diseno UI/UX

- El diseno centrado en el usuario prioriza necesidades reales sobre preferencias esteticas del equipo
- Toda decision de diseno debe validarse con investigacion: entrevistas, pruebas de usabilidad, analisis de datos
- Atomic Design organiza componentes en atomos, moleculas, organismos, plantillas y paginas para escalabilidad
- Design Tokens (colores, tipografia, espaciado) como variables abstractas reutilizables en todo el sistema
- Jerarquia visual guia la atencion: tamano, contraste, posicion y espacio en blanco determinan que ve primero el usuario
- Accesibilidad no es opcional: WCAG 2.1 AA minimo, contraste 4.5:1 para texto, 3:1 para elementos de interfaz
- Cada pantalla necesita una accion primaria clara; multiples acciones de igual peso generan paralisis de decision
- Estados vacios, de carga, de error y de exito deben disenarse con la misma intencion que el estado ideal
- Consistencia entre plataformas: unificar logica de negocio y modelos, divergir en gestos e iconos nativos
- Medir impacto con metricas reales (conversion, retencion, NPS) cierra el ciclo de mejora continua

## Anti-patrones
- Disenar para pantallas perfectas ignorando edge cases (sin datos, errores de red, textos largos)
- Copiar tendencias sin evaluar si sirven al contexto y audiencia del producto
- Entregar disenos sin especificaciones de interaccion, estados y responsividad
