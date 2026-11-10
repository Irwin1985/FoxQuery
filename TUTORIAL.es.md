# FoxQuery paso a paso

En este tutorial vas a guardar las consultas SQL de un programa en ficheros `.sql`, a ejecutarlas por su
nombre contra tablas DBF y después contra SQLite sin cambiar una línea, y a terminar con un `.exe` que
lleva las consultas dentro. Todo con funciones desde un `.prg`; las clases salen al final, para quien las
quiera.

Necesitas Visual FoxPro 9 SP2 y el fichero `foxquery.prg`. Para el paso 6, el driver ODBC de SQLite.
Cada paso dice qué fichero crear, qué escribir dentro y qué tiene que salir en pantalla. Si en algún paso
sale otra cosa, para ahí: el error dice qué ha pasado.

Los programas del tutorial escriben en inglés lo que enseñan en pantalla, igual que los mensajes de
FoxQuery.

## Paso 1: la carpeta y la librería

En la ventana de comandos de Visual FoxPro, escribe estas dos líneas, cada una seguida de Intro:

```foxpro
MKDIR C:\FoxQueryTutorial
SET DEFAULT TO C:\FoxQueryTutorial
```

Copia `foxquery.prg` en `C:\FoxQueryTutorial`. Si usas FoxPack, `foxpack add foxquery` lo deja en
`lib\foxquery\` de tu proyecto: cópialo de ahí.

Ahora crea el primer programa. Escribe en la ventana de comandos:

```foxpro
MODIFY COMMAND step01-hello
```

Se abre el editor. Escribe esto dentro:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
? FQ_VERSION()
```

Pulsa Ctrl+W para guardar y cerrar. Escribe `DO step01-hello` en la ventana de comandos y pulsa Intro.
En la ventana principal de Visual FoxPro sale:

```
1.0.2
```

La primera línea carga FoxQuery; la segunda pregunta su versión. Todos los programas del tutorial empiezan
con esa misma primera línea. Si en vez de la versión sale «File 'foxquery.prg' does not exist», el fichero
no está en `C:\FoxQueryTutorial`, o `SET DEFAULT` apunta a otra carpeta.

A partir de aquí, cada programa nuevo se hace igual: `MODIFY COMMAND` con su nombre, escribir el código,
Ctrl+W y `DO` con su nombre.

## Paso 2: una tabla de clientes

Crea `step02-table.prg`:

```foxpro
SET SAFETY OFF
CLOSE TABLES ALL
CREATE TABLE customers FREE (id I, name C(30), city C(20), country C(2), born D)
INSERT INTO customers VALUES (1, "Ana Muñoz", "Oslo", "NO", DATE(1990, 5, 1))
INSERT INTO customers VALUES (2, "Erik Berg", "Oslo", "NO", DATE(1975, 3, 1))
INSERT INTO customers VALUES (3, "Carla Ruiz", "Madrid", "ES", DATE(1995, 7, 1))
INSERT INTO customers VALUES (4, "Dora Lima", "Lisboa", "PT", DATE(1980, 1, 15))
INSERT INTO customers VALUES (5, "Hans Weber", "Berlin", "DE", DATE(1988, 8, 8))
? RECCOUNT("customers")
USE IN customers
```

Ejecútalo con `DO step02-table`. Sale:

```
5
```

Ahora tienes `customers.dbf` en la carpeta, con cinco clientes. Uno de ellos lleva eñe: Ana Muñoz.
`SET SAFETY OFF` hace que, si vuelves a ejecutar el programa, la tabla se cree otra vez sin preguntarte si
quieres sobrescribirla. `FREE` dice que es una tabla libre, fuera de cualquier base de datos.

## Paso 3: la primera consulta

Las consultas van en una carpeta, una por fichero. Crea la carpeta y el fichero de la primera:

```foxpro
MKDIR queries
MODIFY FILE queries\customers.by_city.sql
```

Escribe esto en el editor y guarda con Ctrl+W:

```sql
-- name: customers.by_city
-- description: The customers of one city, by name.
-- kind: read
-- param: city C required
SELECT id, name, city
FROM customers
WHERE city = :city
ORDER BY name
```

