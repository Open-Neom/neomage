import '../utils/constants/neomage_translation_constants.dart';

/// Spanish translations for neomage.
class AppEsTranslations {
  AppEsTranslations._();

  static Map<String, String> keys = {
    // ── App General ──
    NeomageTranslationConstants.appTitle: 'Neomage',
    NeomageTranslationConstants.appSubtitleDesktop:
        'Tu agente IA para crear, explorar y ejecutar',
    NeomageTranslationConstants.splashTagline2:
        'Cualquier modelo. Cualquier plataforma.',
    NeomageTranslationConstants.splashTagline3:
        'Inteligencia que amplifica la tuya.',
    NeomageTranslationConstants.appSubtitleMobile:
        'IA multi-modelo para crear y ejecutar',
    NeomageTranslationConstants.welcomeSubtitle:
        'Tu agente IA para crear, explorar y ejecutar.\nCualquier modelo. Cualquier plataforma.',
    NeomageTranslationConstants.language: 'Idioma',
    NeomageTranslationConstants.save: 'Guardar',
    NeomageTranslationConstants.cancel: 'Cancelar',
    NeomageTranslationConstants.delete: 'Eliminar',
    NeomageTranslationConstants.close: 'Cerrar',
    NeomageTranslationConstants.retry: 'Reintentar',
    NeomageTranslationConstants.back: 'Atr\u00e1s',
    NeomageTranslationConstants.skip: 'Omitir',
    NeomageTranslationConstants.add: 'Agregar',
    NeomageTranslationConstants.exit: 'Salir',
    NeomageTranslationConstants.copiedToClipboard: 'Copiado al portapapeles',
    NeomageTranslationConstants.notYetImplemented: 'A\u00fan no implementado',

    // ── Chat Screen ──
    NeomageTranslationConstants.newConversation: 'Nueva Conversaci\u00f3n',
    NeomageTranslationConstants.clearConversation: 'Limpiar Conversaci\u00f3n',
    NeomageTranslationConstants.conversationCleared: 'Conversaci\u00f3n limpiada',
    NeomageTranslationConstants.exportConversation: 'Exportar Conversaci\u00f3n',
    NeomageTranslationConstants.exportNotImplemented:
        'Exportaci\u00f3n a\u00fan no implementada',
    NeomageTranslationConstants.selectModel: 'Seleccionar Modelo',
    NeomageTranslationConstants.modelChangedTo: 'Modelo cambiado a',
    NeomageTranslationConstants.typeACommand: 'Escribe un comando...',
    NeomageTranslationConstants.commandPalette: 'Paleta de comandos',
    NeomageTranslationConstants.commandPaletteShortcut:
        'Ctrl+K para paleta de comandos',

    // ── Chat \u2013 Top Bar ──
    NeomageTranslationConstants.openSidePanel: 'Abrir panel lateral',
    NeomageTranslationConstants.toggleSidePanel: 'Alternar Panel Lateral',
    NeomageTranslationConstants.settings: 'Configuraci\u00f3n',
    NeomageTranslationConstants.changeModel: 'Cambiar Modelo',

    // ── Chat \u2013 Empty State (Desktop) ──
    NeomageTranslationConstants.explainCodebase: 'Explica este c\u00f3digo',
    NeomageTranslationConstants.findTodoComments: 'Busca todos los TODO',
    NeomageTranslationConstants.writeUnitTests: 'Escribe pruebas unitarias',
    NeomageTranslationConstants.refactorFunction: 'Refactoriza esta funci\u00f3n',
    NeomageTranslationConstants.reviewPR: 'Revisa este PR',
    NeomageTranslationConstants.debugError: 'Depura este error',

    // ── Chat \u2013 Empty State (Mobile) ──
    NeomageTranslationConstants.summarizeArticle: 'Resume este art\u00edculo',
    NeomageTranslationConstants.translateToEnglish: 'Traduce al ingl\u00e9s',
    NeomageTranslationConstants.draftQuickReply: 'Redacta una respuesta r\u00e1pida',
    NeomageTranslationConstants.brainstormIdeas: 'Lluvia de ideas',
    NeomageTranslationConstants.explainConcept: 'Explica un concepto',
    NeomageTranslationConstants.writeShortNote: 'Escribe una nota r\u00e1pida',

    // ── Chat \u2013 Side Panel ──
    NeomageTranslationConstants.agents: 'Agentes',
    NeomageTranslationConstants.tasks: 'Tareas',
    NeomageTranslationConstants.mcp: 'MCP',
    NeomageTranslationConstants.noActiveAgents: 'Sin agentes activos',
    NeomageTranslationConstants.agentsWillAppear:
        'Los agentes aparecer\u00e1n aqu\u00ed cuando se invoquen durante la conversaci\u00f3n.',
    NeomageTranslationConstants.noActiveTasks: 'Sin tareas activas',
    NeomageTranslationConstants.tasksWillAppear:
        'Las tareas creadas con TodoWrite se rastrear\u00e1n aqu\u00ed.',
    NeomageTranslationConstants.noTasks: 'Sin tareas',

    // ── Chat \u2013 MCP Panel ──
    NeomageTranslationConstants.addMcpServer: 'Agregar Servidor MCP',
    NeomageTranslationConstants.serverName: 'Nombre del Servidor',
    NeomageTranslationConstants.serverNameHint: 'ej. filesystem, github',
    NeomageTranslationConstants.serverUrl: 'URL del Servidor',
    NeomageTranslationConstants.serverUrlHint:
        'ej. http://localhost:3001/sse',
    NeomageTranslationConstants.command: 'Comando',
    NeomageTranslationConstants.commandHint:
        'ej. npx -y @modelcontextprotocol/server-filesystem /ruta',
    NeomageTranslationConstants.stdio: 'stdio',
    NeomageTranslationConstants.sse: 'SSE',
    NeomageTranslationConstants.remove: 'Eliminar',
    NeomageTranslationConstants.reconnect: 'Reconectar',
    NeomageTranslationConstants.searchTools: 'Buscar herramientas...',
    NeomageTranslationConstants.server: 'Servidor',
    NeomageTranslationConstants.decline: 'Rechazar',
    NeomageTranslationConstants.submit: 'Enviar',

    // ── Chat \u2013 Streaming ──
    NeomageTranslationConstants.thinking: 'Pensando',

    // ── API Key Dialog ──
    NeomageTranslationConstants.apiKey: 'Llave API',
    NeomageTranslationConstants.apiKeyHint: 'sk-...',
    NeomageTranslationConstants.apiKeyRequired:
        'Se necesita una llave API para usar modelos de @provider. '
            'Ingresa tu llave para continuar.',
    NeomageTranslationConstants.saveAndContinue: 'Guardar y Continuar',
    NeomageTranslationConstants.pasteFromClipboard: 'Pegar del portapapeles',

    // ── Model Selector ──
    NeomageTranslationConstants.desktopOnly: 'Solo escritorio',
    NeomageTranslationConstants.ollamaDesktopNote:
        'Ollama corre localmente \u2014 usa la app de escritorio para gestionar modelos.',

    // ── Settings Screen ──
    NeomageTranslationConstants.settingsSaved: 'Configuraci\u00f3n guardada',
    NeomageTranslationConstants.apiProvider: 'Proveedor API',
    NeomageTranslationConstants.version: 'Versi\u00f3n',
    NeomageTranslationConstants.provider: 'Proveedor',
    NeomageTranslationConstants.model: 'Modelo',
    NeomageTranslationConstants.defaultModel: 'Modelo predeterminado',
    NeomageTranslationConstants.baseUrl: 'URL Base',
    NeomageTranslationConstants.baseUrlHint: 'https://tu-endpoint.com/v1',
    NeomageTranslationConstants.searchSettings: 'Buscar configuraci\u00f3n...',
    NeomageTranslationConstants.diagnostics: 'Diagn\u00f3sticos',
    NeomageTranslationConstants.refreshUsageData: 'Actualizar datos de uso',
    NeomageTranslationConstants.noUsageData: 'Sin datos de uso disponibles',

    // ── Settings \u2013 Toggles ──
    NeomageTranslationConstants.autoCompact: 'Auto-compactar',
    NeomageTranslationConstants.showTips: 'Mostrar consejos',
    NeomageTranslationConstants.reduceMotion: 'Reducir movimiento',
    NeomageTranslationConstants.thinkingMode: 'Modo pensamiento',
    NeomageTranslationConstants.verboseOutput: 'Salida detallada',
    NeomageTranslationConstants.fileCheckpointing: 'Puntos de control',
    NeomageTranslationConstants.notifications: 'Notificaciones',
    NeomageTranslationConstants.toggleTheme: 'Cambiar Tema',
    NeomageTranslationConstants.themeToggleNotImplemented:
        'Cambio de tema a\u00fan no implementado',

    // ── Settings \u2013 Status Properties ──
    NeomageTranslationConstants.loginMethod: 'M\u00e9todo de inicio de sesi\u00f3n',
    NeomageTranslationConstants.authToken: 'Token de autenticaci\u00f3n',
    NeomageTranslationConstants.organization: 'Organizaci\u00f3n',
    NeomageTranslationConstants.email: 'Correo electr\u00f3nico',
    NeomageTranslationConstants.apiProviderLabel: 'Proveedor API',
    NeomageTranslationConstants.gcpProject: 'Proyecto GCP',
    NeomageTranslationConstants.mcpServers: 'Servidores MCP',
    NeomageTranslationConstants.settingSources: 'Fuentes de configuraci\u00f3n',
    NeomageTranslationConstants.bashSandbox: 'Sandbox Bash',
    NeomageTranslationConstants.enabled: 'Habilitado',
    NeomageTranslationConstants.disabled: 'Deshabilitado',

    // ── Ollama Setup ──
    NeomageTranslationConstants.localModelsOllama: 'Modelos Locales (Ollama)',
    NeomageTranslationConstants.localModelsDesktopOnly:
        'Modelos Locales (Ollama) \u2014 Solo Escritorio',
    NeomageTranslationConstants.ollamaWebNote:
        'Ollama corre localmente en tu m\u00e1quina. Usa la app de macOS, Windows o Linux para gestionar modelos locales.',
    NeomageTranslationConstants.refresh: 'Actualizar',
    NeomageTranslationConstants.installedModels: 'Modelos Instalados',
    NeomageTranslationConstants.noModelsInstalled: 'No hay modelos instalados',
    NeomageTranslationConstants.downloadModelBelow:
        'Descarga un modelo para comenzar',
    NeomageTranslationConstants.downloadModels: 'Descargar Modelos',
    NeomageTranslationConstants.recommendedModels:
        'Modelos recomendados para programaci\u00f3n',
    NeomageTranslationConstants.installed: 'Instalado',
    NeomageTranslationConstants.download: 'Descargar',
    NeomageTranslationConstants.pull: 'Descargar',
    NeomageTranslationConstants.testModel: 'Probar Modelo',
    NeomageTranslationConstants.testing: 'Probando...',
    NeomageTranslationConstants.useThisModel: 'Usar Este Modelo',
    NeomageTranslationConstants.deleteModel: 'Eliminar Modelo',
    NeomageTranslationConstants.deleteModelConfirm:
        '\u00bfEliminar @model (@size)?\n\nPuedes volver a descargarlo despu\u00e9s.',
    NeomageTranslationConstants.redownloadLater:
        'Puedes volver a descargarlo despu\u00e9s.',
    NeomageTranslationConstants.customModelHint:
        'Nombre del modelo (ej. phi3:mini)',
    NeomageTranslationConstants.activatedAsDefault:
        '@model activado como modelo predeterminado',

    // ── Choose Mode ──
    NeomageTranslationConstants.chooseModeTitle: '\u00bfC\u00f3mo quieres usar la IA?',
    NeomageTranslationConstants.chooseModeSubtitle:
        'Elige entre proveedores en la nube o ejecutar modelos localmente.',
    NeomageTranslationConstants.cloudMode: 'Nube',
    NeomageTranslationConstants.cloudModeDesc:
        'Conecta con Gemini, OpenAI, Anthropic y otros. '
            'Requiere una llave API (hay plan gratuito).',
    NeomageTranslationConstants.localMode: 'Local',
    NeomageTranslationConstants.localModeDesc:
        'Ejecuta modelos de IA en tu propia m\u00e1quina con Ollama. '
            'Sin llave API, completamente offline y privado.',
    NeomageTranslationConstants.localModeDesktopOnly:
        'Los modelos locales requieren la app de escritorio',

    // ── API Configuration ──
    NeomageTranslationConstants.apiConfigTitle: 'Configuraci\u00f3n de API',
    NeomageTranslationConstants.apiConfigSubtitle:
        'Conecta con tu proveedor de IA preferido.',
    NeomageTranslationConstants.apiConfigExplanation:
        'Neomage se conecta directamente a los proveedores de IA usando tu '
            'propia llave API. Solo pagas por lo que usas \u2014 la facturaci\u00f3n '
            'es bajo demanda seg\u00fan los tokens consumidos por conversaci\u00f3n. '
            'Sin suscripciones, sin intermediarios.',

    // ── Ollama Setup ──
    NeomageTranslationConstants.ollamaSetupTitle: 'Configuraci\u00f3n Local (Ollama)',
    NeomageTranslationConstants.ollamaSetupSubtitle:
        'Ejecuta modelos de IA en tu propia m\u00e1quina.',
    NeomageTranslationConstants.ollamaNotDetected: 'Ollama no detectado',
    NeomageTranslationConstants.ollamaNotDetectedDesc:
        'Instala Ollama para ejecutar modelos localmente. Es gratis y toma menos de un minuto.',
    NeomageTranslationConstants.ollamaInstallHint:
        'Visita ollama.com para descargar e instalar, luego presiona Reintentar.',
    NeomageTranslationConstants.ollamaRunning: 'Ollama est\u00e1 corriendo',
    NeomageTranslationConstants.ollamaCheckStatus: 'Verificar estado',
    NeomageTranslationConstants.ollamaInstalledModels: 'Modelos instalados',
    NeomageTranslationConstants.ollamaNoModels:
        'No hay modelos instalados. Descarga uno para comenzar.',
    NeomageTranslationConstants.ollamaRecommended: 'Modelos recomendados',
    NeomageTranslationConstants.ollamaSelectModel: 'Selecciona un modelo para continuar',
    NeomageTranslationConstants.ollamaPulling: 'Descargando...',

    // ── Onboarding ──
    NeomageTranslationConstants.getStarted: 'Comenzar',
    NeomageTranslationConstants.codeEditing: 'Crear y editar archivos',
    NeomageTranslationConstants.codebaseSearch: 'Buscar y organizar',
    NeomageTranslationConstants.shellCommands: 'Ejecutar comandos',
    NeomageTranslationConstants.mcpTools: 'Conectar herramientas',
    NeomageTranslationConstants.gitIntegration: 'Integraci\u00f3n Git',
    NeomageTranslationConstants.gitIntegrationDesc:
        'Habilitar funciones de git como vista de diff y ayudantes de commit',
    NeomageTranslationConstants.createNeomageMd: 'Crear NEOMAGE.md',
    NeomageTranslationConstants.createNeomageMdDesc:
        'Inicializar un archivo de memoria con contexto e instrucciones del proyecto',
    NeomageTranslationConstants.browse: 'Explorar',
    NeomageTranslationConstants.backToSettings: 'Volver a configuraci\u00f3n',

    // ── Permissions ──
    NeomageTranslationConstants.permDefault: 'Predeterminado',
    NeomageTranslationConstants.permAcceptEdits: 'Aceptar Ediciones',
    NeomageTranslationConstants.permAcceptEditsDesc:
        'Auto-aprobar ediciones de archivos. A\u00fan preguntar para comandos de terminal.',
    NeomageTranslationConstants.permPlanMode: 'Modo Planificaci\u00f3n',
    NeomageTranslationConstants.permPlanModeDesc:
        'Solo planificar, nunca ejecutar. Todas las modificaciones est\u00e1n bloqueadas.',
    NeomageTranslationConstants.permFullAuto: 'Auto Completo',
    NeomageTranslationConstants.permFullAutoDesc:
        'Auto-aprobar todo. \u00a1Usar con precauci\u00f3n!',
    NeomageTranslationConstants.addRule: 'Agregar Regla',
    NeomageTranslationConstants.editRule: 'Editar Regla',
    NeomageTranslationConstants.rulePatternHint:
        'ej. Bash(npm:*), Edit(src/**/*.dart)',
    NeomageTranslationConstants.behavior: 'Comportamiento',
    NeomageTranslationConstants.allow: 'Permitir',
    NeomageTranslationConstants.deny: 'Denegar',
    NeomageTranslationConstants.ask: 'Preguntar',
    NeomageTranslationConstants.scope: 'Alcance',
    NeomageTranslationConstants.tool: 'Herramienta',
    NeomageTranslationConstants.file: 'Archivo',
    NeomageTranslationConstants.cmd: 'Cmd',
    NeomageTranslationConstants.ruleReasonHint: 'Por qu\u00e9 existe esta regla',
    NeomageTranslationConstants.toolInput: 'Entrada de Herramienta:',
    NeomageTranslationConstants.rememberSession:
        'Recordar para esta sesi\u00f3n',
    NeomageTranslationConstants.rememberProject:
        'Recordar para este proyecto',
    NeomageTranslationConstants.trustAndContinue: 'Confiar y Continuar',

    // ── Input Bar ──
    NeomageTranslationConstants.attachFile: 'Archivo',
    NeomageTranslationConstants.pickAnyFile: 'Elegir cualquier archivo',
    NeomageTranslationConstants.image: 'Imagen',
    NeomageTranslationConstants.fromGallery: 'Desde galer\u00eda',
    NeomageTranslationConstants.camera: 'C\u00e1mara',
    NeomageTranslationConstants.takePhoto: 'Tomar una foto',
    NeomageTranslationConstants.pdf: 'PDF',
    NeomageTranslationConstants.pickPdf: 'Elegir un documento PDF',
    NeomageTranslationConstants.attachTooltip: 'Adjuntar archivo, imagen o PDF',

    // ── Plan Mode ──
    NeomageTranslationConstants.exitPlanMode: 'Salir del Modo Plan',
    NeomageTranslationConstants.execute: 'Ejecutar',

    // ── Feedback Survey ──
    NeomageTranslationConstants.bad: 'Malo',
    NeomageTranslationConstants.fine: 'Bien',
    NeomageTranslationConstants.good: 'Bueno',
    NeomageTranslationConstants.dismiss: 'Descartar',
    NeomageTranslationConstants.share: 'Compartir',
    NeomageTranslationConstants.dontAskAgain: 'No preguntar de nuevo',

    // ── Background Tasks ──
    NeomageTranslationConstants.done: 'completado',
    NeomageTranslationConstants.error: 'error',
    NeomageTranslationConstants.stopped: 'detenido',
    NeomageTranslationConstants.idle: 'Inactivo',
    NeomageTranslationConstants.awaitingApproval: 'Esperando Aprobaci\u00f3n',
    NeomageTranslationConstants.shutdownRequested: 'Apagado Solicitado',
    NeomageTranslationConstants.stop: 'Detener',
    NeomageTranslationConstants.status: 'Estado',
    NeomageTranslationConstants.description: 'Descripci\u00f3n',
    NeomageTranslationConstants.title: 'T\u00edtulo',
    NeomageTranslationConstants.agent: 'Agente',
    NeomageTranslationConstants.activity: 'Actividad',
    NeomageTranslationConstants.started: 'Iniciado',
    NeomageTranslationConstants.duration: 'Duraci\u00f3n',
    NeomageTranslationConstants.foreground: 'Primer plano',
    NeomageTranslationConstants.taskNotFound: 'Tarea no encontrada',

    // ── Memory Panel ──
    NeomageTranslationConstants.openAutoMemory:
        'Abrir carpeta de auto-memoria',
    NeomageTranslationConstants.openAgentMemory:
        'Abrir memoria del agente @agent',
    NeomageTranslationConstants.autoMemory: 'Auto-memoria',
    NeomageTranslationConstants.autoDream: 'Auto-dream',

    // ── Terminal View ──
    NeomageTranslationConstants.copyAll: 'Copiar todo',
    NeomageTranslationConstants.scrollToBottom: 'Ir al final',
    NeomageTranslationConstants.searchOutput: 'Buscar en salida...',
    NeomageTranslationConstants.logsCopied: 'Logs copiados al portapapeles',

    // ── Providers ──
    NeomageTranslationConstants.gemini: 'Gemini',
    NeomageTranslationConstants.qwen: 'Qwen',
    NeomageTranslationConstants.openai: 'OpenAI',
    NeomageTranslationConstants.deepseek: 'DeepSeek',
    NeomageTranslationConstants.anthropic: 'Anthropic',
    NeomageTranslationConstants.ollama: 'Ollama',

    // ── Side Panel Commands ──
    NeomageTranslationConstants.showAgents: 'Mostrar Agentes',
    NeomageTranslationConstants.showTasks: 'Mostrar Tareas',
    NeomageTranslationConstants.showMcpServers: 'Mostrar Servidores MCP',
  };
}
