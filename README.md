# FoxQuery

English · [Español](README.es.md) · [Deutsch](README.de.md)

FoxQuery keeps the SQL of a Visual FoxPro 9 application in named queries: one `.sql` file per query, with
a short header that says its name, its kind and its parameters. Your program asks for a query by its name
(`customers.by_city`), passes the values as parameters, and never builds SQL text.

The same `.sql` file runs on SQL Server, MySQL, MariaDB, PostgreSQL, Firebird, SQLite and on local DBF
tables. For the version you ship, the files compile to one signed catalog (`.fq`) that travels inside the
EXE or next to it.

You can use it from a `.prg` with plain functions (`FQ_LOAD`, `FQ_RUN`, …) and no classes at all. It
works with the default values, and when something is wrong the error says the file, the line, what
happened and what to do.

## Install

With [FoxPack](https://irwinrodriguez.dev/products/foxpack), which downloads libraries for Visual FoxPro
projects at a fixed version:

```
foxpack add foxquery
```

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
```

Without FoxPack, copy `foxquery.prg` next to your program: it is the whole library. It needs Visual
FoxPro 9 SP2 and nothing else. FoxQuery does not connect to any server: it runs the queries on a
connection that you open, so you need your engine's ODBC driver anyway. VFP is a 32-bit program and
needs the **32-bit** driver, also on 64-bit Windows. These are the drivers FoxQuery is tested with:

| Engine | Driver | Tested with |
|---|---|---|
| SQL Server | `ODBC Driver 18 for SQL Server` or `ODBC Driver 17 for SQL Server` | SQL Server 2025 Express |
| MySQL | `MariaDB ODBC 3.2 Driver` (the MariaDB one: see [Pitfalls](#pitfalls)) | MySQL 8.4 |
| MariaDB | `MariaDB ODBC 3.2 Driver` | MariaDB 11.8 |
| PostgreSQL | `PostgreSQL ANSI` (psqlODBC) | PostgreSQL 18 |
| Firebird | `Firebird ODBC Driver` 3.0, with the 32-bit `fbclient.dll` | Firebird 5.0 |
| SQLite | `SQLite3 ODBC Driver` 0.99991 (ch-werner.de, `sqliteodbc.exe`) | SQLite 3.43 |
| Local DBF | none | Visual FoxPro 9 SP2 |

FoxNone is optional. It is a small library that also installs with FoxPack (`foxpack add foxnone`), and
`FQ_PARAMS()` and `QueryStore.Params()` return one of its objects. Without FoxNone, everything else works.

## Example

Paste it into a `.prg` in an empty folder and run it. It creates a DBF table and one query, and runs the
query on the DBF: no server needed.

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

It shows:

```
1 Ana Muñoz
2 Erik Berg
```

To go step by step from zero, follow [TUTORIAL.md](TUTORIAL.md).

## The `.sql` files

One file per query, in one folder (`queries\`). The name of the file is the name of the query plus `.sql`.
The file is plain text in Windows-1252 (CP1252), like any VFP source. The header comes first, as SQL
comments, and the SQL goes below it:

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

| Header line | What it says |
|---|---|
| `-- name: customers.search` | The name of the query. It has to be the name of the file without `.sql`. Required |
| `-- description: …` | Free text, for whoever reads the file. Optional |
| `-- kind: read` | `read` for a `SELECT` (it runs with `FQ_RUN` or `FQ_SCALAR`), `write` for `INSERT`, `UPDATE` or `DELETE` (it runs with `FQ_EXECUTE`). Required. FoxQuery checks it against the first word of the SQL |
| `-- param: city C required` | One line per parameter: the name, the type, and then `required`, `list` and `default <value>`, in any order |
| `-- ident: sort letters 1-20` | An identifier: a name that the program writes into the SQL with `FQ_SET`, once, for every query that uses it. Its form says what the value may be (`digits`, `letters`, `alnum` or `ident`, and a length `2` or a range `1-20`) |
| `-- sort: name, id` | The columns the caller may choose for `ORDER BY` (see `{sort}` below) |
| `-- engine: firebird` | Starts a whole SQL text for one engine. It goes after the common SQL |

**The types** are the ones of VFP: `C` (text), `N` (any number), `I` (a whole number), `D` (date), `T`
(date and time), `L` (logical), `Y` (currency, which also takes a number) and `M` (memo). FoxQuery checks
the type of each value before anything reaches the engine (`param_type`).

**`default <value>`** is used when the call does not give the parameter: a number (`10`), a text in quotes
(`'Oslo'` or `"Oslo"`), a date (`{^2026-11-04}`, or `{}` for an empty one), a date and time
(`{^2026-11-04 10:30}`), `.T.`, `.F.` or `.NULL.`. A list takes no default. An optional parameter without
a default that the call does not give reaches the engine as `.NULL.`.

**Comments.** In a header line, whatever comes after ` --` is a comment. A line of the SQL that starts with
`--` is a comment too. A `--` after SQL on the same line stays in the text: see [Pitfalls](#pitfalls).

**What goes in the SQL:**

- **`:name`** is a parameter. The value travels apart from the text, as an ODBC parameter (or, on DBF, as a
  property that VFP reads): no value of the caller is ever pasted into the SQL. A `:` inside quotes and
  the `::` of PostgreSQL are left alone.
- **`{if :since} … {endif}`**: the text inside goes into the SQL only when the call gives `since` (as a
  pair, or as a property of the object), whatever its value. One level only: an `{if}` inside another is
  `if_unbalanced`.
- **`{ident sort}`** writes the value that the program set with `FQ_SET("sort", "name")`, as it is and without
  quotes: `ORDER BY {ident sort}` runs as `ORDER BY name`. It is for a name inside the SQL (a column, for example),
  set once for every query that uses it; `{sort}`, below, is the order that each call chooses. FoxQuery checks the
  value when it is set (only letters, digits and `_`, and the form of `-- ident:`), and a call cannot bring it
  (`ident_not_a_param`). A `{ident}` between quotes stays as it is. The example is in [FQ_SET](#fq_setcname-cvalue).
- **`{sort}`** is the `ORDER BY` the caller chooses among the columns of `-- sort:`, each one with `ASC` or
  `DESC`: `"sort", "name DESC"` or `"sort", "name, id DESC"`. `{sort name}` says which one to use when the
  call says nothing. Anything that is not in the list is `bad_option`, and nothing reaches the engine. On
  `vfp` (DBF), `{sort}` writes the position of each column in the `SELECT` list (`ORDER BY 2 DESC, 1`): by
  name, an alias that is also a column of a joined table gives VFP error 1832. So on `vfp` every column of
  `-- sort:` has to be in that list, and a `SELECT *` does not work (`sort_not_in_select`). The other engines get
  the names.
- **A list** (`-- param: countries C required list`, and `IN (:countries)` in the SQL) takes a text with
  commas (`"ES,PT,DE"`), an array passed with `@`, or a `Collection`. FoxQuery writes
  `IN (:countries_1, :countries_2, :countries_3)` and sends one parameter per item. The text with commas is only
  for lists of `C` and `M`; a list of numbers or dates is an array or a `Collection`. An empty list is
  `param_type` with "the list is empty", however it comes: an empty text, an empty `Collection`, or an array of
  one `.F.` (VFP has no arrays without elements: that is what `DIMENSION`, `ADIR` or `ALINES` leave). On a list of
  `L`, `[.F.]` is the value false.
- **`{macro …}`**: the nine macros below, for what each engine writes in its own way.
- **A whole text for one engine**: after the common SQL, a line `-- engine: firebird` and the SQL for
  that engine. The engines are `sqlserver`, `mysql`, `mariadb`, `postgresql`, `firebird`, `sqlite` and
  `vfp` (local DBF tables).

**What you cannot do.** A table or column name that comes from the caller: write one query for each
case. That is the classic SQL injection, and FoxQuery has no way to do it.

## Macros

Nine come with FoxQuery, checked on the seven engines. Their arguments are separated by commas.

| Macro | SQL Server | MySQL / MariaDB | PostgreSQL | Firebird | SQLite | VFP |
|---|---|---|---|---|---|---|
| `{limit n}` | `OFFSET 0 ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n` | `LIMIT n` | `ROWS n` | `LIMIT n` | `TOP n` after the `SELECT` |
| `{offset k}` | `OFFSET k ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n OFFSET k` | `LIMIT n OFFSET k` | `OFFSET k ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n OFFSET k` | not possible |
| `{concat a, b, …}` | `a + b` | `CONCAT(a, b)` | `a \|\| b` | `a \|\| b` | `a \|\| b` | `a + b` |
| `{now}` | `GETDATE()` | `NOW()` | `LOCALTIMESTAMP` | `LOCALTIMESTAMP` | `datetime('now', 'localtime')` | `DATETIME()` |
| `{nvl a, b}` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `NVL(a, b)` |
| `{substr s, i, n}` | `SUBSTRING(s, i, n)` | `SUBSTRING(s, i, n)` | `SUBSTRING(s, i, n)` | `SUBSTRING(s FROM i FOR n)` | `SUBSTR(s, i, n)` | `SUBSTR(s, i, n)` |
| `{true}` | `1` | `1` | `TRUE` | `TRUE` | `1` | `.T.` |
| `{false}` | `0` | `0` | `FALSE` | `FALSE` | `0` | `.F.` |
| `{like_ci col, :p}` | `UPPER(col) LIKE UPPER(:p)` | the same | the same | the same | the same | the same |

**`{limit}` and `{offset}`** take a parameter declared `N` or `I` (`{limit :rows}`) or a whole number
(`{limit 10}`). They go at the end of the statement, `{offset}` right after `{limit}`, and the query needs an
`ORDER BY` (SQL Server and VFP ask for it, and with it every engine returns the same rows). FoxQuery checks
that the number is a whole number and not negative, and writes it into the SQL: it is the only value of the
caller that goes into the text, because the MariaDB driver cannot bind it. On VFP, `{limit}` becomes
`TOP n` after the `SELECT`, `{offset}` does not exist (`macro_unsupported`) and `TOP 0` neither (a 0 is
`limit_value_invalid`).

**Your own macros**: `FQ_ADD_MACRO(cEngine, cName, cTemplate)`, or `AddMacro` on the class. `$1` to `$9` are
the arguments; `$*[sep]` is all of them joined by `sep` (`, ` when there are no brackets). The same call on
an engine that already has the macro replaces it for that engine.

```foxpro
=FQ_ADD_MACRO("sqlite", "greatest", "MAX($*[, ])")
=FQ_ADD_MACRO("vfp", "greatest", "MAX($*[, ])")
```

A macro has to exist for an engine before a query that uses it runs there: for the others it is
`macro_unknown`.

## The `.fq` catalog

For the version you ship, `FQ_BUILD` compiles the folder into one file:

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

- **`FQ_BUILD` reads the folder like `FQ_LOAD`**: all or nothing, with the same errors. If one file is
  wrong there is no `.fq`, and `FQ_ERRORS()` lists every mistake.
- **The `.fq` keeps every query already resolved for the seven engines** (the variant or the common text,
  with the macros written out). Where an engine cannot run a query (`{offset}` on VFP), the `.fq` keeps the
  error, and the query still works on the others.
- **The key.** With your key, a `.fq` that someone changes on purpose does not load (`catalog_tampered`).
  Without a key, FoxQuery uses a fixed key of its own: a `.fq` changed by mistake (an editor that saved it)
  does not load, but someone who knows FoxQuery can sign a new one.
- **Encrypting** (`FQ_BUILD(cFolder, cFq, cKey, .T.)`) hides the SQL from someone who opens your EXE with an
  editor, and that is all. It needs your key (`catalog_key_required`). Your key travels inside your program:
  what travels in the EXE is not a secret for someone who works at it.
- **Where `FQ_LOAD` finds it**: by the name you give, inside the EXE first (add the `.fq` to the project as
  a file, included); if it is not there, next to the EXE, also when the program starts from another folder.
- **A loaded catalog is frozen**: its queries keep the macros they were built with. `FQ_ADD_MACRO` gives
  `catalog_frozen`, and the macro is kept for the next `FQ_BUILD`. `FQ_LOAD` of a folder goes back to the
  `.sql` files.
- **How long it takes**: it depends on the size of the catalog more than on the number of queries. With 500
  queries, measured on a development laptop: a `.fq` of 1 MB (short queries) takes about 4 seconds to build and
  50 milliseconds to load; one of 2 MB, 7 seconds and 75 milliseconds (85 encrypted); one of 14 MB (queries of about
  4 KB), 66 seconds and 230 milliseconds (255 encrypted). On a slower machine, in an application with 500
  queries and a `.fq` of 2 MB, it was 7.9 seconds and 216 milliseconds. It loads once, when the program starts.
- **The format has a version.** A `.fq` built by an older FoxQuery gives `catalog_version`: build it again.

## API

### The functions

They keep their state in `_SCREEN`: a second `SET PROCEDURE TO foxquery.prg ADDITIVE` loses nothing.

**How they fail.** When something goes wrong while running (a missing parameter, a query that does not
exist, the engine that fails), the function returns its failure value (`.F.`, `.NULL.` or `-1`) and
`FQ_LAST_ERROR()` says why, with the name of the function first:
`FQ_RUN: param_missing: city (…)`. `FQ_LAST_ERROR_CODE()` returns only the code. Every function that does
something empties them first. A program that calls `FQ_RUN` before `FQ_LOAD`, or before one of the
`FQ_USE…` functions, has a bug: that raises a VFP error. With `FQ_STRICT(.T.)` every failure raises a
VFP error.

**The parameters go in pairs** after the fixed arguments: the name, then the value. Up to 12 pairs in
`FQ_RUN` and 13 in `FQ_SCALAR` and `FQ_EXECUTE`. With more, pass one object in the place of the first pair:
any object whose properties are the parameters (`CREATEOBJECT("Empty")` with `ADDPROPERTY`, or
`FQ_PARAMS()`). A list goes as a text with commas or as an array with `@`; the order of `{sort}` goes as the
pair `"sort"`.

### FQ_LOAD(cFolderOrFq [, cKey])

Loads the `.sql` files of a folder, or a `.fq` catalog with its key. All or nothing: with one mistake,
nothing loads and what was loaded before stays. Returns `.T.` or `.F.`; every mistake is in `FQ_ERRORS()`.
What one engine cannot run (`sql_too_long` or `sort_not_in_select` on `vfp`, a `macro_unsupported`) gives a
warning in `FQ_WARNINGS()` and the load goes on, because the other engines run the query. The warning comes when
the engine in use is chosen (`FQ_USE_DBF`, `FQ_USE_HANDLE`, `FQ_USE`; or in this `FQ_LOAD`, with one already in use).

```foxpro
IF !FQ_LOAD("queries\")
	? FQ_ERRORS()
ENDIF
```

### FQ_RELOAD()

Reads the same folder or `.fq` again (after you change a `.sql` with the program running). Returns `.T.` or
`.F.`.

### FQ_BUILD(cFolder, cFq [, cKey [, lEncrypt]])

Compiles the `.sql` files of `cFolder` into the catalog `cFq`, with the macros of `FQ_ADD_MACRO`. It does
not touch what `FQ_LOAD` loaded. Returns `.T.` or `.F.`; every mistake is in `FQ_ERRORS()`. What one engine
cannot run is a warning in `FQ_WARNINGS()`, and the `.fq` records it: `FQ_LOAD` of that `.fq` warns again.
If the `.fq` is open in an editor (`MODIFY FILE app.fq`, to look at it), `FQ_BUILD` cannot write it: `.F.` with
`catalog_not_written`, and the previous `.fq` stays as it was. If the folder of `cFq` does not exist, the same `.F.`,
and the message names the folder.

```foxpro
=FQ_BUILD("queries\", "app.fq", "the key of my application")
```

### FQ_ADD_MACRO(cEngine, cName, cTemplate)

Adds a macro of yours, or replaces one, for one engine. It works on the folder loaded with `FQ_LOAD`, and
`FQ_BUILD` always gives it to the compiler. With a `.fq` loaded it returns `.F.` with `catalog_frozen`: the
loaded `.fq` does not change, and the macro is kept for the next `FQ_BUILD`. Returns `.T.` or `.F.`.

```foxpro
=FQ_ADD_MACRO("sqlite", "greatest", "MAX($*[, ])")
```

### FQ_USE_DBF()

The queries run on local DBF tables, with the SQL of VFP (the engine `vfp`). VFP finds the tables as always:
an open alias, the current folder, `SET PATH`, the open database. Returns `.T.`. With queries loaded, the ones
`vfp` cannot run go to `FQ_WARNINGS()`.

### FQ_USE_HANDLE(nHandle [, cEngine])

The queries run on a connection you opened with `SQLCONNECT` or `SQLSTRINGCONNECT`. FoxQuery asks the driver
which engine it is; `cEngine` says it when the driver does not (`engine_unknown`). FoxQuery never connects,
disconnects or changes the connection. Returns `.T.` or `.F.`. With queries loaded, the ones that engine cannot
run go to `FQ_WARNINGS()`.

```foxpro
=FQ_USE_HANDLE(lnHandle)
```

### FQ_USE(oExecutor)

The queries run on any object that runs SQL: a FoxRemote database object (see [FoxRemote](#foxremote)), or one
of your own (see [An executor of your own](#an-executor-of-your-own)). Returns `.T.` or `.F.`. With queries
loaded, the ones that engine cannot run go to `FQ_WARNINGS()`.

### FQ_RUN(cName [, cCursor [, cParam1, vValue1, … | oParams]])

Runs a `read` query into a cursor (`c_fr_query` when `cCursor` is empty). Returns `.T.` or `.F.`.

```foxpro
IF !FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	? FQ_LAST_ERROR()
ENDIF
```

### FQ_SCALAR(cName [, cParam1, vValue1, … | oParams])

Runs a `read` query that returns one value, and returns it. Returns `.NULL.` when it fails, and also when
the value is `.NULL.` or there are no rows: then `FQ_LAST_ERROR()` is empty.

```foxpro
lnCount = FQ_SCALAR("customers.count_by_city", "city", "Oslo")
```

### FQ_EXECUTE(cName [, cParam1, vValue1, … | oParams])

Runs a `write` query. Returns the number of rows it changed, or `-1`.

```foxpro
lnRows = FQ_EXECUTE("customers.deactivate_city", "city", "Oslo")
```

### FQ_SQL(cName [, cEngine [, cObject [, oParams]]])

Returns the SQL text of a query for an engine (the one in use if `cEngine` is empty), without running it,
or `.NULL.`. The `:name` stay as they are; `cObject` writes them as `?cObject.name`, and `oParams` resolves
`{if}`, `{sort}` and the lists as a run would.

`cEngine` is one of the seven: `sqlserver`, `mysql`, `mariadb`, `postgresql`, `firebird`, `sqlite` and
`vfp` (the DBF tables of `FQ_USE_DBF`); another name gives `.NULL.` with `engine_unknown`.

```foxpro
? FQ_SQL("customers.by_city", "postgresql")
```

### FQ_SET(cName, cValue)

Sets the value of an identifier (`{ident}`, declared with `-- ident:`) for every query that uses it, until you set
it again. `.T.`, or `.F.` with `ident_invalid` (only letters, digits and `_`, and the form each loaded query
declares). `FQ_LOAD` and `FQ_RELOAD` keep what was set, and `FQ_SQL` shows the text with the value in place. The
value is set by the program, never by a call.

The form in `-- ident:` says what the value may be: `digits` (only digits), `letters` (only letters), `alnum`
(letters and digits) or `ident` (letters, digits and `_`), with a length (`2`) or a range (`1-20`). This example
sorts the customers by the column that the program sets. It runs the same query on a DBF table and on SQLite, so it
needs the SQLite driver:

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

Returns an empty object of FoxNone to put the parameters in, one line each (`loP.city = "Oslo"`), or
`.NULL.` with `foxnone_missing` when FoxNone is not loaded.

### FQ_ERRORS()

Every mistake of the last `FQ_LOAD`, `FQ_RELOAD` or `FQ_BUILD`, one per line: `file(line): code: reason`,
or `code: reason` when it is not about a `.sql` file. `""` when it went well.

```
customers.broken.sql(2): param_type_invalid: the type of city is 'X': it is one of C N I D T L Y M
customers.broken.sql(1): header_kind_missing: the header has no '-- kind:' (read or write)
```

### FQ_WARNINGS()

Every warning of the last `FQ_LOAD`, `FQ_RELOAD` or `FQ_BUILD`, and of the last `FQ_USE_DBF`, `FQ_USE_HANDLE` or
`FQ_USE`, one per line like `FQ_ERRORS()`: what is declared and no text uses (`param_unused`, `ident_unused`), and
what the engine in use cannot run (`sql_too_long`, `sort_not_in_select`, `macro_unsupported`). A warning does not
stop the load: `FQ_RUN` of that query fails with the same code, and the other engines run it. `""` when there is
none.

```
customers.report.sql(1): sql_too_long: on vfp, the vfp text is 9105 characters as QueryLocal runs it, and VFP runs 8190 at most in one line (…)
```

### FQ_LAST_ERROR() and FQ_LAST_ERROR_CODE()

Why the last function failed, with its name first; and only its code. `""` when it went well.

### FQ_STRICT([lOn])

`FQ_STRICT(.T.)`: every failure raises a VFP error, for programs that handle errors with `TRY … CATCH`.
Without an argument it changes nothing. It returns the current state.

### FQ_STORE() and FQ_DB()

The `QueryStore` and the executor the functions use, for when you want to go on with the classes. Put them
in a variable first: VFP cannot use a property of what a function returns (`FQ_STORE().nQueries` fails).

### FQ_VERSION()

Returns the version of FoxQuery (`"1.0.2"`).

### The classes

The functions call these classes, and you can use them directly:

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

| Member | What it does |
|---|---|
| `LoadFolder(cFolder)` | Loads the `.sql` files of a folder. `.T.` or `.F.` |
| `Load(cFq [, cKey])` | Loads a `.fq` catalog. `.T.` or `.F.` |
| `Reload()` | Reads the same folder or `.fq` again |
| `CheckFile(cFile)` | Reads and checks one `.sql` as the load does, and touches nothing that is loaded. It empties `cLastError` and `cLastErrorCode` when it starts. `.T.`, or `.F.` with the first mistake in `cLastError` as a line of `FQ_ERRORS()` (`file(line): code: reason`) and all of them in `aLoadErrors`; `file_not_found`; `query_duplicate` if that query is loaded from another file |
| `LoadFile(cFile)` | It empties `cLastError` and `cLastErrorCode` when it starts. `CheckFile`, and then adds the query of that file, or replaces the one that came from it, in the same place of the load order. The texts cached for that query are dropped, and its warnings are made again (the ones of the load, and the ones for the engine of the last `CheckEngine`): what `Reload()` would leave, for that file only. `catalog_frozen` with a `.fq` loaded. `.T.` or `.F.` |
| `Run(oExecutor, cName, oParams [, cCursor])` | Runs a `read` query into a cursor. `.T.` or `.F.` |
| `Scalar(oExecutor, cName, oParams)` | Runs a `read` query and returns one value, or `.NULL.` |
| `Execute(oExecutor, cName, oParams)` | Runs a `write` query. The rows it changed, or `-1` |
| `Sql(cName, cEngine [, cObject [, oParams]])` | The SQL text for an engine, or `.NULL.` |
| `Args(cName, oParams)` | The object with the parameters that `Run` gives the executor, or `.NULL.` |
| `Get(cName)` | The `QueryDef` of a query (its header, already read), or `.NULL.`. Also by its number, `Get(1)` to `Get(nQueries)`, in the load order; out of range, `.NULL.` with `query_not_found` |
| `Names()` | The names of the loaded queries in the load order (the order of the catalog), in a new `Collection` each time; empty if nothing is loaded. With a `.fq`, it is how you know what it carries |
| `CheckEngine(cEngine [, nFrom [, nCount]])` | The loaded queries that engine cannot run, each a warning in `aWarnings` (what the `FQ_USE…` functions do). How many, or `-1`. With `nFrom` and `nCount`, only that range of the load order, so that the work can be spread over the moments the program is idle: the warnings of each range add to the ones before, and `nFrom` 1 or another engine starts again from the warnings of the load. A range checked again, or two ranges that overlap, never add the same warning twice (the same code, file and line) |
| `CheckQuery(cName, cEngine)` | Whether that engine can run that query. It empties `cLastError` and `cLastErrorCode` when it starts: `.T.`, or `.F.` with the failure in `cLastErrorCode` and `cLastError` (the one `Sql` would give). It does not touch `aWarnings` |
| `SetIdent(cName, cValue)` | Sets an identifier, as `FQ_SET` does. `.T.` or `.F.` with `ident_invalid` |
| `AddMacro(cEngine, cName, cTemplate)` | A macro of yours. `.T.` or `.F.` |
| `Params()` | An empty object of FoxNone, or `.NULL.` |
| `nQueries` | How many queries are loaded |
| `cFolder`, `cCatalog` | What is loaded: the folder, or the `.fq` |
| `nLoadErrors`, `aLoadErrors[n, 4]` | The mistakes of the last load: code, file, line, message |
| `nWarnings`, `aWarnings[n, 4]` | The warnings of the last load (`param_unused`, `ident_unused`) and of the last `CheckEngine`, the same way |
| `nErrors`, `cLastError`, `cLastErrorCode` | How many failures, the last one, and its code. The last failure stays until the next one, except in `CheckFile`, `LoadFile` and `CheckQuery`, which empty `cLastError` and `cLastErrorCode` when they start |
| `lStrict` | `.T.`: every failure raises a VFP error |
| `cLastQuery`, `cLastSql` | The last query asked for, and the last SQL given to an executor |

### QueryCompiler

A `QueryStore` with one more method, `Build(cFolder, cFq [, cKey [, lEncrypt]])`, which is what `FQ_BUILD`
calls. Give it your macros with `AddMacro` before `Build`. `cFq` keeps the name of the last `.fq` written.

### QueryOdbc

The executor for a connection you opened (`FQ_USE_HANDLE` creates one): `CREATEOBJECT("QueryOdbc", lnHandle)`,
or `.nHandle = lnHandle`. `cEngine` says the engine the driver reported (`cDbmsName`, `cDriver`); write
`cEngine` yourself to choose it. It does the `SQLEXEC` inside its own method, and before that it checks
that every `:name` of the text is in the object of parameters (`param_missing`): a `SQLEXEC` with a missing
parameter would open a "View Parameter" window that stops the program.

After `Run`, the cursor of the query is the selected work area, as with `SELECT … INTO CURSOR` and `SQLEXEC`, so
`BROWSE` or `SCAN` work on it. After `Scalar` and `Execute`, the work area that was selected before the call is
selected again, also when they fail (an empty one if none was).

### QueryLocal

The executor for local DBF tables (`FQ_USE_DBF` creates one): `CREATEOBJECT("QueryLocal")`. While a query
runs it sets `SET ANSI ON`, `SET DELETED ON` and `SET TABLEPROMPT OFF`, and leaves them as they were
afterwards: the same `.sql` returns the same rows as on a server, and a table that is not there is
`query_failed` instead of the "Open" dialog, which would wait for a person. `lDeletedOn = .F.` leaves
`DELETED` alone, and `lAnsiOn = .F.` leaves `ANSI` alone (see [Pitfalls](#pitfalls)). `SET EXACT`, `SET NULL`
and `SET ENGINEBEHAVIOR` are yours.

The work areas are left as with [QueryOdbc](#queryodbc): the cursor of `Run` selected, and after `Scalar` and
`Execute` the area that was selected before. A `write` query on a DBF table moves the record pointer of that table,
as the same `UPDATE` would if you ran it yourself, and FoxQuery does not put it back.

### FoxRemote

[FoxRemote](https://github.com/Irwin1985/FoxRemote) is a VFP library for remote databases through ODBC (it also
installs with FoxPack: `foxpack add foxremote`). Its database objects (`RemoteSqlServer`, `RemoteSqlite`, …) are
executors as they are: `FQ_USE(loDb)`, or `loStore.Run(loDb, …)`. FoxQuery does not need FoxRemote, and FoxRemote
does not change.

### An executor of your own

Any object with these members is an executor: `cEngine` (one of the seven engines), and the methods
`Query(cSql, cCursor, oParams)`, `Execute(cSql, oParams)` and `Scalar(cSql, oParams)`. The SQL arrives
with the `:name` as they are, and `oParams` has one property per parameter. If it has `nErrors` and
`cLastError`, FoxQuery reads them when it fails (`executor_failed`).

### Running the SQL yourself

With `{if}` or a list, the SQL text only works with the parameters that go with it. `Args` returns that
object and `Sql` the text that uses it; both check the parameters as `Run` does. The third argument of
`Sql` is the name of the variable that holds the object, and the `SQLEXEC` has to see that variable (a
local of the same program; a `PRIVATE` when the `SQLEXEC` runs somewhere else, see
[With another connection library](#with-another-connection-library)). This one needs the SQLite driver:

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

On SQLite, convert your text parameters with `STRCONV(x, 9)` and what you read with `STRCONV(x, 11)`, as
FoxQuery does (see [Pitfalls](#pitfalls)).

### With another connection library

Your program may open its connections with a library of its own, built on `SQLCONNECT` or on ADO, and
FoxQuery still connects nothing. There are three ways, and the first asks nothing of the library:

1. **The handle.** If the library gives you the number of its `SQLCONNECT` or `SQLSTRINGCONNECT` (almost
   every library for VFP does), `FQ_USE_HANDLE(loLib.nHandle)`, or `CREATEOBJECT("QueryOdbc", loLib.nHandle)`:
   FoxQuery runs the SQL itself and asks the driver which engine it is. The library takes no part, and it needs
   no particular members.
2. **The object.** `FQ_USE(loLib)` needs the four members of [An executor of your own](#an-executor-of-your-own),
   and the SQL arrives with the `:name` as they are. FoxRemote has them; another library does not, and then
   you write an adapter: a small class with `cEngine`, `Query`, `Execute` and `Scalar` that turns each `:name`
   into what the library understands and calls it. It is the only way for a library that is not ODBC (ADO,
   OLE DB).
3. **The library runs the SQL.** `Args` and `Sql` give you the object and the text with `?loArgs.name`, and
   the library runs the text. The variable has to be visible where the `SQLEXEC` happens: a `LOCAL` of your
   program is not seen from a method of the library (a local lives only in the procedure that declares it),
   and a `SQLEXEC` with a parameter it cannot see opens "View Parameter" and waits for a person. Declare it
   `PRIVATE`.

The example takes the first way and the third, with a stand-in for such a library; it needs the SQLite
driver:

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

### The object of parameters: FoxNone

Any object works as `oParams`. A `None` of FoxNone (`FQ_PARAMS()`, or `loStore.Params()` with
`SET PROCEDURE TO foxnone.prg ADDITIVE`) takes a property in one line, without `ADDPROPERTY`:

```foxpro
loP = FQ_PARAMS()
loP.city = "Oslo"
=FQ_RUN("customers.by_city", "c_result", loP)
```

The executor never receives your object: FoxQuery copies the declared parameters to a new object. A
parameter cannot have the name of a member of `Custom` (`name`, `tag`, `width`, `parent`, …): that is
`param_reserved`, and the message proposes another name.

## Errors

Every failure has a code in English that does not change between versions. `FQ_LAST_ERROR_CODE()` and
`cLastErrorCode` return it; `FQ_LAST_ERROR()`, `FQ_ERRORS()` and `cLastError` add the reason.

**Loading the `.sql` files** (`FQ_LOAD`, `FQ_BUILD`; with the file and the line in `FQ_ERRORS()`):

| Code | What happened | What to do |
|---|---|---|
| `folder_not_found` | The folder does not exist | Check the name. A relative name starts at the current folder (`SET DEFAULT`) |
| `file_not_found` | `CheckFile` or `LoadFile` of a `.sql` that does not exist | Check the name |
| `header_name_missing` | The file has no `-- name:` | Add it, with the name of the file without `.sql` |
| `header_name_mismatch` | `-- name:` and the name of the file are different | Make them the same |
| `header_kind_missing` | The file has no `-- kind:` | Add `-- kind: read` or `-- kind: write` |
| `header_kind_invalid` | `-- kind:` is not `read` or `write` | Write one of the two |
| `kind_mismatch` | `read` with a SQL that does not start with `SELECT`, or `write` with one that does | Correct `-- kind:` or the SQL |
| `sql_missing` | There is no SQL under the header, or a `-- engine:` section is empty | Write the SQL |
| `param_name_invalid` | A parameter has a name that is not valid, or a pair of a function is wrong (a name that is not text, a name repeated, a name without its value) | A letter or `_`, then letters, digits or `_`, without the `:`; the arguments go in pairs |
| `param_type_invalid` | The type of a parameter is not one of `C N I D T L Y M` | Write one of them |
| `param_flag_invalid` | A word after the type that is not `required`, `list` or `default` | Remove it or correct it |
| `param_duplicate` | A parameter is declared twice | Remove one |
| `param_reserved` | The name of a parameter is a member of a VFP object (`name`, `tag`, …) | Use the name the message proposes |
| `default_type` | The `default` does not fit the type, or a list has a `default` | Write a value of the type |
| `param_undeclared` | The SQL uses a `:name` that the header does not declare | Add its `-- param:` line |
| `param_unused` | A warning, not an error: a parameter is declared and the SQL does not use it | Remove it, or use it |
| `engine_unknown` | An engine that is not one of the seven (`-- engine:`, a macro, an executor) | `sqlserver mysql mariadb postgresql firebird sqlite vfp` |
| `engine_duplicate` | Two `-- engine:` sections for the same engine | Leave one |
| `bad_option` | `-- sort:` without columns, or with something that is not a column; or a call that asks for an order that is not in the list | Use the columns of `-- sort:`, with `ASC` or `DESC` |
| `sort_without_macro` | There is a `-- sort:` and no `{sort}` in the SQL | Add `ORDER BY {sort}`, or remove `-- sort:` |
| `macro_sort_without_list` | There is a `{sort}` and no `-- sort:` | Add `-- sort:` with the columns |
| `sql_too_long` | On `vfp`, the text is longer than the 8,190 characters VFP runs in one line: a warning in `FQ_WARNINGS()` at `FQ_BUILD` and when `vfp` is the engine in use, with the file and the line; the error when it runs (also after a list grows) | Write a shorter `-- engine: vfp` text, or give fewer elements |
| `ident_undeclared` | A `{ident x}` in the text without its `-- ident: x` (on load, with the file and the line) | Add `-- ident: x` with its form, for example `-- ident: x letters 1-20` |
| `ident_form_invalid` | A `-- ident:` line that has no form (on load) | `-- ident: sort letters 1-20`: a name, then `digits`, `letters`, `alnum` or `ident`, and a length `2` or a range `1-8` |
| `ident_param_clash` | The same name in `-- ident:` and in `-- param:` (on load) | Pick one |
| `ident_unused` | A warning, not an error: a `-- ident:` that no text uses | Use it with `{ident x}`, or remove the line |
| `ident_missing` | The query uses `{ident x}` and nobody set it | `FQ_SET("x", ...)` once, when the program starts |
| `ident_invalid` | `FQ_SET` with a value that is not letters, digits and `_`, or not of the declared form (the message says what that form takes: `(2 digits)`, `(1 to 20 letters)`); or, when it runs, a value that a newer load declares stricter (it says which declaration) | Set a value of the form |
| `ident_not_a_param` | An identifier that comes in the call (`FQ_RUN(..., "x", "10")`, or a property of the object of parameters) | `FQ_SET` it once; it never goes in the call |
| `sort_not_in_select` | On `vfp`, a column of `-- sort:` is not in the `SELECT` list, or the list is `*`: a warning in `FQ_WARNINGS()` at `FQ_BUILD` and when `vfp` is the engine in use, the error when it runs (it says the file and the line of `-- sort:`) | Put the column in the `SELECT` list, or write a `-- engine: vfp` text |
| `if_unbalanced` | An `{if}` without its `{endif}`, an `{if}` inside another, or an `{if}` without `:name` | One `{if :name} … {endif}` at a time |
| `macro_unknown` | A `{macro}` that no engine has | Correct the name, or add it with `FQ_ADD_MACRO` |
| `macro_unsupported` | The engine cannot do it (`{offset}` on VFP, `{limit 0}` on VFP) | Write a `-- engine:` text for that engine |
| `macro_reserved` | `FQ_ADD_MACRO` with the name of a mark (`if`, `endif`, `sort`, `limit`, `offset`) or of an ODBC escape (`d`, `t`, `ts`, `fn`, `oj`, `call`, `escape`) | Choose another name |
| `limit_arg_invalid` | `{limit}` or `{offset}` with something that is not a `N`/`I` parameter or a whole number, or two `{limit}` | `{limit :rows}` or `{limit 10}`, once |
| `limit_without_order_by` | `{limit}` in a query without `ORDER BY` | Add the `ORDER BY` |
| `offset_without_limit` | `{offset}` without a `{limit}` right before | Write `{limit …} {offset …}` |

**Running a query** (`FQ_RUN`, `FQ_SCALAR`, `FQ_EXECUTE`, `FQ_SQL`):

| Code | What happened | What to do |
|---|---|---|
| `not_loaded` | A function ran before `FQ_LOAD` (a VFP error: it is a bug of the program) | Call `FQ_LOAD` first |
| `not_connected` | No `FQ_USE…` before (a VFP error), or a handle that is not an open connection | Call `FQ_USE_DBF`, `FQ_USE_HANDLE` or `FQ_USE` first, with an open connection |
| `query_not_found` | There is no query with that name | Check the name, and that `FQ_LOAD` loaded its file |
| `query_duplicate` | `CheckFile` or `LoadFile` of a `.sql` whose query is already loaded from another file (another folder) | A query has one file: load that folder, or rename it |
| `param_missing` | A required parameter did not come in the call | Pass it |
| `param_unknown` | A pair with a name that the query does not declare (`"cty"` for `city`); the message lists the ones it declares | Write the name of its `-- param:` line |
| `param_type` | A value that does not fit its type (a text for a `N`, a text with commas for a list that is not `C` or `M`), or an empty list | Pass a value of the type of `-- param:` |
| `limit_value_invalid` | The value for `{limit}` or `{offset}` is not a whole number, is negative, or is 0 on VFP | Pass a whole number, 1 or more |
| `wrong_kind` | `FQ_RUN` or `FQ_SCALAR` with a `write` query, or `FQ_EXECUTE` with a `read` one | Use the function of its kind |
| `executor_failed` | The engine returned an error: its message is in the reason | Read the message of the engine |
| `query_failed` | The same, said by `QueryOdbc` or `QueryLocal` when you call them directly | Read the message of the engine |
| `executor_invalid` | `FQ_USE` with an object that is not an executor | See [An executor of your own](#an-executor-of-your-own) |
| `foxnone_missing` | `FQ_PARAMS()` without FoxNone loaded | `SET PROCEDURE TO foxnone.prg ADDITIVE`, or use any other object |
| `internal_error` | FoxQuery failed and could not say why | Report it, with what `FQ_LAST_ERROR()` says |

**The catalog** (`FQ_BUILD`, `FQ_LOAD` of a `.fq`, `FQ_ADD_MACRO`):

| Code | What happened | What to do |
|---|---|---|
| `catalog_not_found` | There is no `.fq` with that name, inside the EXE or next to it | Check the name, and that the project includes the file |
| `catalog_tampered` | The signature does not match: the file changed, it is cut, it is not a `.fq`, or the key is not the one of `FQ_BUILD` (the signature is checked before anything else) | Build it again; use the same key in both |
| `catalog_invalid` | A `.fq` with a good signature and a content FoxQuery cannot read | Build it again |
| `catalog_not_written` | `FQ_BUILD` could not write the `.fq`: the file is open in an editor or is read-only (the message says how many bytes went), or the folder does not exist (the message names it) | Close the editor or fix the path and build again |
| `catalog_version` | An older FoxQuery built it | Build it again with this one |
| `catalog_key_required` | The `.fq` is encrypted and `FQ_LOAD` got no key; or `FQ_BUILD` was asked to encrypt without a key | Pass your key |
| `catalog_frozen` | `FQ_ADD_MACRO` with a `.fq` loaded: the loaded `.fq` does not change, and the macro is kept for the next `FQ_BUILD` | Nothing, if you build again; give your macros before `FQ_BUILD` |

## Pitfalls

- **VFP cannot use a property or a method of what a function returns.** `FQ_STORE().nQueries` compiles and
  fails when it runs. Put it in a variable first: `loStore = FQ_STORE()`.
- **A list or an array goes with `@`.** `"countries", @laCountries`; without `@`, VFP passes only the first
  element.
- **SQLite and accented letters.** The SQLite driver converts the SQL text to UTF-8, but neither the parameters
  nor what comes back. FoxQuery converts both, so `FQ_RUN` with `"Muñoz"` works. If you run `SQLEXEC` yourself, do the
  same: `STRCONV(x, 9)` for each text parameter and `STRCONV(x, 11)` for what you read.
- **SQLite and dates.** A `D` or `T` parameter travels as text with the time (`'2026-11-02 00:00:00.000'`):
  it does not match a column that keeps `'2026-11-02'` with `=`, and it works with `>=` and `<`.
- **SQLite: a calculated column comes back as a memo.** A column of the `SELECT` that is an expression
  (`SUBSTR(name, 1, 3) AS first3`) has no declared type, and VFP gets a `Memo`. Declare the columns of the
  table with a type (`VARCHAR(30)`, not `TEXT`).
- **SQLite: `{like_ci}` only works with ASCII.** SQLite changes to capitals only the letters without
  accents: `Muñoz` does not match `MUÑOZ`. `{now}` returns text, not a date and time.
- **MySQL: use the MariaDB driver.** Oracle's ODBC driver sends a number as a double that does not match a
  `DECIMAL`, and after a lock timeout it has left VFP hanging.
- **Firebird.** `{nvl}` goes on a column, not on a parameter alone (`?p` without a column is "Data type
  unknown"); `:p IS NULL` does not work: use an `{if :p}` block; and `.NULL.` does not go into a `BOOLEAN`.
- **VFP: `{limit}` and ties.** With `SET ENGINEBEHAVIOR 70`, `TOP n` also returns the rows tied with the
  last one, so you can get more than n rows. With 90, the default, you get n.
- **VFP: a `--` after SQL on the same line.** VFP does not know `--`. FoxQuery removes the lines that start
  with `--`, but not a `--` after SQL. In a query that runs on DBF, put the comment on its own line.
- **VFP has no `COALESCE`.** Use `{nvl}`, or a `-- engine: vfp` text.
- **VFP: `ANSI ON` costs time on big joins.** While a query runs, `QueryLocal` sets `SET ANSI ON`, so that `=`
  compares as on a server. On joins of many rows over DBF that was 30 to 40 % slower than `ANSI OFF` (255 s
  against 195 s on joins of 148,027 rows over 6 tables). `loDb = FQ_DB()` and then `loDb.lAnsiOn = .F.` leave
  `SET ANSI` as you have it, and then `=` compares as your `SET ANSI` says: with `OFF`, `city = 'Os'` matches
  `'Oslo'`, so the rows may differ from the ones a server returns.
- **VFP: a query of more than 8,190 characters does not fit in one line.** On DBF, VFP runs the SQL as one line,
  and 8,190 characters is the most it takes, counting the `INTO CURSOR` that `QueryLocal` adds (one more is VFP
  error 18).

  `FQ_BUILD` warns about it in `FQ_WARNINGS()` with `sql_too_long`, the file and the line, and so do `FQ_LOAD` once
  `vfp` is the engine in use and `FQ_USE_DBF` with the queries loaded. `FQ_RUN` of that query fails with the same
  code, and the other engines run the same `.sql`. A short query with a long list can also grow past the limit when
  it runs: then `FQ_RUN` gives `sql_too_long` before the SQL reaches VFP. Use a shorter `-- engine: vfp` text, or
  fewer elements in the list.

  On DBF, `FQ_RUN` sets `SYS(3055, 2040)` while it runs and puts the old value back afterwards, so a list is only
  limited by `sql_too_long` (514 elements, with the `INTO`). If your program runs the same SQL itself with VFP's
  default `SYS(3055)`, an `IN` takes 158 elements (VFP error 1812).

  Finding these queries takes time with a folder, not with a `.fq`: to say what `vfp` cannot run, `FQ_USE_DBF` (and
  `FQ_LOAD` with `vfp` in use) resolves the text of every loaded query, which each first `FQ_RUN` would do anyway.
  With 500 queries of about 550 characters loaded from a folder that is about 2.3 s, once; from a `.fq`, about 5 ms.
  After that it costs nothing, because the result is kept and a second `FQ_USE_DBF` finds it. In production, load
  the `.fq`.
- **A `bit` of SQL Server copied to DBF is `L`.** `WHERE active = 0` then gives VFP error 107 ("Operator/operand
  type mismatch"). Write `{false}` (and `{true}`): each engine gets what it understands.
- **A free table does not take a field name of more than 10 letters.** If your `.sql` files use
  `customer_id`, the DBF tables go in a database (`.dbc`).
- **A "View Parameter" window.** It appears when a `SQLEXEC` uses `?name` and that variable does not exist,
  and it stops the program until someone answers. FoxQuery checks every `:name` before it calls the
  engine, so it does not appear with `FQ_RUN`. It can appear with your own `SQLEXEC`: use `Args`.
- **`CLEAR DLLS`.** FoxQuery declares the CryptoAPI functions it needs once (for the `.fq`). After a
  `CLEAR DLLS` with no list, it declares them again by itself. A `CLEAR DLLS` that removes only some of
  them can make the next `FQ_LOAD` of a `.fq` fail: then call `CLEAR DLLS` with no list.
- **`FQ_ADD_MACRO` and a `.fq`.** The state lives in `_SCREEN`, so when you run your program again in the
  same VFP the `.fq` of the last run is still loaded and `FQ_ADD_MACRO` gives `catalog_frozen`. The macro
  is kept all the same, and the next `FQ_BUILD` carries it.
- **`SET SAFETY ON` and your own files.** A new VFP starts with `SET SAFETY ON`: a `STRTOFILE` or a
  `CREATE TABLE` over a file that exists asks before it writes. FoxQuery writes the `.fq` without asking;
  your own programs need `SET SAFETY OFF`.

## Changes

- **1.0.2** (2026-11-10): internal code that the library did not use is gone. A program that uses FoxQuery sees no
  change.
- **1.0.1** (2026-11-05): `FQ_BUILD` and `Build` fail with `catalog_not_written` when they cannot write the `.fq`
  (the file is open in an editor or read-only, or its folder does not exist, and then the message names the folder).
  New in `QueryStore`: `CheckEngine(cEngine, nFrom, nCount)` checks the queries by ranges and adds up the warnings,
  never the same one twice; `CheckQuery` checks one query; `CheckFile` and `LoadFile` check or replace one query from
  its `.sql` without reloading the rest (`file_not_found`, `query_duplicate`); `Names()` lists the queries in load
  order, and `Get()` also takes a number. `CheckQuery`, `CheckFile` and `LoadFile` empty `cLastError` when they
  start, and the error of `CheckFile` and `LoadFolder` is the first line of `FQ_ERRORS()`
  (`file(line): code: reason`), also in `FQ_LAST_ERROR()`. In `QueryLocal` and `QueryOdbc`, `Scalar` and `Execute`
  select again the work area that was selected before the call; `Run` still leaves the query cursor selected.
- **1.0.0** (2026-11-04): the first version.

## License

MIT. The text is in `LICENSE`.
