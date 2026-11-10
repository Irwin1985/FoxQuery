# FoxQuery Schritt für Schritt

In diesem Tutorial speicherst du die SQL-Abfragen eines Programms in `.sql`-Dateien, führst sie über ihren
Namen gegen DBF-Tabellen und danach gegen SQLite aus, ohne eine Zeile zu ändern, und am Ende steht eine
`.exe`, die die Abfragen in sich trägt. Alles mit Funktionen aus einer `.prg`; die Klassen kommen am Ende,
für alle, die sie möchten.

Du brauchst Visual FoxPro 9 SP2 und die Datei `foxquery.prg`. Für Schritt 6 den ODBC-Treiber von SQLite.
Jeder Schritt sagt, welche Datei du anlegst, was du hineinschreibst und was auf dem Bildschirm erscheinen
muss. Erscheint in einem Schritt etwas anderes, hör dort auf: Die Fehlermeldung sagt, was passiert ist.

Die Programme des Tutorials schreiben auf Englisch, was sie auf dem Bildschirm anzeigen, ebenso wie die
Meldungen von FoxQuery.

## Schritt 1: der Ordner und die Bibliothek

Gib im Befehlsfenster von Visual FoxPro diese zwei Zeilen ein und drücke nach jeder die Eingabetaste:

```foxpro
MKDIR C:\FoxQueryTutorial
SET DEFAULT TO C:\FoxQueryTutorial
```

Kopiere `foxquery.prg` nach `C:\FoxQueryTutorial`. Wenn du FoxPack verwendest, legt `foxpack add foxquery`
die Datei in `lib\foxquery\` deines Projekts ab: Kopiere sie von dort.

Lege jetzt das erste Programm an. Gib im Befehlsfenster ein:

```foxpro
MODIFY COMMAND step01-hello
```

Der Editor öffnet sich. Schreib Folgendes hinein:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
? FQ_VERSION()
```

Drücke Strg+W, um zu speichern und zu schließen. Gib `DO step01-hello` im Befehlsfenster ein und drücke die
Eingabetaste. Im Hauptfenster von Visual FoxPro erscheint:

```
1.0.2
```

Die erste Zeile lädt FoxQuery; die zweite fragt seine Version ab. Alle Programme des Tutorials beginnen mit
derselben ersten Zeile. Erscheint statt der Version „File 'foxquery.prg' does not exist“, liegt die Datei
nicht in `C:\FoxQueryTutorial`, oder `SET DEFAULT` zeigt auf einen anderen Ordner.

Ab hier entsteht jedes neue Programm auf dieselbe Weise: `MODIFY COMMAND` mit seinem Namen, den Code
schreiben, Strg+W und `DO` mit seinem Namen.

## Schritt 2: eine Kundentabelle

Lege `step02-table.prg` an:

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

Führe es mit `DO step02-table` aus. Es erscheint:

```
5
```

Jetzt hast du `customers.dbf` im Ordner, mit fünf Kunden. Einer davon hat ein ñ: Ana Muñoz.
`SET SAFETY OFF` sorgt dafür, dass die Tabelle, wenn du das Programm noch einmal ausführst, neu angelegt
wird, ohne dass du gefragt wirst, ob du sie überschreiben willst. `FREE` sagt, dass es eine freie Tabelle
ist, außerhalb jeder Datenbank.

## Schritt 3: die erste Abfrage

Die Abfragen liegen in einem Ordner, eine pro Datei. Lege den Ordner und die Datei der ersten an:

```foxpro
MKDIR queries
MODIFY FILE queries\customers.by_city.sql
```

Schreib das in den Editor und speichere mit Strg+W:

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

Die ersten vier Zeilen sind der Kopf. Sie beginnen mit `--`, was in SQL ein Kommentar ist; die Datei bleibt
also SQL, das du in jedes Datenbankwerkzeug einfügen kannst.

