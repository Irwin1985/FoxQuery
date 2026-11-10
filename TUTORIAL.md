# FoxQuery step by step

In this tutorial you will put a program's SQL queries in `.sql` files, run them by name against DBF
tables and then against SQLite without changing a line, and finish with an `.exe` that carries the
queries inside. You do everything with functions from a `.prg`; the classes come at the end, for those
who want them.

You need Visual FoxPro 9 SP2 and the file `foxquery.prg`. For step 6, the SQLite ODBC driver.
Each step says which file to create, what to write in it and what must appear on the screen. If a step
shows something else, stop there: the error tells you what happened.

The tutorial programs print their messages in English, like FoxQuery itself.

## Step 1: the folder and the library

In the Visual FoxPro Command window, type these two lines, pressing Enter after each one:

```foxpro
MKDIR C:\FoxQueryTutorial
SET DEFAULT TO C:\FoxQueryTutorial
```

Copy `foxquery.prg` to `C:\FoxQueryTutorial`. If you use FoxPack, `foxpack add foxquery` puts it in
your project's `lib\foxquery\` folder; copy it from there.

Now create the first program. Type in the Command window:

```foxpro
MODIFY COMMAND step01-hello
```

The editor opens. Type this in it:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
? FQ_VERSION()
```

Press Ctrl+W to save and close. Type `DO step01-hello` in the Command window and press Enter.
The main Visual FoxPro window shows:

```
1.0.2
```

The first line loads FoxQuery; the second one asks for its version. Every program in the tutorial starts
with that same line. If instead of the version you see "File 'foxquery.prg' does not exist", the file
is not in `C:\FoxQueryTutorial`, or `SET DEFAULT` points to another folder.

From here on, you make each new program the same way: `MODIFY COMMAND` with its name, type the code,
Ctrl+W and `DO` with its name.

## Step 2: a table of customers

Create `step02-table.prg`:

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

Run it with `DO step02-table`. It shows:

```
5
```

Now you have `customers.dbf` in the folder, with five customers. One of them has an ñ: Ana Muñoz.
With `SET SAFETY OFF`, running the program again creates the table again without asking whether you want
to overwrite it. `FREE` makes it a free table, outside any database.

## Step 3: the first query

The queries go in a folder, one per file. Create the folder and the file for the first one:

```foxpro
MKDIR queries
MODIFY FILE queries\customers.by_city.sql
```

Type this in the editor and save with Ctrl+W:

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

The first four lines are the header. They start with `--`, which is a comment in SQL, so the file is
still SQL that you can paste into any database tool.

- `-- name: customers.by_city` is the name of the query. It must match the file name without
  `.sql`. The dot in the middle only groups the queries about customers.
- `-- description:` tells whoever reads the file what the query is for.
- `-- kind: read` says that the query reads (a `SELECT`). The ones that write (`INSERT`, `UPDATE`, `DELETE`)
  have `-- kind: write`.
- `-- param: city C required` declares a parameter: its name is `city`, its type is `C` (text) and it is
  required.

The SQL goes below the header. `:city` marks where the parameter goes: FoxQuery sends the value
separately and never pastes it into the SQL text.

Create `step03-load.prg`, which loads the folder:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
IF FQ_LOAD("queries\")
	? "The queries are loaded"
ELSE
	? FQ_ERRORS()
ENDIF
```

`DO step03-load` shows:

```
The queries are loaded
```

If there is a mistake in the header, you see an error line instead, with the file name, the line number
and what is wrong. Step 9 shows the most common errors.

## Step 4: run the query

Create `step04-run.prg`:

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

