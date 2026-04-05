# Accesibilidad en Interfaces

- Accesibilidad es requisito de calidad, no caracteristica opcional; beneficia a todos los usuarios
- WCAG 2.1/2.2: A (minimo), AA (estandar recomendado), AAA (maximo); apuntar siempre a AA
- Contraste de color: 4.5:1 minimo para texto normal, 3:1 para texto grande y elementos UI
- Navegacion por teclado completa: Tab para foco, Enter/Space para activar, Escape para cerrar
- Indicadores de foco visibles obligatorios en todos los elementos interactivos
- Cada imagen necesita texto alternativo descriptivo; decorativas usan alt vacio
- Formularios: etiquetas asociadas, mensajes de error con aria-invalid y aria-describedby
- Modales: atrapar foco dentro, cerrar con Escape, devolver foco al disparador
- Touch targets WCAG 2.2: minimo 44x44px con 8px de separacion entre adyacentes

## Usuarios con discapacidad motriz
- Targets generosos (48px+), tiempos ajustables para gestos
- Soporte para control por voz y switch control
- Alternativas visibles para cada gesto

## Anti-patrones
- Eliminar focus ring sin reemplazo visible
- Componentes sin roles ARIA ni etiquetas semanticas
- Contenido que comunica informacion solo por color