- `-- name: customers.by_city` ist der Name der Abfrage. Er muss der Dateiname ohne `.sql` sein. Der Punkt
  in der Mitte dient nur dazu, die Abfragen zu den Kunden zu gruppieren.
- `-- description:` sagt dem Leser der Datei, wozu die Abfrage dient.
- `-- kind: read` sagt, dass die Abfrage liest (ein `SELECT`). Die Abfragen, die schreiben (`INSERT`,
  `UPDATE`, `DELETE`), haben `-- kind: write`.
- `-- param: city C required` deklariert einen Parameter: Er heißt `city`, ist vom Typ `C` (Text) und ist
  Pflicht.

Darunter steht das SQL. `:city` ist der Platzhalter für den Parameter: FoxQuery schickt den Wert getrennt und fügt
ihn nie in den SQL-Text ein.

Lege `step03-load.prg` an, das den Ordner lädt:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
IF FQ_LOAD("queries\")
	? "The queries are loaded"
ELSE
	? FQ_ERRORS()
ENDIF
```

`DO step03-load` zeigt:

```
The queries are loaded
```

Hast du dich im Kopf vertan, erscheint stattdessen eine Fehlerzeile mit dem Dateinamen, der Zeilennummer
und dem Problem. In Schritt 9 geht es um die häufigsten Fehler.

## Schritt 4: die Abfrage ausführen

Lege `step04-run.prg` an:

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

`DO step04-run` zeigt:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
FQ_RUN: param_missing: city (customers.by_city needs it, and the call gives no city)
```

Die Zahlen erscheinen mit ein paar Leerzeichen davor: So richtet VFP Zahlen bei `?` aus.

Zeile für Zeile:

- `FQ_LOAD("queries\")` lädt die Abfragen aus dem Ordner.
- `FQ_USE_DBF()` sagt, wo sie laufen: auf den DBF-Tabellen im aktuellen Ordner.
- `FQ_RUN("customers.by_city", "c_result", "city", "Oslo")` führt die Abfrage über ihren Namen aus und legt
  die Zeilen im Cursor `c_result` ab. Nach dem Namen des Cursors kommen die Parameter paarweise: der Name
  des Parameters und sein Wert. Gibt `.T.` zurück, wenn alles geklappt hat.
- Das `SCAN` durchläuft den Cursor und schreibt jede Zeile aus. Wenn du sie lieber in einem Raster siehst,
  gib nach dem Ausführen des Programms `BROWSE` im Befehlsfenster ein.

Der zweite Aufruf von `FQ_RUN` übergibt die Stadt nicht. Deshalb gibt FoxQuery `.F.` zurück, ohne die
Tabelle anzurühren, und `FQ_LAST_ERROR()` sagt, welche Funktion fehlgeschlagen ist, den Fehlercode
(`param_missing`) und was fehlt. Alle Funktionen von FoxQuery schlagen so fehl, ohne Fenster anzuzeigen und
ohne das Programm anzuhalten.

## Schritt 5: ein optionaler Filter, die Sortierung und eine Liste

Lege zwei weitere Abfragen an. Die erste, `queries\customers.search.sql`:

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

Darin gibt es drei neue Dinge:

- `-- param: since D` ist ein Parameter vom Typ Datum ohne `required` und damit optional.
- `{if :since}AND born >= :since{endif}` ist ein Stück, das nur dann ins SQL kommt, wenn der Aufruf `since`
  übergibt. Übergibt er es nicht, bleibt das `WHERE` bei `city = :city`.
- `-- sort: name, id` sagt, nach welchen Spalten der Aufrufer sortieren darf, und `{sort name}` ist der
  Platzhalter für die Sortierspalten, mit `name`, wenn der Aufruf nichts angibt. Eine Spalte, die nicht in der Liste
  steht, kommt nie ins SQL.

Die zweite, `queries\customers.in_countries.sql`:

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

Das Wort `list` sagt, dass `countries` eine Liste von Werten ist, für das `IN`.

Lege `step05-options.prg` an:

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

`DO step05-options` zeigt:

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

Die Sortierung wird als ein weiteres Paar übergeben: `"sort", "id DESC"`. Die Liste als Text mit Kommas
(`"ES,PT,DE"`); wenn du sie in einem Array hast, übergib es mit `@` davor: `"countries", @laCountries`.

## Schritt 6: dieselbe `.sql`-Datei gegen SQLite

SQLite ist eine Datenbank in einer einzigen Datei, ohne Server. Für diesen Schritt brauchst du ihren
32-Bit-ODBC-Treiber: Lade `sqliteodbc.exe` von ch-werner.de herunter und installiere ihn. Visual FoxPro ist
ein 32-Bit-Programm und sieht die 64-Bit-Treiber nicht.

Lege eine weitere Abfrage an, `queries\customers.by_initial.sql`:

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

`{substr name, 1, 1}` ist ein Makro: Jede Datenbank-Engine schreibt das Herausschneiden eines Textstücks
auf ihre eigene Art, und FoxQuery setzt bei jeder das ein, was zu ihr passt.

Lege `step06-sqlite.prg` an:

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

`DO step06-sqlite` zeigt:

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

Das Programm öffnet eine Verbindung mit `SQLSTRINGCONNECT`, wie du es auch tun würdest, und legt dieselbe
Kundentabelle in `tutorial.db` an. Danach:

- `FQ_USE_HANDLE(lnHandle)` sagt FoxQuery, dass die Abfragen über diese Verbindung laufen. FoxQuery fragt
  den Treiber, welche Engine es ist (hier SQLite), und wählt das SQL dieser Engine.
- `FQ_RUN` ist derselbe Aufruf wie in Schritt 4, mit derselben `.sql`-Datei, und liefert dieselben Zeilen.
  Das ñ von Ana Muñoz kommt richtig an: SQLite speichert den Text in UTF-8, und FoxQuery wandelt in beide
  Richtungen um.
- Die letzten drei Zeilen zeigen das SQL von `customers.by_initial` für SQLite, für Firebird und für die
  DBF-Tabellen, ohne es auszuführen: `FQ_SQL`. Das Makro erscheint in zwei Schreibweisen: SQLite und
  die DBF-Tabellen schreiben es gleich, Firebird auf seine eigene Art.
- Das zweite Argument von `FQ_SQL` ist der Name der Engine, einer dieser sieben: `sqlserver`, `mysql`,
  `mariadb`, `postgresql`, `firebird`, `sqlite` und `vfp` (die DBF-Tabellen von `FQ_USE_DBF`, aus
  Schritt 4). Ohne dieses Argument nimmt `FQ_SQL` die aktive Engine.
- Gibt `FQ_SQL` oder eine andere `FQ_*` `.NULL.` oder `.F.` zurück, sagt `? FQ_LAST_ERROR()` warum. Ein
  Engine-Name, den es nicht gibt, ergibt `engine_unknown` mit der Liste der sieben.

Erscheint „No connection: is the SQLite3 ODBC Driver installed?“, ist der Treiber nicht installiert, oder
es ist der 64-Bit-Treiber installiert.

## Schritt 7: der Katalog `.fq`

Für die Version, die du an deine Kunden auslieferst, wird der Ordner `queries` in eine einzige signierte
Datei kompiliert: den Katalog. Lege `step07-build.prg` an:

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
IF FQ_BUILD("queries\", "app.fq", "my secret key")
	? "app.fq is ready"
ELSE
	? FQ_ERRORS()
ENDIF
```

`DO step07-build` zeigt:

```
app.fq is ready
```

`FQ_BUILD` liest alle Abfragen des Ordners, prüft, ob sie in Ordnung sind, und schreibt `app.fq` mit einer
Signatur, die mit deinem Schlüssel erstellt wird (`"my secret key"`; in deinem Programm setzt du deinen
eigenen ein). Hat eine Abfrage einen Fehler, wird die `.fq`-Datei nicht geschrieben, und `FQ_ERRORS()`
nennt alle Fehler, einen pro Zeile.

Lege jetzt `step07-catalog.prg` an, das den Katalog statt des Ordners lädt:

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

`DO step07-catalog` zeigt dieselben Kunden:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

**Was passiert, wenn jemand die `.fq`-Datei verändert.** Öffne `app.fq` mit dem Editor (Rechtsklick auf die
Datei, „Öffnen mit“, „Editor“). Du siehst Text mit seltsamen Zeichen; such `ORDER BY name`, ändere einen
Buchstaben (zum Beispiel `nAme`) und speichere. Geh zurück zu Visual FoxPro und führe noch einmal
`DO step07-catalog` aus. Es erscheint:

```
FQ_LOAD: catalog_tampered: app.fq: the signature does not match; the file changed, or the key is not the one of the build
```

Die Signatur passt nicht mehr zum Inhalt, und FoxQuery lädt nichts aus der Datei. Dasselbe passiert, wenn
du den Katalog mit einem anderen Schlüssel lädst. Um das zu beheben, kompiliere neu: `DO step07-build`, und
`DO step07-catalog` zeigt wieder die Kunden.

Die Signatur mit deinem Schlüssel verhindert, dass jemand die Abfragen deines Programms ändert, aber der
SQL-Text bleibt in der Datei lesbar, wie du gerade gesehen hast. Um ihn vor jemandem
zu verbergen, der die Datei mit einem Editor öffnet, kompiliere mit Verschlüsselung:
`FQ_BUILD("queries\", "app.fq", "my secret key", .T.)`. Der Schlüssel steckt in deinem Programm; wer es
darauf anlegt, kann ihn also herausholen.

## Schritt 8: der Katalog in der `.exe`

Lege `step08-main.prg` an; es wird das Hauptprogramm der `.exe`:

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

Die ersten drei Zeilen sind für die `.exe`: `_VFP.StartMode` ist 4, wenn das Programm als `.exe` läuft, und
dann macht `SET DEFAULT` den Ordner der `.exe` zum aktuellen Ordner (`SYS(16, 0)` ist der Pfad der `.exe`). Im
Befehlsfenster tun sie nichts, weil der aktuelle Ordner schon `C:\FoxQueryTutorial` ist.

Probier es zuerst im Befehlsfenster aus: `DO step08-main` zeigt die Kunden, es erscheint ein Fenster mit
„Press a key to close“, und wenn du eine Taste drückst, schließt es sich:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

Jetzt das Projekt. Im Befehlsfenster:

```foxpro
CREATE PROJECT tutorial
```

Der Project Manager öffnet sich:

1. Wähle auf der Registerkarte `Code` den Eintrag `Programs` und klicke auf `Add...`. Füge
   `step08-main.prg` hinzu. Klicke noch einmal auf `Add...` und füge `foxquery.prg` hinzu.
2. Klicke mit der rechten Maustaste auf `step08-main` und wähle `Set Main`. Sein Name wird fett angezeigt.
3. Wähle auf der Registerkarte `Other` den Eintrag `Other Files` und klicke auf `Add...`. Wähle bei
   `Files of type` den Eintrag `All Files (*.*)` und füge `app.fq` hinzu. Erscheint die Datei links mit
   einem durchgestrichenen Kreis, ist sie ausgeschlossen: Rechtsklick, `Include`.
4. Klicke auf `Build...`, wähle `Win32 executable / COM server (exe)` und klicke auf `OK`. Speichere die Datei als
   `tutorial.exe` in `C:\FoxQueryTutorial`.

Öffne `C:\FoxQueryTutorial` im Windows-Explorer und doppelklicke auf `tutorial.exe`. Es erscheinen die
beiden Kunden aus Oslo und das Fenster „Press a key to close“.

`app.fq` steckt in der `.exe`: `FQ_LOAD("app.fq", …)` sucht die Datei zuerst dort und, wenn sie nicht darin
ist, neben der `.exe`. Die Tabelle `customers.dbf` bleibt draußen, neben der `.exe`, wie jede
Datentabelle, und VFP sucht sie im aktuellen Ordner. Dafür sind die ersten drei Zeilen da: Ohne sie findet eine
`.exe`, die aus einem anderen Ordner startet (eine Verknüpfung, ein anderes Fenster), die Tabelle nicht, und
`FQ_RUN` liefert `executor_failed` mit einer Meldung, dass `customers.dbf` nicht existiert. In deinem eigenen
Programm liegen die Tabellen dort, wo dein Programm sie sucht: im Ordner der `.exe`, in einem `SET PATH` oder in
einer geöffneten Datenbank.

## Schritt 9: die häufigsten Fehler

Lege `step09-errors.prg` an. Es löst absichtlich sechs Fehler aus:

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

`DO step09-errors` zeigt:

```
FQ_RUN: param_missing: city (customers.by_city needs it, and the call gives no city)
FQ_RUN: param_unknown: cty (customers.by_city declares city)
FQ_RUN: param_type: city is declared C and the value is N (customers.by_city)
FQ_RUN: query_not_found: there is no query called customers.by_town
FQ_RUN: param_name_invalid: the parameter city has no value: the arguments go in pairs, name and value
customers.broken.sql(2): param_type_invalid: the type of city is 'X': it is one of C N I D T L Y M
customers.broken.sql(1): header_kind_missing: the header has no '-- kind:' (read or write)
```

Einer nach dem anderen:

1. `param_missing`: Ein Pflichtparameter fehlt. Übergib ihn.
2. `param_unknown`: Der Name des Parameters ist falsch geschrieben (`cty` statt `city`). Die Meldung nennt
   die Parameter, die die Abfrage deklariert: Schreib einen davon.
3. `param_type`: Der Wert hat nicht den Typ, den der Kopf angibt (`42` ist eine Zahl, und `city` ist `C`).
   Übergib einen Wert von dem Typ, den `-- param:` nennt.
4. `query_not_found`: Es gibt keine Abfrage mit diesem Namen. Sieh nach, wie die Datei heißt und ob sie in
   dem Ordner liegt, den du geladen hast.
5. `param_name_invalid`: Die Parameter kommen paarweise, und hier fehlt der Wert von `city`.
6. Eine `.sql`-Datei mit zwei Fehlern: `FQ_ERRORS()` nennt beide, jeden mit seiner Datei und seiner Zeile
   in Klammern. Den Typ `X` gibt es nicht (es gibt `C N I D T L Y M`), und die Zeile `-- kind:` fehlt.
   Schlägt ein Ladevorgang fehl, bleibt alles, was schon geladen war, unverändert: Die Abfragen aus
   `queries` funktionieren weiter.

Die vollständige Liste der Codes, mit dem, was in jedem Fall zu tun ist, steht im Abschnitt „Fehler“ von
[README.de.md](README.de.md).

## Schritt 10: dasselbe mit Klassen

Die Funktionen `FQ_*` verwenden intern Klassen, die du auch selbst verwenden kannst. Lege
`step10-classes.prg` an:

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

`DO step10-classes` zeigt:

```
1 Ana Muñoz                      Oslo
2 Erik Berg                      Oslo
```

`QueryStore` ist der Abfragespeicher und `QueryLocal` der Executor für DBF-Tabellen. Für eine
ODBC-Verbindung ist der Executor `QueryOdbc` (`CREATEOBJECT("QueryOdbc", lnHandle)`), und wenn du schon
FoxRemote verwendest, taugt eine seiner Datenbanken unverändert als Executor. Die Parameter kommen in ein
Objekt mit einer Eigenschaft pro Parameter. Fehler liest du aus `cLastErrorCode` und `cLastError` statt aus
`FQ_LAST_ERROR()`.

Alles, was die Klassen tun, steht im Abschnitt „API“ von [README.de.md](README.de.md).
