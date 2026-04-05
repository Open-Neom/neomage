# Diseno para Movil

- Movil no es un escritorio pequeno: restricciones de pantalla, red, bateria y atencion son fundamentalmente distintas
- Touch-first: el dedo tiene ~7mm de area de contacto; targets tactiles minimo 44-48px
- Ley de Fitts para touch: acciones primarias en zona del pulgar (parte inferior), destructivas lejos del alcance facil
- 49% de usuarios sostiene con una mano; zona superior se convierte en area muerta en pantallas grandes
- Retroalimentacion instantanea al tocar (<50ms): cambio visual, escala sutil o hapticos
- Cada gesto (swipe, pinch, long press) debe tener alternativa visible con boton
- Una accion primaria por pantalla, divulgacion progresiva, maximo 5 items en navegacion
- Offline-first: disenar asumiendo que la red fallara; degradacion elegante y sincronizacion posterior

## Diferencias por plataforma
- iOS: minimo 44pt touch, SF Pro, edge swipe para volver, SF Symbols
- Android: minimo 48dp touch, Roboto, boton de sistema para volver, Material Icons
- Unificar: logica de negocio, modelos de datos, contratos API
- Divergir: navegacion, gestos, tipografia, iconos, pickers

## Anti-patrones
- ScrollView para listas largas (usar listas virtualizadas)
- Targets tactiles menores a 44px, acciones solo por gesto
- Tokens en almacenamiento inseguro (usar SecureStore o Keychain)