`DO step04-run` shows:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
FQ_RUN: param_missing: city (customers.by_city needs it, and the call gives no city)
```

The numbers have some spaces in front: that is how `?` aligns numbers in VFP.

Line by line:

- `FQ_LOAD("queries\")` loads the queries in the folder.
- `FQ_USE_DBF()` says where they run: on the DBF tables of the current folder.
- `FQ_RUN("customers.by_city", "c_result", "city", "Oslo")` runs the query by its name and puts the
  rows in the cursor `c_result`. After the cursor name come the parameters in pairs: the parameter name and
  its value. It returns `.T.` if it succeeds.
- The `SCAN` goes through the cursor and writes each row. If you prefer to see it in a grid, type
  `BROWSE` in the Command window after you run the program.

The second call to `FQ_RUN` does not pass the city, so FoxQuery returns `.F.` without touching the table,
and `FQ_LAST_ERROR()` says which function failed, the error code (`param_missing`) and what is missing. All
FoxQuery functions fail this way, without showing windows or stopping the program.

## Step 5: an optional filter, the order and a list

Create two more queries. The first one, `queries\customers.search.sql`:

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

It has three new things:

- `-- param: since D` is a date parameter without `required`, so it is optional.
- `{if :since}AND born >= :since{endif}` is a piece that goes into the SQL only when the call passes
  `since`. If the call does not pass it, the `WHERE` stays as `city = :city`.
- `-- sort: name, id` lists the columns the caller can sort by, and `{sort name}` marks where the sort
  columns go, with `name` when the call does not choose any. A column that is not in the list never reaches
  the SQL.

The second one, `queries\customers.in_countries.sql`:

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

The word `list` says that `countries` is a list of values, for the `IN`.

Create `step05-options.prg`:

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

`DO step05-options` shows:

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

The sort order goes as one more pair: `"sort", "id DESC"`. The list goes as a text with commas
(`"ES,PT,DE"`); if you have it in an array, pass it with `@` in front: `"countries", @laCountries`.

## Step 6: the same `.sql` against SQLite

SQLite is a database in a single file, without a server. For this step you need its 32-bit ODBC
driver: download `sqliteodbc.exe` from ch-werner.de and install it. Visual FoxPro is a 32-bit program and
does not see 64-bit drivers.

Create one more query, `queries\customers.by_initial.sql`:

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

`{substr name, 1, 1}` is a macro: each database engine has its own syntax for taking part of a string,
and FoxQuery writes the form that each engine needs.

Create `step06-sqlite.prg`:

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

`DO step06-sqlite` shows:

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

The program opens a connection with `SQLSTRINGCONNECT`, as you would do, and creates the same customers
table in `tutorial.db`. Then:

- `FQ_USE_HANDLE(lnHandle)` tells FoxQuery that the queries run on that connection. FoxQuery asks
  the driver which engine it is (here, SQLite) and picks the SQL for that engine.
- `FQ_RUN` is the same call as in step 4, with the same `.sql`, and it gives the same rows. The ñ in Ana
  Muñoz comes through correctly: SQLite keeps the text in UTF-8 and FoxQuery does the conversion in both directions.
- The last three lines use `FQ_SQL` to show the SQL of `customers.by_initial` for SQLite, Firebird and
  the DBF tables, without running it. The macro comes out in two forms: SQLite and the DBF tables write it
  the same way, and Firebird has its own.
- The second argument of `FQ_SQL` is the engine name, one of these seven: `sqlserver`, `mysql`,
  `mariadb`, `postgresql`, `firebird`, `sqlite` and `vfp` (the DBF tables of `FQ_USE_DBF`, from step 4).
  Without it, `FQ_SQL` uses the current engine.
- If `FQ_SQL`, or any other `FQ_*`, gives `.NULL.` or `.F.`, `? FQ_LAST_ERROR()` says why. An engine name
  that does not exist gives `engine_unknown` and the list of the seven.

If you see "No connection: is the SQLite3 ODBC Driver installed?", the driver is not installed, or the
64-bit one is installed.

## Step 7: the `.fq` catalog

For the version that you deliver to your customers, the `queries` folder is compiled into a single signed file:
the catalog. Create `step07-build.prg`:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
IF FQ_BUILD("queries\", "app.fq", "my secret key")
	? "app.fq is ready"
ELSE
	? FQ_ERRORS()
ENDIF
```

`DO step07-build` shows:

```
app.fq is ready
```

`FQ_BUILD` reads all the queries in the folder, checks that they are correct and writes `app.fq` with a signature
made with your key (`"my secret key"`; in your program, put your own). If a query has an error, the `.fq`
is not written and `FQ_ERRORS()` gives all the errors, one per line.

Now create `step07-catalog.prg`, which loads the catalog instead of the folder:

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

`DO step07-catalog` shows the same customers:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

**What happens if someone changes the `.fq`.** Open `app.fq` with Notepad (right-click the file,
"Open with", "Notepad"). You will see text with strange characters; find `ORDER BY name`, change one letter
(for example, `nAme`) and save. Go back to Visual FoxPro and run `DO step07-catalog` again. It shows:

```
FQ_LOAD: catalog_tampered: app.fq: the signature does not match; the file changed, or the key is not the one of the build
```

The signature no longer matches the content, and FoxQuery loads nothing from the file. The same happens if you load the
catalog with another key. To fix it, compile again: `DO step07-build`, and `DO step07-catalog` shows
the customers again.

The signature with your key stops anyone from changing your program's queries, but the SQL text can still
be read in the file, as you have seen. To hide it from someone who opens the file with an editor, compile
with encryption: `FQ_BUILD("queries\", "app.fq", "my secret key", .T.)`. The key is inside your program, so
someone who tries hard enough can get it out.

## Step 8: the catalog inside the `.exe`

Create `step08-main.prg`, which will be the main program of the `.exe`:

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

The first three lines are for the `.exe`: `_VFP.StartMode` is 4 when the program runs as an `.exe`, and then
`SET DEFAULT` makes the `.exe` folder the current folder (`SYS(16, 0)` is the path of the `.exe`). From
the Command window they do nothing, because the current folder is already `C:\FoxQueryTutorial`.

Try it first from the Command window: `DO step08-main` shows the customers, a window with
"Press a key to close" appears and, when you press a key, it closes:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

Now the project. In the Command window:

```foxpro
CREATE PROJECT tutorial
```

The Project Manager opens:

1. In the `Code` tab, choose `Programs` and click `Add...`. Add `step08-main.prg`. Click `Add...`
   again and add `foxquery.prg`.
2. Right-click `step08-main` and choose `Set Main`. Its name turns bold.
3. In the `Other` tab, choose `Other Files` and click `Add...`. In `Files of type` choose `All Files (*.*)`
   and add `app.fq`. If it shows a crossed-out circle on its left, it is excluded: right-click it,
   `Include`.
4. Click `Build...`, choose `Win32 executable / COM server (exe)` and click `OK`. Save it as
   `tutorial.exe` in `C:\FoxQueryTutorial`.

Open `C:\FoxQueryTutorial` in File Explorer and double-click `tutorial.exe`. You see the two
customers from Oslo and the "Press a key to close" window.

`app.fq` goes inside the `.exe`: `FQ_LOAD("app.fq", …)` looks for it there first and, if it is not inside, next
to the `.exe`. The table `customers.dbf` stays outside, next to the `.exe`, like any data table,
and VFP looks for it in the current folder. That is what the first three lines are for: without them, an `.exe`
started from another folder (a shortcut, another window) does not find the table, and `FQ_RUN` gives
`executor_failed` with a message that says `customers.dbf` does not exist. In your own program, the tables are
where your program says: the folder of the `.exe`, a `SET PATH` or an open database.

## Step 9: the most common errors

Create `step09-errors.prg`. It causes six errors on purpose:

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

`DO step09-errors` shows:

```
FQ_RUN: param_missing: city (customers.by_city needs it, and the call gives no city)
FQ_RUN: param_unknown: cty (customers.by_city declares city)
FQ_RUN: param_type: city is declared C and the value is N (customers.by_city)
FQ_RUN: query_not_found: there is no query called customers.by_town
FQ_RUN: param_name_invalid: the parameter city has no value: the arguments go in pairs, name and value
customers.broken.sql(2): param_type_invalid: the type of city is 'X': it is one of C N I D T L Y M
customers.broken.sql(1): header_kind_missing: the header has no '-- kind:' (read or write)
```

One by one:

1. `param_missing`: a required parameter is missing. Pass it.
2. `param_unknown`: the parameter name is misspelled (`cty` instead of `city`). The message lists
   the parameters that the query declares: write one of them.
3. `param_type`: the value is not of the type that the header says (`42` is a number and `city` is `C`).
   Pass a value of the type in `-- param:`.
4. `query_not_found`: there is no query with that name. Check the file name and that the file is in
   the folder that you loaded.
5. `param_name_invalid`: the parameters go in pairs, and here the value of `city` is missing.
6. A `.sql` with two errors: `FQ_ERRORS()` gives both, each one with its file and its line in
   parentheses. The type `X` does not exist (the types are `C N I D T L Y M`) and the line `-- kind:` is missing. When a load
   fails, what was loaded stays as it was: the queries of `queries` keep working.

The full list of codes, with what to do in each case, is in the "Errors" section of
[README.md](README.md).

## Step 10: the same with classes

The `FQ_*` functions use some classes inside, and you can use them too. Create `step10-classes.prg`:

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

`DO step10-classes` shows:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

`QueryStore` is the query store and `QueryLocal` is the executor for DBF tables. For an ODBC
connection, the executor is `QueryOdbc` (`CREATEOBJECT("QueryOdbc", lnHandle)`), and if you already use FoxRemote, any of
its databases works as an executor without changes. The parameters go in an object with one property per
parameter. You read errors from `cLastErrorCode` and `cLastError` instead of `FQ_LAST_ERROR()`.

Everything that the classes do is in the "API" section of [README.md](README.md).
