# Google Colab MCP Server

## Descripcion
Permite ejecutar codigo Python en Google Colab directamente desde Neomage.
Usa el Model Context Protocol (MCP) para controlar notebooks programaticamente.

## Capacidades
- Crear notebooks (.ipynb) nuevos
- Escribir y ejecutar celdas de Python
- Instalar dependencias (pip install)
- Organizar celdas (markdown, codigo, resultados)
- Leer resultados de ejecucion en tiempo real

## Casos de uso
- Analisis de datos: "Analiza las ventas del ultimo mes y genera una grafica"
- Procesamiento de audio: "Convierte este archivo WAV a MP3"
- Machine learning: "Entrena un modelo simple con estos datos"
- Scraping: "Extrae los precios de esta pagina web"
- Automatizacion: "Genera un reporte PDF con estos datos"

## Configuracion MCP
```json
{
  "colab-proxy-mcp": {
    "command": "uvx",
    "args": ["git+https://github.com/googlecolab/colab-mcp"]
  }
}
```

## Requisitos
- Python instalado en el sistema
- uv (pip install uv)
- Cuenta de Google con acceso a Colab

## Limitaciones
- Solo disponible en Neomage desktop (no web/mobile)
- Requiere conexion a internet
- Las ejecuciones consumen recursos de Colab (GPU limitada en plan gratuito)
