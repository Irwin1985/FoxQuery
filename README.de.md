# FoxQuery

[English](README.md) · [Español](README.es.md) · Deutsch

FoxQuery hält das SQL einer Visual-FoxPro-9-Anwendung in benannten Abfragen: eine `.sql`-Datei pro Abfrage,
mit einem kurzen Kopf, der ihren Namen, ihre Art und ihre Parameter angibt. Dein Programm fordert eine
Abfrage über ihren Namen an (`customers.by_city`), übergibt die Werte als Parameter und baut nie SQL-Text
zusammen.

Dieselbe `.sql`-Datei läuft auf SQL Server, MySQL, MariaDB, PostgreSQL, Firebird, SQLite und auf lokalen
DBF-Tabellen. Für die Version, die du auslieferst, werden die Dateien zu einem signierten Katalog (`.fq`)
kompiliert, der in der EXE oder neben ihr mitgeliefert wird.

Du kannst es aus einer `.prg`-Datei mit einfachen Funktionen (`FQ_LOAD`, `FQ_RUN`, …) verwenden, ganz ohne
Klassen. Es funktioniert mit den Standardwerten, und wenn etwas nicht stimmt, nennt der Fehler die Datei,
die Zeile, was passiert ist und was zu tun ist.

## Installation

Mit [FoxPack](https://irwinrodriguez.dev/products/foxpack), das Bibliotheken für Visual-FoxPro-Projekte in
einer festen Version herunterlädt:

```
foxpack add foxquery
```

```foxpro
SET PROCEDURE TO foxquery.prg ADDITIVE
```

Ohne FoxPack kopierst du `foxquery.prg` neben dein Programm: Das ist die ganze Bibliothek. Sie braucht
Visual FoxPro 9 SP2 und sonst nichts. FoxQuery verbindet sich mit keinem Server: Es führt die Abfragen
über eine Verbindung aus, die du öffnest, also brauchst du ohnehin den ODBC-Treiber deiner Engine. VFP ist
ein 32-Bit-Programm und braucht den **32-Bit**-Treiber, auch unter 64-Bit-Windows. Mit diesen Treibern
ist FoxQuery getestet:

| Engine | Treiber | Getestet mit |
|---|---|---|
| SQL Server | `ODBC Driver 18 for SQL Server` oder `ODBC Driver 17 for SQL Server` | SQL Server 2025 Express |
| MySQL | `MariaDB ODBC 3.2 Driver` (der von MariaDB: siehe [Stolperfallen](#stolperfallen)) | MySQL 8.4 |
| MariaDB | `MariaDB ODBC 3.2 Driver` | MariaDB 11.8 |
| PostgreSQL | `PostgreSQL ANSI` (psqlODBC) | PostgreSQL 18 |
| Firebird | `Firebird ODBC Driver` 3.0, mit der 32-Bit-`fbclient.dll` | Firebird 5.0 |
| SQLite | `SQLite3 ODBC Driver` 0.99991 (ch-werner.de, `sqliteodbc.exe`) | SQLite 3.43 |
| Lokale DBF | keiner | Visual FoxPro 9 SP2 |

FoxNone ist optional. Es ist eine kleine Bibliothek, die sich ebenfalls mit FoxPack installieren lässt
(`foxpack add foxnone`), und `FQ_PARAMS()` und `QueryStore.Params()` geben eines seiner Objekte zurück. Ohne
FoxNone funktioniert alles andere.

## Beispiel

Füge es in eine `.prg`-Datei in einem leeren Ordner ein und führe sie aus. Es legt eine DBF-Tabelle und
eine Abfrage an und führt die Abfrage auf der DBF aus: Du brauchst keinen Server.

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

Ausgabe:

```
1 Ana Muñoz
2 Erik Berg
```

Wenn du Schritt für Schritt bei null anfangen willst, folge [TUTORIAL.de.md](TUTORIAL.de.md).

## Die `.sql`-Dateien

Eine Datei pro Abfrage, in einem Ordner (`queries\`). Der Dateiname ist der Name der Abfrage plus `.sql`.
Die Datei ist reiner Text in Windows-1252 (CP1252), wie jeder VFP-Quelltext. Zuerst kommt der Kopf, als
SQL-Kommentare, und darunter das SQL:

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

| Kopfzeile | Was sie angibt |
|---|---|
| `-- name: customers.search` | Der Name der Abfrage. Er muss der Dateiname ohne `.sql` sein. Pflicht |
| `-- description: …` | Freier Text für alle, die die Datei lesen. Optional |
| `-- kind: read` | `read` für ein `SELECT` (es läuft mit `FQ_RUN` oder `FQ_SCALAR`), `write` für `INSERT`, `UPDATE` oder `DELETE` (es läuft mit `FQ_EXECUTE`). Pflicht. FoxQuery prüft die Angabe gegen das erste Wort des SQL |
| `-- param: city C required` | Eine Zeile pro Parameter: der Name, der Typ und dann `required`, `list` und `default <value>`, in beliebiger Reihenfolge |
| `-- ident: sort letters 1-20` | Ein Bezeichner: ein Name, den das Programm mit `FQ_SET` einmal für alle Abfragen, die ihn verwenden, ins SQL schreibt. Seine Form gibt an, welcher Wert erlaubt ist (`digits`, `letters`, `alnum` oder `ident`, und eine Länge `2` oder ein Bereich `1-20`) |
| `-- sort: name, id` | Die Spalten, die der Aufrufer für `ORDER BY` wählen darf (siehe `{sort}` unten) |
| `-- engine: firebird` | Beginnt einen vollständigen SQL-Text für eine Engine. Die Zeile steht nach dem gemeinsamen SQL |

**Die Typen** sind die von VFP: `C` (Text), `N` (beliebige Zahl), `I` (ganze Zahl), `D` (Datum), `T`
(Datum mit Uhrzeit), `L` (logisch), `Y` (Währung, nimmt auch eine Zahl an) und `M` (Memo). FoxQuery prüft
den Typ jedes Werts, bevor irgendetwas die Engine erreicht (`param_type`).

**`default <value>`** wird verwendet, wenn der Aufruf den Parameter nicht angibt: eine Zahl (`10`), ein
Text in Anführungszeichen (`'Oslo'` oder `"Oslo"`), ein Datum (`{^2026-11-04}`, oder `{}` für ein leeres),
ein Datum mit Uhrzeit (`{^2026-11-04 10:30}`), `.T.`, `.F.` oder `.NULL.`. Eine Liste nimmt keinen Default
an. Ein optionaler Parameter ohne Default, den der Aufruf nicht angibt, kommt bei der Engine als `.NULL.`
an.

**Kommentare.** In einer Kopfzeile ist alles nach ` --` ein Kommentar. Eine Zeile des SQL, die mit `--`
beginnt, ist ebenfalls ein Kommentar. Ein `--` nach SQL in derselben Zeile bleibt im Text: siehe
[Stolperfallen](#stolperfallen).

**Was ins SQL kommt:**

- **`:name`** ist ein Parameter. Der Wert reist getrennt vom Text, als ODBC-Parameter (oder, bei DBF, als
  Eigenschaft, die VFP liest): Kein Wert des Aufrufers wird je in das SQL eingefügt. Ein `:` in
  Anführungszeichen und das `::` von PostgreSQL bleiben unangetastet.
- **`{if :since} … {endif}`**: Der Text dazwischen kommt nur ins SQL, wenn der Aufruf `since` angibt (als
  Paar oder als Eigenschaft des Objekts), egal mit welchem Wert. Nur eine Ebene: Ein `{if}` in einem
  anderen ist `if_unbalanced`.
- **`{ident sort}`** schreibt den Wert, den das Programm mit `FQ_SET("sort", "name")` festgelegt hat, so wie er ist
  und ohne Anführungszeichen: `ORDER BY {ident sort}` läuft als `ORDER BY name`. Das ist für einen Namen im SQL
  gedacht (zum Beispiel eine Spalte), der einmal für alle Abfragen festgelegt wird, die ihn verwenden; `{sort}`
  weiter unten ist die Reihenfolge, die jeder Aufruf wählt. FoxQuery prüft den Wert beim Festlegen (nur Buchstaben,
  Ziffern und `_`, und die Form von `-- ident:`), und ein Aufruf kann ihn nicht mitbringen (`ident_not_a_param`). Ein
  `{ident}` zwischen Anführungszeichen bleibt, wie es ist. Das Beispiel steht bei [FQ_SET](#fq_setcname-cvalue).
- **`{sort}`** ist das `ORDER BY`, das der Aufrufer aus den Spalten von `-- sort:` wählt, jede mit `ASC`
  oder `DESC`: `"sort", "name DESC"` oder `"sort", "name, id DESC"`. `{sort name}` gibt an, welche
  verwendet wird, wenn der Aufruf nichts angibt. Alles, was nicht in der Liste steht, ist `bad_option`, und
  nichts erreicht die Engine. Auf `vfp` (DBF) schreibt `{sort}` die Position jeder Spalte in der Liste des
  `SELECT` (`ORDER BY 2 DESC, 1`): Nach Namen ergibt ein Alias, der auch eine Spalte einer verknüpften Tabelle
  ist, den VFP-Fehler 1832. Deshalb muss auf `vfp` jede Spalte von `-- sort:` in dieser Liste stehen, und ein
  `SELECT *` geht nicht (`sort_not_in_select`). Die anderen Engines bekommen die Namen.
- **Eine Liste** (`-- param: countries C required list` und `IN (:countries)` im SQL) nimmt einen Text
  mit Kommas (`"ES,PT,DE"`), ein mit `@` übergebenes Array oder eine `Collection` an. FoxQuery schreibt
  `IN (:countries_1, :countries_2, :countries_3)` und sendet einen Parameter pro Element. Der Text mit Kommas gilt
  nur für Listen vom Typ `C` und `M`; eine Liste von Zahlen oder Datumswerten ist ein Array oder eine `Collection`.
  Eine leere Liste ergibt `param_type` mit „the list is empty“, wie auch immer sie kommt: ein leerer Text, eine leere
  `Collection` oder ein Array mit einem einzigen `.F.` (VFP kennt keine Arrays ohne Elemente: Das hinterlassen
  `DIMENSION`, `ADIR` oder `ALINES`). In einer Liste vom Typ `L` ist `[.F.]` der Wert falsch.
- **`{macro …}`**: die neun Makros unten, für das, was jede Engine auf ihre eigene Art schreibt.
- **Ein vollständiger Text für eine Engine**: nach dem gemeinsamen SQL eine Zeile `-- engine: firebird`
  und das SQL für diese Engine. Die Engines sind `sqlserver`, `mysql`, `mariadb`, `postgresql`,
  `firebird`, `sqlite` und `vfp` (lokale DBF-Tabellen).

**Was du nicht tun kannst.** Ein Tabellen- oder Spaltenname, der vom Aufrufer kommt: Schreib eine Abfrage
für jeden Fall. Das ist die klassische SQL-Injection, und FoxQuery bietet keinen Weg dafür.

## Makros

Neun liefert FoxQuery mit, geprüft auf den sieben Engines. Ihre Argumente werden durch Kommas getrennt.

| Makro | SQL Server | MySQL / MariaDB | PostgreSQL | Firebird | SQLite | VFP |
|---|---|---|---|---|---|---|
| `{limit n}` | `OFFSET 0 ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n` | `LIMIT n` | `ROWS n` | `LIMIT n` | `TOP n` nach dem `SELECT` |
| `{offset k}` | `OFFSET k ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n OFFSET k` | `LIMIT n OFFSET k` | `OFFSET k ROWS FETCH NEXT n ROWS ONLY` | `LIMIT n OFFSET k` | nicht möglich |
| `{concat a, b, …}` | `a + b` | `CONCAT(a, b)` | `a \|\| b` | `a \|\| b` | `a \|\| b` | `a + b` |
| `{now}` | `GETDATE()` | `NOW()` | `LOCALTIMESTAMP` | `LOCALTIMESTAMP` | `datetime('now', 'localtime')` | `DATETIME()` |
| `{nvl a, b}` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `COALESCE(a, b)` | `NVL(a, b)` |
| `{substr s, i, n}` | `SUBSTRING(s, i, n)` | `SUBSTRING(s, i, n)` | `SUBSTRING(s, i, n)` | `SUBSTRING(s FROM i FOR n)` | `SUBSTR(s, i, n)` | `SUBSTR(s, i, n)` |
| `{true}` | `1` | `1` | `TRUE` | `TRUE` | `1` | `.T.` |
| `{false}` | `0` | `0` | `FALSE` | `FALSE` | `0` | `.F.` |
| `{like_ci col, :p}` | `UPPER(col) LIKE UPPER(:p)` | dasselbe | dasselbe | dasselbe | dasselbe | dasselbe |

**`{limit}` und `{offset}`** nehmen einen als `N` oder `I` deklarierten Parameter (`{limit :rows}`) oder
eine ganze Zahl (`{limit 10}`). Sie stehen am Ende der Anweisung, `{offset}` direkt nach `{limit}`, und die
Abfrage braucht ein `ORDER BY` (SQL Server und VFP verlangen es, und damit liefert jede Engine dieselben
Zeilen). FoxQuery prüft, dass die Zahl ganz und nicht negativ ist, und schreibt sie ins SQL: Das ist der
einzige Wert des Aufrufers, der in den Text kommt, weil der MariaDB-Treiber ihn nicht binden kann. Bei VFP
wird `{limit}` zu `TOP n` nach dem `SELECT`, `{offset}` gibt es nicht (`macro_unsupported`) und `TOP 0`
auch nicht (eine 0 ist `limit_value_invalid`).

**Eigene Makros**: `FQ_ADD_MACRO(cEngine, cName, cTemplate)` oder `AddMacro` an der Klasse. `$1` bis `$9`
sind die Argumente; `$*[sep]` sind alle, verbunden durch `sep` (`, ` ohne eckige Klammern). Derselbe Aufruf
für eine Engine, die das Makro schon hat, ersetzt es für diese Engine.

```foxpro
=FQ_ADD_MACRO("sqlite", "greatest", "MAX($*[, ])")
=FQ_ADD_MACRO("vfp", "greatest", "MAX($*[, ])")
```

Ein Makro muss für eine Engine existieren, bevor dort eine Abfrage läuft, die es verwendet: Für die anderen
ist es `macro_unknown`.

## Der Katalog `.fq`

Für die Version, die du auslieferst, kompiliert `FQ_BUILD` den Ordner zu einer Datei:

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

- **`FQ_BUILD` liest den Ordner wie `FQ_LOAD`**: alles oder nichts, mit denselben Fehlern. Ist eine Datei
  fehlerhaft, entsteht keine `.fq`, und `FQ_ERRORS()` listet jeden Fehler auf.
- **Die `.fq` enthält jede Abfrage bereits aufgelöst für die sieben Engines** (die Variante oder den
  gemeinsamen Text, mit ausgeschriebenen Makros). Wo eine Engine eine Abfrage nicht ausführen kann
  (`{offset}` bei VFP), enthält die `.fq` den Fehler, und auf den anderen funktioniert die Abfrage
  trotzdem.
- **Der Schlüssel.** Mit deinem Schlüssel lädt eine `.fq`, die jemand absichtlich ändert, nicht
  (`catalog_tampered`). Ohne Schlüssel verwendet FoxQuery einen eigenen festen Schlüssel: Eine versehentlich
  geänderte `.fq` (ein Editor hat sie gespeichert) lädt nicht, aber wer FoxQuery kennt, kann eine neue
  signieren.
- **Verschlüsseln** (`FQ_BUILD(cFolder, cFq, cKey, .T.)`) verbirgt das SQL vor jemandem, der deine EXE mit
  einem Editor öffnet, und mehr nicht. Es braucht deinen Schlüssel (`catalog_key_required`). Dein Schlüssel
  reist in deinem Programm mit: Was in der EXE steckt, ist für jemanden, der sich Mühe gibt, kein Geheimnis.
- **Wo `FQ_LOAD` sie findet**: über den Namen, den du angibst, zuerst in der EXE (füge die `.fq` dem
  Projekt als eingeschlossene Datei hinzu); wenn sie dort nicht ist, neben der EXE, auch wenn das Programm
  aus einem anderen Ordner startet.
- **Ein geladener Katalog ist eingefroren**: Seine Abfragen behalten die Makros, mit denen sie kompiliert
  wurden. `FQ_ADD_MACRO` liefert `catalog_frozen`, und das Makro wird für das nächste `FQ_BUILD` vorgemerkt.
  `FQ_LOAD` eines Ordners kehrt zu den `.sql`-Dateien zurück.
- **Wie lange es dauert**: Es hängt mehr von der Größe des Katalogs ab als von der Zahl der Abfragen. Bei 500
  Abfragen, gemessen auf einem Entwicklungs-Laptop: Eine `.fq` von 1 MB (kurze Abfragen) braucht etwa 4 Sekunden zum
  Bauen und 50 Millisekunden zum Laden; eine von 2 MB 7 Sekunden und 75 Millisekunden (85 verschlüsselt); eine von
  14 MB (Abfragen von etwa 4 KB) 66 Sekunden und 230 Millisekunden (255 verschlüsselt). Auf einem langsameren
  Rechner waren es in einer Anwendung mit 500 Abfragen und einer `.fq` von 2 MB 7,9 Sekunden und 216 Millisekunden. Der
  Katalog wird einmal geladen, beim Programmstart.
- **Das Format hat eine Version.** Eine `.fq`, die ein älteres FoxQuery gebaut hat, liefert
  `catalog_version`: Bau sie neu.

## API

### Die Funktionen

Sie halten ihren Zustand in `_SCREEN`: Ein zweites `SET PROCEDURE TO foxquery.prg ADDITIVE` verliert
nichts.

**Wie sie fehlschlagen.** Wenn bei der Ausführung etwas schiefgeht (ein fehlender Parameter, eine Abfrage,
die es nicht gibt, die Engine, die einen Fehler meldet), gibt die Funktion ihren Fehlerwert zurück (`.F.`,
`.NULL.` oder `-1`), und `FQ_LAST_ERROR()` sagt, warum, mit dem Namen der Funktion vorne:
`FQ_RUN: param_missing: city (…)`. `FQ_LAST_ERROR_CODE()` liefert nur den Code. Jede Funktion, die etwas
tut, leert beide zuerst. Ein Programm, das `FQ_RUN` vor `FQ_LOAD` oder vor einer der `FQ_USE…`-Funktionen
aufruft, hat einen Bug: Das löst einen VFP-Fehler aus. Mit `FQ_STRICT(.T.)` löst jeder Fehlschlag einen
VFP-Fehler aus.

**Die Parameter kommen paarweise** nach den festen Argumenten: der Name, dann der Wert. Bis zu 12 Paare in
`FQ_RUN` und 13 in `FQ_SCALAR` und `FQ_EXECUTE`. Bei mehr übergibst du ein Objekt an der Stelle des ersten
Paars: irgendein Objekt, dessen Eigenschaften die Parameter sind (`CREATEOBJECT("Empty")` mit
`ADDPROPERTY`, oder `FQ_PARAMS()`). Eine Liste geht als Text mit Kommas oder als Array mit `@`; die
Reihenfolge für `{sort}` geht als Paar `"sort"`.

### FQ_LOAD(cFolderOrFq [, cKey])

Lädt die `.sql`-Dateien eines Ordners oder einen `.fq`-Katalog mit seinem Schlüssel. Alles oder nichts: Bei
einem Fehler wird nichts geladen, und was vorher geladen war, bleibt. Gibt `.T.` oder `.F.` zurück; jeder
Fehler steht in `FQ_ERRORS()`. Was eine Engine nicht ausführen kann (`sql_too_long` oder `sort_not_in_select` auf
`vfp`, ein `macro_unsupported`), ergibt eine Warnung in `FQ_WARNINGS()`, und das Laden geht weiter, weil die anderen
Engines die Abfrage ausführen. Die Warnung kommt, wenn die verwendete Engine gewählt wird (`FQ_USE_DBF`,
`FQ_USE_HANDLE`, `FQ_USE`; oder in diesem `FQ_LOAD`, wenn schon eine in Verwendung ist).

```foxpro
IF !FQ_LOAD("queries\")
	? FQ_ERRORS()
ENDIF
```

### FQ_RELOAD()

Liest denselben Ordner oder dieselbe `.fq` neu ein (nachdem du eine `.sql` bei laufendem Programm geändert
hast). Gibt `.T.` oder `.F.` zurück.

### FQ_BUILD(cFolder, cFq [, cKey [, lEncrypt]])

Kompiliert die `.sql`-Dateien von `cFolder` in den Katalog `cFq`, mit den Makros von `FQ_ADD_MACRO`. Was
`FQ_LOAD` geladen hat, bleibt unberührt. Gibt `.T.` oder `.F.` zurück; jeder Fehler steht in `FQ_ERRORS()`. Was
eine Engine nicht ausführen kann, ist eine Warnung in `FQ_WARNINGS()`, und die `.fq` vermerkt es: `FQ_LOAD` dieser
`.fq` warnt erneut.
Ist die `.fq` in einem Editor geöffnet (`MODIFY FILE app.fq`, um sie anzusehen), kann `FQ_BUILD` sie nicht schreiben:
`.F.` mit `catalog_not_written`, und die bisherige `.fq` bleibt, wie sie war. Existiert der Ordner von `cFq` nicht,
dasselbe `.F.`, und die Meldung nennt den Ordner.

```foxpro
=FQ_BUILD("queries\", "app.fq", "the key of my application")
```

### FQ_ADD_MACRO(cEngine, cName, cTemplate)

Fügt ein eigenes Makro für eine Engine hinzu oder ersetzt eines. Es wirkt auf den mit `FQ_LOAD` geladenen
Ordner, und `FQ_BUILD` gibt es immer an den Compiler weiter. Mit einer geladenen `.fq` liefert es `.F.` mit
`catalog_frozen`: Die geladene `.fq` ändert sich nicht, und das Makro wird für das nächste `FQ_BUILD`
vorgemerkt. Gibt `.T.` oder `.F.` zurück.

```foxpro
=FQ_ADD_MACRO("sqlite", "greatest", "MAX($*[, ])")
```

### FQ_USE_DBF()

Die Abfragen laufen auf lokalen DBF-Tabellen, mit dem SQL von VFP (die Engine `vfp`). VFP findet die
Tabellen wie immer: ein offener Alias, der aktuelle Ordner, `SET PATH`, die offene Datenbank. Gibt `.T.`
zurück. Sind Abfragen geladen, gehen die, die `vfp` nicht ausführen kann, nach `FQ_WARNINGS()`.

### FQ_USE_HANDLE(nHandle [, cEngine])

Die Abfragen laufen über eine Verbindung, die du mit `SQLCONNECT` oder `SQLSTRINGCONNECT` geöffnet hast.
FoxQuery fragt den Treiber, welche Engine es ist; `cEngine` gibt sie an, wenn der Treiber es nicht sagt
(`engine_unknown`). FoxQuery baut nie eine Verbindung auf, trennt sie nie und ändert sie nicht. Gibt `.T.`
oder `.F.` zurück. Sind Abfragen geladen, gehen die, die diese Engine nicht ausführen kann, nach `FQ_WARNINGS()`.

```foxpro
=FQ_USE_HANDLE(lnHandle)
```

### FQ_USE(oExecutor)

Die Abfragen laufen auf jedem Objekt, das SQL ausführt: einem Datenbankobjekt von FoxRemote (siehe
[FoxRemote](#foxremote)) oder einem eigenen (siehe [Ein eigener Executor](#ein-eigener-executor)). Gibt `.T.`
oder `.F.` zurück. Sind Abfragen geladen, gehen die, die diese Engine nicht ausführen kann, nach `FQ_WARNINGS()`.

### FQ_RUN(cName [, cCursor [, cParam1, vValue1, … | oParams]])

Führt eine `read`-Abfrage in einen Cursor aus (`c_fr_query`, wenn `cCursor` leer ist). Gibt `.T.` oder
`.F.` zurück.

```foxpro
IF !FQ_RUN("customers.by_city", "c_result", "city", "Oslo")
	? FQ_LAST_ERROR()
ENDIF
```

### FQ_SCALAR(cName [, cParam1, vValue1, … | oParams])

Führt eine `read`-Abfrage aus, die einen Wert liefert, und gibt ihn zurück. Gibt `.NULL.` zurück, wenn sie
fehlschlägt, und auch, wenn der Wert `.NULL.` ist oder es keine Zeilen gibt: Dann ist `FQ_LAST_ERROR()`
leer.

```foxpro
lnCount = FQ_SCALAR("customers.count_by_city", "city", "Oslo")
```

### FQ_EXECUTE(cName [, cParam1, vValue1, … | oParams])

Führt eine `write`-Abfrage aus. Gibt die Anzahl der geänderten Zeilen zurück, oder `-1`.

```foxpro
lnRows = FQ_EXECUTE("customers.deactivate_city", "city", "Oslo")
```

### FQ_SQL(cName [, cEngine [, cObject [, oParams]]])

Gibt den SQL-Text einer Abfrage für eine Engine zurück (die aktive, wenn `cEngine` leer ist), ohne sie
auszuführen, oder `.NULL.`. Die `:name` bleiben, wie sie sind; `cObject` schreibt sie als `?cObject.name`,
und `oParams` löst `{if}`, `{sort}` und die Listen so auf, wie es eine Ausführung tun würde.

`cEngine` ist eine der sieben: `sqlserver`, `mysql`, `mariadb`, `postgresql`, `firebird`, `sqlite` und
`vfp` (die DBF-Tabellen von `FQ_USE_DBF`); ein anderer Name ergibt `.NULL.` mit `engine_unknown`.

```foxpro
? FQ_SQL("customers.by_city", "postgresql")
```

### FQ_SET(cName, cValue)

Legt den Wert eines Bezeichners (`{ident}`, deklariert mit `-- ident:`) für alle Abfragen fest, die ihn verwenden,
bis du ihn erneut festlegst. `.T.`, oder `.F.` mit `ident_invalid` (nur Buchstaben, Ziffern und `_`, und die Form,
die jede geladene Abfrage deklariert). `FQ_LOAD` und `FQ_RELOAD` behalten das Festgelegte, und `FQ_SQL` zeigt den
Text mit dem eingesetzten Wert. Den Wert legt das Programm fest, nie ein Aufruf.

Die Form in `-- ident:` gibt an, welcher Wert erlaubt ist: `digits` (nur Ziffern), `letters` (nur Buchstaben),
`alnum` (Buchstaben und Ziffern) oder `ident` (Buchstaben, Ziffern und `_`), mit einer Länge (`2`) oder einem
Bereich (`1-20`). Dieses Beispiel sortiert die Kunden nach der Spalte, die das Programm festlegt. Es führt dieselbe
Abfrage auf einer DBF-Tabelle und auf SQLite aus und braucht deshalb den SQLite-Treiber:

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

Gibt ein leeres Objekt von FoxNone zurück, in das du die Parameter einträgst, eine Zeile pro Parameter
(`loP.city = "Oslo"`), oder `.NULL.` mit `foxnone_missing`, wenn FoxNone nicht geladen ist.

### FQ_ERRORS()

Jeder Fehler des letzten `FQ_LOAD`, `FQ_RELOAD` oder `FQ_BUILD`, einer pro Zeile: `file(line): code: reason`,
oder `code: reason`, wenn er keine `.sql`-Datei betrifft. `""`, wenn alles gut ging.

```
customers.broken.sql(2): param_type_invalid: the type of city is 'X': it is one of C N I D T L Y M
customers.broken.sql(1): header_kind_missing: the header has no '-- kind:' (read or write)
```

### FQ_WARNINGS()

Jede Warnung des letzten `FQ_LOAD`, `FQ_RELOAD` oder `FQ_BUILD` und des letzten `FQ_USE_DBF`, `FQ_USE_HANDLE` oder
`FQ_USE`, eine pro Zeile wie `FQ_ERRORS()`: was deklariert ist und kein Text verwendet (`param_unused`,
`ident_unused`), und was die verwendete Engine nicht ausführen kann (`sql_too_long`, `sort_not_in_select`,
`macro_unsupported`). Eine Warnung verhindert das Laden nicht: `FQ_RUN` dieser Abfrage schlägt mit demselben Code
fehl, und die anderen Engines führen sie aus. `""`, wenn es keine gibt.

```
customers.report.sql(1): sql_too_long: on vfp, the vfp text is 9105 characters as QueryLocal runs it, and VFP runs 8190 at most in one line (…)
```

### FQ_LAST_ERROR() und FQ_LAST_ERROR_CODE()

Warum die letzte Funktion fehlgeschlagen ist, mit ihrem Namen vorne; und nur ihr Code. `""`, wenn alles
gut ging.

### FQ_STRICT([lOn])

`FQ_STRICT(.T.)`: Jeder Fehlschlag löst einen VFP-Fehler aus, für Programme, die Fehler mit
`TRY … CATCH` behandeln. Ohne Argument sagt sie nur, wie es eingestellt ist. Gibt den Zustand zurück.

### FQ_STORE() und FQ_DB()

Der `QueryStore` und der Executor, die die Funktionen verwenden, für den Fall, dass du mit den Klassen
weitermachen willst. Leg sie zuerst in einer Variablen ab: VFP kann keine Eigenschaft dessen verwenden,
was eine Funktion zurückgibt (`FQ_STORE().nQueries` schlägt fehl).

### FQ_VERSION()

Gibt die Version von FoxQuery zurück (`"1.0.2"`).

### Die Klassen

Die Funktionen rufen diese Klassen auf, und du kannst sie direkt verwenden:

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

| Member | Was es tut |
|---|---|
| `LoadFolder(cFolder)` | Lädt die `.sql`-Dateien eines Ordners. `.T.` oder `.F.` |
| `Load(cFq [, cKey])` | Lädt einen `.fq`-Katalog. `.T.` oder `.F.` |
| `Reload()` | Liest denselben Ordner oder dieselbe `.fq` neu ein |
| `CheckFile(cFile)` | Liest und prüft eine `.sql` wie das Laden und rührt nichts Geladenes an. Es leert `cLastError` und `cLastErrorCode` beim Eintritt. `.T.`, oder `.F.` mit dem ersten Fehler in `cLastError` als Zeile von `FQ_ERRORS()` (`file(line): code: reason`) und allen in `aLoadErrors`; `file_not_found`; `query_duplicate`, wenn diese Abfrage aus einer anderen Datei geladen ist |
| `LoadFile(cFile)` | Es leert `cLastError` und `cLastErrorCode` beim Eintritt. `CheckFile`, und danach fügt es die Abfrage dieser Datei hinzu oder ersetzt die, die aus ihr kam, an derselben Stelle der Ladereihenfolge. Die zwischengespeicherten Texte dieser Abfrage werden verworfen, und ihre Warnungen werden neu ermittelt (die des Ladens und die für die Engine des letzten `CheckEngine`): was `Reload()` hinterließe, nur für diese Datei. `catalog_frozen` mit einer geladenen `.fq`. `.T.` oder `.F.` |
| `Run(oExecutor, cName, oParams [, cCursor])` | Führt eine `read`-Abfrage in einen Cursor aus. `.T.` oder `.F.` |
| `Scalar(oExecutor, cName, oParams)` | Führt eine `read`-Abfrage aus und gibt einen Wert zurück, oder `.NULL.` |
| `Execute(oExecutor, cName, oParams)` | Führt eine `write`-Abfrage aus. Die geänderten Zeilen, oder `-1` |
| `Sql(cName, cEngine [, cObject [, oParams]])` | Der SQL-Text für eine Engine, oder `.NULL.` |
| `Args(cName, oParams)` | Das Objekt mit den Parametern, das `Run` dem Executor übergibt, oder `.NULL.` |
| `Get(cName)` | Die `QueryDef` einer Abfrage (ihr Kopf, bereits gelesen), oder `.NULL.`. Auch über ihre Nummer, `Get(1)` bis `Get(nQueries)`, in der Ladereihenfolge; außerhalb des Bereichs `.NULL.` mit `query_not_found` |
| `Names()` | Die Namen der geladenen Abfragen in der Ladereihenfolge (der des Katalogs), jedes Mal in einer neuen `Collection`; leer, wenn nichts geladen ist. Bei einer `.fq` erfährst du so, was sie enthält |
| `CheckEngine(cEngine [, nFrom [, nCount]])` | Die geladenen Abfragen, die diese Engine nicht ausführen kann, jede eine Warnung in `aWarnings` (was die `FQ_USE…`-Funktionen tun). Wie viele, oder `-1`. Mit `nFrom` und `nCount` nur diese Abfragen der Ladereihenfolge, um es auf Leerlaufzeit zu verteilen: Die Warnungen summieren sich Abschnitt für Abschnitt und gehen mit `nFrom` 1 oder einer anderen Engine auf die des Ladens zurück. Ein wiederholter Abschnitt oder zwei, die sich überlappen, setzen keine Warnung zweimal (derselbe Code, dieselbe Datei und Zeile) |
| `CheckQuery(cName, cEngine)` | Ob diese Engine diese Abfrage ausführen kann. Es leert `cLastError` und `cLastErrorCode` beim Eintritt: `.T.`, oder `.F.` mit dem Fehler in `cLastErrorCode` und `cLastError` (dem, den `Sql` gäbe). `aWarnings` bleibt unberührt |
| `SetIdent(cName, cValue)` | Legt einen Bezeichner fest, wie `FQ_SET`. `.T.` oder `.F.` mit `ident_invalid` |
| `AddMacro(cEngine, cName, cTemplate)` | Ein eigenes Makro. `.T.` oder `.F.` |
| `Params()` | Ein leeres Objekt von FoxNone, oder `.NULL.` |
| `nQueries` | Wie viele Abfragen geladen sind |
| `cFolder`, `cCatalog` | Was geladen ist: der Ordner oder die `.fq` |
| `nLoadErrors`, `aLoadErrors[n, 4]` | Die Fehler des letzten Ladens: Code, Datei, Zeile, Meldung |
| `nWarnings`, `aWarnings[n, 4]` | Die Warnungen des letzten Ladens (`param_unused`, `ident_unused`) und des letzten `CheckEngine`, auf dieselbe Weise |
| `nErrors`, `cLastError`, `cLastErrorCode` | Wie viele Fehlschläge, der letzte und sein Code. Der letzte Fehlschlag bleibt bis zum nächsten, außer in `CheckFile`, `LoadFile` und `CheckQuery`, die `cLastError` und `cLastErrorCode` beim Eintritt leeren |
| `lStrict` | `.T.`: Jeder Fehlschlag löst einen VFP-Fehler aus |
| `cLastQuery`, `cLastSql` | Die zuletzt angeforderte Abfrage und das letzte SQL, das an einen Executor ging |

### QueryCompiler

Ein `QueryStore` mit einer Methode mehr, `Build(cFolder, cFq [, cKey [, lEncrypt]])`, die `FQ_BUILD`
aufruft. Gib ihm deine Makros mit `AddMacro` vor `Build`. `cFq` enthält den Namen der zuletzt geschriebenen
`.fq`.

### QueryOdbc

Der Executor für eine eigene Verbindung (`FQ_USE_HANDLE` legt einen an): `CREATEOBJECT("QueryOdbc", lnHandle)`
oder `.nHandle = lnHandle`. `cEngine` nennt die Engine, die der Treiber gemeldet hat (`cDbmsName`,
`cDriver`); schreib `cEngine` selbst, um sie festzulegen. Er führt das `SQLEXEC` in seiner eigenen Methode
aus und prüft vorher, dass jeder `:name` des Texts im Parameterobjekt steht (`param_missing`): Ein
`SQLEXEC` mit einem fehlenden Parameter würde ein Fenster „View Parameter“ öffnen, das das Programm anhält.

Nach `Run` ist der Cursor der Abfrage der ausgewählte Arbeitsbereich, wie bei `SELECT … INTO CURSOR` und `SQLEXEC`,
sodass `BROWSE` oder `SCAN` darauf laufen. Nach `Scalar` und `Execute` ist der Bereich, der vor dem Aufruf
ausgewählt war, wieder ausgewählt, auch wenn sie fehlschlagen (ein leerer, wenn keiner ausgewählt war).

### QueryLocal

Der Executor für lokale DBF-Tabellen (`FQ_USE_DBF` legt einen an): `CREATEOBJECT("QueryLocal")`. Während
eine Abfrage läuft, setzt er `SET ANSI ON`, `SET DELETED ON` und `SET TABLEPROMPT OFF` und stellt danach
den vorherigen Zustand wieder her: Dieselbe `.sql` liefert dieselben Zeilen wie auf einem Server, und eine
Tabelle, die nicht da ist, ergibt `query_failed` statt des Dialogs „Öffnen“, der auf einen Menschen warten
würde. `lDeletedOn = .F.` lässt `DELETED` unberührt, und `lAnsiOn = .F.` lässt `ANSI` unberührt (siehe
[Stolperfallen](#stolperfallen)). `SET EXACT`, `SET NULL` und `SET ENGINEBEHAVIOR` liegen bei dir.

Die Arbeitsbereiche bleiben wie bei [QueryOdbc](#queryodbc): Nach `Run` ist der Cursor ausgewählt, nach `Scalar` und
`Execute` der Bereich, der vorher ausgewählt war. Eine `write`-Abfrage auf einer DBF-Tabelle bewegt deren
Datensatzzeiger, so wie es dasselbe `UPDATE` täte, wenn du es selbst ausführst, und FoxQuery setzt ihn nicht zurück.

### FoxRemote

[FoxRemote](https://github.com/Irwin1985/FoxRemote) ist eine VFP-Bibliothek für entfernte Datenbanken über ODBC
(sie lässt sich ebenfalls mit FoxPack installieren: `foxpack add foxremote`). Ihre Datenbankobjekte
(`RemoteSqlServer`, `RemoteSqlite`, …) sind so, wie sie sind, Executors: `FQ_USE(loDb)` oder
`loStore.Run(loDb, …)`. FoxQuery braucht FoxRemote nicht, und FoxRemote ändert sich nicht.

### Ein eigener Executor

Jedes Objekt mit diesen Membern ist ein Executor: `cEngine` (eine der sieben Engines) und die Methoden
`Query(cSql, cCursor, oParams)`, `Execute(cSql, oParams)` und `Scalar(cSql, oParams)`. Das SQL kommt mit
den `:name` an, wie sie sind, und `oParams` hat eine Eigenschaft pro Parameter. Hat das Objekt `nErrors`
und `cLastError`, liest FoxQuery sie, wenn es fehlschlägt (`executor_failed`).

### Das SQL selbst ausführen

Mit `{if}` oder einer Liste funktioniert der SQL-Text nur mit den Parametern, die dazugehören. `Args`
liefert dieses Objekt und `Sql` den Text, der es verwendet; beide prüfen die Parameter wie `Run`. Das
dritte Argument von `Sql` ist der Name der Variablen, die das Objekt enthält, und das `SQLEXEC` muss diese
Variable sehen (eine lokale Variable desselben Programms; eine `PRIVATE`, wenn das `SQLEXEC` woanders läuft,
siehe [Mit einer anderen Verbindungsbibliothek](#mit-einer-anderen-verbindungsbibliothek)). Dieses Beispiel
braucht den SQLite-Treiber:

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

Bei SQLite konvertierst du deine Text-Parameter mit `STRCONV(x, 9)` und das Gelesene mit
`STRCONV(x, 11)`, wie FoxQuery es tut (siehe [Stolperfallen](#stolperfallen)).

### Mit einer anderen Verbindungsbibliothek

Dein Programm kann seine Verbindungen mit einer eigenen Bibliothek öffnen, auf `SQLCONNECT` oder auf ADO
gebaut, und FoxQuery verbindet weiterhin nichts. Es gibt drei Wege, und der erste verlangt nichts von der
Bibliothek:

1. **Das Handle.** Gibt dir die Bibliothek die Nummer ihres `SQLCONNECT` oder `SQLSTRINGCONNECT` (fast jede
   Bibliothek für VFP tut das), dann `FQ_USE_HANDLE(loLib.nHandle)` oder `CREATEOBJECT("QueryOdbc", loLib.nHandle)`:
   FoxQuery führt das SQL selbst aus und fragt den Treiber, welche Engine es ist. Die Bibliothek ist nicht
   beteiligt und braucht keine bestimmten Member.
2. **Das Objekt.** `FQ_USE(loLib)` braucht die vier Member aus [Ein eigener Executor](#ein-eigener-executor),
   und das SQL kommt mit den `:name` an, wie sie sind. FoxRemote hat sie; eine andere Bibliothek nicht, und
   dann schreibst du einen Adapter: eine kleine Klasse mit `cEngine`, `Query`, `Execute` und `Scalar`, die jedes
   `:name` in das umsetzt, was die Bibliothek versteht, und sie aufruft. Es ist der einzige Weg für eine
   Bibliothek, die nicht ODBC ist (ADO, OLE DB).
3. **Die Bibliothek führt das SQL aus.** `Args` und `Sql` geben dir das Objekt und den Text mit
   `?loArgs.name`, und die Bibliothek führt den Text aus. Die Variable muss dort sichtbar sein, wo das `SQLEXEC`
   stattfindet: eine `LOCAL` deines Programms ist aus einer Methode der Bibliothek nicht zu sehen (eine lokale
   Variable lebt nur in der Prozedur, die sie deklariert), und ein `SQLEXEC` mit einem Parameter, den es nicht
   sieht, öffnet „View Parameter“ und wartet auf einen Menschen. Deklariere sie `PRIVATE`.

Das Beispiel nimmt den ersten und den dritten Weg, mit einem Platzhalter für eine solche Bibliothek; es
braucht den SQLite-Treiber:

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

### Das Parameterobjekt: FoxNone

Jedes Objekt funktioniert als `oParams`. Ein `None` von FoxNone (`FQ_PARAMS()` oder `loStore.Params()` mit
`SET PROCEDURE TO foxnone.prg ADDITIVE`) nimmt eine Eigenschaft in einer Zeile an, ohne `ADDPROPERTY`:

```foxpro
loP = FQ_PARAMS()
loP.city = "Oslo"
=FQ_RUN("customers.by_city", "c_result", loP)
```

Der Executor bekommt dein Objekt nie: FoxQuery kopiert die deklarierten Parameter in ein neues Objekt. Ein
Parameter darf nicht wie ein Member von `Custom` heißen (`name`, `tag`, `width`, `parent`, …): Das ist
`param_reserved`, und die Meldung schlägt einen anderen Namen vor.

## Fehler

Jeder Fehlschlag hat einen Code auf Englisch, der sich zwischen Versionen nicht ändert.
`FQ_LAST_ERROR_CODE()` und `cLastErrorCode` liefern ihn; `FQ_LAST_ERROR()`, `FQ_ERRORS()` und `cLastError`
fügen den Grund hinzu.

**Laden der `.sql`-Dateien** (`FQ_LOAD`, `FQ_BUILD`; mit Datei und Zeile in `FQ_ERRORS()`):

| Code | Was passiert ist | Was zu tun ist |
|---|---|---|
| `folder_not_found` | Der Ordner existiert nicht | Prüf den Namen. Ein relativer Name beginnt im aktuellen Ordner (`SET DEFAULT`) |
| `file_not_found` | `CheckFile` oder `LoadFile` einer `.sql`, die es nicht gibt | Prüf den Namen |
| `header_name_missing` | Die Datei hat kein `-- name:` | Füg es hinzu, mit dem Dateinamen ohne `.sql` |
| `header_name_mismatch` | `-- name:` und der Dateiname unterscheiden sich | Gleiche sie an |
| `header_kind_missing` | Die Datei hat kein `-- kind:` | Füg `-- kind: read` oder `-- kind: write` hinzu |
| `header_kind_invalid` | `-- kind:` ist weder `read` noch `write` | Schreib einen der beiden Werte |
| `kind_mismatch` | `read` mit einem SQL, das nicht mit `SELECT` beginnt, oder `write` mit einem, das damit beginnt | Korrigier `-- kind:` oder das SQL |
| `sql_missing` | Unter dem Kopf steht kein SQL, oder ein `-- engine:`-Abschnitt ist leer | Schreib das SQL |
| `param_name_invalid` | Ein Parameter hat einen ungültigen Namen, oder ein Paar einer Funktion ist falsch (ein Name, der kein Text ist, ein wiederholter Name, ein Name ohne seinen Wert) | Ein Buchstabe oder `_`, dann Buchstaben, Ziffern oder `_`, ohne den `:`; die Argumente kommen paarweise |
| `param_type_invalid` | Der Typ eines Parameters ist keiner von `C N I D T L Y M` | Schreib einen davon |
| `param_flag_invalid` | Ein Wort nach dem Typ, das nicht `required`, `list` oder `default` ist | Entfern es oder korrigier es |
| `param_duplicate` | Ein Parameter ist zweimal deklariert | Entfern einen |
| `param_reserved` | Der Name eines Parameters ist ein Member eines VFP-Objekts (`name`, `tag`, …) | Verwende den Namen, den die Meldung vorschlägt |
| `default_type` | Der `default` passt nicht zum Typ, oder eine Liste hat einen `default` | Schreib einen Wert des Typs |
| `param_undeclared` | Das SQL verwendet einen `:name`, den der Kopf nicht deklariert | Füg seine `-- param:`-Zeile hinzu |
| `param_unused` | Eine Warnung und kein Fehler: Ein Parameter ist deklariert, und das SQL verwendet ihn nicht | Entfern ihn oder verwende ihn |
| `engine_unknown` | Eine Engine, die nicht zu den sieben gehört (`-- engine:`, ein Makro, ein Executor) | `sqlserver mysql mariadb postgresql firebird sqlite vfp` |
| `engine_duplicate` | Zwei `-- engine:`-Abschnitte für dieselbe Engine | Lass einen stehen |
| `bad_option` | `-- sort:` ohne Spalten oder mit etwas, das keine Spalte ist; oder ein Aufruf, der eine Reihenfolge verlangt, die nicht in der Liste steht | Verwende die Spalten von `-- sort:`, mit `ASC` oder `DESC` |
| `sort_without_macro` | Es gibt ein `-- sort:` und kein `{sort}` im SQL | Füg `ORDER BY {sort}` hinzu oder entfern `-- sort:` |
| `macro_sort_without_list` | Es gibt ein `{sort}` und kein `-- sort:` | Füg `-- sort:` mit den Spalten hinzu |
| `sql_too_long` | Auf `vfp` ist der Text länger als die 8.190 Zeichen, die VFP in einer Zeile ausführt: eine Warnung in `FQ_WARNINGS()` bei `FQ_BUILD` und wenn `vfp` die verwendete Engine ist, mit Datei und Zeile; der Fehler beim Ausführen (auch wenn eine Liste wächst) | Schreib einen kürzeren `-- engine: vfp`-Text, oder gib weniger Elemente an |
| `ident_undeclared` | Ein `{ident x}` im Text ohne sein `-- ident: x` (beim Laden, mit Datei und Zeile) | Füg `-- ident: x` mit seiner Form hinzu, zum Beispiel `-- ident: x letters 1-20` |
| `ident_form_invalid` | Eine `-- ident:`-Zeile ohne Form (beim Laden) | `-- ident: sort letters 1-20`: ein Name, dann `digits`, `letters`, `alnum` oder `ident`, und eine Länge `2` oder ein Bereich `1-8` |
| `ident_param_clash` | Derselbe Name in `-- ident:` und in `-- param:` (beim Laden) | Wähl eines |
| `ident_unused` | Eine Warnung, kein Fehler: ein `-- ident:`, das kein Text verwendet | Verwende es mit `{ident x}`, oder entfern die Zeile |
| `ident_missing` | Die Abfrage verwendet `{ident x}`, und niemand hat es festgelegt | `FQ_SET("x", ...)` einmal, beim Programmstart |
| `ident_invalid` | `FQ_SET` mit einem Wert, der nicht aus Buchstaben, Ziffern und `_` besteht oder nicht die deklarierte Form hat (die Meldung sagt, was diese Form annimmt: `(2 digits)`, `(1 to 20 letters)`); oder beim Ausführen ein Wert, den ein neueres Laden strenger deklariert (es nennt die Deklaration) | Leg einen Wert der Form fest |
| `ident_not_a_param` | Ein Bezeichner, der im Aufruf kommt (`FQ_RUN(..., "x", "10")`, oder eine Eigenschaft des Parameterobjekts) | Leg ihn einmal mit `FQ_SET` fest; er kommt nie in den Aufruf |
| `sort_not_in_select` | Auf `vfp` steht eine Spalte von `-- sort:` nicht in der Liste des `SELECT`, oder die Liste ist `*`: eine Warnung in `FQ_WARNINGS()` bei `FQ_BUILD` und wenn `vfp` die verwendete Engine ist, der Fehler beim Ausführen (nennt die Datei und die Zeile von `-- sort:`) | Nimm die Spalte in die Liste des `SELECT` auf, oder schreib einen `-- engine: vfp`-Text |
| `if_unbalanced` | Ein `{if}` ohne sein `{endif}`, ein `{if}` in einem anderen oder ein `{if}` ohne `:name` | Ein `{if :name} … {endif}` nach dem anderen |
| `macro_unknown` | Ein `{macro}`, das keine Engine hat | Korrigier den Namen oder füg es mit `FQ_ADD_MACRO` hinzu |
| `macro_unsupported` | Die Engine kann es nicht (`{offset}` bei VFP, `{limit 0}` bei VFP) | Schreib einen `-- engine:`-Text für diese Engine |
| `macro_reserved` | `FQ_ADD_MACRO` mit dem Namen einer Markierung (`if`, `endif`, `sort`, `limit`, `offset`) oder eines ODBC-Escapes (`d`, `t`, `ts`, `fn`, `oj`, `call`, `escape`) | Wähl einen anderen Namen |
| `limit_arg_invalid` | `{limit}` oder `{offset}` mit etwas, das weder ein `N`/`I`-Parameter noch eine ganze Zahl ist, oder zwei `{limit}` | `{limit :rows}` oder `{limit 10}`, einmal |
| `limit_without_order_by` | `{limit}` in einer Abfrage ohne `ORDER BY` | Füg das `ORDER BY` hinzu |
| `offset_without_limit` | `{offset}` ohne ein `{limit}` direkt davor | Schreib `{limit …} {offset …}` |

**Ausführen einer Abfrage** (`FQ_RUN`, `FQ_SCALAR`, `FQ_EXECUTE`, `FQ_SQL`):

| Code | Was passiert ist | Was zu tun ist |
|---|---|---|
| `not_loaded` | Eine Funktion lief vor `FQ_LOAD` (ein VFP-Fehler: Es ist ein Bug des Programms) | Ruf zuerst `FQ_LOAD` auf |
| `not_connected` | Kein `FQ_USE…` vorher (ein VFP-Fehler), oder ein Handle, das keine offene Verbindung ist | Ruf zuerst `FQ_USE_DBF`, `FQ_USE_HANDLE` oder `FQ_USE` auf, mit einer offenen Verbindung |
| `query_not_found` | Es gibt keine Abfrage mit diesem Namen | Prüf den Namen und ob `FQ_LOAD` ihre Datei geladen hat |
| `query_duplicate` | `CheckFile` oder `LoadFile` einer `.sql`, deren Abfrage schon aus einer anderen Datei (einem anderen Ordner) geladen ist | Eine Abfrage hat eine Datei: Lade diesen Ordner oder benenne sie um |
| `param_missing` | Der Aufruf bringt einen Pflichtparameter nicht mit | Übergib ihn |
| `param_unknown` | Ein Paar mit einem Namen, den die Abfrage nicht deklariert (`"cty"` statt `city`); die Meldung nennt die deklarierten | Schreib den Namen aus seiner `-- param:`-Zeile |
| `param_type` | Ein Wert, der nicht zu seinem Typ passt (ein Text für ein `N`, ein Text mit Kommas für eine Liste, die nicht `C` oder `M` ist), oder eine leere Liste | Übergib einen Wert vom Typ aus `-- param:` |
| `limit_value_invalid` | Der Wert für `{limit}` oder `{offset}` ist keine ganze Zahl, ist negativ oder ist 0 bei VFP | Übergib eine ganze Zahl, 1 oder größer |
| `wrong_kind` | `FQ_RUN` oder `FQ_SCALAR` mit einer `write`-Abfrage, oder `FQ_EXECUTE` mit einer `read`-Abfrage | Verwende die Funktion für ihre Art |
| `executor_failed` | Die Engine hat einen Fehler gemeldet: Ihre Meldung steht im Grund | Lies die Meldung der Engine |
| `query_failed` | Dasselbe, gemeldet von `QueryOdbc` oder `QueryLocal`, wenn du sie direkt aufrufst | Lies die Meldung der Engine |
| `executor_invalid` | `FQ_USE` mit einem Objekt, das kein Executor ist | Siehe [Ein eigener Executor](#ein-eigener-executor) |
| `foxnone_missing` | `FQ_PARAMS()` ohne geladenes FoxNone | `SET PROCEDURE TO foxnone.prg ADDITIVE`, oder verwende ein beliebiges anderes Objekt |
| `internal_error` | FoxQuery ist fehlgeschlagen und konnte nicht sagen, warum | Melde es, mit dem, was `FQ_LAST_ERROR()` sagt |

**Der Katalog** (`FQ_BUILD`, `FQ_LOAD` einer `.fq`, `FQ_ADD_MACRO`):

| Code | Was passiert ist | Was zu tun ist |
|---|---|---|
| `catalog_not_found` | Es gibt keine `.fq` mit diesem Namen, weder in der EXE noch daneben | Prüf den Namen und ob das Projekt die Datei einschließt |
| `catalog_tampered` | Die Signatur stimmt nicht: Die Datei wurde geändert, sie ist abgeschnitten, sie ist keine `.fq`, oder der Schlüssel ist nicht der von `FQ_BUILD` (die Signatur wird vor allem anderen geprüft) | Bau sie neu; verwende in beiden denselben Schlüssel |
| `catalog_invalid` | Eine `.fq` mit gültiger Signatur und einem Inhalt, den FoxQuery nicht lesen kann | Bau sie neu |
| `catalog_not_written` | `FQ_BUILD` konnte die `.fq` nicht schreiben: Die Datei ist in einem Editor geöffnet oder schreibgeschützt (die Meldung sagt, wie viele Bytes geschrieben wurden), oder der Ordner existiert nicht (die Meldung nennt ihn) | Schließ den Editor oder korrigiere den Pfad, und bau sie neu |
| `catalog_version` | Ein älteres FoxQuery hat sie gebaut | Bau sie mit diesem neu |
| `catalog_key_required` | Die `.fq` ist verschlüsselt und `FQ_LOAD` hat keinen Schlüssel bekommen; oder `FQ_BUILD` sollte ohne Schlüssel verschlüsseln | Übergib deinen Schlüssel |
| `catalog_frozen` | `FQ_ADD_MACRO` bei geladener `.fq`: Die geladene `.fq` ändert sich nicht, und das Makro wird für das nächste `FQ_BUILD` vorgemerkt | Nichts, wenn du neu kompilierst; gib deine Makros vor `FQ_BUILD` an |

## Stolperfallen

- **VFP kann keine Eigenschaft und keine Methode dessen verwenden, was eine Funktion zurückgibt.**
  `FQ_STORE().nQueries` kompiliert und schlägt bei der Ausführung fehl. Leg es zuerst in einer Variablen
  ab: `loStore = FQ_STORE()`.
- **Eine Liste oder ein Array geht mit `@`.** `"countries", @laCountries`; ohne `@` übergibt VFP nur das
  erste Element.
- **SQLite und Sonderzeichen.** Der SQLite-Treiber konvertiert den SQL-Text nach UTF-8, aber weder die Parameter
  noch das, was zurückkommt. FoxQuery konvertiert beides, deshalb funktioniert `FQ_RUN` mit `"Muñoz"`. Wenn
  du `SQLEXEC` selbst ausführst, mach dasselbe: `STRCONV(x, 9)` für jeden Text-Parameter und
  `STRCONV(x, 11)` für das Gelesene.
- **SQLite und Datumswerte.** Ein `D`- oder `T`-Parameter reist als Text mit Uhrzeit
  (`'2026-11-02 00:00:00.000'`): Mit `=` passt er nicht zu einer Spalte, die `'2026-11-02'` enthält, mit
  `>=` und `<` funktioniert er.
- **SQLite: Eine berechnete Spalte kommt als Memo zurück.** Eine Spalte des `SELECT`, die ein Ausdruck ist
  (`SUBSTR(name, 1, 3) AS first3`), hat keinen deklarierten Typ, und VFP bekommt ein `Memo`. Deklarier die
  Spalten der Tabelle mit einem Typ (`VARCHAR(30)`, nicht `TEXT`).
- **SQLite: `{like_ci}` funktioniert nur mit ASCII.** SQLite wandelt nur die Buchstaben ohne Akzent in
  Großbuchstaben um: `Muñoz` passt nicht zu `MUÑOZ`. `{now}` liefert Text, kein Datum mit Uhrzeit.
- **MySQL: Verwende den MariaDB-Treiber.** Der ODBC-Treiber von Oracle sendet eine Zahl als Double, das
  nicht zu einem `DECIMAL` passt, und er hat VFP nach einem Lock-Timeout schon einmal angehalten.
- **Firebird.** `{nvl}` gehört auf eine Spalte, nicht auf einen einzelnen Parameter (`?p` ohne Spalte
  ergibt „Data type unknown“); `:p IS NULL` funktioniert nicht: Verwende einen `{if :p}`-Block; und
  `.NULL.` geht nicht in ein `BOOLEAN`.
- **VFP: `{limit}` und Gleichstände.** Mit `SET ENGINEBEHAVIOR 70` liefert `TOP n` auch die Zeilen, die
  mit der letzten gleichauf liegen, sodass du mehr als n Zeilen bekommen kannst. Mit 90, dem Standard,
  bekommst du n.
- **VFP: ein `--` nach SQL in derselben Zeile.** VFP kennt `--` nicht. FoxQuery entfernt die Zeilen, die
  mit `--` beginnen, aber kein `--` nach SQL. Schreib den Kommentar in einer Abfrage, die auf DBF läuft,
  in eine eigene Zeile.
- **VFP hat kein `COALESCE`.** Verwende `{nvl}` oder einen `-- engine: vfp`-Text.
- **VFP: `ANSI ON` kostet Zeit bei großen Joins.** Während eine Abfrage läuft, setzt `QueryLocal`
  `SET ANSI ON`, damit `=` wie auf einem Server vergleicht. Bei Joins mit vielen Zeilen über DBF war das 30 bis
  40 % langsamer als `ANSI OFF` (255 s gegenüber 195 s bei Joins von 148.027 Zeilen über 6 Tabellen).
  `loDb = FQ_DB()` und danach `loDb.lAnsiOn = .F.` lassen `SET ANSI` so, wie du es hast, und dann vergleicht `=` so,
  wie dein `SET ANSI` es sagt: Mit `OFF` passt `city = 'Os'` auf `'Oslo'`, sodass die Zeilen von denen abweichen
  können, die ein Server liefert.
- **VFP: Eine Abfrage mit mehr als 8.190 Zeichen passt nicht in eine Zeile.** Auf DBF führt VFP das SQL als eine
  Zeile aus, und 8.190 Zeichen sind das Meiste, was es annimmt, mitgezählt das `INTO CURSOR`, das `QueryLocal`
  anhängt (eines mehr ist der VFP-Fehler 18).

  `FQ_BUILD` meldet es als Warnung in `FQ_WARNINGS()` mit `sql_too_long`, der Datei und der Zeile, und ebenso
  `FQ_LOAD`, sobald `vfp` die verwendete Engine ist, und `FQ_USE_DBF` mit geladenen Abfragen. `FQ_RUN` dieser Abfrage
  schlägt mit demselben Code fehl, und die anderen Engines führen dieselbe `.sql`-Datei aus. Eine kurze Abfrage mit
  einer langen Liste kann auch erst beim Ausführen über die Grenze wachsen: Dann liefert `FQ_RUN` `sql_too_long`,
  bevor das SQL VFP erreicht. Verwende einen kürzeren `-- engine: vfp`-Text oder weniger Elemente in der Liste.

  Auf DBF setzt `FQ_RUN` während der Ausführung `SYS(3055, 2040)` und stellt danach den vorherigen Wert wieder her,
  deshalb begrenzt nur `sql_too_long` eine Liste (514 Elemente, mit dem `INTO`). Führt dein Programm dasselbe SQL
  selbst mit dem voreingestellten `SYS(3055)` von VFP aus, nimmt ein `IN` 158 Elemente an (VFP-Fehler 1812).

  Diese Abfragen zu finden kostet bei einem Ordner Zeit, bei einer `.fq` nicht: Um zu sagen, was `vfp` nicht
  ausführen kann, löst `FQ_USE_DBF` (und `FQ_LOAD`, wenn `vfp` in Gebrauch ist) den Text jeder geladenen Abfrage
  auf, was jedes erste `FQ_RUN` ohnehin täte. Mit 500 Abfragen von etwa 550 Zeichen aus einem Ordner sind das etwa
  2,3 s, einmal; aus einer `.fq` etwa 5 ms. Danach kostet es nichts mehr, weil das Ergebnis gespeichert wird und ein
  zweites `FQ_USE_DBF` es findet. In der Produktion lade die `.fq`.
- **Ein `bit` von SQL Server, nach DBF übernommen, ist `L`.** Dann ergibt `WHERE active = 0` den VFP-Fehler 107
  („Operator/operand type mismatch“). Schreib `{false}` (und `{true}`): Jede Engine bekommt, was sie versteht.
- **Eine freie Tabelle nimmt keinen Feldnamen mit mehr als 10 Buchstaben an.** Wenn deine `.sql`-Dateien
  `customer_id` verwenden, gehören die DBF-Tabellen in eine Datenbank (`.dbc`).
- **Ein Fenster „View Parameter“.** Es erscheint, wenn ein `SQLEXEC` `?name` verwendet und diese Variable
  nicht existiert, und es hält das Programm an, bis jemand antwortet. FoxQuery prüft jeden `:name`, bevor es
  die Engine aufruft, deshalb erscheint es mit `FQ_RUN` nicht. Mit deinem eigenen `SQLEXEC` kann es
  erscheinen: Verwende `Args`.
- **`CLEAR DLLS`.** FoxQuery deklariert die CryptoAPI-Funktionen, die es braucht, einmal (für die `.fq`).
  Nach einem `CLEAR DLLS` ohne Liste deklariert es sie von selbst neu. Ein `CLEAR DLLS`, das nur einige
  davon entfernt, kann das nächste `FQ_LOAD` einer `.fq` scheitern lassen: Ruf dann `CLEAR DLLS` ohne Liste
  auf.
- **`FQ_ADD_MACRO` und eine `.fq`.** Der Zustand liegt in `_SCREEN`, deshalb ist die `.fq` des letzten
  Laufs noch geladen, wenn du dein Programm im selben VFP erneut startest, und `FQ_ADD_MACRO` liefert
  `catalog_frozen`. Das Makro wird trotzdem vorgemerkt, und das nächste `FQ_BUILD` nimmt es mit.
- **`SET SAFETY ON` und deine eigenen Dateien.** Ein neues VFP startet mit `SET SAFETY ON`: Ein `STRTOFILE`
  oder ein `CREATE TABLE` über eine vorhandene Datei fragt nach, bevor es schreibt. FoxQuery schreibt die
  `.fq` ohne Nachfrage; deine eigenen Programme brauchen `SET SAFETY OFF`.

## Änderungen

- **1.0.2** (2026-11-10): Interner Code, den die Bibliothek nicht benutzte, ist entfernt. Für ein Programm, das
  FoxQuery benutzt, ändert sich nichts.
- **1.0.1** (2026-11-05): `FQ_BUILD` und `Build` schlagen mit `catalog_not_written` fehl, wenn sie die `.fq` nicht
  schreiben können (die Datei ist in einem Editor geöffnet oder schreibgeschützt, oder ihr Ordner existiert nicht,
  und dann nennt die Meldung den Ordner). Neu in `QueryStore`: `CheckEngine(cEngine, nFrom, nCount)` prüft die
  Abfragen in Abschnitten und sammelt die Warnungen, ohne eine zu wiederholen; `CheckQuery` prüft eine Abfrage;
  `CheckFile` und `LoadFile` prüfen oder ersetzen eine Abfrage aus ihrer `.sql`, ohne die übrigen neu zu laden
  (`file_not_found`, `query_duplicate`); `Names()` listet die Abfragen in Ladereihenfolge, und `Get()` nimmt auch
  eine Nummer. `CheckQuery`, `CheckFile` und `LoadFile` leeren `cLastError` beim Eintritt, und der Fehler von
  `CheckFile` und `LoadFolder` ist die erste Zeile von `FQ_ERRORS()` (`file(line): code: reason`), auch in
  `FQ_LAST_ERROR()`. In `QueryLocal` und `QueryOdbc` wählen `Scalar` und `Execute` wieder den Arbeitsbereich aus,
  der vor dem Aufruf ausgewählt war; `Run` lässt weiterhin den Cursor der Abfrage ausgewählt.
- **1.0.0** (2026-11-04): die erste Version.

## Lizenz

MIT. Der Text steht in `LICENSE`.
