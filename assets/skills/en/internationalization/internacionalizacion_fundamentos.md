# Internacionalizacion — Fundamentos

- i18n (internacionalizacion) prepara el producto para multiples idiomas; l10n (localizacion) adapta a un idioma/region especifica
- Separar TODO el texto visible del codigo: usar archivos de traduccion (JSON, ARB, XLIFF), nunca strings hardcodeados
- Las claves de traduccion deben ser semanticas: `button.submit` > `btn1`; reflejar proposito, no contenido
- Pluralizacion varia por idioma: ingles tiene 2 formas, arabe tiene 6, ruso tiene 3; usar ICU MessageFormat
- Formateo de numeros, fechas, monedas depende del locale: 1,234.56 (en-US) vs 1.234,56 (es-MX)
- El texto traducido puede ser 30-50% mas largo que ingles; disenar UI con espacio flexible
- Direccionalidad: soportar RTL (arabe, hebreo) requiere propiedades logicas (start/end en vez de left/right)
- Concatenar strings es anti-patron: orden de palabras cambia entre idiomas; usar templates con placeholders

## Proceso de localizacion
- Extraer strings → enviar a traductores → importar traducciones → QA visual → deploy
- Pseudo-localizacion detecta strings no externalizados y problemas de layout antes de traducir
- Context para traductores: donde aparece el string, longitud maxima, capturas de pantalla

## Anti-patrones
- Asumir que todos los idiomas leen izquierda a derecha
- Hardcodear formatos de fecha/moneda (usar Intl o equivalente)
- Traducir con Google Translate sin revision humana para produccion
- Ignorar pluralizacion y genero gramatical
