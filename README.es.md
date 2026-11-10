# FoxQuery

[English](README.md) · Español · [Deutsch](README.de.md)

FoxQuery guarda la SQL de una aplicación de Visual FoxPro 9 en consultas con nombre: un fichero `.sql` por
consulta, con una cabecera corta que dice su nombre, su tipo y sus parámetros. Tu programa pide una consulta
por su nombre (`customers.by_city`), pasa los valores como parámetros y nunca construye texto SQL.

El mismo fichero `.sql` funciona en SQL Server, MySQL, MariaDB, PostgreSQL, Firebird, SQLite y en tablas DBF
locales. Para la versión que entregas, los ficheros se compilan en un solo catálogo firmado (`.fq`) que viaja
dentro del EXE o a su lado.

Puedes usarlo desde un `.prg` con funciones sencillas (`FQ_LOAD`, `FQ_RUN`, …) y sin ninguna clase.
Funciona con los valores por defecto, y cuando algo está mal el error dice el fichero, la línea, qué pasó y
qué hacer.

## Instalación

Con [FoxPack](https://irwinrodriguez.dev/products/foxpack), que descarga librerías para proyectos de Visual
FoxPro en una versión fija:

```
foxpack add foxquery
```

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
```

Sin FoxPack, copia `foxquery.prg` junto a tu programa: es la librería entera. Necesita Visual FoxPro 9 SP2 y
nada más. FoxQuery no se conecta a ningún servidor: ejecuta las consultas sobre una conexión que abres tú,
así que el driver ODBC de tu motor lo necesitas igualmente. VFP es un programa de 32 bits y necesita el
driver de **32 bits**, también en Windows de 64 bits. Estos son los drivers con los que se prueba FoxQuery:

| Motor | Driver | Probado con |
|---|---|---|
| SQL Server | `ODBC Driver 18 for SQL Server` o `ODBC Driver 17 for SQL Server` | SQL Server 2025 Express |
| MySQL | `MariaDB ODBC 3.2 Driver` (el de MariaDB: mira [Lo que conviene saber](#lo-que-conviene-saber)) | MySQL 8.4 |
| MariaDB | `MariaDB ODBC 3.2 Driver` | MariaDB 11.8 |
| PostgreSQL | `PostgreSQL ANSI` (psqlODBC) | PostgreSQL 18 |
| Firebird | `Firebird ODBC Driver` 3.0, con el `fbclient.dll` de 32 bits | Firebird 5.0 |
| SQLite | `SQLite3 ODBC Driver` 0.99991 (ch-werner.de, `sqliteodbc.exe`) | SQLite 3.43 |
| DBF local | ninguno | Visual FoxPro 9 SP2 |

FoxNone es opcional. Es una librería pequeña que también se instala con FoxPack (`foxpack add foxnone`), y
`FQ_PARAMS()` y `QueryStore.Params()` devuelven uno de sus objetos. Sin FoxNone, todo lo demás funciona.

## Ejemplo

Pégalo en un `.prg` en una carpeta vacía y ejecútalo. Crea una tabla DBF y una consulta, y ejecuta la
consulta sobre la DBF: no hace falta ningún servidor.

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
SET SAFETY OFF
CLOSE TABLES ALL
LOCAL lcSql

* A table with three customers
CREATE TABLE customers FREE (id I, name C(30), city C(20))
INSERT INTO customers VALUES (1, "Ana Muñoz", "Oslo")
INSERT INTO customers VALUES (2, "Erik Berg", "Oslo")
INSERT INTO customers VALUES (3, "Carla Ruiz", "Madrid")
USE IN customers

* One query, in its own .sql file
IF !DIRECTORY("queries")
	MKDIR queries
ENDIF
lcSql = "-- name: customers.by_city" + CHR(13) + CHR(10) + ;
	"-- kind: read" + CHR(13) + CHR(10) + ;
	"-- param: city C required" + CHR(13) + CHR(10) + ;
	"SELECT id, name FROM customers WHERE city = :city ORDER BY name"
=STRTOFILE(lcSql, "queries\customers.by_city.sql")

* Load the queries, say where they run, and run one by its name
IF FQ_LOAD("queries\") AND FQ_USE_DBF() AND FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	SELECT c_result
	SCAN
		? id, name
	ENDSCAN
ELSE
	? FQ_LAST_ERROR()
ENDIF
```

Muestra:

```
1 Ana Muñoz
2 Erik Berg
```

Para ir paso a paso desde cero, sigue [TUTORIAL.es.md](TUTORIAL.es.md).

## Los ficheros `.sql`

Un fichero por consulta, en una carpeta (`queries\`). El nombre del fichero es el nombre de la consulta más
`.sql`. El fichero es texto plano en Windows-1252 (CP1252), como cualquier fuente de VFP. Primero va la
cabecera, como comentarios de SQL, y debajo va la SQL:

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

| Línea de la cabecera | Qué dice |
|---|---|
| `-- name: customers.search` | El nombre de la consulta. Tiene que ser el nombre del fichero sin `.sql`. Obligatoria |
| `-- description: …` | Texto libre, para quien lea el fichero. Opcional |
| `-- kind: read` | `read` para un `SELECT` (se ejecuta con `FQ_RUN` o `FQ_SCALAR`), `write` para `INSERT`, `UPDATE` o `DELETE` (se ejecuta con `FQ_EXECUTE`). Obligatoria. FoxQuery lo comprueba con la primera palabra de la SQL |
| `-- param: city C required` | Una línea por parámetro: el nombre, el tipo, y después `required`, `list` y `default <value>`, en cualquier orden |
| `-- ident: sort letters 1-20` | Un identificador: un nombre que el programa escribe en la SQL con `FQ_SET`, una vez, para todas las consultas que lo usan. Su forma dice qué valor admite (`digits`, `letters`, `alnum` o `ident`, y una longitud `2` o un rango `1-20`) |
| `-- sort: name, id` | Las columnas que quien llama puede elegir para el `ORDER BY` (mira `{sort}` más abajo) |
| `-- engine: firebird` | Empieza un texto SQL entero para un motor. Va después de la SQL común |

**Los tipos** son los de VFP: `C` (texto), `N` (cualquier número), `I` (un número entero), `D` (fecha), `T`
(fecha y hora), `L` (lógico), `Y` (moneda, que también acepta un número) y `M` (memo). FoxQuery comprueba el
tipo de cada valor antes de que nada llegue al motor (`param_type`).

**`default <value>`** se usa cuando la llamada no da el parámetro: un número (`10`), un texto entre comillas
(`'Oslo'` o `"Oslo"`), una fecha (`{^2026-11-04}`, o `{}` para una vacía), una fecha y hora
(`{^2026-11-04 10:30}`), `.T.`, `.F.` o `.NULL.`. Una lista no lleva valor por defecto. Un parámetro
opcional sin valor por defecto que la llamada no da llega al motor como `.NULL.`.

**Comentarios.** En una línea de la cabecera, lo que viene después de ` --` es un comentario. Una línea de la
SQL que empieza por `--` también es un comentario. Un `--` después de SQL en la misma línea se queda en el
texto: mira [Lo que conviene saber](#lo-que-conviene-saber).

**Qué va en la SQL:**

- **`:name`** es un parámetro. El valor viaja aparte del texto, como parámetro ODBC (o, en DBF, como una
  propiedad que lee VFP): ningún valor de quien llama se pega nunca en la SQL. Un `:` entre comillas y el
  `::` de PostgreSQL se dejan como están.
- **`{if :since} … {endif}`**: el texto de dentro entra en la SQL solo cuando la llamada da `since` (como par,
  o como propiedad del objeto), sea cual sea su valor. Un solo nivel: un `{if}` dentro de otro es
  `if_unbalanced`.
- **`{ident sort}`** escribe el valor que el programa fijó con `FQ_SET("sort", "name")`, tal cual y sin comillas:
  `ORDER BY {ident sort}` se ejecuta como `ORDER BY name`. Sirve para un nombre dentro de la SQL (una columna, por
  ejemplo), fijado una vez para todas las consultas que lo usan; `{sort}`, más abajo, es el orden que elige cada
  llamada. FoxQuery comprueba el valor al fijarlo (solo letras, dígitos y `_`, y la forma de `-- ident:`), y una
  llamada no puede traerlo (`ident_not_a_param`). Un `{ident}` entre comillas se queda como está. El ejemplo está en
  [FQ_SET](#fq_setcname-cvalue).
- **`{sort}`** es el `ORDER BY` que quien llama elige entre las columnas de `-- sort:`, cada una con `ASC` o
  `DESC`: `"sort", "name DESC"` o `"sort", "name, id DESC"`. `{sort name}` dice cuál usar cuando la llamada
  no dice nada. Cualquier cosa que no esté en la lista es `bad_option`, y no llega nada al motor. En `vfp`
  (DBF), `{sort}` escribe la posición de cada columna en la lista del `SELECT` (`ORDER BY 2 DESC, 1`): por
  nombre, un alias que también es columna de una tabla unida da el error 1832 de VFP. Por eso en `vfp` cada
  columna de `-- sort:` tiene que estar en esa lista, y un `SELECT *` no vale (`sort_not_in_select`). Los demás
  motores reciben los nombres.
- **Una lista** (`-- param: countries C required list`, e `IN (:countries)` en la SQL) acepta un texto con
  comas (`"ES,PT,DE"`), un array pasado con `@`, o una `Collection`. FoxQuery escribe
  `IN (:countries_1, :countries_2, :countries_3)` y manda un parámetro por elemento. El texto con comas vale solo
  para listas de `C` y `M`; una lista de números o de fechas es un array o una `Collection`. Una lista vacía es
  `param_type` con «the list is empty», venga como venga: un texto vacío, una `Collection` vacía o un array de un
  solo `.F.` (en VFP no hay arrays sin elementos: es lo que dejan `DIMENSION`, `ADIR` o `ALINES`). En una lista de
  `L`, `[.F.]` es el valor falso.
- **`{macro …}`**: las nueve macros de abajo, para lo que cada motor escribe a su manera.
- **Un texto entero para un motor**: después de la SQL común, una línea `-- engine: firebird` y la SQL de ese
  motor. Los motores son `sqlserver`, `mysql`, `mariadb`, `postgresql`, `firebird`, `sqlite` y `vfp` (tablas
  DBF locales).

**Lo que no puedes hacer.** Un nombre de tabla o de columna que venga de quien llama: escribe una consulta
para cada caso. Esa es la inyección SQL clásica, y FoxQuery no tiene forma de hacerlo.

## Macros

FoxQuery trae nueve, comprobadas en los siete motores. Sus argumentos van separados por comas.

| Macro | SQL Server | MySQL / MariaDB | PostgreSQL | Firebird | SQLite | VFP |
|---|---|---|---|---|---|---|
| `{limit n}` | `OFFSET 0 ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n` | `LIMIT n` | `ROWS n` | `LIMIT n` | `TOP n` detrás del `SELECT` |
| `{offset k}` | `OFFSET k ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n OFFSET k` | `LIMIT n OFFSET k` | `OFFSET k ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n OFFSET k` | no se puede |
| `{concat a, b, …}` | `a + b` | `CONCAT(a, b)` | `a \|\| b` | `a \|\| b` | `a \|\| b` | `a + b` |
| `{now}` | `GETDATE()` | `NOW()` | `LOCALTIMESTAMP` | `LOCALTIMESTAMP` | `datetime('now', 'localtime')` | `DATETIME()` |
| `{nvl a, b}` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `NVL(a, b)` |
| `{substr s, i, n}` | `SUBSTRING(s, i, n)` | `SUBSTRING(s, i, n)` | `SUBSTRING(s, i, n)` | `SUBSTRING(s FROM i FOR n)` | `SUBSTR(s, i, n)` | `SUBSTR(s, i, n)` |
| `{true}` | `1` | `1` | `TRUE` | `TRUE` | `1` | `.T.` |
| `{false}` | `0` | `0` | `FALSE` | `FALSE` | `0` | `.F.` |
| `{like_ci col, :p}` | `UPPER(col) LIKE UPPER(:p)` | igual | igual | igual | igual | igual |

**`{limit}` y `{offset}`** aceptan un parámetro declarado `N` o `I` (`{limit :rows}`) o un número entero
(`{limit 10}`). Van al final de la sentencia, `{offset}` justo después de `{limit}`, y la consulta necesita un
`ORDER BY` (SQL Server y VFP lo piden, y con él todos los motores devuelven las mismas filas). FoxQuery
comprueba que el número es entero y no negativo, y lo escribe en la SQL: es el único valor de quien llama que
entra en el texto, porque el driver de MariaDB no puede enlazarlo como parámetro. En VFP, `{limit}` se
convierte en `TOP n` detrás del `SELECT`, `{offset}` no existe (`macro_unsupported`) y `TOP 0` tampoco (un 0
es `limit_value_invalid`).

**Tus propias macros**: `FQ_ADD_MACRO(cEngine, cName, cTemplate)`, o `AddMacro` en la clase. De `$1` a `$9`
son los argumentos; `$*[sep]` son todos ellos unidos por `sep` (`, ` cuando no hay corchetes). La misma
llamada sobre un motor que ya tiene la macro la sustituye para ese motor.

```foxpro
=FQ_ADD_MACRO("sqlite", "greatest", "MAX($*[, ])")
=FQ_ADD_MACRO("vfp", "greatest", "MAX($*[, ])")
```

Una macro tiene que existir para un motor antes de que se ejecute allí una consulta que la usa: para los
demás es `macro_unknown`.

## El catálogo `.fq`

Para la versión que entregas, `FQ_BUILD` compila la carpeta en un solo fichero:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
IF !FQ_BUILD("queries\", "app.fq", "the key of my application")
	? FQ_ERRORS()
	RETURN
ENDIF
IF FQ_LOAD("app.fq", "the key of my application") AND FQ_USE_DBF() AND FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	SELECT c_result
	SCAN
		? id, name
	ENDSCAN
ELSE
	? FQ_LAST_ERROR()
ENDIF
```

```
1 Ana Muñoz
2 Erik Berg
```

- **`FQ_BUILD` lee la carpeta igual que `FQ_LOAD`**: todo o nada, con los mismos errores. Si un fichero está
  mal no hay `.fq`, y `FQ_ERRORS()` lista todos los errores.
- **El `.fq` guarda cada consulta ya resuelta para los siete motores** (la variante o el texto común, con las
  macros ya escritas). Donde un motor no puede ejecutar una consulta (`{offset}` en VFP), el `.fq` guarda el
  error, y la consulta sigue funcionando en los demás.
- **La clave.** Con tu clave, un `.fq` que alguien cambia a propósito no carga (`catalog_tampered`). Sin
  clave, FoxQuery usa una clave fija propia: un `.fq` cambiado por error (un editor que lo guardó) no carga,
  pero alguien que conozca FoxQuery puede firmar uno nuevo.
- **Cifrar** (`FQ_BUILD(cFolder, cFq, cKey, .T.)`) oculta la SQL a quien abra tu EXE con un editor, y nada
  más. Necesita tu clave (`catalog_key_required`). Tu clave viaja dentro de tu programa: lo que viaja en el
  EXE no es un secreto para quien se ponga a buscarlo.
- **Dónde lo encuentra `FQ_LOAD`**: por el nombre que le das, primero dentro del EXE (añade el `.fq` al
  proyecto como fichero, incluido); si no está ahí, junto al EXE, también cuando el programa arranca desde
  otra carpeta.
- **Un catálogo cargado está congelado**: sus consultas llevan las macros con las que se compilaron.
  `FQ_ADD_MACRO` da `catalog_frozen`, y la macro queda apuntada para el siguiente `FQ_BUILD`. Un `FQ_LOAD` de
  una carpeta vuelve a los ficheros `.sql`.
- **Cuánto tarda**: depende más del tamaño del catálogo que del número de consultas. Con 500 consultas, medido en
  un portátil de desarrollo: un `.fq` de 1 MB (consultas cortas) tarda unos 4 segundos en construirse y 50
  milisegundos en cargarse; uno de 2 MB, 7 segundos y 75 milisegundos (85 cifrado); uno de 14 MB (consultas de unos
  4 KB), 66 segundos y 230 milisegundos (255 cifrado). En una máquina más lenta, en una aplicación con 500 consultas
  y un `.fq` de 2 MB, fueron 7,9 segundos y 216 milisegundos. Se carga una vez, al arrancar el programa.
- **El formato tiene versión.** Un `.fq` construido por un FoxQuery anterior da `catalog_version`: vuelve a
  construirlo.

## API

### Las funciones

Guardan su estado en `_SCREEN`: un segundo `SET PROCEDURE TO foxquery.prg ADDITIVE` no pierde nada.

**Cómo fallan.** Cuando algo va mal al ejecutar (un parámetro que falta, una consulta que no existe, el motor
que falla), la función devuelve su valor de fallo (`.F.`, `.NULL.` o `-1`) y `FQ_LAST_ERROR()` dice por qué,
con el nombre de la función delante:
`FQ_RUN: param_missing: city (…)`. `FQ_LAST_ERROR_CODE()` devuelve solo el código. Cada función que hace
algo los vacía primero. Un programa que llama a `FQ_RUN` antes de `FQ_LOAD`, o antes de una de las funciones
`FQ_USE…`, tiene un bug: eso lanza un error de VFP. Con `FQ_STRICT(.T.)` cada fallo lanza un error de
VFP.

**Los parámetros van en pares** después de los argumentos fijos: el nombre y luego el valor. Hasta 12 pares en
`FQ_RUN` y 13 en `FQ_SCALAR` y `FQ_EXECUTE`. Con más, pasa un objeto en el lugar del primer par: cualquier
objeto cuyas propiedades sean los parámetros (`CREATEOBJECT("Empty")` con `ADDPROPERTY`, o `FQ_PARAMS()`).
Una lista va como texto con comas o como array con `@`; el orden de `{sort}` va como el par `"sort"`.

### FQ_LOAD(cFolderOrFq [, cKey])

Carga los ficheros `.sql` de una carpeta, o un catálogo `.fq` con su clave. Todo o nada: con un solo error,
no se carga nada y lo que estaba cargado antes se queda. Devuelve `.T.` o `.F.`; todos los errores están en
`FQ_ERRORS()`. Lo que un motor no puede ejecutar (`sql_too_long` o `sort_not_in_select` en `vfp`, una
`macro_unsupported`) da un aviso en `FQ_WARNINGS()` y la carga sigue, porque los demás motores ejecutan la
consulta. El aviso sale al elegir el motor en uso (`FQ_USE_DBF`, `FQ_USE_HANDLE`, `FQ_USE`; o en este `FQ_LOAD`,
con uno ya en uso).

```foxpro
IF !FQ_LOAD("queries\")
	? FQ_ERRORS()
ENDIF
```

### FQ_RELOAD()

Vuelve a leer la misma carpeta o el mismo `.fq` (después de cambiar un `.sql` con el programa en marcha).
Devuelve `.T.` o `.F.`.

### FQ_BUILD(cFolder, cFq [, cKey [, lEncrypt]])

Compila los ficheros `.sql` de `cFolder` en el catálogo `cFq`, con las macros de `FQ_ADD_MACRO`. No toca lo
que cargó `FQ_LOAD`. Devuelve `.T.` o `.F.`; todos los errores están en `FQ_ERRORS()`. Lo que un motor no puede
ejecutar es un aviso en `FQ_WARNINGS()`, y el `.fq` lo apunta: `FQ_LOAD` de ese `.fq` avisa otra vez.
Si el `.fq` está abierto en un editor (`MODIFY FILE app.fq`, para mirarlo), `FQ_BUILD` no puede escribirlo: `.F.`
con `catalog_not_written`, y el `.fq` de antes se queda como estaba. Si la carpeta de `cFq` no existe, el mismo
`.F.`, y el mensaje dice qué carpeta.

```foxpro
=FQ_BUILD("queries\", "app.fq", "the key of my application")
```

### FQ_ADD_MACRO(cEngine, cName, cTemplate)

Añade una macro tuya, o sustituye una, para un motor. Funciona sobre la carpeta cargada con `FQ_LOAD`, y
`FQ_BUILD` se la pasa siempre al compilador. Con un `.fq` cargado devuelve `.F.` con `catalog_frozen`: el
`.fq` cargado no cambia, y la macro queda apuntada para el siguiente `FQ_BUILD`. Devuelve `.T.` o `.F.`.

```foxpro
=FQ_ADD_MACRO("sqlite", "greatest", "MAX($*[, ])")
```

### FQ_USE_DBF()

Las consultas se ejecutan sobre tablas DBF locales, con la SQL de VFP (el motor `vfp`). VFP encuentra las
tablas como siempre: un alias abierto, la carpeta actual, `SET PATH`, la base de datos abierta. Devuelve
`.T.`. Con consultas cargadas, las que `vfp` no puede ejecutar van a `FQ_WARNINGS()`.

### FQ_USE_HANDLE(nHandle [, cEngine])

Las consultas se ejecutan sobre una conexión que abriste con `SQLCONNECT` o `SQLSTRINGCONNECT`. FoxQuery le
pregunta al driver qué motor es; `cEngine` lo dice cuando el driver no lo dice (`engine_unknown`). FoxQuery
nunca conecta, desconecta ni cambia la conexión. Devuelve `.T.` o `.F.`. Con consultas cargadas, las que ese
motor no puede ejecutar van a `FQ_WARNINGS()`.

```foxpro
=FQ_USE_HANDLE(lnHandle)
```

### FQ_USE(oExecutor)

Las consultas se ejecutan sobre cualquier objeto que ejecute SQL: un objeto de base de datos de FoxRemote (mira
[FoxRemote](#foxremote)), o uno tuyo (mira [Un ejecutor propio](#un-ejecutor-propio)). Devuelve `.T.` o `.F.`.
Con consultas cargadas, las que ese motor no puede ejecutar van a `FQ_WARNINGS()`.

### FQ_RUN(cName [, cCursor [, cParam1, vValue1, … | oParams]])

Ejecuta una consulta `read` en un cursor (`c_fr_query` cuando `cCursor` está vacío). Devuelve `.T.` o `.F.`.

```foxpro
IF !FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	? FQ_LAST_ERROR()
ENDIF
```

### FQ_SCALAR(cName [, cParam1, vValue1, … | oParams])

Ejecuta una consulta `read` que devuelve un valor, y lo devuelve. Devuelve `.NULL.` cuando falla, y también
cuando el valor es `.NULL.` o no hay filas: entonces `FQ_LAST_ERROR()` está vacío.

```foxpro
lnCount = FQ_SCALAR("customers.count_by_city", "city", "Oslo")
```

### FQ_EXECUTE(cName [, cParam1, vValue1, … | oParams])

Ejecuta una consulta `write`. Devuelve el número de filas que cambió, o `-1`.

```foxpro
lnRows = FQ_EXECUTE("customers.deactivate_city", "city", "Oslo")
```

### FQ_SQL(cName [, cEngine [, cObject [, oParams]]])

Devuelve el texto SQL de una consulta para un motor (el que está en uso si `cEngine` está vacío), sin
ejecutarla, o `.NULL.`. Los `:name` se quedan como están; `cObject` los escribe como `?cObject.name`, y
`oParams` resuelve `{if}`, `{sort}` y las listas como lo haría una ejecución.

`cEngine` es uno de los siete: `sqlserver`, `mysql`, `mariadb`, `postgresql`, `firebird`, `sqlite` y `vfp`
(las tablas DBF de `FQ_USE_DBF`); otro nombre da `.NULL.` con `engine_unknown`.

```foxpro
? FQ_SQL("customers.by_city", "postgresql")
```

### FQ_SET(cName, cValue)

Fija el valor de un identificador (`{ident}`, declarado con `-- ident:`) para todas las consultas que lo usan, hasta
que lo vuelvas a fijar. `.T.`, o `.F.` con `ident_invalid` (solo letras, dígitos y `_`, y la forma que declara cada
consulta cargada). `FQ_LOAD` y `FQ_RELOAD` conservan lo fijado, y `FQ_SQL` enseña el texto con el valor puesto. El
valor lo fija el programa, nunca una llamada.

La forma de `-- ident:` dice qué valor admite: `digits` (solo dígitos), `letters` (solo letras), `alnum` (letras y
dígitos) o `ident` (letras, dígitos y `_`), con una longitud (`2`) o un rango (`1-20`). Este ejemplo ordena los
clientes por la columna que fija el programa. Ejecuta la misma consulta sobre una tabla DBF y sobre SQLite, así que
necesita el driver de SQLite:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
SET SAFETY OFF
CLOSE TABLES ALL
LOCAL lcSql, lnHandle

* The same three customers in a DBF table and in a SQLite database
CREATE TABLE customers FREE (id I, name C(30), city C(20))
INSERT INTO customers VALUES (1, "Ana", "Oslo")
INSERT INTO customers VALUES (2, "Erik", "Oslo")
INSERT INTO customers VALUES (3, "Carla", "Madrid")
USE IN customers
lnHandle = SQLSTRINGCONNECT("Driver={SQLite3 ODBC Driver};Database=" + FULLPATH("readme.db") + ";NoWCHAR=1;")
=SQLEXEC(lnHandle, "DROP TABLE IF EXISTS customers")
=SQLEXEC(lnHandle, "CREATE TABLE customers (id INTEGER, name VARCHAR(30), city VARCHAR(20))")
=SQLEXEC(lnHandle, "INSERT INTO customers VALUES (1, 'Ana', 'Oslo'), (2, 'Erik', 'Oslo'), (3, 'Carla', 'Madrid')")

* A query that sorts by the column the program sets
IF !DIRECTORY("queries")
	MKDIR queries
ENDIF
lcSql = "-- name: customers.sorted" + CHR(13) + CHR(10) + ;
	"-- kind: read" + CHR(13) + CHR(10) + ;
	"-- ident: sort letters 1-20" + CHR(13) + CHR(10) + ;
	"SELECT id, name FROM customers ORDER BY {ident sort}"
=STRTOFILE(lcSql, "queries\customers.sorted.sql")

* Set the column once, then run the query on the DBF table and on SQLite
IF FQ_LOAD("queries\") AND FQ_SET("sort", "name") AND ;
		FQ_USE_DBF() AND FQ_RUN("customers.sorted", "c_dbf") AND ;
		FQ_USE_HANDLE(lnHandle) AND FQ_RUN("customers.sorted", "c_sqlite")
	? "DBF"
	SELECT c_dbf
	SCAN
		? id, name
	ENDSCAN
	? "SQLite"
	SELECT c_sqlite
	SCAN
		? id, name
	ENDSCAN
ELSE
	? FQ_LAST_ERROR()
ENDIF
=SQLDISCONNECT(lnHandle)
```

```
DBF
1 Ana
3 Carla
2 Erik
SQLite
1 Ana
3 Carla
2 Erik
```

### FQ_PARAMS()

Devuelve un objeto vacío de FoxNone para meter los parámetros, uno por línea (`loP.city = "Oslo"`), o
`.NULL.` con `foxnone_missing` cuando FoxNone no está cargado.

### FQ_ERRORS()

Todos los errores del último `FQ_LOAD`, `FQ_RELOAD` o `FQ_BUILD`, uno por línea: `file(line): code: reason`,
o `code: reason` cuando no tiene que ver con un fichero `.sql`. `""` cuando ha ido bien.

```
customers.broken.sql(2): param_type_invalid: the type of city is 'X': it is one of C N I D T L Y M
customers.broken.sql(1): header_kind_missing: the header has no '-- kind:' (read or write)
```

### FQ_WARNINGS()

Todos los avisos del último `FQ_LOAD`, `FQ_RELOAD` o `FQ_BUILD`, y del último `FQ_USE_DBF`, `FQ_USE_HANDLE` o
`FQ_USE`, uno por línea como `FQ_ERRORS()`: lo declarado que ningún texto usa (`param_unused`, `ident_unused`), y lo
que el motor en uso no puede ejecutar (`sql_too_long`, `sort_not_in_select`, `macro_unsupported`). Un aviso no impide
la carga: `FQ_RUN` de esa consulta falla con el mismo código, y los demás motores la ejecutan. `""` cuando no hay
ninguno.

```
customers.report.sql(1): sql_too_long: on vfp, the vfp text is 9105 characters as QueryLocal runs it, and VFP runs 8190 at most in one line (…)
```

### FQ_LAST_ERROR() y FQ_LAST_ERROR_CODE()

Por qué falló la última función, con su nombre delante; y solo su código. `""` cuando ha ido bien.

### FQ_STRICT([lOn])

`FQ_STRICT(.T.)`: cada fallo lanza un error de VFP, para los programas que gestionan los errores con
`TRY … CATCH`. Sin argumento solo dice cómo está. Devuelve el estado.

### FQ_STORE() y FQ_DB()

El `QueryStore` y el ejecutor que usan las funciones, para cuando quieras seguir con las clases. Guárdalos
primero en una variable: VFP no puede usar una propiedad de lo que devuelve una función (`FQ_STORE().nQueries`
falla).

### FQ_VERSION()

Devuelve la versión de FoxQuery (`"1.0.2"`).

### Las clases

Las funciones llaman a estas clases, y puedes usarlas directamente:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
LOCAL loStore, loDb, loParams
loStore = CREATEOBJECT("QueryStore")
loDb = CREATEOBJECT("QueryLocal")
loParams = CREATEOBJECT("Empty")
ADDPROPERTY(loParams, "city", "Oslo")
IF loStore.LoadFolder("queries\") AND loStore.Run(loDb, "customers.by_city", loParams, "c_result")
	SELECT c_result
	SCAN
		? id, name
	ENDSCAN
ELSE
	? loStore.cLastErrorCode, loStore.cLastError
ENDIF
```

```
1 Ana Muñoz
2 Erik Berg
```

### QueryStore

| Miembro | Qué hace |
|---|---|
| `LoadFolder(cFolder)` | Carga los ficheros `.sql` de una carpeta. `.T.` o `.F.` |
| `Load(cFq [, cKey])` | Carga un catálogo `.fq`. `.T.` o `.F.` |
| `Reload()` | Vuelve a leer la misma carpeta o el mismo `.fq` |
| `CheckFile(cFile)` | Lee y comprueba un `.sql` como la carga, y no toca nada de lo cargado. Vacía `cLastError` y `cLastErrorCode` al entrar. `.T.`, o `.F.` con el primer error en `cLastError` como una línea de `FQ_ERRORS()` (`file(line): code: reason`) y todos en `aLoadErrors`; `file_not_found`; `query_duplicate` si esa consulta está cargada desde otro fichero |
| `LoadFile(cFile)` | Vacía `cLastError` y `cLastErrorCode` al entrar. `CheckFile`, y después mete la consulta de ese fichero, o reemplaza la que vino de él, en su sitio del orden. Sus textos guardados se van y sus avisos se renuevan (los de la carga, y los del motor del último `CheckEngine`): lo que dejaría `Reload()`, solo para ese fichero. `catalog_frozen` con un `.fq` cargado. `.T.` o `.F.` |
| `Run(oExecutor, cName, oParams [, cCursor])` | Ejecuta una consulta `read` en un cursor. `.T.` o `.F.` |
| `Scalar(oExecutor, cName, oParams)` | Ejecuta una consulta `read` y devuelve un valor, o `.NULL.` |
| `Execute(oExecutor, cName, oParams)` | Ejecuta una consulta `write`. Las filas que cambió, o `-1` |
| `Sql(cName, cEngine [, cObject [, oParams]])` | El texto SQL para un motor, o `.NULL.` |
| `Args(cName, oParams)` | El objeto con los parámetros que `Run` le da al ejecutor, o `.NULL.` |
| `Get(cName)` | El `QueryDef` de una consulta (su cabecera, ya leída), o `.NULL.`. También por su número, `Get(1)` a `Get(nQueries)`, en el orden de carga; fuera de rango, `.NULL.` con `query_not_found` |
| `Names()` | Los nombres de las consultas cargadas en el orden de carga (el del catálogo), en una `Collection` nueva cada vez; vacía si no hay nada cargado. Con un `.fq`, es la forma de saber qué lleva |
| `CheckEngine(cEngine [, nFrom [, nCount]])` | Las consultas cargadas que ese motor no puede ejecutar, cada una un aviso en `aWarnings` (lo que hacen las funciones `FQ_USE…`). Cuántas, o `-1`. Con `nFrom` y `nCount`, solo esas consultas del orden de carga, para repartirlo en los ratos libres: los avisos se suman tramo a tramo, y vuelven a los de la carga con `nFrom` 1 o con otro motor. Un tramo repetido, o dos que se solapan, no ponen un aviso dos veces (el mismo código, fichero y línea) |
| `CheckQuery(cName, cEngine)` | Si ese motor puede con esa consulta. Vacía `cLastError` y `cLastErrorCode` al entrar: `.T.`, o `.F.` con el fallo en `cLastErrorCode` y `cLastError` (el que daría `Sql`). No toca `aWarnings` |
| `SetIdent(cName, cValue)` | Fija un identificador, como `FQ_SET`. `.T.` o `.F.` con `ident_invalid` |
| `AddMacro(cEngine, cName, cTemplate)` | Una macro tuya. `.T.` o `.F.` |
| `Params()` | Un objeto vacío de FoxNone, o `.NULL.` |
| `nQueries` | Cuántas consultas hay cargadas |
| `cFolder`, `cCatalog` | Lo que está cargado: la carpeta, o el `.fq` |
| `nLoadErrors`, `aLoadErrors[n, 4]` | Los errores de la última carga: código, fichero, línea, mensaje |
| `nWarnings`, `aWarnings[n, 4]` | Los avisos de la última carga (`param_unused`, `ident_unused`) y del último `CheckEngine`, de la misma forma |
| `nErrors`, `cLastError`, `cLastErrorCode` | Cuántos fallos, el último, y su código. El último fallo se queda hasta el siguiente, salvo en `CheckFile`, `LoadFile` y `CheckQuery`, que vacían `cLastError` y `cLastErrorCode` al entrar |
| `lStrict` | `.T.`: cada fallo lanza un error de VFP |
| `cLastQuery`, `cLastSql` | La última consulta pedida, y la última SQL que se le dio a un ejecutor |

### QueryCompiler

Un `QueryStore` con un método más, `Build(cFolder, cFq [, cKey [, lEncrypt]])`, que es lo que llama
`FQ_BUILD`. Dale tus macros con `AddMacro` antes de `Build`. `cFq` guarda el nombre del último `.fq` escrito.

### QueryOdbc

El ejecutor de una conexión tuya (`FQ_USE_HANDLE` crea uno): `CREATEOBJECT("QueryOdbc", lnHandle)`, o
`.nHandle = lnHandle`. `cEngine` dice el motor que informó el driver (`cDbmsName`, `cDriver`); escribe tú
`cEngine` para elegirlo. Hace el `SQLEXEC` dentro de su propio método, y antes comprueba que cada `:name` del
texto está en el objeto de parámetros (`param_missing`): un `SQLEXEC` con un parámetro que falta abriría una
ventana «View Parameter» que para el programa.

Después de `Run`, el cursor de la consulta es el área de trabajo seleccionada, como con `SELECT … INTO CURSOR` y
`SQLEXEC`, así que `BROWSE` o `SCAN` van sobre él. Después de `Scalar` y `Execute`, el área que estaba seleccionada
antes de la llamada lo vuelve a estar, también si fallan (una vacía si no había ninguna).

### QueryLocal

El ejecutor de tablas DBF locales (`FQ_USE_DBF` crea uno): `CREATEOBJECT("QueryLocal")`. Mientras se ejecuta
una consulta pone `SET ANSI ON`, `SET DELETED ON` y `SET TABLEPROMPT OFF`, y después los deja como estaban:
el mismo `.sql` devuelve las mismas filas que en un servidor, y una tabla que no está es `query_failed` en vez
del diálogo «Abrir», que esperaría a una persona. `lDeletedOn = .F.` deja `DELETED` como esté, y
`lAnsiOn = .F.` deja `ANSI` como esté (mira [Lo que conviene saber](#lo-que-conviene-saber)). `SET EXACT`,
`SET NULL` y `SET ENGINEBEHAVIOR` son cosa tuya.

Las áreas de trabajo quedan como con [QueryOdbc](#queryodbc): seleccionado el cursor de `Run`, y después de `Scalar`
y `Execute`, el área que estaba seleccionada antes. Una consulta `write` sobre una tabla DBF mueve el puntero de
registro de esa tabla, igual que si ejecutaras tú el mismo `UPDATE`, y FoxQuery no lo devuelve a su sitio.

### FoxRemote

[FoxRemote](https://github.com/Irwin1985/FoxRemote) es una librería de VFP para bases de datos remotas por ODBC
(también se instala con FoxPack: `foxpack add foxremote`). Sus objetos de base de datos (`RemoteSqlServer`,
`RemoteSqlite`, …) son ejecutores tal cual: `FQ_USE(loDb)`, o `loStore.Run(loDb, …)`. FoxQuery no necesita
FoxRemote, y FoxRemote no cambia.

### Un ejecutor propio

Cualquier objeto con estos miembros es un ejecutor: `cEngine` (uno de los siete motores), y los métodos
`Query(cSql, cCursor, oParams)`, `Execute(cSql, oParams)` y `Scalar(cSql, oParams)`. La SQL llega con los
`:name` tal como están, y `oParams` tiene una propiedad por parámetro. Si tiene `nErrors` y `cLastError`,
FoxQuery los lee cuando falla (`executor_failed`).

### Ejecutar tú la SQL

Con `{if}` o una lista, el texto SQL solo funciona con los parámetros que lo acompañan. `Args` devuelve ese
objeto y `Sql` el texto que lo usa; los dos comprueban los parámetros igual que `Run`. El tercer argumento de
`Sql` es el nombre de la variable que guarda el objeto, y el `SQLEXEC` tiene que ver esa variable (una
variable local del mismo programa; una `PRIVATE` si el `SQLEXEC` corre en otro sitio, mira
[Con otra librería de conexión](#con-otra-librería-de-conexión)). Este necesita el driver de SQLite:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
LOCAL lnHandle, loStore, loParams, loArgs, lcSql
lnHandle = SQLSTRINGCONNECT("Driver={SQLite3 ODBC Driver};Database=" + FULLPATH("readme.db") + ";NoWCHAR=1;")
=SQLEXEC(lnHandle, "DROP TABLE IF EXISTS customers")
=SQLEXEC(lnHandle, "CREATE TABLE customers (id INTEGER, name VARCHAR(30), city VARCHAR(20))")
=SQLEXEC(lnHandle, "INSERT INTO customers VALUES (1, 'Ana', 'Oslo'), (2, 'Erik', 'Oslo'), (3, 'Carla', 'Madrid')")

loStore = CREATEOBJECT("QueryStore")
=loStore.LoadFolder("queries\")
loParams = CREATEOBJECT("Empty")
ADDPROPERTY(loParams, "city", "Oslo")
loArgs = loStore.Args("customers.by_city", loParams)
lcSql = loStore.Sql("customers.by_city", "sqlite", "loArgs", loParams)
IF ISNULL(loArgs) OR ISNULL(lcSql)
	? loStore.cLastErrorCode, loStore.cLastError
ELSE
	? lcSql
	IF SQLEXEC(lnHandle, lcSql, "c_result") > 0
		SELECT c_result
		SCAN
			? id, name
		ENDSCAN
	ENDIF
ENDIF
=SQLDISCONNECT(lnHandle)
```

```
SELECT id, name FROM customers WHERE city = ?loArgs.city ORDER BY name
1 Ana
2 Erik
```

En SQLite, convierte tus parámetros de texto con `STRCONV(x, 9)` y lo que leas con `STRCONV(x, 11)`, como
hace FoxQuery (mira [Lo que conviene saber](#lo-que-conviene-saber)).

### Con otra librería de conexión

Tu programa puede abrir sus conexiones con una librería suya, montada sobre `SQLCONNECT` o sobre ADO, y
FoxQuery sigue sin conectar nada. Hay tres puertas, y la primera no le pide nada a la librería:

1. **El handle.** Si la librería te da el número de su `SQLCONNECT` o `SQLSTRINGCONNECT` (casi todas las de
   VFP lo dan), `FQ_USE_HANDLE(loLib.nHandle)`, o `CREATEOBJECT("QueryOdbc", loLib.nHandle)`: FoxQuery ejecuta
   la SQL él mismo y le pregunta al driver qué motor es. La librería no interviene, y no necesita ningún miembro en
   particular.
2. **El objeto.** `FQ_USE(loLib)` necesita los cuatro miembros de [Un ejecutor propio](#un-ejecutor-propio), y la
   SQL llega con los `:name` tal cual. FoxRemote los tiene; otra librería no, y entonces escribes un
   adaptador: una clase pequeña con `cEngine`, `Query`, `Execute` y `Scalar` que convierte cada `:name` en
   lo que la librería entienda y la llama. Es la única puerta para una librería que no sea ODBC (ADO, OLE DB).
3. **La librería ejecuta la SQL.** `Args` y `Sql` te dan el objeto y el texto con `?loArgs.name`, y la
   librería ejecuta el texto. La variable tiene que verse desde donde ocurre el `SQLEXEC`: una `LOCAL` de tu
   programa no se ve desde un método de la librería (una local vive solo en el procedimiento que la declara),
   y un `SQLEXEC` con un parámetro que no ve abre «View Parameter» y espera a una persona. Decláralo
   `PRIVATE`.

El ejemplo entra por la primera puerta y por la tercera, con un doble de una librería así; necesita el driver
de SQLite:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
LOCAL loLib, loStore, loParams, lcSql
PRIVATE loArgs
loLib = CREATEOBJECT("MyDbLib")
=loLib.Open("Driver={SQLite3 ODBC Driver};Database=" + FULLPATH("readme.db") + ";NoWCHAR=1;")
=loLib.Exec("DROP TABLE IF EXISTS customers")
=loLib.Exec("CREATE TABLE customers (id INTEGER, name VARCHAR(30), city VARCHAR(20))")
=loLib.Exec("INSERT INTO customers VALUES (1, 'Ana', 'Oslo'), (2, 'Erik', 'Oslo'), (3, 'Carla', 'Madrid')")

* 1. The handle: FoxQuery runs the SQL itself
=FQ_LOAD("queries\")
IF FQ_USE_HANDLE(loLib.nHandle) AND FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	SELECT c_result
	SCAN
		? "handle:", id, name
	ENDSCAN
ENDIF

* 3. The library runs the SQL: the object of parameters has to be PRIVATE
loStore = FQ_STORE()
loParams = CREATEOBJECT("Empty")
ADDPROPERTY(loParams, "city", "Oslo")
loArgs = loStore.Args("customers.by_city", loParams)
lcSql = loStore.Sql("customers.by_city", "sqlite", "loArgs", loParams)
IF loLib.Exec(lcSql, "c_result")
	SELECT c_result
	SCAN
		? "library:", id, name
	ENDSCAN
ENDIF
loLib.Close()

* A stand-in for any connection library built on SQLCONNECT: it owns the handle and runs the SQL in a method of its own
DEFINE CLASS MyDbLib AS Custom
	nHandle = 0
	FUNCTION Open(tcConnection)
		This.nHandle = SQLSTRINGCONNECT(tcConnection)
		RETURN This.nHandle > 0
	ENDFUNC
	FUNCTION Exec(tcSql, tcCursor)
		RETURN SQLEXEC(This.nHandle, tcSql, IIF(VARTYPE(tcCursor) == "C", tcCursor, "sqlresult")) > 0
	ENDFUNC
	PROCEDURE Close
		IF This.nHandle > 0
			=SQLDISCONNECT(This.nHandle)
			This.nHandle = 0
		ENDIF
	ENDPROC
ENDDEFINE
```

```
handle:           1 Ana
handle:           2 Erik
library:           1 Ana
library:           2 Erik
```

### El objeto de parámetros: FoxNone

Cualquier objeto sirve como `oParams`. Un `None` de FoxNone (`FQ_PARAMS()`, o `loStore.Params()` con
`SET PROCEDURE TO foxnone.prg ADDITIVE`) acepta una propiedad en una línea, sin `ADDPROPERTY`:

```foxpro
loP = FQ_PARAMS()
loP.city = "Oslo"
=FQ_RUN("customers.by_city", "c_result", loP)
```

El ejecutor nunca recibe tu objeto: FoxQuery copia los parámetros declarados a un objeto nuevo. Un parámetro
no se puede llamar como un miembro de `Custom` (`name`, `tag`, `width`, `parent`, …): eso es
`param_reserved`, y el mensaje propone otro nombre.

## Errores

Cada fallo tiene un código en inglés que no cambia entre versiones. `FQ_LAST_ERROR_CODE()` y
`cLastErrorCode` lo devuelven; `FQ_LAST_ERROR()`, `FQ_ERRORS()` y `cLastError` añaden el motivo.

**Al cargar los ficheros `.sql`** (`FQ_LOAD`, `FQ_BUILD`; con el fichero y la línea en `FQ_ERRORS()`):

| Código | Qué pasó | Qué hacer |
|---|---|---|
| `folder_not_found` | La carpeta no existe | Revisa el nombre. Un nombre relativo parte de la carpeta actual (`SET DEFAULT`) |
| `file_not_found` | `CheckFile` o `LoadFile` de un `.sql` que no existe | Revisa el nombre |
| `header_name_missing` | El fichero no tiene `-- name:` | Añádelo, con el nombre del fichero sin `.sql` |
| `header_name_mismatch` | `-- name:` y el nombre del fichero son distintos | Haz que sean iguales |
| `header_kind_missing` | El fichero no tiene `-- kind:` | Añade `-- kind: read` o `-- kind: write` |
| `header_kind_invalid` | `-- kind:` no es `read` ni `write` | Escribe uno de los dos |
| `kind_mismatch` | `read` con una SQL que no empieza por `SELECT`, o `write` con una que sí | Corrige `-- kind:` o la SQL |
| `sql_missing` | No hay SQL debajo de la cabecera, o una sección `-- engine:` está vacía | Escribe la SQL |
| `param_name_invalid` | Un parámetro tiene un nombre que no es válido, o un par de una función está mal (un nombre que no es texto, un nombre repetido, un nombre sin su valor) | Una letra o `_`, y luego letras, dígitos o `_`, sin los `:`; los argumentos van en pares |
| `param_type_invalid` | El tipo de un parámetro no es uno de `C N I D T L Y M` | Escribe uno de ellos |
| `param_flag_invalid` | Una palabra después del tipo que no es `required`, `list` ni `default` | Quítala o corrígela |
| `param_duplicate` | Un parámetro está declarado dos veces | Quita uno |
| `param_reserved` | El nombre de un parámetro es un miembro de un objeto de VFP (`name`, `tag`, …) | Usa el nombre que propone el mensaje |
| `default_type` | El `default` no encaja con el tipo, o una lista tiene `default` | Escribe un valor del tipo |
| `param_undeclared` | La SQL usa un `:name` que la cabecera no declara | Añade su línea `-- param:` |
| `param_unused` | Un aviso, no un error: un parámetro está declarado y la SQL no lo usa | Quítalo, o úsalo |
| `engine_unknown` | Un motor que no es uno de los siete (`-- engine:`, una macro, un ejecutor) | `sqlserver mysql mariadb postgresql firebird sqlite vfp` |
| `engine_duplicate` | Dos secciones `-- engine:` para el mismo motor | Deja una |
| `bad_option` | `-- sort:` sin columnas, o con algo que no es una columna; o una llamada que pide un orden que no está en la lista | Usa las columnas de `-- sort:`, con `ASC` o `DESC` |
| `sort_without_macro` | Hay un `-- sort:` y ningún `{sort}` en la SQL | Añade `ORDER BY {sort}`, o quita `-- sort:` |
| `macro_sort_without_list` | Hay un `{sort}` y ningún `-- sort:` | Añade `-- sort:` con las columnas |
| `sql_too_long` | En `vfp`, el texto pasa de los 8.190 caracteres que VFP ejecuta en una línea: un aviso en `FQ_WARNINGS()` en `FQ_BUILD` y cuando `vfp` es el motor en uso, con el fichero y la línea; el error al ejecutar (también cuando una lista crece) | Escribe un texto `-- engine: vfp` más corto, o pasa menos elementos |
| `ident_undeclared` | Un `{ident x}` en el texto sin su `-- ident: x` (al cargar, con el fichero y la línea) | Añade `-- ident: x` con su forma, por ejemplo `-- ident: x letters 1-20` |
| `ident_form_invalid` | Una línea `-- ident:` sin forma (al cargar) | `-- ident: sort letters 1-20`: un nombre, y después `digits`, `letters`, `alnum` o `ident`, y una longitud `2` o un rango `1-8` |
| `ident_param_clash` | El mismo nombre en `-- ident:` y en `-- param:` (al cargar) | Elige uno |
| `ident_unused` | Un aviso, no un error: un `-- ident:` que ningún texto usa | Úsalo con `{ident x}`, o quita la línea |
| `ident_missing` | La consulta usa `{ident x}` y nadie lo fijó | `FQ_SET("x", ...)` una vez, al arrancar el programa |
| `ident_invalid` | `FQ_SET` con un valor que no es letras, dígitos y `_`, o no es de la forma declarada (el mensaje dice lo que admite esa forma: `(2 digits)`, `(1 to 20 letters)`); o, al ejecutar, un valor que una carga más nueva declara más estricto (dice qué declaración) | Fija un valor de la forma |
| `ident_not_a_param` | Un identificador que llega en la llamada (`FQ_RUN(..., "x", "10")`, o una propiedad del objeto de parámetros) | Fíjalo con `FQ_SET` una vez; nunca va en la llamada |
| `sort_not_in_select` | En `vfp`, una columna de `-- sort:` no está en la lista del `SELECT`, o la lista es `*`: un aviso en `FQ_WARNINGS()` en `FQ_BUILD` y cuando `vfp` es el motor en uso, el error al ejecutar (dice el fichero y la línea de `-- sort:`) | Pon la columna en la lista del `SELECT`, o escribe un texto `-- engine: vfp` |
| `if_unbalanced` | Un `{if}` sin su `{endif}`, un `{if}` dentro de otro, o un `{if}` sin `:name` | Un `{if :name} … {endif}` cada vez |
| `macro_unknown` | Una `{macro}` que no tiene ningún motor | Corrige el nombre, o añádela con `FQ_ADD_MACRO` |
| `macro_unsupported` | El motor no puede hacerlo (`{offset}` en VFP, `{limit 0}` en VFP) | Escribe un texto `-- engine:` para ese motor |
| `macro_reserved` | `FQ_ADD_MACRO` con el nombre de una marca (`if`, `endif`, `sort`, `limit`, `offset`) o de un escape ODBC (`d`, `t`, `ts`, `fn`, `oj`, `call`, `escape`) | Elige otro nombre |
| `limit_arg_invalid` | `{limit}` u `{offset}` con algo que no es un parámetro `N`/`I` ni un número entero, o dos `{limit}` | `{limit :rows}` o `{limit 10}`, una sola vez |
| `limit_without_order_by` | `{limit}` en una consulta sin `ORDER BY` | Añade el `ORDER BY` |
| `offset_without_limit` | `{offset}` sin un `{limit}` justo antes | Escribe `{limit …} {offset …}` |

**Al ejecutar una consulta** (`FQ_RUN`, `FQ_SCALAR`, `FQ_EXECUTE`, `FQ_SQL`):

| Código | Qué pasó | Qué hacer |
|---|---|---|
| `not_loaded` | Una función se ejecutó antes de `FQ_LOAD` (un error de VFP: es un bug del programa) | Llama primero a `FQ_LOAD` |
| `not_connected` | Ningún `FQ_USE…` antes (un error de VFP), o un handle que no es una conexión abierta | Llama primero a `FQ_USE_DBF`, `FQ_USE_HANDLE` o `FQ_USE`, con una conexión abierta |
| `query_not_found` | No hay ninguna consulta con ese nombre | Revisa el nombre, y que `FQ_LOAD` cargó su fichero |
| `query_duplicate` | `CheckFile` o `LoadFile` de un `.sql` cuya consulta ya está cargada desde otro fichero (otra carpeta) | Una consulta tiene un fichero: carga esa carpeta, o cámbiale el nombre |
| `param_missing` | La llamada no trae un parámetro obligatorio | Pásalo |
| `param_unknown` | Un par con un nombre que la consulta no declara (`"cty"` en vez de `city`); el mensaje dice los que declara | Escribe el nombre de su línea `-- param:` |
| `param_type` | Un valor que no encaja con su tipo (un texto para un `N`, un texto con comas para una lista que no es `C` ni `M`), o una lista vacía | Pasa un valor del tipo de `-- param:` |
| `limit_value_invalid` | El valor para `{limit}` u `{offset}` no es un número entero, es negativo, o es 0 en VFP | Pasa un número entero, 1 o más |
| `wrong_kind` | `FQ_RUN` o `FQ_SCALAR` con una consulta `write`, o `FQ_EXECUTE` con una `read` | Usa la función de su tipo |
| `executor_failed` | El motor devolvió un error: su mensaje está en el motivo | Lee el mensaje del motor |
| `query_failed` | Lo mismo, dicho por `QueryOdbc` o `QueryLocal` cuando los llamas directamente | Lee el mensaje del motor |
| `executor_invalid` | `FQ_USE` con un objeto que no es un ejecutor | Mira [Un ejecutor propio](#un-ejecutor-propio) |
| `foxnone_missing` | `FQ_PARAMS()` sin FoxNone cargado | `SET PROCEDURE TO foxnone.prg ADDITIVE`, o usa cualquier otro objeto |
| `internal_error` | FoxQuery falló y no pudo decir por qué | Comunícalo, con lo que diga `FQ_LAST_ERROR()` |

**El catálogo** (`FQ_BUILD`, `FQ_LOAD` de un `.fq`, `FQ_ADD_MACRO`):

| Código | Qué pasó | Qué hacer |
|---|---|---|
| `catalog_not_found` | No hay ningún `.fq` con ese nombre, ni dentro del EXE ni a su lado | Revisa el nombre, y que el proyecto incluye el fichero |
| `catalog_tampered` | La firma no cuadra: el fichero cambió, está cortado, no es un `.fq`, o la clave no es la de `FQ_BUILD` (la firma se comprueba antes que nada) | Vuelve a construirlo; usa la misma clave en los dos |
| `catalog_invalid` | Un `.fq` bien firmado con un contenido que FoxQuery no sabe leer | Vuelve a construirlo |
| `catalog_not_written` | `FQ_BUILD` no pudo escribir el `.fq`: el fichero está abierto en un editor o es de solo lectura (el mensaje dice cuántos bytes se escribieron), o la carpeta no existe (el mensaje dice cuál) | Cierra el editor o corrige la ruta, y vuelve a construirlo |
| `catalog_version` | Lo construyó un FoxQuery anterior | Vuelve a construirlo con este |
| `catalog_key_required` | El `.fq` está cifrado y `FQ_LOAD` no recibió ninguna clave; o se le pidió a `FQ_BUILD` cifrar sin clave | Pasa tu clave |
| `catalog_frozen` | `FQ_ADD_MACRO` con un `.fq` cargado: el `.fq` cargado no cambia, y la macro queda apuntada para el siguiente `FQ_BUILD` | Nada, si vuelves a compilar; añade tus macros antes de `FQ_BUILD` |

## Lo que conviene saber

- **VFP no puede usar una propiedad ni un método de lo que devuelve una función.** `FQ_STORE().nQueries`
  compila y falla al ejecutarse. Guárdalo primero en una variable: `loStore = FQ_STORE()`.
- **Una lista o un array va con `@`.** `"countries", @laCountries`; sin `@`, VFP pasa solo el primer
  elemento.
- **SQLite y la eñe.** El driver de SQLite convierte el texto SQL a UTF-8, pero ni los parámetros ni lo que
  vuelve. FoxQuery convierte las dos cosas, así que `FQ_RUN` con `"Muñoz"` funciona. Si ejecutas `SQLEXEC`
  tú mismo, haz lo mismo: `STRCONV(x, 9)` para cada parámetro de texto y `STRCONV(x, 11)` para lo que leas.
- **SQLite y las fechas.** Un parámetro `D` o `T` viaja como texto con la hora (`'2026-11-02 00:00:00.000'`):
  no casa con `=` con una columna que guarda `'2026-11-02'`, y funciona con `>=` y `<`.
- **SQLite: una columna calculada vuelve como memo.** Una columna del `SELECT` que es una expresión
  (`SUBSTR(name, 1, 3) AS first3`) no tiene tipo declarado, y VFP recibe un `Memo`. Declara las columnas de
  la tabla con un tipo (`VARCHAR(30)`, no `TEXT`).
- **SQLite: `{like_ci}` solo funciona con ASCII.** SQLite pasa a mayúsculas solo las letras sin acentos:
  `Muñoz` no casa con `MUÑOZ`. `{now}` devuelve texto, no una fecha y hora.
- **MySQL: usa el driver de MariaDB.** El driver ODBC de Oracle manda un número como double, que no casa con
  un `DECIMAL`, y ha llegado a parar VFP después de que expirara la espera de un bloqueo.
- **Firebird.** `{nvl}` va sobre una columna, no sobre un parámetro solo (`?p` sin columna da «Data type
  unknown»); `:p IS NULL` no funciona: usa un bloque `{if :p}`; y `.NULL.` no entra en un `BOOLEAN`.
- **VFP: `{limit}` y los empates.** Con `SET ENGINEBEHAVIOR 70`, `TOP n` devuelve también las filas empatadas
  con la última, así que puedes recibir más de n filas. Con 90, el valor por defecto, recibes n.
- **VFP: un `--` después de SQL en la misma línea.** VFP no conoce `--`. FoxQuery quita las líneas que
  empiezan por `--`, pero no un `--` después de SQL. En una consulta que se ejecuta sobre DBF, pon el
  comentario en su propia línea.
- **VFP no tiene `COALESCE`.** Usa `{nvl}`, o un texto `-- engine: vfp`.
- **VFP: `ANSI ON` cuesta tiempo en los joins grandes.** Mientras se ejecuta una consulta, `QueryLocal` pone
  `SET ANSI ON`, para que `=` compare como en un servidor. En joins de muchas filas sobre DBF eso fue un 30 a
  40 % más lento que `ANSI OFF` (255 s frente a 195 s en joins de 148.027 filas sobre 6 tablas). `loDb = FQ_DB()`
  y después `loDb.lAnsiOn = .F.` dejan `SET ANSI` como lo tengas, y entonces `=` compara como diga tu `SET ANSI`:
  con `OFF`, `city = 'Os'` casa con `'Oslo'`, así que las filas pueden no ser las que devolvería un servidor.
- **VFP: una consulta de más de 8.190 caracteres no cabe en una línea.** Sobre DBF, VFP ejecuta la SQL como una
  línea, y 8.190 caracteres es lo más que admite, contando el `INTO CURSOR` que añade `QueryLocal` (uno más es el
  error 18 de VFP).

  `FQ_BUILD` lo avisa en `FQ_WARNINGS()` con `sql_too_long`, el fichero y la línea, y también `FQ_LOAD` cuando `vfp`
  es el motor en uso y `FQ_USE_DBF` con las consultas cargadas. `FQ_RUN` de esa consulta falla con el mismo código, y
  los demás motores ejecutan el mismo `.sql`. Una consulta corta con una lista larga también puede pasar del límite
  al ejecutarse: entonces `FQ_RUN` da `sql_too_long` antes de que la SQL llegue a VFP. Usa un texto `-- engine: vfp`
  más corto, o menos elementos en la lista.

  Sobre DBF, `FQ_RUN` pone `SYS(3055, 2040)` mientras ejecuta y después repone el valor que había, así que una lista
  solo tiene el límite de `sql_too_long` (514 elementos, con el `INTO`). Si tu programa ejecuta la misma SQL por su
  cuenta con el `SYS(3055)` por defecto de VFP, un `IN` admite 158 elementos (error 1812 de VFP).

  Encontrar esas consultas cuesta tiempo con una carpeta, no con un `.fq`: para decir lo que `vfp` no puede ejecutar,
  `FQ_USE_DBF` (y `FQ_LOAD` con `vfp` en uso) resuelve el texto de todas las consultas cargadas, que es lo que cada
  primer `FQ_RUN` haría igual. Con 500 consultas de unos 550 caracteres cargadas de una carpeta son unos 2,3 s, una
  vez; desde un `.fq`, unos 5 ms. Después ya no cuesta nada, porque el resultado se guarda y un segundo `FQ_USE_DBF`
  lo encuentra. En producción, carga el `.fq`.
- **Un `bit` de SQL Server pasado a DBF es `L`.** Entonces `WHERE active = 0` da el error 107 de VFP
  («Operator/operand type mismatch»). Escribe `{false}` (y `{true}`): cada motor recibe lo que entiende.
- **Una tabla libre no acepta un nombre de campo de más de 10 letras.** Si tus ficheros `.sql` usan
  `customer_id`, las tablas DBF van en una base de datos (`.dbc`).
- **Una ventana «View Parameter».** Aparece cuando un `SQLEXEC` usa `?name` y esa variable no existe, y para
  el programa hasta que alguien responde. FoxQuery comprueba cada `:name` antes de llamar al motor, así que
  con `FQ_RUN` no aparece. Puede aparecer con tu propio `SQLEXEC`: usa `Args`.
- **`CLEAR DLLS`.** FoxQuery declara una sola vez las funciones de CryptoAPI que necesita (para el `.fq`).
  Después de un `CLEAR DLLS` sin lista, las vuelve a declarar por su cuenta. Un `CLEAR DLLS` que quita solo
  algunas puede hacer que falle el siguiente `FQ_LOAD` de un `.fq`: en ese caso llama a `CLEAR DLLS` sin
  lista.
- **`FQ_ADD_MACRO` y un `.fq`.** El estado vive en `_SCREEN`, así que cuando vuelves a ejecutar tu programa
  en el mismo VFP el `.fq` de la ejecución anterior sigue cargado y `FQ_ADD_MACRO` da `catalog_frozen`. La
  macro queda apuntada igual, y el siguiente `FQ_BUILD` la lleva.
- **`SET SAFETY ON` y tus propios ficheros.** Un VFP recién abierto arranca con `SET SAFETY ON`: un
  `STRTOFILE` o un `CREATE TABLE` sobre un fichero que existe pregunta antes de escribir. FoxQuery escribe el
  `.fq` sin preguntar; tus propios programas necesitan `SET SAFETY OFF`.

## Cambios

- **1.0.2** (2026-11-10): sale código interno que la librería no usaba. A un programa que usa FoxQuery no le cambia
  nada.
- **1.0.1** (2026-11-05): `FQ_BUILD` y `Build` fallan con `catalog_not_written` cuando no pueden escribir el `.fq`
  (el fichero está abierto en un editor o es de solo lectura, o su carpeta no existe, y entonces el mensaje dice qué
  carpeta). Novedades en `QueryStore`: `CheckEngine(cEngine, nFrom, nCount)` comprueba las consultas por tramos y
  suma los avisos, sin repetir ninguno; `CheckQuery` comprueba una consulta; `CheckFile` y `LoadFile` comprueban o
  reemplazan una consulta desde su `.sql` sin recargar las demás (`file_not_found`, `query_duplicate`); `Names()`
  lista las consultas en el orden de carga, y `Get()` acepta también un número. `CheckQuery`, `CheckFile` y
  `LoadFile` vacían `cLastError` al entrar, y el error de `CheckFile` y `LoadFolder` es la primera línea de
  `FQ_ERRORS()` (`file(line): code: reason`), también en `FQ_LAST_ERROR()`. En `QueryLocal` y `QueryOdbc`, `Scalar`
  y `Execute` vuelven a seleccionar el área de trabajo que estaba seleccionada antes de la llamada; `Run` sigue
  dejando seleccionado el cursor de la consulta.
- **1.0.0** (2026-11-04): la primera versión.

## Licencia

MIT. El texto está en `LICENSE`.
