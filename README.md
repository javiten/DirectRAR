# DirectRAR

App para iPhone y iPad que extrae archivos RAR leyendo el original donde está, sin importar una segunda copia a la app. Pensada para archivos grandes cuando el espacio del dispositivo es justo.

- RAR y RAR5 (un solo volumen, sin contraseña) y ZIP.
- Lo extraído va a una carpeta nueva `Extraido-UUID` dentro del destino que elijas.
- SwiftUI + un motor pequeño en C sobre [libarchive](https://www.libarchive.org) 3.8.4.
- Requiere iOS 16 o superior.

## Instalar

No está en el App Store: se compila e instala con Xcode desde una Mac.

1. Cloná el repositorio y abrí `DirectRAR.xcodeproj`.

   ```bash
   git clone https://github.com/javiten/DirectRAR.git
   ```

2. En el target DirectRAR → Signing & Capabilities, elegí tu Team.
3. Cambiá el Bundle Identifier `com.javiten.DirectRAR` por uno propio.
4. Conectá el iPhone, habilitá Developer Mode si Xcode lo pide y elegilo como destino.
5. Presioná Run (▶).

La primera compilación construye libarchive desde las fuentes incluidas en `Vendor/` y tarda más. No requiere Homebrew ni descargar dependencias. Si una compilación interrumpida deja el motor inconsistente, borrá la carpeta `.build` del proyecto y volvé a compilar.

Con una cuenta gratuita de Apple hay que reinstalar la app cuando vence su firma (7 días).

## Uso

Elegir RAR → elegir carpeta de destino → Extraer.

- El archivo se abre con el selector de documentos sin copiarlo (`asCopy: false`). Un proveedor como iCloud igual puede descargar o mantener su propia caché; para evitarlo, usá un archivo ya descargado en “En mi iPhone”.
- Mantené la app abierta durante la extracción: la pantalla queda encendida, pero iOS puede suspender la app si cambiás de app o bloqueás el teléfono. No hay reanudación.
- Cancelar o fallar elimina la carpeta creada. Si iOS termina el proceso de golpe, borrá la carpeta parcial desde Archivos.

## Límites

- Sin soporte para RAR con contraseña ni multivolumen. No se garantiza compatibilidad con toda variante RAR. 7z tiene soporte parcial del motor y no está validado.
- Sin integración con el menú Compartir: el archivo se abre desde la app.
- Necesitás espacio libre para lo extraído; el tamaño total no se estima por adelantado.
- Lectura y escritura en bloques de 128 KiB, pero un RAR con diccionario de compresión muy grande puede exceder la memoria del dispositivo.
- El progreso es aproximado (bytes comprimidos leídos).
- Por seguridad se rechazan enlaces simbólicos, enlaces duros, rutas absolutas y recorridos `..`, y no se sobrescriben archivos existentes.

## Estructura

| Ruta | Contenido |
| --- | --- |
| `App/` | Interfaz SwiftUI e ícono |
| `Engine/` | Extractor en C (`Extractor.c`) que usa libarchive |
| `Vendor/` | Fuente oficial de libarchive 3.8.4 y su licencia |
| `build-engine.sh` | Compila libarchive como biblioteca estática para el SDK y arquitectura en uso; Xcode lo ejecuta en cada build |

## Licencia

El código de DirectRAR se publica bajo licencia [MIT](LICENSE).

libarchive se distribuye bajo su propia licencia (BSD), incluida en [Vendor/LIBARCHIVE-LICENSE.txt](Vendor/LIBARCHIVE-LICENSE.txt).