Las cuatro primeras líneas son la cabecera. Empiezan por `--`, que en SQL es un comentario, así que el
fichero sigue siendo SQL que puedes pegar en cualquier herramienta de base de datos.

- `-- name: customers.by_city` es el nombre de la consulta. Tiene que ser el nombre del fichero sin
  `.sql`. El punto del medio solo sirve para agrupar las consultas de los clientes.
- `-- description:` dice para qué sirve, a quien lea el fichero.
- `-- kind: read` dice que la consulta lee (un `SELECT`). Las que escriben (`INSERT`, `UPDATE`, `DELETE`)
  llevan `-- kind: write`.
- `-- param: city C required` declara un parámetro: se llama `city`, es de tipo `C` (texto) y es
  obligatorio.

Debajo va la SQL. `:city` es el sitio del parámetro: FoxQuery manda el valor aparte, nunca lo pega en el
texto de la SQL.

Crea `step03-load.prg`, que carga la carpeta:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
IF FQ_LOAD("queries\")
	? "The queries are loaded"
ELSE
	? FQ_ERRORS()
ENDIF
```

`DO step03-load` enseña:

```
The queries are loaded
```

Si te has equivocado en la cabecera, sale en su lugar la línea del error con el nombre del fichero, la
línea y lo que pasa. En el paso 9 se ven los errores más corrientes.

## Paso 4: ejecutar la consulta

Crea `step04-run.prg`:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
=FQ_LOAD("queries\")
=FQ_USE_DBF()
IF FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	SELECT c_result
	SCAN
		? id, name, city
	ENDSCAN
ELSE
	? FQ_LAST_ERROR()
ENDIF
IF !FQ_RUN("customers.by_city", "c_result")
	? FQ_LAST_ERROR()
ENDIF
```

`DO step04-run` enseña:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
FQ_RUN: param_missing: city (customers.by_city needs it, and the call gives no city)
```

Los números salen con unos espacios delante: así alinea VFP los números con `?`.

Línea a línea:

- `FQ_LOAD("queries\")` carga las consultas de la carpeta.
- `FQ_USE_DBF()` dice dónde corren: en las tablas DBF de la carpeta actual.
- `FQ_RUN("customers.by_city", "c_result", "city", "Oslo")` ejecuta la consulta por su nombre y deja las
  filas en el cursor `c_result`. Detrás del nombre del cursor van los parámetros por pares: el nombre del
  parámetro y su valor. Devuelve `.T.` si fue bien.
- El `SCAN` recorre el cursor y escribe cada fila. Si prefieres verlo en una rejilla, escribe
  `BROWSE` en la ventana de comandos después de ejecutar el programa.

La segunda llamada a `FQ_RUN` no pasa la ciudad, así que FoxQuery devuelve `.F.` sin tocar la tabla, y
`FQ_LAST_ERROR()` dice qué función falló, el código del error (`param_missing`) y qué falta. Todas las
funciones de FoxQuery fallan así, sin enseñar ventanas ni parar el programa.

## Paso 5: un filtro opcional, el orden y una lista

Crea dos consultas más. La primera, `queries\customers.search.sql`:

```sql
-- name: customers.search
-- description: The customers of one city, born since a date if you give one, in the order you choose.
-- kind: read
-- param: city C required
-- param: since D
-- sort: name, id
SELECT id, name
FROM customers
WHERE city = :city {if :since}AND born >= :since{endif}
ORDER BY {sort name}
```

Tiene tres cosas nuevas:

- `-- param: since D` es un parámetro de tipo fecha sin `required`, así que es opcional.
- `{if :since}AND born >= :since{endif}` es un trozo que solo entra en la SQL cuando la llamada pasa
  `since`. Si no lo pasa, el `WHERE` se queda en `city = :city`.
- `-- sort: name, id` dice por qué columnas puede ordenar quien llama, y `{sort name}` es el sitio del
  `ORDER BY`, con `name` cuando la llamada no dice nada. Una columna que no está en la lista no llega
  nunca a la SQL.

La segunda, `queries\customers.in_countries.sql`:

```sql
-- name: customers.in_countries
-- description: The customers of a list of countries.
-- kind: read
-- param: countries C required list
SELECT id, name, country
FROM customers
WHERE country IN (:countries)
ORDER BY name
```

La palabra `list` dice que `countries` es una lista de valores, para el `IN`.

Crea `step05-options.prg`:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
=FQ_LOAD("queries\")
=FQ_USE_DBF()
? "Oslo:"
IF FQ_RUN("customers.search", "c_result", "city", "Oslo")
	SELECT c_result
	SCAN
		? id, name
	ENDSCAN
ENDIF
? "Oslo, born in 1985 or later:"
IF FQ_RUN("customers.search", "c_result", "city", "Oslo", "since", DATE(1985, 1, 1))
	SELECT c_result
	SCAN
		? id, name
	ENDSCAN
ENDIF
? "Oslo, by id from the last:"
IF FQ_RUN("customers.search", "c_result", "city", "Oslo", "sort", "id DESC")
	SELECT c_result
	SCAN
		? id, name
	ENDSCAN
ENDIF
? "Spain, Portugal and Germany:"
IF FQ_RUN("customers.in_countries", "c_result", "countries", "ES,PT,DE")
	SELECT c_result
	SCAN
		? id, name, country
	ENDSCAN
ENDIF
```

`DO step05-options` enseña:

```
Oslo:
1 Ana Muñoz
2 Erik Berg
Oslo, born in 1985 or later:
1 Ana Muñoz
Oslo, by id from the last:
2 Erik Berg
1 Ana Muñoz
Spain, Portugal and Germany:
3 Carla Ruiz                     ES
4 Dora Lima                      PT
5 Hans Weber                     DE
```

El orden va como un par más: `"sort", "id DESC"`. La lista va como un texto con comas
(`"ES,PT,DE"`); si la tienes en un array, pásalo con `@` delante: `"countries", @laCountries`.

## Paso 6: el mismo `.sql` contra SQLite

SQLite es una base de datos en un solo fichero, sin servidor. Para este paso necesitas su driver ODBC de
32 bits: descarga `sqliteodbc.exe` de ch-werner.de e instálalo. Visual FoxPro es un programa de 32 bits y
no ve los drivers de 64 bits.

Crea una consulta más, `queries\customers.by_initial.sql`:

```sql
-- name: customers.by_initial
-- description: The customers whose name starts with a letter.
-- kind: read
-- param: letter C required
SELECT id, name
FROM customers
WHERE {substr name, 1, 1} = :letter
ORDER BY name
```

`{substr name, 1, 1}` es una macro: cada motor de base de datos escribe a su manera lo de sacar un trozo
de texto, y FoxQuery pone en cada uno lo que le toca.

Crea `step06-sqlite.prg`:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
LOCAL lnHandle
lnHandle = SQLSTRINGCONNECT("Driver={SQLite3 ODBC Driver};Database=" + FULLPATH("tutorial.db") + ";NoWCHAR=1;")
IF lnHandle < 1
	? "No connection: is the SQLite3 ODBC Driver installed?"
	RETURN
ENDIF
=SQLEXEC(lnHandle, "DROP TABLE IF EXISTS customers")
=SQLEXEC(lnHandle, "CREATE TABLE customers (id INTEGER, name VARCHAR(30), city VARCHAR(20), country VARCHAR(2), born DATE)")
=SQLEXEC(lnHandle, "INSERT INTO customers VALUES (1, 'Ana Muñoz', 'Oslo', 'NO', '1990-05-01')")
=SQLEXEC(lnHandle, "INSERT INTO customers VALUES (2, 'Erik Berg', 'Oslo', 'NO', '1975-03-01')")
=SQLEXEC(lnHandle, "INSERT INTO customers VALUES (3, 'Carla Ruiz', 'Madrid', 'ES', '1995-07-01')")
=SQLEXEC(lnHandle, "INSERT INTO customers VALUES (4, 'Dora Lima', 'Lisboa', 'PT', '1980-01-15')")
=SQLEXEC(lnHandle, "INSERT INTO customers VALUES (5, 'Hans Weber', 'Berlin', 'DE', '1988-08-08')")
=FQ_LOAD("queries\")
IF !FQ_USE_HANDLE(lnHandle)
	? FQ_LAST_ERROR()
ENDIF
IF FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	SELECT c_result
	SCAN
		? id, name, city
	ENDSCAN
ENDIF
IF FQ_RUN("customers.by_initial", "c_result", "letter", "C")
	SELECT c_result
	SCAN
		? id, name
	ENDSCAN
ENDIF
? FQ_SQL("customers.by_initial", "sqlite")
? FQ_SQL("customers.by_initial", "firebird")
? FQ_SQL("customers.by_initial", "vfp")
=SQLDISCONNECT(lnHandle)
```

`DO step06-sqlite` enseña:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
3 Carla Ruiz
SELECT id, name
FROM customers
WHERE SUBSTR(name, 1, 1) = :letter
ORDER BY name
SELECT id, name
FROM customers
WHERE SUBSTRING(name FROM 1 FOR 1) = :letter
ORDER BY name
SELECT id, name
FROM customers
WHERE SUBSTR(name, 1, 1) = :letter
ORDER BY name
```

El programa abre una conexión con `SQLSTRINGCONNECT`, como harías tú, y crea la misma tabla de clientes
en `tutorial.db`. Después:

- `FQ_USE_HANDLE(lnHandle)` le dice a FoxQuery que las consultas corren en esa conexión. FoxQuery pregunta
  al driver qué motor es (aquí, SQLite) y elige la SQL de ese motor.
- `FQ_RUN` es la misma llamada del paso 4, con el mismo `.sql`, y da las mismas filas. La eñe de Ana
  Muñoz llega bien: SQLite guarda el texto en UTF-8 y FoxQuery hace la conversión en los dos sentidos.
- Las tres últimas líneas enseñan la SQL de `customers.by_initial` para SQLite, para Firebird y para las
  tablas DBF, sin ejecutarla: `FQ_SQL`. La macro sale escrita de dos formas: SQLite y las DBF la escriben
  igual, Firebird a su manera.
- El segundo argumento de `FQ_SQL` es el nombre del motor, uno de estos siete: `sqlserver`, `mysql`,
  `mariadb`, `postgresql`, `firebird`, `sqlite` y `vfp` (las tablas DBF de `FQ_USE_DBF`, del paso 4). Sin
  él, `FQ_SQL` usa el motor que está en uso.
- Si `FQ_SQL`, o cualquier otra `FQ_*`, devuelve `.NULL.` o `.F.`, `? FQ_LAST_ERROR()` dice por qué. Un
  nombre de motor que no existe da `engine_unknown` y la lista de los siete.

Si sale «No connection: is the SQLite3 ODBC Driver installed?», el driver no está instalado, o está
instalado el de 64 bits.

## Paso 7: el catálogo `.fq`

Para la versión que entregas a tus clientes, la carpeta `queries` se compila en un solo fichero firmado:
el catálogo. Crea `step07-build.prg`:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
IF FQ_BUILD("queries\", "app.fq", "my secret key")
	? "app.fq is ready"
ELSE
	? FQ_ERRORS()
ENDIF
```

`DO step07-build` enseña:

```
app.fq is ready
```

`FQ_BUILD` lee todas las consultas de la carpeta, comprueba que están bien y escribe `app.fq` con una firma
hecha con tu clave (`"my secret key"`; en tu programa, pon la tuya). Si una consulta tiene un error, no se
escribe el `.fq` y `FQ_ERRORS()` dice todos los errores, uno por línea.

Ahora crea `step07-catalog.prg`, que carga el catálogo en vez de la carpeta:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
IF !FQ_LOAD("app.fq", "my secret key")
	? FQ_LAST_ERROR()
	RETURN
ENDIF
=FQ_USE_DBF()
IF FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	SELECT c_result
	SCAN
		? id, name, city
	ENDSCAN
ENDIF
```

`DO step07-catalog` enseña los mismos clientes:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

**Qué pasa si alguien toca el `.fq`.** Abre `app.fq` con el Bloc de notas (botón derecho sobre el fichero,
«Abrir con», «Bloc de notas»). Verás texto con caracteres raros; busca `ORDER BY name`, cambia una letra
(por ejemplo, `nAme`) y guarda. Vuelve a Visual FoxPro y ejecuta otra vez `DO step07-catalog`. Sale:

```
FQ_LOAD: catalog_tampered: app.fq: the signature does not match; the file changed, or the key is not the one of the build
```

La firma ya no cuadra con el contenido, y FoxQuery no carga nada del fichero. Lo mismo pasa si cargas el
catálogo con otra clave. Para arreglarlo, compila otra vez: `DO step07-build`, y `DO step07-catalog` vuelve
a enseñar los clientes.

La firma con tu clave impide que alguien cambie las consultas de tu programa, pero el texto de la SQL se
sigue leyendo en el fichero, como acabas de ver. Para esconderlo de quien abra el fichero con un editor, compila
con cifrado: `FQ_BUILD("queries\", "app.fq", "my secret key", .T.)`. La clave va dentro de tu programa, así
que quien se empeñe puede sacarla.

## Paso 8: el catálogo dentro del `.exe`

Crea `step08-main.prg`, que será el programa principal del `.exe`:

```foxpro
IF _VFP.StartMode = 4
	SET DEFAULT TO (JUSTPATH(SYS(16, 0)))
ENDIF
SET PROCEDURE TO foxquery.prg ADDITIVE
IF FQ_LOAD("app.fq", "my secret key") AND FQ_USE_DBF() AND FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	SELECT c_result
	SCAN
		? id, name, city
	ENDSCAN
ELSE
	? FQ_LAST_ERROR()
ENDIF
WAIT WINDOW "Press a key to close"
```

Las tres primeras líneas son para el `.exe`: `_VFP.StartMode` vale 4 cuando el programa corre como `.exe`, y
entonces `SET DEFAULT` pone como carpeta actual la del `.exe` (`SYS(16, 0)` es la ruta del `.exe`). Desde la
ventana de comandos no hacen nada, porque la carpeta actual ya es `C:\FoxQueryTutorial`.

Pruébalo primero desde la ventana de comandos: `DO step08-main` enseña los clientes, sale una ventana con
«Press a key to close» y, al pulsar una tecla, se cierra:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

Ahora el proyecto. En la ventana de comandos:

```foxpro
CREATE PROJECT tutorial
```

Se abre el Project Manager:

1. En la pestaña `Code`, elige `Programs` y pulsa `Add...`. Añade `step08-main.prg`. Vuelve a pulsar
   `Add...` y añade `foxquery.prg`.
2. Haz clic con el botón derecho sobre `step08-main` y elige `Set Main`. Su nombre se pone en negrita.
3. En la pestaña `Other`, elige `Other Files` y pulsa `Add...`. En `Files of type` elige `All Files (*.*)`
   y añade `app.fq`. Si sale con un círculo tachado a la izquierda, está excluido: botón derecho,
   `Include`.
4. Pulsa `Build...`, elige `Win32 executable / COM server (exe)` y pulsa `OK`. Guárdalo como
   `tutorial.exe` en `C:\FoxQueryTutorial`.

Abre `C:\FoxQueryTutorial` en el Explorador de Windows y haz doble clic en `tutorial.exe`. Salen los dos
clientes de Oslo y la ventana «Press a key to close».

`app.fq` va dentro del `.exe`: `FQ_LOAD("app.fq", …)` lo busca primero ahí y, si no está dentro, al lado del
`.exe`. La tabla `customers.dbf` se queda fuera, al lado del `.exe`, como cualquier tabla de datos, y VFP
la busca en la carpeta actual. Para eso están las tres primeras líneas: sin ellas, un `.exe` arrancado desde
otra carpeta (un acceso directo, otra ventana) no encuentra la tabla, y `FQ_RUN` da `executor_failed` con un
mensaje que dice que `customers.dbf` no existe. En tu programa, las tablas están donde tu programa diga: la
carpeta del `.exe`, un `SET PATH` o una base de datos abierta.

## Paso 9: los errores más corrientes

Crea `step09-errors.prg`. Provoca seis errores a propósito:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
SET SAFETY OFF
LOCAL lcSql
=FQ_LOAD("queries\")
=FQ_USE_DBF()
IF !FQ_RUN("customers.by_city", "c_result")
	? FQ_LAST_ERROR()
ENDIF
IF !FQ_RUN("customers.by_city", "c_result", "cty", "Oslo")
	? FQ_LAST_ERROR()
ENDIF
IF !FQ_RUN("customers.by_city", "c_result", "city", 42)
	? FQ_LAST_ERROR()
ENDIF
IF !FQ_RUN("customers.by_town", "c_result", "city", "Oslo")
	? FQ_LAST_ERROR()
ENDIF
IF !FQ_RUN("customers.by_city", "c_result", "city")
	? FQ_LAST_ERROR()
ENDIF
IF !DIRECTORY("broken")
	MKDIR broken
ENDIF
lcSql = "-- name: customers.broken" + CHR(13) + CHR(10) + ;
	"-- param: city X required" + CHR(13) + CHR(10) + ;
	"SELECT id FROM customers WHERE city = :city"
=STRTOFILE(lcSql, "broken\customers.broken.sql")
IF !FQ_LOAD("broken\")
	? FQ_ERRORS()
ENDIF
```

`DO step09-errors` enseña:

```
FQ_RUN: param_missing: city (customers.by_city needs it, and the call gives no city)
FQ_RUN: param_unknown: cty (customers.by_city declares city)
FQ_RUN: param_type: city is declared C and the value is N (customers.by_city)
FQ_RUN: query_not_found: there is no query called customers.by_town
FQ_RUN: param_name_invalid: the parameter city has no value: the arguments go in pairs, name and value
customers.broken.sql(2): param_type_invalid: the type of city is 'X': it is one of C N I D T L Y M
customers.broken.sql(1): header_kind_missing: the header has no '-- kind:' (read or write)
```

Uno por uno:

1. `param_missing`: falta un parámetro obligatorio. Pásalo.
2. `param_unknown`: el nombre del parámetro está mal escrito (`cty` en vez de `city`). El mensaje dice
   los parámetros que la consulta declara: escribe uno de ellos.
3. `param_type`: el valor no es del tipo que dice la cabecera (`42` es un número y `city` es `C`).
   Pasa un valor del tipo de `-- param:`.
4. `query_not_found`: no hay ninguna consulta con ese nombre. Mira cómo se llama el fichero y que esté en
   la carpeta que cargaste.
5. `param_name_invalid`: los parámetros van por pares, y aquí falta el valor de `city`.
6. Un `.sql` con dos errores: `FQ_ERRORS()` dice los dos, cada uno con su fichero y su línea entre
   paréntesis. El tipo `X` no existe (son `C N I D T L Y M`) y falta la línea `-- kind:`. Cuando una carga
   falla, lo que estaba cargado se queda como estaba: las consultas de `queries` siguen funcionando.

La lista completa de códigos, con lo que hay que hacer en cada caso, está en el apartado «Errores» de
[README.es.md](README.es.md).

## Paso 10: lo mismo con clases

Las funciones `FQ_*` usan por dentro unas clases que también puedes usar tú. Crea `step10-classes.prg`:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
LOCAL loStore, loDb, loParams
loStore = CREATEOBJECT("QueryStore")
IF !loStore.LoadFolder("queries\")
	? loStore.cLastError
	RETURN
ENDIF
loDb = CREATEOBJECT("QueryLocal")
loParams = CREATEOBJECT("Empty")
ADDPROPERTY(loParams, "city", "Oslo")
IF loStore.Run(loDb, "customers.by_city", loParams, "c_result")
	SELECT c_result
	SCAN
		? id, name, city
	ENDSCAN
ELSE
	? loStore.cLastErrorCode, loStore.cLastError
ENDIF
```

`DO step10-classes` enseña:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

`QueryStore` es el almacén de consultas y `QueryLocal`, el ejecutor de tablas DBF. Para una conexión
ODBC, el ejecutor es `QueryOdbc` (`CREATEOBJECT("QueryOdbc", lnHandle)`), y si ya usas FoxRemote, una de
sus bases de datos vale tal cual como ejecutor. Los parámetros van en un objeto con una propiedad por
parámetro. Los fallos se leen en `cLastErrorCode` y `cLastError` en lugar de en `FQ_LAST_ERROR()`.

Todo lo que hacen las clases está en el apartado «API» de [README.es.md](README.es.md).
