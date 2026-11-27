# Guía para probar Overreach v0.1

Overreach sustituye a un registro de gimnasio como Strong y calcula los objetivos de cada sesión a partir de tu
historial. Esta versión es una beta: **haz copias de seguridad y no la uses como único registro de tus datos.**
No es un dispositivo médico.

Necesitas un iPhone con iOS 18 o posterior, un cable, un ordenador con Windows o macOS y un Apple ID.

## 1. Instalar

1. Descarga `Overreach-0.1.0.ipa` desde la
   [página de releases](https://github.com/droidsam1/overreach/releases/tag/v0.1.0).
2. Instala [Sideloadly](https://sideloadly.io/) en el ordenador.
3. Conecta el iPhone, arrastra el `.ipa` a Sideloadly, escribe tu Apple ID y pulsa **Start**.
4. En el iPhone, ve a **Ajustes → General → VPN y gestión de dispositivos** y confía en tu Apple ID.
5. Si iOS lo pide, activa **Ajustes → Privacidad y seguridad → Modo de desarrollador** y reinicia.

### Con Apple Salud: instalar desde un Mac

Sideloadly instala la app, pero al firmarla con tu Apple ID **quita el permiso de Apple Salud**: al pulsar
«Conectar Apple Salud» aparece *Missing com.apple.developer.healthkit entitlement*. Para tener Salud, instálala
desde un Mac con Xcode:

1. En el Mac, instala Xcode desde la App Store y ábrelo una vez.
2. En Xcode, ve a **Xcode → Settings → Accounts → + → Apple ID** y añade tu Apple ID.
3. Conecta el iPhone por cable y desbloquéalo.
4. Abre **Terminal**, pega esta línea y pulsa Intro:

   ```
   curl -fsSL https://raw.githubusercontent.com/droidsam1/overreach/main/scripts/install-from-mac.command | bash
   ```

El script descarga el código y XcodeGen a una carpeta temporal, compila, firma con tu Apple ID, instala la app y
borra la carpeta al terminar. No instala nada más en el Mac. Al final dice si la firma incluye el permiso de
Salud. La app instalada así es distinta de la de Sideloadly: haz una copia de seguridad en la vieja y restáurala
al abrir la nueva. Para renovarla cada 7 días, vuelve a pegar la misma línea (conserva tus datos).

## 2. Volver a firmar cada 7 días

Con un Apple ID gratuito, la app deja de abrirse a los 7 días. Para renovarla:

1. Haz una copia en **Ajustes → Copia de seguridad → Hacer copia ahora**.
2. Repite la instalación con Sideloadly, con **el mismo `.ipa` o uno más nuevo y el mismo Apple ID**.
3. **No borres la app antes.** Borrarla elimina sus datos del iPhone.
4. Abre la app y comprueba que tu historial sigue ahí. Si no está, avísanos y restaura tu copia.

## 3. Copias de seguridad

1. En **Ajustes → Copia de seguridad**, pulsa **Elegir carpeta de iCloud Drive…** y elige una carpeta.
2. La app guarda una copia al terminar cada sesión y te avisa si pasan 7 días sin ninguna.
3. Para recuperar tus datos, usa **Restaurar desde archivo…** y elige una copia. Si instalas la app desde cero,
   también puede ofrecerte restaurar al abrirla.

## 4. Qué probar

- **Primer uso:** la configuración inicial y **Ajustes → Importar desde Strong**, con tu CSV de Strong.
- **Entrenar:** crea una rutina, registra una sesión real y usa el temporizador de descanso.
- **Objetivos:** comprueba si el peso y las repeticiones propuestos tienen sentido y si se entiende el motivo.
- **Historial:** edita y borra una sesión.
- **Ejercicios:** asigna músculos a los importados, crea uno propio y fusiona dos duplicados.
- **Plan:** define tu objetivo y revisa el análisis.
- **Apple Health:** concede el permiso y comprueba que la sesión terminada aparece en Salud, sin duplicados tras
  editarla. Con un Apple ID gratuito puede que el permiso no llegue a aparecer. Si te ocurre, cuéntanoslo.
- **Copias:** haz una copia y restáurala.
- **Pantalla:** idioma (español, inglés o gallego), modo oscuro, texto muy grande y VoiceOver.

## 5. Informar de un problema

Abre un [informe de error](https://github.com/droidsam1/overreach/issues/new?template=bug_report.yml) e indica:

- La versión de la app. La ves en **Ajustes del iPhone → General → Almacenamiento del iPhone → Overreach**.
- Tu modelo de iPhone y versión de iOS.
- Los pasos para reproducirlo, qué esperabas y qué ocurrió.
- Una captura, si ayuda.

Los informes son públicos. No adjuntes copias de seguridad, exportaciones de Salud ni datos personales.
