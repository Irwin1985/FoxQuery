* FoxQuery: consultas SQL con nombre para Visual FoxPro 9. Cada consulta vive en un .sql con cabecera,
* se resuelve por motor y lleva parámetros :nombre que nunca se pegan en el texto.
* Motores: sqlserver, mysql, mariadb, postgresql, firebird, sqlite y vfp (DBF locales, con QueryLocal).
* Licencia: MIT (ver LICENSE). Manual: README.md.
*
* La forma corta, con funciones:
*
*   SET PROCEDURE TO foxquery.prg ADDITIVE
*   FQ_LOAD("queries\")                            && la carpeta de los .sql
*   FQ_USE_HANDLE(lnHandle)                        && o FQ_USE(loFoxRemote), o FQ_USE_DBF()
*   IF !FQ_RUN("customers.by_city", "c_list", "city", "Oslo", "sort", "name")
*       ? FQ_LAST_ERROR()                          && FQ_RUN: param_missing: …
*   ENDIF
*   lnTotal = FQ_SCALAR("customers.count_by_city", "city", "Oslo")
*   lnRows = FQ_EXECUTE("customers.deactivate_city", "city", "Oslo")
*
* La clase que hay debajo, para quien quiera más (FQ_STORE() la da):
*
*   loQ = CREATEOBJECT("QueryStore")
*   IF !loQ.LoadFolder("queries\")
*       ? loQ.cLastErrorCode, loQ.cLastError
*   ENDIF
*   loP = loQ.Params()                     && un None de FoxNone (SET PROCEDURE TO foxnone.prg), o cualquier objeto
*   loP.city = "Oslo"
*   IF !loQ.Run(loDb, "customers.by_city", loP, "c_list")
*       ? loQ.cLastErrorCode, loQ.cLastError
*   ENDIF
*
* loDb es el ejecutor: FoxRemote tal cual, o cualquier objeto con cEngine y los métodos
* Query(cSql, cCursor, oParams), Execute(cSql, oParams) y Scalar(cSql, oParams). FoxQuery no depende
* de FoxRemote y trae dos:
*   loDb = CREATEOBJECT("QueryOdbc", lnHandle)  && el handle de SQLCONNECT/SQLSTRINGCONNECT del usuario
*   loDb = CREATEOBJECT("QueryLocal")           && DBF locales, el dialecto vfp
* Y quien ejecuta por su cuenta pide el texto y el Empty que lo acompaña:
*   loArgs = loQ.Args("customers.by_city", loP)
*   lcSql = loQ.Sql("customers.by_city", "sqlite", "loArgs", loP)
*   =SQLEXEC(lnHandle, lcSql, "c_list")
*
* La librería no abre diálogos ni espera a nadie: cada fallo suma uno a nErrors y deja cLastError,
* cLastErrorCode (estable, en inglés) y cLastQuery; con lStrict, además, lo lanza con ERROR. Nunca pega
* un valor del llamador en el texto SQL (la única excepción, el número de {limit}/{offset}, lo escribe la
* librería validado), y el ejecutor nunca recibe el objeto del llamador: recibe un Empty con los
* parámetros declarados, mirados con PEMSTATUS(…, 5) y leídos con GETPEM (TYPE() crearía la
* propiedad en un None).
RETURN

#DEFINE FQ_CRLF CHR(13) + CHR(10)
#DEFINE FQ_ENGINES " sqlserver mysql mariadb postgresql firebird sqlite vfp "
#DEFINE FQ_TYPES " C N I D T L Y M "
#DEFINE FQ_ODBC_ESCAPES " d t ts fn oj call escape "
* Lo más largo que corre por & sobre DBF es un texto de 8.190 caracteres, contando el INTO de QueryLocal
* (con 8.191, VFP da el error 18, en el IDE y en un .exe). Ese INTO es el de Query y Scalar.
#DEFINE FQ_VFP_LINE 8190
#DEFINE FQ_LOCAL_INTO " INTO CURSOR (lcFqCursor) NOFILTER"
* Las marcas de la librería, que no son macros. Con " nombre " $ lista, y no INLIST: con SET EXACT OFF,
* INLIST("ifnull", "if") es verdadero.
#DEFINE FQ_MARKS " if endif sort limit offset ident "
* Los identificadores de contexto: los caracteres que puede llevar el valor de uno, y las formas que se
* declaran en «-- ident:» (tipo y longitud).
#DEFINE FQ_IDENT_CHARS "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
#DEFINE FQ_IDENT_KINDS " digits letters alnum ident "
* El .fq: la marca del formato (FQ1), su versión, el orden de los siete textos de cada consulta, y la
* clave fija de la librería (sin cKey: un .fq tocado por descuido no carga; uno tocado a conciencia, sí).
#DEFINE FQ_MAGIC "FQ1"
#DEFINE FQ_FORMAT "2"
#DEFINE FQ_ENGINE_ORDER "sqlserver mysql mariadb postgresql firebird sqlite vfp"
#DEFINE FQ_FIXED_KEY "FoxQuery 1.0 - la clave fija de la libreria: integridad, no secreto"
* CryptoAPI.
#DEFINE FQC_PROV_RSA_AES 24
#DEFINE FQC_VERIFYCONTEXT -268435456
#DEFINE FQC_SHA_256 32780
#DEFINE FQC_HMAC 32777
#DEFINE FQC_RC2 26114
#DEFINE FQC_AES_256 26128
#DEFINE FQC_HASHVAL 2
#DEFINE FQC_HMAC_INFO 5
#DEFINE FQC_IPSEC_HMAC_KEY 256
#DEFINE FQC_KP_IV 1

* Los 33 nombres que no valen como parámetro: los miembros de Custom y el This_Access de FoxNone.
FUNCTION FqReservedNames
	RETURN " addobject addproperty baseclass class classlibrary comment controlcount controls destroy " + ;
		"error height helpcontextid init left name newobject objects parent parentclass picture " + ;
		"readexpression readmethod removeobject resettodefault saveasclass showwhatsthis tag " + ;
		"this_access top whatsthishelpid width writeexpression writemethod "
ENDFUNC

* ---------------------------------------------------------------- FqCrypto*: CryptoAPI por DECLARE
* SHA-256, HMAC-SHA256, AES-256 CBC con PKCS#7 y bytes al azar, por advapi32 y sin COM. Los alias llevan
* Fqc delante para no pisar los DECLARE del usuario.
PROCEDURE FqCryptoDeclare
	DECLARE INTEGER CryptAcquireContextA IN advapi32 AS FqcAcquire INTEGER @phProv, INTEGER pszContainer, INTEGER pszProvider, INTEGER dwProvType, INTEGER dwFlags
	DECLARE INTEGER CryptReleaseContext IN advapi32 AS FqcRelease INTEGER hProv, INTEGER dwFlags
	DECLARE INTEGER CryptCreateHash IN advapi32 AS FqcCreateHash INTEGER hProv, INTEGER Algid, INTEGER hKey, INTEGER dwFlags, INTEGER @phHash
	DECLARE INTEGER CryptHashData IN advapi32 AS FqcHashData INTEGER hHash, STRING pbData, INTEGER dwDataLen, INTEGER dwFlags
	DECLARE INTEGER CryptGetHashParam IN advapi32 AS FqcGetHashParam INTEGER hHash, INTEGER dwParam, STRING @pbData, INTEGER @pdwDataLen, INTEGER dwFlags
	DECLARE INTEGER CryptSetHashParam IN advapi32 AS FqcSetHashParam INTEGER hHash, INTEGER dwParam, STRING pbData, INTEGER dwFlags
	DECLARE INTEGER CryptDestroyHash IN advapi32 AS FqcDestroyHash INTEGER hHash
	DECLARE INTEGER CryptImportKey IN advapi32 AS FqcImportKey INTEGER hProv, STRING pbData, INTEGER dwDataLen, INTEGER hPubKey, INTEGER dwFlags, INTEGER @phKey
	DECLARE INTEGER CryptSetKeyParam IN advapi32 AS FqcSetKeyParam INTEGER hKey, INTEGER dwParam, STRING pbData, INTEGER dwFlags
	DECLARE INTEGER CryptEncrypt IN advapi32 AS FqcEncrypt INTEGER hKey, INTEGER hHash, INTEGER Final, INTEGER dwFlags, STRING @pbData, INTEGER @pdwDataLen, INTEGER dwBufLen
	DECLARE INTEGER CryptDecrypt IN advapi32 AS FqcDecrypt INTEGER hKey, INTEGER hHash, INTEGER Final, INTEGER dwFlags, STRING @pbData, INTEGER @pdwDataLen
	DECLARE INTEGER CryptDestroyKey IN advapi32 AS FqcDestroyKey INTEGER hKey
	DECLARE INTEGER CryptGenRandom IN advapi32 AS FqcGenRandom INTEGER hProv, INTEGER dwLen, STRING @pbBuffer
ENDPROC

* Un proveedor de CryptoAPI (0 si no lo da). Los DECLARE se hacen una vez por sesión, porque repetirlos en cada
* llamada es lento; si alguien hizo CLEAR DLLS, la llamada falla, se vuelven a declarar y se repite.
FUNCTION FqCryptoOpen
	LOCAL lnProv, loErr, llOk
	IF TYPE("_SCREEN.__lFoxQueryCrypto") = "U"
		ADDPROPERTY(_SCREEN, "__lFoxQueryCrypto", .F.)
	ENDIF
	IF !_SCREEN.__lFoxQueryCrypto
		FqCryptoDeclare()
		_SCREEN.__lFoxQueryCrypto = .T.
	ENDIF
	lnProv = 0
	llOk = .T.
	TRY
		=FqcAcquire(@lnProv, 0, 0, FQC_PROV_RSA_AES, FQC_VERIFYCONTEXT)
	CATCH TO loErr
		llOk = .F.
	ENDTRY
	IF !llOk
		FqCryptoDeclare()
		lnProv = 0
		=FqcAcquire(@lnProv, 0, 0, FQC_PROV_RSA_AES, FQC_VERIFYCONTEXT)
	ENDIF
	RETURN lnProv
ENDFUNC

* SHA-256 de unos bytes: 32 bytes, o "" si CryptoAPI falla.
FUNCTION FqCryptoSha256(tcData)
	LOCAL lnProv, lnHash, lcOut, lnLen
	lnProv = FqCryptoOpen()
	IF lnProv = 0
		RETURN ""
	ENDIF
	lnHash = 0
	=FqcCreateHash(lnProv, FQC_SHA_256, 0, 0, @lnHash)
	IF LEN(tcData) > 0
		=FqcHashData(lnHash, tcData, LEN(tcData), 0)
	ENDIF
	lcOut = REPLICATE(CHR(0), 32)
	lnLen = 32
	=FqcGetHashParam(lnHash, FQC_HASHVAL, @lcOut, @lnLen, 0)
	=FqcDestroyHash(lnHash)
	=FqcRelease(lnProv, 0)
	RETURN LEFT(lcOut, lnLen)
ENDFUNC

* PLAINTEXTKEYBLOB: BLOBHEADER (bType 8, bVersion 2, reserved 0, aiKeyAlg) + DWORD largo + la clave.
FUNCTION FqCryptoBlob(tnAlg, tcKey)
	RETURN CHR(8) + CHR(2) + CHR(0) + CHR(0) + BINTOC(tnAlg, "4RS") + BINTOC(LEN(tcKey), "4RS") + tcKey
ENDFUNC

* HMAC-SHA256 por CryptoAPI (CALG_HMAC con la clave como PLAINTEXTKEYBLOB): 32 bytes, o "".
FUNCTION FqCryptoHmac(tcKey, tcData)
	LOCAL lnProv, lcBlob, lnKey, lnHash, lcInfo, lcOut, lnLen
	lnProv = FqCryptoOpen()
	IF lnProv = 0
		RETURN ""
	ENDIF
	lcBlob = FqCryptoBlob(FQC_RC2, tcKey)
	lnKey = 0
	IF FqcImportKey(lnProv, lcBlob, LEN(lcBlob), 0, FQC_IPSEC_HMAC_KEY, @lnKey) = 0
		=FqcRelease(lnProv, 0)
		RETURN ""
	ENDIF
	lnHash = 0
	=FqcCreateHash(lnProv, FQC_HMAC, lnKey, 0, @lnHash)
	* HMAC_INFO: HashAlgid + pbInnerString + cbInnerString + pbOuterString + cbOuterString.
	lcInfo = BINTOC(FQC_SHA_256, "4RS") + REPLICATE(CHR(0), 16)
	=FqcSetHashParam(lnHash, FQC_HMAC_INFO, lcInfo, 0)
	IF LEN(tcData) > 0
		=FqcHashData(lnHash, tcData, LEN(tcData), 0)
	ENDIF
	lcOut = REPLICATE(CHR(0), 32)
	lnLen = 32
	=FqcGetHashParam(lnHash, FQC_HASHVAL, @lcOut, @lnLen, 0)
	=FqcDestroyHash(lnHash)
	=FqcDestroyKey(lnKey)
	=FqcRelease(lnProv, 0)
	RETURN LEFT(lcOut, lnLen)
ENDFUNC

* AES-256 CBC con PKCS#7: tcKey de 32 bytes, tcIv de 16. El resultado, o .NULL. si falla (descifrar
* con otra clave suele fallar en el relleno).
FUNCTION FqCryptoAes(tcKey, tcIv, tcData, tlEncrypt)
	LOCAL lnProv, lcBlob, lnKey, lcBuf, lnLen, lnR
	lnProv = FqCryptoOpen()
	IF lnProv = 0
		RETURN .NULL.
	ENDIF
	lcBlob = FqCryptoBlob(FQC_AES_256, tcKey)
	lnKey = 0
	IF FqcImportKey(lnProv, lcBlob, LEN(lcBlob), 0, 0, @lnKey) = 0
		=FqcRelease(lnProv, 0)
		RETURN .NULL.
	ENDIF
	=FqcSetKeyParam(lnKey, FQC_KP_IV, tcIv, 0)
	lnLen = LEN(tcData)
	IF tlEncrypt
		lcBuf = tcData + REPLICATE(CHR(0), 16)
		lnR = FqcEncrypt(lnKey, 0, 1, 0, @lcBuf, @lnLen, LEN(lcBuf))
	ELSE
		lcBuf = tcData
		lnR = FqcDecrypt(lnKey, 0, 1, 0, @lcBuf, @lnLen)
	ENDIF
	=FqcDestroyKey(lnKey)
	=FqcRelease(lnProv, 0)
	IF lnR = 0
		RETURN .NULL.
	ENDIF
	RETURN LEFT(lcBuf, lnLen)
ENDFUNC

* Bytes al azar (el IV de un .fq cifrado).
FUNCTION FqCryptoRandom(tnBytes)
	LOCAL lnProv, lcBuf
	lnProv = FqCryptoOpen()
	lcBuf = REPLICATE(CHR(0), tnBytes)
	IF lnProv > 0
		=FqcGenRandom(lnProv, tnBytes, @lcBuf)
		=FqcRelease(lnProv, 0)
	ENDIF
	RETURN lcBuf
ENDFUNC

* La clave del HMAC de un .fq: SHA-256 de la clave (la del usuario, o la fija) con un sufijo, para
* que no sea la misma que la del AES (SHA-256 de la clave tal cual).
FUNCTION FqCatalogMacKey(tcKey)
	RETURN FqCryptoSha256(IIF(VARTYPE(tcKey) == "C" AND !EMPTY(tcKey), tcKey, FQ_FIXED_KEY) + CHR(0) + "hmac")
ENDFUNC

* Un valor de una cabecera a texto y de vuelta (el default de un parámetro en el .fq): el tipo delante.
* El separador decimal va siempre como punto, sea cual sea SET POINT.
FUNCTION FqValueText(tvValue)
	LOCAL lcV
	IF ISNULL(tvValue)
		RETURN "X"
	ENDIF
	lcV = VARTYPE(tvValue)
	DO CASE
	CASE lcV == "C"
		RETURN "C" + tvValue
	CASE lcV == "N"
		RETURN "N" + FqNumberText(tvValue, 12)
	CASE lcV == "Y"
		RETURN "Y" + FqNumberText(MTON(tvValue), 4)
	CASE lcV == "D"
		RETURN "D" + DTOS(tvValue)
	CASE lcV == "T"
		RETURN "T" + IIF(EMPTY(tvValue), "", TTOC(tvValue, 1))
	CASE lcV == "L"
		RETURN "L" + IIF(tvValue, "T", "F")
	ENDCASE
	RETURN "C" + TRANSFORM(tvValue)
ENDFUNC

* Un número como texto, con punto y sin ceros de cola (12.5, no 12.500000000000): vuelve igual con VAL.
FUNCTION FqNumberText(tnValue, tnDecimals)
	LOCAL lcN
	lcN = CHRTRAN(LTRIM(STR(tnValue, 40, tnDecimals)), SET("POINT"), ".")
	IF "." $ lcN
		lcN = RTRIM(RTRIM(lcN, 0, "0"), 0, ".")
	ENDIF
	RETURN lcN
ENDFUNC

FUNCTION FqTextValue(tcText)
	LOCAL lcT, lcR
	lcT = LEFT(tcText, 1)
	lcR = SUBSTR(tcText, 2)
	DO CASE
	CASE lcT == "X"
		RETURN .NULL.
	CASE lcT == "N"
		RETURN VAL(CHRTRAN(lcR, ".", SET("POINT")))
	CASE lcT == "Y"
		RETURN NTOM(VAL(CHRTRAN(lcR, ".", SET("POINT"))))
	CASE lcT == "D"
		RETURN IIF(EMPTY(lcR), {}, DATE(VAL(LEFT(lcR, 4)), VAL(SUBSTR(lcR, 5, 2)), VAL(SUBSTR(lcR, 7, 2))))
	CASE lcT == "T"
		RETURN IIF(EMPTY(lcR), DTOT({}), DATETIME(VAL(LEFT(lcR, 4)), VAL(SUBSTR(lcR, 5, 2)), VAL(SUBSTR(lcR, 7, 2)), ;
			VAL(SUBSTR(lcR, 9, 2)), VAL(SUBSTR(lcR, 11, 2)), VAL(SUBSTR(lcR, 13, 2))))
	CASE lcT == "L"
		RETURN lcR == "T"
	ENDCASE
	RETURN lcR
ENDFUNC


* ======================================================================== *
* QueryParam: un parámetro declarado en la cabecera.
* ======================================================================== *
DEFINE CLASS QueryParam AS Custom
	cName = ""
	cType = ""
	lRequired = .F.
	lList = .F.
	vDefault = .NULL.
	lHasDefault = .F.
ENDDEFINE


* ======================================================================== *
* QueryDef: una consulta compilada desde su .sql.
* ======================================================================== *
DEFINE CLASS QueryDef AS Custom
	cName = ""
	cDescription = ""
	cKind = ""
	oParams = .NULL.       && Collection de QueryParam, por nombre en minúsculas
	cSql = ""              && el texto común
	oVariants = .NULL.     && Collection motor -> texto (las secciones «-- engine:»)
	DIMENSION aSortList[1]
	nSort = 0
	nSortLine = 0          && la línea del «-- sort:» (para sort_not_in_select)
	cFile = ""
	nLine = 0              && la línea donde empieza el texto común
	oIdents = .NULL.       && Collection de las «-- ident:» (Empty con cName, cKind, nMin, nMax, nLine), por nombre
	cIdentNames = ""       && sus nombres en minúsculas, entre espacios (para mirar los parámetros de una llamada sin recorrer oIdents)

	PROCEDURE Init
		This.oParams = CREATEOBJECT("Collection")
		This.oVariants = CREATEOBJECT("Collection")
		This.oIdents = CREATEOBJECT("Collection")
		This.aSortList[1] = ""
	ENDPROC

	FUNCTION HasVariant(tcEngine)
		RETURN VARTYPE(tcEngine) == "C" AND This.oVariants.GetKey(LOWER(ALLTRIM(tcEngine))) > 0
	ENDFUNC

	* Los parámetros declarados, en su orden, separados por comas.
	FUNCTION ParamNames
		LOCAL lcList, loPar
		lcList = ""
		FOR EACH loPar IN This.oParams
			lcList = lcList + IIF(EMPTY(lcList), "", ",") + loPar.cName
		ENDFOR
		RETURN lcList
	ENDFUNC
ENDDEFINE


* ======================================================================== *
* QueryStore: el almacén. Carga, valida, resuelve y ejecuta por nombre.
* ======================================================================== *
DEFINE CLASS QueryStore AS Custom
	cVersion = "1.0.2"

	* Errores
	lStrict = .F.
	nErrors = 0
	cLastError = ""
	cLastErrorCode = ""
	cLastQuery = ""
	cLastSql = ""          && el último texto que se le dio a un ejecutor (o que devolvió Sql)

	* Lo cargado
	cFolder = ""
	nQueries = 0
	nLoadErrors = 0        && los errores de la última carga: aLoadErrors[n, 4] = código, fichero, línea, mensaje
	DIMENSION aLoadErrors[1, 4]
	nWarnings = 0          && los avisos de la última carga, con la misma forma
	DIMENSION aWarnings[1, 4]
	PROTECTED nWarningsLoaded, cCheckedEngine
	nWarningsLoaded = 0    && cuántos de aWarnings son de la carga; los de CheckEngine van detrás y se reponen
	cCheckedEngine = ""    && el motor del último CheckEngine; un tramo de otro motor vuelve a los de la carga

	* La caché del texto resuelto (Bind). Al llegar al tope se vacía entera y se sigue.
	nResolvedCacheMax = 1000

	* Lo cargado de un .fq (Load). cCatalog, la ruta o el nombre que se cargó; cFolder, vacío.
	cCatalog = ""
	PROTECTED cCatalogKey, oCatalogErrors
	cCatalogKey = ""
	oCatalogErrors = .NULL.  && "nombre|motor" -> código + CHR(29) + motivo, donde un motor no puede

	PROTECTED oQueries, oCache, oMacros, oMacroNames, oGuard, oText, oResolved, nResolves, nEngineTexts
	oQueries = .NULL.
	oCache = .NULL.        && el texto por motor, ya con su variante y sus macros: "nombre|motor" -> texto, o CHR(29) código CHR(29) motivo si ese motor no puede
	oResolved = .NULL.     && el texto que da Resolve, por la forma de la llamada (ShapeKey) -> texto
	nResolves = 0          && cuántas veces corrió Resolve desde Bind
	nEngineTexts = 0       && cuántas veces EngineText calculó un texto o un fallo sin la caché
	oMacros = .NULL.       && "motor|nombre" -> plantilla
	oMacroNames = .NULL.   && los nombres de macro que algún motor tiene
	oIdentValues = .NULL.  && los identificadores fijados (SetIdent, FQ_SET), nombre -> valor; una carga los conserva
	oIdentBad = .NULL.     && los fijados que una declaración cargada rechaza, nombre -> por qué (ident_invalid)
	nIdentGen = 0          && sube con cada SetIdent y cada carga; va en la clave de oResolved de las consultas con {ident}
	oGuard = .NULL.
	oText = .NULL.

	PROCEDURE Init
		This.oQueries = CREATEOBJECT("Collection")
		This.oCache = CREATEOBJECT("Collection")
		This.oResolved = CREATEOBJECT("Collection")
		This.oCatalogErrors = CREATEOBJECT("Collection")
		This.oMacros = CREATEOBJECT("Collection")
		This.oMacroNames = CREATEOBJECT("Collection")
		This.oGuard = CREATEOBJECT("QueryKindGuard")
		This.oText = CREATEOBJECT("QueryText")
		This.oIdentValues = CREATEOBJECT("Collection")
		This.oIdentBad = CREATEOBJECT("Collection")
		This.ClearLoad()
		This.LoadStockMacros()
	ENDPROC

	* Las macros de serie. {limit} y {offset} no están aquí: son marcas de la librería. AddMacro pisa una
	* para un motor o añade las del cliente. $* son todos los argumentos, unidos por lo que va entre corchetes
	* detrás (", " si no hay): CONCAT($*[, ]) con {concat a, b, c} da CONCAT(a, b, c).
	PROTECTED PROCEDURE LoadStockMacros
		LOCAL laE[7], lnE, lcE
		=ALINES(laE, "sqlserver mysql mariadb postgresql firebird sqlite vfp", 1, " ")
		FOR lnE = 1 TO 7
			lcE = laE[lnE]
			DO CASE
			CASE lcE == "sqlserver"
				This.StockMacro(lcE, "$*[ + ]", "GETDATE()", "COALESCE($1, $2)", "SUBSTRING($1, $2, $3)", "1", "0")
			CASE INLIST(lcE, "mysql", "mariadb")
				This.StockMacro(lcE, "CONCAT($*[, ])", "NOW()", "COALESCE($1, $2)", "SUBSTRING($1, $2, $3)", "1", "0")
			CASE lcE == "postgresql"
				This.StockMacro(lcE, "$*[ || ]", "LOCALTIMESTAMP", "COALESCE($1, $2)", "SUBSTRING($1, $2, $3)", "TRUE", "FALSE")
			CASE lcE == "firebird"
				This.StockMacro(lcE, "$*[ || ]", "LOCALTIMESTAMP", "COALESCE($1, $2)", "SUBSTRING($1 FROM $2 FOR $3)", "TRUE", "FALSE")
			CASE lcE == "sqlite"
				This.StockMacro(lcE, "$*[ || ]", "datetime('now', 'localtime')", "COALESCE($1, $2)", "SUBSTR($1, $2, $3)", "1", "0")
			OTHERWISE
				This.StockMacro(lcE, "$*[ + ]", "DATETIME()", "NVL($1, $2)", "SUBSTR($1, $2, $3)", ".T.", ".F.")
			ENDCASE
		ENDFOR
	ENDPROC

	PROTECTED PROCEDURE StockMacro(tcEngine, tcConcat, tcNow, tcNvl, tcSubstr, tcTrue, tcFalse)
		=This.AddMacro(tcEngine, "concat", tcConcat)
		=This.AddMacro(tcEngine, "now", tcNow)
		=This.AddMacro(tcEngine, "nvl", tcNvl)
		=This.AddMacro(tcEngine, "substr", tcSubstr)
		=This.AddMacro(tcEngine, "true", tcTrue)
		=This.AddMacro(tcEngine, "false", tcFalse)
		=This.AddMacro(tcEngine, "like_ci", "UPPER($1) LIKE UPPER($2)")
	ENDPROC

	* ---------------------------------------------------------------- carga

	* Lee todos los .sql de la carpeta (sin subcarpetas). Todo o nada: con un fichero que no compila no
	* se carga ninguno, y lo de antes se queda como estaba.
	FUNCTION LoadFolder(tcFolder)
		LOCAL lcFolder, laF[1], lnF, lnI, loDef, loNew, lcMsg
		This.cLastQuery = ""
		This.ClearLoad()
		IF VARTYPE(tcFolder) # "C" OR EMPTY(tcFolder) OR !DIRECTORY(tcFolder)
			RETURN This.Fail("folder_not_found", "the folder of the queries does not exist: " + TRANSFORM(tcFolder))
		ENDIF
		lcFolder = ADDBS(FULLPATH(tcFolder))
		loNew = CREATEOBJECT("Collection")
		lnF = ADIR(laF, lcFolder + "*.sql", "", 1)      && 1: el nombre como lo escribió el usuario, no en mayúsculas
		FOR lnI = 1 TO lnF
			IF LOWER(JUSTEXT(laF[lnI, 1])) == "sql"
				loDef = This.ReadQuery(lcFolder + laF[lnI, 1])
				IF !ISNULL(loDef)
					loNew.Add(loDef, LOWER(loDef.cName))
				ENDIF
			ENDIF
		ENDFOR
		* El error, como la primera línea de FQ_ERRORS() y como CheckFile: «fichero(línea): código: motivo»,
		* con el código una vez.
		IF This.nLoadErrors > 0
			lcMsg = JUSTFNAME(This.aLoadErrors[1, 2]) + "(" + TRANSFORM(This.aLoadErrors[1, 3]) + "): " + ;
				This.aLoadErrors[1, 4] + IIF(This.nLoadErrors > 1, " (and " + TRANSFORM(This.nLoadErrors - 1) + " more in aLoadErrors)", "")
			RETURN This.FailText(This.aLoadErrors[1, 1], lcMsg)
		ENDIF
		This.oQueries = loNew
		This.oCache = CREATEOBJECT("Collection")
		This.ClearResolved("load")
		This.oCatalogErrors = CREATEOBJECT("Collection")
		This.cCatalog = ""
		This.cCatalogKey = ""
		This.cFolder = lcFolder
		This.nQueries = loNew.Count
		This.CheckIdents()
		This.nWarningsLoaded = This.nWarnings
		RETURN .T.
	ENDFUNC

	* Vuelve a leer lo cargado: la carpeta, o el .fq con la misma ruta y la misma clave.
	FUNCTION Reload
		IF !EMPTY(This.cCatalog)
			RETURN This.Load(This.cCatalog, This.cCatalogKey)
		ENDIF
		RETURN This.LoadFolder(This.cFolder)
	ENDFUNC

	* Lee y valida un .sql como lo haría LoadFolder (la cabecera, «-- param:», «-- ident:», el texto por
	* motor), sin tocar oQueries, oCache ni aWarnings. .T., o .F. con el primer fallo (fichero y línea, como la
	* carga) y todos en aLoadErrors; file_not_found si no está; query_duplicate si esa consulta ya está cargada
	* desde otro fichero. CheckFile, LoadFile y CheckQuery vacían cLastError y cLastErrorCode al entrar, para
	* que un .T. no deje a la vista el fallo de antes. El resto de la librería no: el último fallo se queda
	* hasta el siguiente. nErrors no se toca.
	FUNCTION CheckFile(tcFile)
		This.ClearLastError()
		RETURN !ISNULL(This.ReadFile(tcFile, .NULL.))
	ENDFUNC

	* CheckFile y, si pasa, mete la consulta de ese fichero o reemplaza la que vino de él, en su sitio del
	* orden. Vacía de la caché lo de ese nombre (textos y fallos) y renueva los avisos de ese fichero: los de la
	* carga, y los del motor del último CheckEngine, si lo hubo. Así queda lo que daría Reload, solo para ese
	* fichero, sin leer los otros. Con un .fq cargado, catalog_frozen. El «-- name:» es el nombre del fichero,
	* así que un fichero tiene siempre la misma consulta. .T. o .F.
	FUNCTION LoadFile(tcFile)
		LOCAL loWarn, loDef, lcKey, lnAt, lnE, lcEngine, llStrict, lnErrors, lcError, lcCode
		This.ClearLastError()
		IF !EMPTY(This.cCatalog)
			RETURN This.Fail("catalog_frozen", "a catalog is loaded (" + This.cCatalog + "): LoadFile is for a folder of .sql; build the catalog again")
		ENDIF
		loWarn = CREATEOBJECT("Collection")
		loDef = This.ReadFile(tcFile, loWarn)
		IF ISNULL(loDef)
			RETURN .F.
		ENDIF
		lcKey = LOWER(loDef.cName)
		lnAt = This.oQueries.GetKey(lcKey)
		DO CASE
		CASE lnAt = 0
			This.oQueries.Add(loDef, lcKey)
		CASE lnAt = This.oQueries.Count
			This.oQueries.Remove(lnAt)
			This.oQueries.Add(loDef, lcKey)
		OTHERWISE
			This.oQueries.Remove(lnAt)
			This.oQueries.Add(loDef, lcKey, lnAt)
		ENDCASE
		This.nQueries = This.oQueries.Count
		FOR lnE = 1 TO GETWORDCOUNT(FQ_ENGINES)
			lnAt = This.oCache.GetKey(lcKey + "|" + GETWORDNUM(FQ_ENGINES, lnE))
			IF lnAt > 0
				This.oCache.Remove(lnAt)
			ENDIF
		ENDFOR
		This.ClearResolved("load")
		This.RenewWarnings(loDef.cFile, loWarn)
		IF !EMPTY(This.cCheckedEngine)
			lcEngine = This.cCheckedEngine
			llStrict = This.lStrict
			lnErrors = This.nErrors
			lcError = This.cLastError
			lcCode = This.cLastErrorCode
			This.lStrict = .F.
			IF ISNULL(This.EngineText(loDef, lcEngine))
				This.WarnEngine(loDef, lcEngine, This.cLastErrorCode, SUBSTR(This.cLastError, LEN(This.cLastErrorCode) + 3))
			ENDIF
			This.lStrict = llStrict
			This.nErrors = lnErrors
			This.cLastError = lcError
			This.cLastErrorCode = lcCode
		ENDIF
		This.CheckIdents()
		RETURN .T.
	ENDFUNC

	* Lee un .sql suelto como la carga (ReadQuery), sin dejar sus avisos en aWarnings: los pasa a toWarn (una Collection
	* de Empty con cCode, cFile, nLine y cMessage), si viene. El QueryDef, o .NULL. con el fallo.
	PROTECTED FUNCTION ReadFile(tcFile, toWarn)
		LOCAL lcFile, lnW, loDef, lnAt, lnI, loW, laF[1]
		This.cLastQuery = ""
		This.nLoadErrors = 0
		DIMENSION This.aLoadErrors[1, 4]
		This.aLoadErrors = ""
		IF VARTYPE(tcFile) # "C" OR EMPTY(tcFile) OR !FILE(tcFile)
			=This.Fail("file_not_found", "the .sql file does not exist: " + TRANSFORM(tcFile))
			RETURN .NULL.
		ENDIF
		* El nombre como está en el disco (ADIR con 1, como LoadFolder): FULLPATH lo pasa a mayúsculas.
		lcFile = FULLPATH(tcFile)
		IF ADIR(laF, lcFile, "", 1) = 1
			lcFile = LEFT(lcFile, LEN(lcFile) - LEN(JUSTFNAME(lcFile))) + laF[1, 1]
		ENDIF
		lnW = This.nWarnings
		loDef = This.ReadQuery(lcFile)
		IF VARTYPE(toWarn) == "O"
			FOR lnI = lnW + 1 TO This.nWarnings
				loW = CREATEOBJECT("Empty")
				ADDPROPERTY(loW, "cCode", This.aWarnings[lnI, 1])
				ADDPROPERTY(loW, "cFile", This.aWarnings[lnI, 2])
				ADDPROPERTY(loW, "nLine", This.aWarnings[lnI, 3])
				ADDPROPERTY(loW, "cMessage", This.aWarnings[lnI, 4])
				toWarn.Add(loW)
			ENDFOR
		ENDIF
		This.nWarnings = lnW
		DIMENSION This.aWarnings[MAX(lnW, 1), 4]
		IF lnW = 0
			This.aWarnings = ""
		ENDIF
		* El error, como una línea de FQ_ERRORS(): «fichero(línea): código: motivo», con el código una vez.
		IF ISNULL(loDef)
			=This.FailText(This.aLoadErrors[1, 1], JUSTFNAME(This.aLoadErrors[1, 2]) + "(" + TRANSFORM(This.aLoadErrors[1, 3]) + "): " + ;
				This.aLoadErrors[1, 4] + IIF(This.nLoadErrors > 1, " (and " + TRANSFORM(This.nLoadErrors - 1) + " more in aLoadErrors)", ""))
			RETURN .NULL.
		ENDIF
		lnAt = This.oQueries.GetKey(LOWER(loDef.cName))
		IF lnAt > 0 AND !(LOWER(This.oQueries.Item(lnAt).cFile) == LOWER(lcFile))
			=This.Fail("query_duplicate", loDef.cName + " is already loaded from " + This.oQueries.Item(lnAt).cFile + ;
				"; a query has one file")
			RETURN .NULL.
		ENDIF
		RETURN loDef
	ENDFUNC

	* Los avisos de un fichero fuera, y los nuevos de su carga (toWarn) detrás de los de la carga; los de CheckEngine
	* van detrás de todos, como después de una carga entera.
	PROTECTED PROCEDURE RenewWarnings(tcFile, toWarn)
		LOCAL loRows, lnI, loW, lcFile, lnLoaded
		lcFile = LOWER(JUSTFNAME(tcFile))
		loRows = CREATEOBJECT("Collection")
		lnLoaded = 0
		FOR lnI = 1 TO This.nWarningsLoaded
			IF !(LOWER(JUSTFNAME(TRANSFORM(This.aWarnings[lnI, 2]))) == lcFile)
				loRows.Add(This.WarningRow(lnI))
				lnLoaded = lnLoaded + 1
			ENDIF
		ENDFOR
		FOR EACH loW IN toWarn
			loRows.Add(loW)
			lnLoaded = lnLoaded + 1
		ENDFOR
		FOR lnI = This.nWarningsLoaded + 1 TO This.nWarnings
			IF !(LOWER(JUSTFNAME(TRANSFORM(This.aWarnings[lnI, 2]))) == lcFile)
				loRows.Add(This.WarningRow(lnI))
			ENDIF
		ENDFOR
		This.nWarnings = loRows.Count
		DIMENSION This.aWarnings[MAX(This.nWarnings, 1), 4]
		This.aWarnings = ""
		FOR lnI = 1 TO loRows.Count
			loW = loRows.Item(lnI)
			This.aWarnings[lnI, 1] = loW.cCode
			This.aWarnings[lnI, 2] = loW.cFile
			This.aWarnings[lnI, 3] = loW.nLine
			This.aWarnings[lnI, 4] = loW.cMessage
		ENDFOR
		This.nWarningsLoaded = lnLoaded
	ENDPROC

	PROTECTED FUNCTION WarningRow(tnI)
		LOCAL loW
		loW = CREATEOBJECT("Empty")
		ADDPROPERTY(loW, "cCode", This.aWarnings[tnI, 1])
		ADDPROPERTY(loW, "cFile", This.aWarnings[tnI, 2])
		ADDPROPERTY(loW, "nLine", This.aWarnings[tnI, 3])
		ADDPROPERTY(loW, "cMessage", This.aWarnings[tnI, 4])
		RETURN loW
	ENDFUNC

	* Un catálogo compilado. Se busca por el nombre dado (dentro del EXE gana) y, si no está,
	* junto al EXE; si no, catalog_not_found. El orden: la firma (HMAC) antes que nada, sin descifrar;
	* después la marca del formato y su versión; después descifrar; y las consultas. Si algo falla, lo de antes se queda
	* como estaba. Cargado, el catálogo está congelado: AddMacro es catalog_frozen.
	FUNCTION Load(tcFq, tcKey)
		LOCAL lcKey, lcFile, lcText, laH[1], lnH, lcPlain, laQ[1], lnQ, lnCount, loNew, loCache, loErrs, lnI, loDef
		This.cLastQuery = ""
		This.ClearLoad()
		lcKey = IIF(VARTYPE(tcKey) == "C", tcKey, "")
		lcFile = ""
		lcText = This.CatalogText(tcFq, @lcFile)
		IF ISNULL(lcText)
			RETURN This.Fail("catalog_not_found", "there is no catalog " + TRANSFORM(tcFq) + " (by its name, inside the EXE, or next to the EXE)")
		ENDIF
		* Sin clave y cifrado: lo dice la cabecera, que no se usa para nada más antes de la firma.
		lnH = ALINES(laH, LEFT(lcText, AT(CHR(30), lcText + CHR(30)) - 1), 2, CHR(31))
		IF EMPTY(lcKey) AND lnH >= 5 AND laH[5] == "1"
			RETURN This.Fail("catalog_key_required", lcFile + " is encrypted: Load(cFq, cKey) with the key of the build")
		ENDIF
		IF !This.CatalogSigned(lcText, lcKey, lcFile)
			RETURN .F.
		ENDIF
		lcPlain = This.CatalogPlain(lcText, lcKey, lcFile, @lnCount)
		IF ISNULL(lcPlain)
			RETURN .F.
		ENDIF
		loNew = CREATEOBJECT("Collection")      && lo nuevo, aparte: si algo falla, lo de antes se queda
		loCache = CREATEOBJECT("Collection")
		loErrs = CREATEOBJECT("Collection")
		lnQ = IIF(lnCount = 0, 0, ALINES(laQ, lcPlain, 2, CHR(30)))
		IF lnQ # lnCount
			RETURN This.Fail("catalog_invalid", lcFile + " says " + TRANSFORM(lnCount) + " queries and has " + TRANSFORM(lnQ))
		ENDIF
		FOR lnI = 1 TO lnQ
			loDef = This.CatalogDef(laQ[lnI], loCache, loErrs)
			IF ISNULL(loDef)
				RETURN This.Fail("catalog_invalid", lcFile + ", query " + TRANSFORM(lnI) + ": the record is not one of a .fq")
			ENDIF
			loNew.Add(loDef, LOWER(loDef.cName))
		ENDFOR
		This.oQueries = loNew
		This.oCache = loCache
		This.oCatalogErrors = loErrs
		This.ClearResolved("load")
		This.cFolder = ""
		This.cCatalog = lcFile
		This.cCatalogKey = lcKey
		This.nQueries = loNew.Count
		This.CheckIdents()
		* Lo que un motor no puede, guardado en el .fq por Build, es un aviso (los otros seis lo ejecutan). Va detrás
		* de los de la carga, como los de CheckEngine, que lo repone con los del motor que se elija. Si contaran como
		* de la carga, FQ_USE_DBF los daría dos veces y FQ_USE_HANDLE de SQLite dejaría los de vfp.
		This.nWarningsLoaded = This.nWarnings
		FOR lnI = 1 TO loErrs.Count
			lcKey = loErrs.GetKey(lnI)
			lcText = loErrs.Item(lnI)
			loDef = loNew.Item(loNew.GetKey(LEFT(lcKey, AT("|", lcKey) - 1)))
			This.WarnEngine(loDef, SUBSTR(lcKey, AT("|", lcKey) + 1), LEFT(lcText, AT(CHR(29), lcText + CHR(29)) - 1), ;
				SUBSTR(lcText, AT(CHR(29), lcText + CHR(29)) + 1))
		ENDFOR
		RETURN .T.
	ENDFUNC

	* Los bytes del .fq: por el nombre dado (FILE() y FILETOSTR(): dentro del EXE gana) y, si no está,
	* junto al EXE (JUSTPATH(SYS(16, 0))). .NULL. si no está; en rcFile, lo que se leyó.
	PROTECTED FUNCTION CatalogText(tcFq, rcFile)
		LOCAL lcText, lcNext, loErr
		IF VARTYPE(tcFq) # "C" OR EMPTY(tcFq)
			RETURN .NULL.
		ENDIF
		lcText = .NULL.
		IF FILE(tcFq)
			TRY
				lcText = FILETOSTR(tcFq)
				rcFile = tcFq
			CATCH TO loErr
				lcText = .NULL.
			ENDTRY
		ENDIF
		IF ISNULL(lcText)
			lcNext = ADDBS(JUSTPATH(SYS(16, 0))) + JUSTFNAME(tcFq)
			IF FILE(lcNext)
				TRY
					lcText = FILETOSTR(lcNext)
					rcFile = lcNext
				CATCH TO loErr
					lcText = .NULL.
				ENDTRY
			ENDIF
		ENDIF
		RETURN lcText
	ENDFUNC

	* La firma: el último registro es el HMAC-SHA256 (hexadecimal) de todos los bytes de delante.
	PROTECTED FUNCTION CatalogSigned(tcText, tcKey, tcFile)
		LOCAL lnSep, lcContent, lcMac
		lnSep = RAT(CHR(30), tcText)
		lcContent = IIF(lnSep = 0, tcText, LEFT(tcText, lnSep - 1))
		lcMac = STRCONV(FqCryptoHmac(FqCatalogMacKey(tcKey), lcContent), 15)
		IF lnSep = 0 OR EMPTY(lcMac) OR !(UPPER(SUBSTR(tcText, lnSep + 1)) == lcMac)
			RETURN This.Fail("catalog_tampered", tcFile + ": the signature does not match; the file changed, or the key is not the one of the build")
		ENDIF
		RETURN .T.
	ENDFUNC

	* Lo de dentro, ya firmado: la marca del formato y su versión, y el cuerpo (descifrado si va cifrado). Devuelve los
	* registros de las consultas unidos, y en rnCount cuántas dice la cabecera; o .NULL. con el error.
	PROTECTED FUNCTION CatalogPlain(tcText, tcKey, tcFile, rnCount)
		LOCAL lcContent, lcHead, lnAt, laH[1], lnH, lcBody, lcPlain
		lcContent = LEFT(tcText, RAT(CHR(30), tcText) - 1)
		* La cabecera hasta el primer CHR(30); el cuerpo, por su longitud (formato 2: el cifrado va en binario).
		lnAt = AT(CHR(30), lcContent + CHR(30))
		lcHead = LEFT(lcContent, lnAt - 1)
		lnH = ALINES(laH, lcHead, 2, CHR(31))
		IF lnH < 7 OR !(laH[1] == FQ_MAGIC)
			=This.Fail("catalog_invalid", tcFile + " is not a .fq of FoxQuery")
			RETURN .NULL.
		ENDIF
		IF !(laH[2] == FQ_FORMAT)
			=This.Fail("catalog_version", tcFile + " has the format " + laH[2] + " and this FoxQuery reads " + FQ_FORMAT + " (" + laH[4] + " wrote it)")
			RETURN .NULL.
		ENDIF
		rnCount = VAL(laH[6])
		lcBody = SUBSTR(lcContent, lnAt + 1)
		IF lnH < 8 OR LEN(lcBody) # VAL(laH[8])
			=This.Fail("catalog_invalid", tcFile + ": the body is not as long as the header says")
			RETURN .NULL.
		ENDIF
		IF laH[5] == "1"
			lcPlain = FqCryptoAes(FqCryptoSha256(tcKey), STRCONV(laH[7], 16), lcBody, .F.)
			IF ISNULL(lcPlain)
				=This.Fail("catalog_invalid", tcFile + ": it does not decrypt")
				RETURN .NULL.
			ENDIF
			RETURN lcPlain
		ENDIF
		RETURN lcBody
	ENDFUNC

	* Una consulta de un .fq: su QueryDef, y sus siete textos a la caché (o el código y el motivo del motor
	* que no puede). .NULL. si el registro no es de un .fq.
	PROTECTED FUNCTION CatalogDef(tcRecord, toCache, toErrs)
		LOCAL laF[1], lnF, loDef, laP[1], lnP, lnI, laPf[1], loPar, laS[1], lnS, laE[1], lnE, lcCell, lcKey, lnBar, loI
		lnF = ALINES(laF, tcRecord, 2, CHR(31))
		IF lnF # 14
			RETURN .NULL.
		ENDIF
		loDef = CREATEOBJECT("QueryDef")
		loDef.cName = laF[1]
		loDef.cKind = laF[2]
		loDef.cDescription = laF[3]
		loDef.cFile = laF[4]
		loDef.nLine = VAL(laF[5])
		IF !EMPTY(laF[6])
			lnP = ALINES(laP, laF[6], 2, CHR(29))
			FOR lnI = 1 TO lnP
				IF ALINES(laPf, laP[lnI], 2, CHR(28)) # 4
					RETURN .NULL.
				ENDIF
				IF LEFT(laPf[2], 1) == "@"
					loI = CREATEOBJECT("Empty")
					ADDPROPERTY(loI, "cName", laPf[1])
					ADDPROPERTY(loI, "cKind", SUBSTR(laPf[2], 2))
					ADDPROPERTY(loI, "nMin", VAL(GETWORDNUM(laPf[3], 1, "-")))
					ADDPROPERTY(loI, "nMax", VAL(GETWORDNUM(laPf[3], 2, "-")))
					ADDPROPERTY(loI, "nLine", VAL(SUBSTR(laPf[4], 2)))
					loDef.oIdents.Add(loI, LOWER(loI.cName))
					loDef.cIdentNames = IIF(EMPTY(loDef.cIdentNames), " ", loDef.cIdentNames) + LOWER(loI.cName) + " "
					LOOP
				ENDIF
				loPar = CREATEOBJECT("QueryParam")
				loPar.cName = laPf[1]
				loPar.cType = laPf[2]
				loPar.lRequired = "R" $ laPf[3]
				loPar.lList = "L" $ laPf[3]
				loPar.lHasDefault = LEFT(laPf[4], 1) == "D"
				loPar.vDefault = IIF(loPar.lHasDefault, FqTextValue(SUBSTR(laPf[4], 2)), .NULL.)
				loDef.oParams.Add(loPar, LOWER(loPar.cName))
			ENDFOR
		ENDIF
		IF !EMPTY(laF[7])
			lnS = ALINES(laS, laF[7], 2, CHR(29))
			DIMENSION loDef.aSortList[lnS]
			FOR lnI = 1 TO lnS
				loDef.aSortList[lnI] = laS[lnI]
			ENDFOR
			loDef.nSort = lnS
		ENDIF
		lnE = ALINES(laE, FQ_ENGINE_ORDER, 1, " ")
		FOR lnI = 1 TO lnE
			lcCell = laF[7 + lnI]
			lcKey = LOWER(loDef.cName) + "|" + laE[lnI]
			DO CASE
			CASE LEFT(lcCell, 1) == "T"
				toCache.Add(SUBSTR(lcCell, 2), lcKey)
			CASE LEFT(lcCell, 1) == "E"
				toErrs.Add(SUBSTR(lcCell, 2), lcKey)
			OTHERWISE
				RETURN .NULL.
			ENDCASE
		ENDFOR
		RETURN loDef
	ENDFUNC

	* Fija un identificador de contexto para todas las consultas que lo usan. Se valida aquí, antes de
	* guardarlo: solo letras, dígitos y _ (con LEN(CHRTRAN()) = 0, nunca EMPTY(), que con blancos es .T.), y la
	* forma de cada consulta cargada que lo declara. No toca la caché: el valor va en el hueco en cada llamada. .T. o .F.
	FUNCTION SetIdent(tcName, tcValue)
		LOCAL lcName, loDef, loI, lcProblem
		IF VARTYPE(tcName) # "C" OR !This.oText.IsName(ALLTRIM(tcName), .F.)
			RETURN This.Fail("ident_invalid", TRANSFORM(tcName) + " is not the name of an identifier (letters, digits and _)")
		ENDIF
		lcName = LOWER(ALLTRIM(tcName))
		IF VARTYPE(tcValue) # "C"
			RETURN This.Fail("ident_invalid", lcName + ": the value is " + VARTYPE(tcValue) + "; an identifier is text")
		ENDIF
		lcProblem = ""
		FOR EACH loDef IN This.oQueries
			IF loDef.oIdents.GetKey(lcName) > 0
				loI = loDef.oIdents.Item(loDef.oIdents.GetKey(lcName))
				IF !This.IdentOk(tcValue, loI)
					lcProblem = lcName + ": '" + tcValue + "' is not " + This.IdentForm(loI) + " " + This.IdentTakes(loI)
					EXIT
				ENDIF
			ENDIF
		ENDFOR
		IF EMPTY(lcProblem) AND !FqIdentChars(tcValue, FQ_IDENT_CHARS)
			lcProblem = lcName + ": '" + tcValue + "' is not an identifier (only letters, digits and _)"
		ENDIF
		IF !EMPTY(lcProblem)
			RETURN This.Fail("ident_invalid", lcProblem)
		ENDIF
		IF This.oIdentValues.GetKey(lcName) > 0
			This.oIdentValues.Remove(lcName)
		ENDIF
		This.oIdentValues.Add(tcValue, lcName)
		IF This.oIdentBad.GetKey(lcName) > 0
			This.oIdentBad.Remove(lcName)
		ENDIF
		This.nIdentGen = This.nIdentGen + 1
		RETURN .T.
	ENDFUNC

	* Después de una carga, los valores ya fijados contra las declaraciones nuevas; los que una rechaza dan
	* ident_invalid al ejecutar, con la declaración que los rechaza.
	PROTECTED PROCEDURE CheckIdents
		LOCAL lnI, lcName, lcValue, loDef, loI
		This.oIdentBad = CREATEOBJECT("Collection")
		This.nIdentGen = This.nIdentGen + 1
		FOR lnI = 1 TO This.oIdentValues.Count
			lcName = This.oIdentValues.GetKey(lnI)
			lcValue = This.oIdentValues.Item(lnI)
			FOR EACH loDef IN This.oQueries
				IF loDef.oIdents.GetKey(lcName) > 0
					loI = loDef.oIdents.Item(loDef.oIdents.GetKey(lcName))
					IF !This.IdentOk(lcValue, loI)
						This.oIdentBad.Add(lcName + ": '" + lcValue + "' is not " + This.IdentForm(loI) + ", as " + ;
							IIF(EMPTY(loDef.cFile), loDef.cName, JUSTFNAME(loDef.cFile) + "(" + TRANSFORM(loI.nLine) + ")") + ;
							" declares it (FQ_SET it again)", lcName)
						EXIT
					ENDIF
				ENDIF
			ENDFOR
		ENDFOR
	ENDPROC

	* Los huecos CHR(2) nombre CHR(2) con los valores fijados; .NULL. con ident_missing o ident_invalid.
	PROTECTED FUNCTION FillIdents(tcText, toDef)
		LOCAL lcOut, lnA, lnB, lcName, lnAt
		lcOut = tcText
		DO WHILE CHR(2) $ lcOut
			lnA = AT(CHR(2), lcOut)
			lnB = AT(CHR(2), lcOut, 2)
			lcName = SUBSTR(lcOut, lnA + 1, lnB - lnA - 1)
			IF This.oIdentBad.GetKey(lcName) > 0
				=This.Fail("ident_invalid", This.oIdentBad.Item(This.oIdentBad.GetKey(lcName)) + " (" + toDef.cName + ")")
				RETURN .NULL.
			ENDIF
			lnAt = This.oIdentValues.GetKey(lcName)
			IF lnAt = 0
				=This.Fail("ident_missing", toDef.cName + " uses {ident " + lcName + "} and it is not set: FQ_SET(" + ;
					'"' + lcName + '"' + ", ...) once, when the program starts")
				RETURN .NULL.
			ENDIF
			lcOut = STRTRAN(lcOut, CHR(2) + lcName + CHR(2), This.oIdentValues.Item(lnAt))
		ENDDO
		RETURN lcOut
	ENDFUNC

	* «digits 2», «alnum 3-10».
	FUNCTION IdentForm(toI)
		RETURN toI.cKind + " " + TRANSFORM(toI.nMin) + IIF(toI.nMax = toI.nMin, "", "-" + TRANSFORM(toI.nMax))
	ENDFUNC

	* Lo que admite una forma, el paréntesis de ident_invalid: «(2 digits)», «(2 to 4 digits)», «(9 to 12
	* letters or digits)», «(1 to 4 letters, digits or _)».
	FUNCTION IdentTakes(toI)
		LOCAL llOne, lcWhat
		llOne = toI.nMax = 1
		DO CASE
		CASE toI.cKind == "digits"
			lcWhat = IIF(llOne, "digit", "digits")
		CASE toI.cKind == "letters"
			lcWhat = IIF(llOne, "letter", "letters")
		CASE toI.cKind == "alnum"
			lcWhat = IIF(llOne, "letter or digit", "letters or digits")
		OTHERWISE
			lcWhat = IIF(llOne, "letter, digit or _", "letters, digits or _")
		ENDCASE
		RETURN "(" + TRANSFORM(toI.nMin) + IIF(toI.nMax = toI.nMin, "", " to " + TRANSFORM(toI.nMax)) + " " + lcWhat + ")"
	ENDFUNC

	* ¿El valor es de la forma de la declaración?
	FUNCTION IdentOk(tcValue, toI)
		LOCAL lcSet
		DO CASE
		CASE toI.cKind == "digits"
			lcSet = "0123456789"
		CASE toI.cKind == "letters"
			lcSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
		CASE toI.cKind == "alnum"
			lcSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
		OTHERWISE
			lcSet = FQ_IDENT_CHARS
		ENDCASE
		RETURN FqIdentChars(tcValue, lcSet) AND BETWEEN(LEN(tcValue), toI.nMin, toI.nMax)
	ENDFUNC

	* El QueryDef de una consulta, o .NULL.
	FUNCTION Get(tvName)
		LOCAL lnAt
		This.cLastQuery = TRANSFORM(tvName)
		lnAt = 0
		DO CASE
		CASE VARTYPE(tvName) == "C"
			lnAt = This.oQueries.GetKey(LOWER(ALLTRIM(tvName)))
		CASE INLIST(VARTYPE(tvName), "N", "I", "Y")
			* También por su número, 1 a nQueries, en el orden de carga (el del catálogo).
			IF tvName = INT(tvName) AND BETWEEN(tvName, 1, This.oQueries.Count)
				lnAt = tvName
			ENDIF
		ENDCASE
		IF lnAt = 0
			=This.Fail("query_not_found", IIF(VARTYPE(tvName) == "C", "there is no query called " + tvName, ;
				"there is no query number " + TRANSFORM(tvName) + " (there are " + TRANSFORM(This.oQueries.Count) + ")"))
			RETURN .NULL.
		ENDIF
		RETURN This.oQueries.Item(lnAt)
	ENDFUNC

	* Los nombres de lo cargado, en el orden de carga (el del catálogo), en una Collection nueva cada vez;
	* vacía si no hay nada cargado. Con un .fq es la única forma de saber qué lleva.
	FUNCTION Names
		LOCAL loNames, loDef
		loNames = CREATEOBJECT("Collection")
		FOR EACH loDef IN This.oQueries
			loNames.Add(loDef.cName)
		ENDFOR
		RETURN loNames
	ENDFUNC

	* Un objeto de parámetros: un None de FoxNone, que crea cada propiedad al asignarla.
	FUNCTION Params
		LOCAL loP, loErr, llOk
		llOk = .T.
		TRY
			loP = CREATEOBJECT("None")
		CATCH TO loErr
			llOk = .F.
		ENDTRY
		IF !llOk
			=This.Fail("foxnone_missing", "FoxNone is not loaded: SET PROCEDURE TO foxnone.prg ADDITIVE (foxpack add foxnone), " + ;
				"or pass any other object, such as CREATEOBJECT('Empty') with ADDPROPERTY")
			RETURN .NULL.
		ENDIF
		RETURN loP
	ENDFUNC

	* Una macro: {nombre arg1, arg2} en el texto de tcEngine se cambia por tcTemplate, con $1, $2… por
	* los argumentos. Las de serie las pone LoadStockMacros.
	FUNCTION AddMacro(tcEngine, tcName, tcTemplate)
		LOCAL lcEngine, lcName, lcKey
		IF LEN(This.cCatalog) > 0
			RETURN This.Fail("catalog_frozen", "a catalog is loaded (" + This.cCatalog + "): the macros of the client go to the compiler, before Build")
		ENDIF
		lcEngine = LOWER(ALLTRIM(TRANSFORM(tcEngine)))
		lcName = LOWER(ALLTRIM(TRANSFORM(tcName)))
		IF !(" " + lcEngine + " " $ FQ_ENGINES)
			RETURN This.Fail("engine_unknown", "unknown engine " + TRANSFORM(tcEngine) + "; the engines are" + RTRIM(FQ_ENGINES))
		ENDIF
		IF !This.oText.IsName(lcName, .F.) OR " " + lcName + " " $ FQ_MARKS OR " " + lcName + " " $ FQ_ODBC_ESCAPES
			RETURN This.Fail("macro_reserved", "a macro cannot be called " + TRANSFORM(tcName) + ;
				" (a name, and not if, endif, sort, limit, offset or an ODBC escape:" + FQ_ODBC_ESCAPES + ")")
		ENDIF
		IF VARTYPE(tcTemplate) # "C"
			RETURN This.Fail("macro_reserved", "the template of a macro is text")
		ENDIF
		lcKey = lcEngine + "|" + lcName
		IF This.oMacros.GetKey(lcKey) > 0
			This.oMacros.Remove(lcKey)
		ENDIF
		This.oMacros.Add(tcTemplate, lcKey)
		IF This.oMacroNames.GetKey(lcName) = 0
			This.oMacroNames.Add(lcName, lcName)
		ENDIF
		This.oCache = CREATEOBJECT("Collection")
		This.ClearResolved("macro")
		RETURN .T.
	ENDFUNC

	* ---------------------------------------------------------------- texto

	* El texto de una consulta para un motor, sin ejecutarlo. tcObject: vacío deja los :nombre; "?" los
	* da como ?nombre; otro, como ?<tcObject>.nombre. Sin objeto de parámetros, los bloques {if} se
	* quitan, {sort} toma su defecto y una lista se queda como :nombre. Con toParams, el texto se
	* resuelve con ellos como en Run (los {if} por presencia, el sort del llamador, cada lista a :p_1,
	* :p_2…) validando igual (param_missing, param_type, bad_option: .NULL. con el error puesto); el
	* Empty que va con ese texto lo da Args().
	FUNCTION Sql(tcName, tcEngine, tcObject, toParams)
		LOCAL loDef, lcEngine, lcText, loArgs
		This.cLastSql = ""
		lcEngine = LOWER(ALLTRIM(TRANSFORM(tcEngine)))
		IF !(" " + lcEngine + " " $ FQ_ENGINES)
			=This.Fail("engine_unknown", "unknown engine " + TRANSFORM(tcEngine) + "; the engines are" + RTRIM(FQ_ENGINES))
			RETURN .NULL.
		ENDIF
		loDef = This.Get(tcName)
		IF ISNULL(loDef)
			RETURN .NULL.
		ENDIF
		IF VARTYPE(toParams) == "O"
			loArgs = .NULL.
			lcText = This.Bind(loDef, lcEngine, toParams, @loArgs)
			IF ISNULL(lcText)
				RETURN .NULL.
			ENDIF
		ELSE
			lcText = This.EngineText(loDef, lcEngine)
			IF ISNULL(lcText)
				RETURN .NULL.
			ENDIF
			lcText = This.oText.Resolve(lcText, loDef, .NULL., .NULL., lcEngine)
			IF ISNULL(lcText)
				=This.Fail(This.oText.cErrorCode, This.oText.cError + " (" + loDef.cName + ")")
				RETURN .NULL.
			ENDIF
			lcText = This.oText.HolesAsNames(lcText)
			lcText = This.FillIdents(lcText, loDef)
			IF ISNULL(lcText)
				RETURN .NULL.
			ENDIF
		ENDIF
		IF VARTYPE(tcObject) == "C" AND !EMPTY(tcObject)
			lcText = This.oText.Style(lcText, ALLTRIM(tcObject))
		ENDIF
		This.cLastSql = lcText
		RETURN lcText
	ENDFUNC

	* El Empty que Run le daría al ejecutor con estos parámetros (los declarados validados, los
	* default, .NULL. en los opcionales que no vienen, p_1, p_2… de cada lista), o .NULL. con el error.
	* Es el que acompaña al texto de Sql(name, engine, cObject, toParams) para quien ejecuta él.
	FUNCTION Args(tcName, toParams)
		LOCAL loDef, loArgs
		loDef = This.Get(tcName)
		IF ISNULL(loDef)
			RETURN .NULL.
		ENDIF
		loArgs = This.Arguments(loDef, toParams, CREATEOBJECT("Collection"))
		RETURN loArgs
	ENDFUNC

	* ---------------------------------------------------------------- ejecución

	* Una consulta read, a un cursor. .T. o .F.
	FUNCTION Run(toDb, tcName, toParams, tcCursor)
		LOCAL lcSql, loArgs, llOk, lcErr, loErr
		loArgs = .NULL.
		lcSql = This.Prepare(toDb, tcName, toParams, "read", "Run", @loArgs)
		IF ISNULL(lcSql)
			RETURN .F.
		ENDIF
		llOk = .F.
		lcErr = ""
		TRY
			llOk = toDb.Query(lcSql, IIF(VARTYPE(tcCursor) == "C", tcCursor, ""), loArgs)
		CATCH TO loErr
			lcErr = "error " + TRANSFORM(loErr.ErrorNo) + ": " + loErr.Message
		ENDTRY
		IF !(VARTYPE(llOk) == "L" AND llOk)
			RETURN This.Fail("executor_failed", This.ExecutorError(toDb, lcErr))
		ENDIF
		RETURN .T.
	ENDFUNC

	* Una consulta read que da un valor: el valor, o .NULL. (también si falla: mira nErrors).
	FUNCTION Scalar(toDb, tcName, toParams)
		LOCAL lcSql, loArgs, lvValue, lcErr, loErr, lnBefore, llFailed
		loArgs = .NULL.
		lcSql = This.Prepare(toDb, tcName, toParams, "read", "Scalar", @loArgs)
		IF ISNULL(lcSql)
			RETURN .NULL.
		ENDIF
		lnBefore = This.ExecutorErrors(toDb)
		lvValue = .NULL.
		lcErr = ""
		TRY
			lvValue = toDb.Scalar(lcSql, loArgs)
		CATCH TO loErr
			lcErr = "error " + TRANSFORM(loErr.ErrorNo) + ": " + loErr.Message
		ENDTRY
		llFailed = !EMPTY(lcErr) OR This.ExecutorErrors(toDb) > lnBefore
		IF llFailed
			=This.Fail("executor_failed", This.ExecutorError(toDb, lcErr))
			RETURN .NULL.
		ENDIF
		RETURN lvValue
	ENDFUNC

	* Una consulta write: las filas que tocó, o -1.
	FUNCTION Execute(toDb, tcName, toParams)
		LOCAL lcSql, loArgs, lnRows, lcErr, loErr
		loArgs = .NULL.
		lcSql = This.Prepare(toDb, tcName, toParams, "write", "Execute", @loArgs)
		IF ISNULL(lcSql)
			RETURN -1
		ENDIF
		lnRows = -1
		lcErr = ""
		TRY
			lnRows = toDb.Execute(lcSql, loArgs)
		CATCH TO loErr
			lcErr = "error " + TRANSFORM(loErr.ErrorNo) + ": " + loErr.Message
		ENDTRY
		IF VARTYPE(lnRows) # "N" OR lnRows < 0
			=This.Fail("executor_failed", This.ExecutorError(toDb, lcErr))
			RETURN -1
		ENDIF
		RETURN lnRows
	ENDFUNC

	* Todo lo que se comprueba antes de tocar el ejecutor. Devuelve el texto (y en roArgs el Empty que
	* recibirá el ejecutor) o .NULL. con el error puesto.
	PROTECTED FUNCTION Prepare(toDb, tcName, toParams, tcKind, tcVerb, roArgs)
		LOCAL lcEngine, loDef, loArgs, lcText
		This.cLastQuery = TRANSFORM(tcName)
		This.cLastSql = ""
		IF VARTYPE(toDb) # "O" OR !PEMSTATUS(toDb, "cEngine", 5) OR !PEMSTATUS(toDb, "Query", 5) OR ;
				!PEMSTATUS(toDb, "Execute", 5) OR !PEMSTATUS(toDb, "Scalar", 5)
			=This.Fail("executor_invalid", "the executor has to be an object with cEngine, Query(), Execute() and Scalar(), " + ;
				"such as a database of FoxRemote")
			RETURN .NULL.
		ENDIF
		lcEngine = LOWER(ALLTRIM(TRANSFORM(toDb.cEngine)))
		IF !(" " + lcEngine + " " $ FQ_ENGINES)
			=This.Fail("engine_unknown", "the executor says its engine is '" + TRANSFORM(toDb.cEngine) + "'; the engines are" + RTRIM(FQ_ENGINES))
			RETURN .NULL.
		ENDIF
		loDef = This.Get(tcName)
		IF ISNULL(loDef)
			RETURN .NULL.
		ENDIF
		IF !(loDef.cKind == tcKind)
			=This.Fail("wrong_kind", loDef.cName + " is a " + loDef.cKind + " query: " + tcVerb + "() runs only " + tcKind + ;
				" queries (" + IIF(tcKind == "read", "Run or Scalar", "Execute") + " is for " + tcKind + ", " + ;
				IIF(loDef.cKind == "read", "Run or Scalar", "Execute") + " for " + loDef.cKind + ")")
			RETURN .NULL.
		ENDIF
		loArgs = .NULL.
		lcText = This.Bind(loDef, lcEngine, toParams, @loArgs)
		IF ISNULL(lcText)
			RETURN .NULL.
		ENDIF
		This.cLastSql = lcText
		roArgs = loArgs
		RETURN lcText
	ENDFUNC

	* El texto resuelto con los parámetros del llamador y el Empty que lo acompaña (roArgs), o .NULL.
	* con el error puesto. Lo usan Run, Scalar, Execute y Sql con toParams: un solo sitio.
	PROTECTED FUNCTION Bind(toDef, tcEngine, toParams, roArgs)
		LOCAL loDef, loArgs, loLists, lcText, lcShape, lnAt
		loDef = toDef
		loLists = CREATEOBJECT("Collection")
		loArgs = This.Arguments(loDef, toParams, loLists)
		IF ISNULL(loArgs)
			RETURN .NULL.
		ENDIF
		* La misma forma de llamada da el mismo texto; Arguments (los tipos, el Empty) corre siempre.
		lcShape = This.ShapeKey(loDef, tcEngine, toParams, loLists)
		lnAt = IIF(EMPTY(lcShape), 0, This.oResolved.GetKey(lcShape))
		IF lnAt > 0
			lcText = This.oResolved.Item(lnAt)
		ELSE
			lcText = This.EngineText(loDef, tcEngine)
			IF ISNULL(lcText)
				RETURN .NULL.
			ENDIF
			This.nResolves = This.nResolves + 1
			lcText = This.oText.Resolve(lcText, loDef, toParams, loLists, tcEngine)
			IF ISNULL(lcText)
				=This.Fail(This.oText.cErrorCode, This.oText.cError + " (" + loDef.cName + ")")
				RETURN .NULL.
			ENDIF
			* Los identificadores van antes de la caché; la clave lleva su generación (nIdentGen), así que un
			* SetIdent no vacía nada y la llamada siguiente con los mismos valores no rellena otra vez.
			lcText = This.FillIdents(lcText, loDef)
			IF ISNULL(lcText)
				RETURN .NULL.
			ENDIF
			IF !EMPTY(lcShape)
				IF This.oResolved.Count >= MAX(This.nResolvedCacheMax, 1)
					This.ClearResolved("full")
				ENDIF
				This.oResolved.Add(lcText, lcShape)
			ENDIF
		ENDIF
		* El número de {limit}/{offset}, validado, sobre el hueco del texto; después de la caché, para
		* que la clave de oResolved no lleve ningún valor.
		lcText = This.FillLimits(lcText, loArgs, tcEngine, loDef)
		IF ISNULL(lcText)
			RETURN .NULL.
		ENDIF
		roArgs = loArgs
		RETURN lcText
	ENDFUNC

	* Los huecos de {limit :p} y {offset :p} (CHR(1) p CHR(1), que no puede salir en SQL) con el entero del
	* Empty: entero, no negativo; en vfp, 1 o más (TOP 0 es el error 1866). Es la única vez que la librería
	* escribe un valor en el texto, y lo escribe validado. .NULL. con el error.
	PROTECTED FUNCTION FillLimits(tcText, toArgs, tcEngine, toDef)
		LOCAL lcOut, lnA, lnB, lcName, lvValue
		lcOut = tcText
		DO WHILE CHR(1) $ lcOut
			lnA = AT(CHR(1), lcOut)
			lnB = AT(CHR(1), lcOut, 2)
			lcName = SUBSTR(lcOut, lnA + 1, lnB - lnA - 1)
			lvValue = IIF(PEMSTATUS(toArgs, lcName, 5), GETPEM(toArgs, lcName), .NULL.)
			IF ISNULL(lvValue) OR VARTYPE(lvValue) # "N" OR lvValue # INT(lvValue) OR lvValue < 0 OR (tcEngine == "vfp" AND lvValue < 1)
				=This.Fail("limit_value_invalid", lcName + " is " + IIF(ISNULL(lvValue), ".NULL.", TRANSFORM(lvValue)) + ;
					"; {limit} and {offset} take a whole number, 0 or more" + IIF(tcEngine == "vfp", " (1 or more in vfp: TOP 0 does not exist)", "") + ;
					" (" + toDef.cName + ")")
				RETURN .NULL.
			ENDIF
			lcOut = LEFT(lcOut, lnA - 1) + LTRIM(STR(lvValue, 20)) + SUBSTR(lcOut, lnB + 1)
		ENDDO
		RETURN lcOut
	ENDFUNC

	* La clave de la caché del texto resuelto: la forma de la llamada, nunca un valor (los valores no se
	* pegan, así que no cambian el texto). Nombre, motor, los declarados presentes en el orden de
	* la cabecera (deciden los {if}), cuántos elementos trae cada lista (deciden :p_1, :p_2…) y el sort
	* pedido tal como lo escribe el llamador (solo si el texto tiene {sort}):
	*   customers.by_city|sqlite|city,since||sort=name DESC     customers.in_countries|sqlite|countries|countries=3|sort=
	* "" si la llamada no se cachea: un sort que no es texto, que Resolve rechaza.
	PROTECTED FUNCTION ShapeKey(toDef, tcEngine, toParams, toLists)
		LOCAL llObj, lcPresent, lcLists, lcSort, loPar, lnAt, lvSort
		llObj = VARTYPE(toParams) == "O"
		lcPresent = ""
		lcLists = ""
		FOR EACH loPar IN toDef.oParams
			IF llObj AND PEMSTATUS(toParams, loPar.cName, 5)
				lcPresent = lcPresent + IIF(EMPTY(lcPresent), "", ",") + LOWER(loPar.cName)
			ENDIF
			IF loPar.lList
				lnAt = toLists.GetKey(LOWER(loPar.cName))
				lcLists = lcLists + IIF(EMPTY(lcLists), "", ",") + LOWER(loPar.cName) + "=" + TRANSFORM(IIF(lnAt > 0, toLists.Item(lnAt), 0))
			ENDIF
		ENDFOR
		lcSort = ""
		IF toDef.nSort > 0 AND llObj AND PEMSTATUS(toParams, "sort", 5)
			lvSort = GETPEM(toParams, "sort")
			DO CASE
			CASE ISNULL(lvSort)
			CASE VARTYPE(lvSort) == "C"
				lcSort = lvSort
			OTHERWISE
				RETURN ""
			ENDCASE
		ENDIF
		RETURN LOWER(toDef.cName) + "|" + tcEngine + "|" + lcPresent + "|" + lcLists + "|sort=" + lcSort + ;
			IIF(EMPTY(toDef.cIdentNames), "", "|ident=" + TRANSFORM(This.nIdentGen))
	ENDFUNC

	* Vacía la caché del texto resuelto: con una carga nueva, una macro nueva, o al llegar al tope.
	PROTECTED PROCEDURE ClearResolved(tcWhy)
		This.oResolved = CREATEOBJECT("Collection")
	ENDPROC

	* El Empty que recibe el ejecutor: los declarados que el llamador trae (validados), los default de
	* los que no trae, .NULL. para los opcionales sin default, y name_1, name_2… de cada lista (en
	* toLists, nombre -> cuántos). El objeto del llamador no se toca: PEMSTATUS(…, 5) y GETPEM, nunca
	* TYPE() ni una lectura que dispare su This_Access sobre una propiedad que no tiene.
	PROTECTED FUNCTION Arguments(toDef, toParams, toLists)
		LOCAL loArgs, loPar, lcName, llHas, lvValue, llObj, laItems[1], lnItems, lnI, lcWhy, loI
		loArgs = CREATEOBJECT("Empty")
		llObj = VARTYPE(toParams) == "O"
		* Un identificador lo fija el programa, nunca una llamada.
		IF llObj AND !EMPTY(toDef.cIdentNames)
			FOR lnI = 1 TO AMEMBERS(laItems, toParams, 0)
				IF " " + LOWER(laItems[lnI]) + " " $ toDef.cIdentNames
					=This.Fail("ident_not_a_param", LOWER(laItems[lnI]) + " is an identifier of the context: FQ_SET it once, not in the call (" + toDef.cName + ")")
					RETURN .NULL.
				ENDIF
			ENDFOR
		ENDIF
		FOR EACH loPar IN toDef.oParams
			lcName = loPar.cName
			llHas = llObj AND PEMSTATUS(toParams, lcName, 5)
			IF !llHas
				IF loPar.lRequired AND !loPar.lHasDefault
					=This.Fail("param_missing", lcName + " (" + toDef.cName + " needs it, and the call gives no " + lcName + ")")
					RETURN .NULL.
				ENDIF
				ADDPROPERTY(loArgs, lcName, IIF(loPar.lHasDefault, loPar.vDefault, .NULL.))
				LOOP
			ENDIF
			IF loPar.lList
				lcWhy = ""
				lnItems = This.ListItems(toParams, lcName, loPar.cType, @laItems, @lcWhy)
				DO CASE
				CASE lnItems < 0
					=This.Fail("param_type", lcName + ": " + lcWhy + " (" + toDef.cName + ")")
					RETURN .NULL.
				CASE lnItems = 0
					ADDPROPERTY(loArgs, lcName, .NULL.)
				OTHERWISE
					FOR lnI = 1 TO lnItems
						ADDPROPERTY(loArgs, lcName + "_" + TRANSFORM(lnI), laItems[lnI])
					ENDFOR
					toLists.Add(lnItems, LOWER(lcName))
				ENDCASE
				LOOP
			ENDIF
			lvValue = GETPEM(toParams, lcName)
			IF !This.TypeOk(lvValue, loPar.cType)
				=This.Fail("param_type", lcName + " is declared " + loPar.cType + " and the value is " + VARTYPE(lvValue) + " (" + toDef.cName + ")")
				RETURN .NULL.
			ENDIF
			ADDPROPERTY(loArgs, lcName, lvValue)
		ENDFOR
		RETURN loArgs
	ENDFUNC

	* Los elementos de una lista: una propiedad array, una Collection o una cadena con comas (solo en C
	* y M). Devuelve cuántos (0 si es .NULL.) o -1 con el motivo en rcWhy.
	* Una lista vacía es «the list is empty» venga como venga: el texto "" (de cualquier tipo), la Collection
	* vacía y el array de un solo .F. (en VFP no hay arrays sin elementos: DIMENSION, ADIR o ALINES dejan
	* uno, .F.), salvo en una lista L, donde [.F.] es el valor falso.
	* Una sola sonda, TYPE("toParams.x", 1), decide array (A), Collection (C) o lo demás (U), sin TRY: la
	* excepción de un ALEN() sobre lo que no es un array es mucho más lenta. La propiedad ya existe (PEMSTATUS(…, 5)
	* la dio), así que en un None la sonda despierta un This_Access y no cambia ni crea nada.
	PROTECTED FUNCTION ListItems(toParams, tcName, tcType, raItems, rcWhy)
		LOCAL lnN, lvValue, lnI, loItem, laParts[1], lcKind
		lnN = 0
		lcKind = TYPE("toParams." + tcName, 1)
		IF lcKind == "A"
			lnN = ALEN(toParams.&tcName)
			DIMENSION raItems[MAX(lnN, 1)]
			FOR lnI = 1 TO lnN
				raItems[lnI] = toParams.&tcName[lnI]
			ENDFOR
			IF lnN = 1 AND VARTYPE(raItems[1]) == "L" AND !raItems[1] AND !(tcType == "L")
				lnN = 0
			ENDIF
		ELSE
			lvValue = GETPEM(toParams, tcName)
			DO CASE
			CASE ISNULL(lvValue)
				RETURN 0
			CASE lcKind == "C" OR (VARTYPE(lvValue) == "O" AND PEMSTATUS(lvValue, "Count", 5) AND PEMSTATUS(lvValue, "Item", 5))
				lnN = 0
				FOR EACH loItem IN lvValue
					lnN = lnN + 1
					DIMENSION raItems[lnN]
					raItems[lnN] = loItem
				ENDFOR
			CASE VARTYPE(lvValue) == "C" AND EMPTY(lvValue)
				lnN = 0
			CASE VARTYPE(lvValue) == "C" AND INLIST(tcType, "C", "M")
				lnN = ALINES(laParts, lvValue, 1 + 4, ",")
				DIMENSION raItems[MAX(lnN, 1)]
				FOR lnI = 1 TO lnN
					raItems[lnI] = laParts[lnI]
				ENDFOR
			CASE VARTYPE(lvValue) == "C"
				rcWhy = "text with commas is only for lists of C or M; a list of " + tcType + " is an array or a Collection"
				RETURN -1
			OTHERWISE
				rcWhy = "a list is an array, a Collection" + IIF(INLIST(tcType, "C", "M"), " or text with commas", "") + ;
					", and the value is " + VARTYPE(lvValue)
				RETURN -1
			ENDCASE
		ENDIF
		IF lnN = 0
			rcWhy = "the list is empty"
			RETURN -1
		ENDIF
		FOR lnI = 1 TO lnN
			IF !This.TypeOk(raItems[lnI], tcType)
				rcWhy = "item " + TRANSFORM(lnI) + " of the list is " + VARTYPE(raItems[lnI]) + " and the list is declared " + tcType
				RETURN -1
			ENDIF
		ENDFOR
		RETURN lnN
	ENDFUNC

	PROTECTED FUNCTION TypeOk(tvValue, tcType)
		LOCAL lcV
		IF ISNULL(tvValue)
			RETURN .T.
		ENDIF
		lcV = VARTYPE(tvValue)
		DO CASE
		CASE INLIST(tcType, "C", "M")
			RETURN lcV == "C"
		CASE tcType == "N"
			RETURN lcV == "N"
		CASE tcType == "I"
			RETURN lcV == "N" AND tvValue = INT(tvValue)
		CASE tcType == "Y"
			* Un N también: lo que se liga es un número en los dos casos, y exigir un Y no aporta nada.
			RETURN INLIST(lcV, "Y", "N")
		ENDCASE
		RETURN lcV == tcType
	ENDFUNC

	* El texto de la consulta para un motor: su variante o el común, con las macros de ese motor. Se
	* calcula una vez por nombre y motor y se guarda; Reload() y AddMacro() lo vacían.
	PROTECTED FUNCTION EngineText(toDef, tcEngine)
		LOCAL lcKey, lnAt, lcText, lnLen
		lcKey = LOWER(toDef.cName) + "|" + tcEngine
		lnAt = This.oCache.GetKey(lcKey)
		IF lnAt > 0
			lcText = This.oCache.Item(lnAt)
			* Un fallo guardado da el mismo código y el mismo mensaje, sin calcular otra vez.
			IF LEFT(lcText, 1) == CHR(29)
				=This.Fail(STREXTRACT(lcText, CHR(29), CHR(29)), SUBSTR(lcText, AT(CHR(29), lcText, 2) + 1))
				RETURN .NULL.
			ENDIF
			RETURN lcText
		ENDIF
		* Con un catálogo, el texto viene del fichero: ExpandMacros no corre.
		IF !EMPTY(This.cCatalog)
			lnAt = This.oCatalogErrors.GetKey(lcKey)
			IF lnAt > 0
				lcText = This.oCatalogErrors.Item(lnAt)
				=This.Fail(LEFT(lcText, AT(CHR(29), lcText + CHR(29)) - 1), SUBSTR(lcText, AT(CHR(29), lcText + CHR(29)) + 1))
				RETURN .NULL.
			ENDIF
			=This.Fail("catalog_invalid", "the catalog has no text of " + toDef.cName + " for " + tcEngine)
			RETURN .NULL.
		ENDIF
		This.nEngineTexts = This.nEngineTexts + 1
		lnAt = toDef.oVariants.GetKey(tcEngine)
		lcText = IIF(lnAt > 0, toDef.oVariants.Item(lnAt), toDef.cSql)
		lcText = This.oText.ExpandMacros(lcText, tcEngine, This.oMacros)
		IF ISNULL(lcText)
			RETURN This.EngineFail(lcKey, This.oText.cErrorCode, This.oText.cError + " (" + toDef.cName + ")")
		ENDIF
		* {ident x} se queda como hueco, CHR(2) x CHR(2), en el texto por motor y en el .fq; cada llamada lo
		* rellena después de la caché (FillIdents), como FillLimits.
		lcText = This.oText.IdentHoles(lcText)
		* En vfp, el texto como lo correría QueryLocal (con los {if} tal cual, que es lo más largo, y el INTO
		* de una lectura) no puede pasar de FQ_VFP_LINE: sql_too_long, solo en vfp, y el .fq lo guarda así.
		IF tcEngine == "vfp"
			lnLen = LEN(This.oText.LocalText(This.oText.IdentsAtMost(lcText, toDef))) + IIF(toDef.cKind == "read", LEN(FQ_LOCAL_INTO), 0)
			IF lnLen > FQ_VFP_LINE
				RETURN This.EngineFail(lcKey, "sql_too_long", "the vfp text is " + TRANSFORM(lnLen) + " characters as QueryLocal runs it, and VFP runs " + ;
					TRANSFORM(FQ_VFP_LINE) + " at most in one line (a longer one stops with error 18, Line is too long); write a shorter -- engine: vfp text (" + ;
					IIF(EMPTY(toDef.cFile), toDef.cName, JUSTFNAME(toDef.cFile) + "(" + ;
					TRANSFORM(IIF(toDef.HasVariant("vfp") AND PEMSTATUS(toDef, "nLine_vfp", 5), GETPEM(toDef, "nLine_vfp"), toDef.nLine)) + ")") + ")")
			ENDIF
		ENDIF
		* En vfp, {sort} escribe la posición de la columna en la lista del SELECT; una columna que no está
		* en ella es sort_not_in_select, solo en vfp (y así lo guarda el .fq, como macro_unsupported).
		IF tcEngine == "vfp" AND toDef.nSort > 0 AND "{sort" $ LOWER(lcText) AND ISNULL(This.oText.SortPositions(lcText, toDef))
			RETURN This.EngineFail(lcKey, This.oText.cErrorCode, This.oText.cError)
		ENDIF
		This.oCache.Add(lcText, lcKey)
		RETURN lcText
	ENDFUNC

	* Lo que un motor no puede se guarda en la caché como el texto, CHR(29) código CHR(29) motivo (como
	* las celdas E del .fq), y EngineText lo devuelve sin calcular otra vez; si no, con 500 consultas que vfp
	* no puede, cada CheckEngine costaría lo mismo que el primero. Reload y AddMacro vacían la caché, y con
	* ella los fallos. Devuelve .NULL.
	PROTECTED FUNCTION EngineFail(tcKey, tcCode, tcMessage)
		This.oCache.Add(CHR(29) + tcCode + CHR(29) + tcMessage, tcKey)
		=This.Fail(tcCode, tcMessage)
		RETURN .NULL.
	ENDFUNC

	* Lo que un motor no puede ejecutar (sql_too_long y sort_not_in_select en vfp, una
	* macro_unsupported) no impide la carga, porque los otros seis lo ejecutan; pero quien carga y ve .T. tiene que
	* poder saberlo sin ejecutar. Aquí se resuelve el texto de ese motor para todo lo cargado (lo que la primera
	* llamada de cada consulta haría igual, y se queda en la caché) y cada consulta que ese motor no puede es un
	* aviso en aWarnings, detrás de los de la carga; los de un CheckEngine anterior se quitan. FQ_USE_DBF,
	* FQ_USE_HANDLE y FQ_USE lo llaman con lo cargado, y FQ_LOAD con el motor en uso. Devuelve cuántas consultas
	* no puede ese motor (0: todas valen), o -1 con engine_unknown.
	* Con tnFrom y tnCount, solo las consultas tnFrom a tnFrom + tnCount - 1, en el orden de carga, para
	* repartirlo en los ratos libres del programa. Los avisos se acumulan tramo a tramo: vuelven a los de la carga con tnFrom 1 (o sin él) o si
	* el motor no es el del tramo anterior. Un tnFrom más allá del final devuelve 0 sin tocar nada; un tnCount que se pasa
	* se recorta. Sin los dos, todas.
	FUNCTION CheckEngine(tcEngine, tnFrom, tnCount)
		LOCAL lcEngine, llStrict, lnErrors, lcError, lcCode, loDef, lnBad, lnFrom, lnTo, lnI, llOnce
		lcEngine = LOWER(ALLTRIM(TRANSFORM(tcEngine)))
		IF !(" " + lcEngine + " " $ FQ_ENGINES)
			=This.Fail("engine_unknown", "unknown engine " + TRANSFORM(tcEngine) + "; the engines are" + RTRIM(FQ_ENGINES))
			RETURN -1
		ENDIF
		lnFrom = IIF(INLIST(VARTYPE(tnFrom), "N", "I", "Y"), MAX(1, INT(tnFrom)), 1)
		lnTo = IIF(INLIST(VARTYPE(tnCount), "N", "I", "Y"), MIN(lnFrom + MAX(0, INT(tnCount)) - 1, This.oQueries.Count), This.oQueries.Count)
		IF lnFrom > 1 AND lnFrom > This.oQueries.Count
			RETURN 0
		ENDIF
		* Un tramo que no empieza en 1 acumula, y no añade un aviso que ya esté (el mismo código,
		* fichero y línea; el motor es el mismo, porque si cambia se vuelve a los de la carga): quien llama puede
		* repetir tramos. La pasada desde 1 no compara nada: empieza de los de la carga, y cada consulta da un aviso.
		llOnce = lnFrom > 1 AND lcEngine == This.cCheckedEngine
		IF lnFrom = 1 OR !(lcEngine == This.cCheckedEngine)
			This.nWarnings = This.nWarningsLoaded
			DIMENSION This.aWarnings[MAX(This.nWarnings, 1), 4]
			IF This.nWarnings = 0
				This.aWarnings = ""
			ENDIF
		ENDIF
		This.cCheckedEngine = lcEngine
		llStrict = This.lStrict
		lnErrors = This.nErrors
		lcError = This.cLastError
		lcCode = This.cLastErrorCode
		This.lStrict = .F.
		lnBad = 0
		FOR lnI = lnFrom TO lnTo
			loDef = This.oQueries.Item(lnI)
			IF ISNULL(This.EngineText(loDef, lcEngine))
				lnBad = lnBad + 1
				This.WarnEngine(loDef, lcEngine, This.cLastErrorCode, SUBSTR(This.cLastError, LEN(This.cLastErrorCode) + 3), llOnce)
			ENDIF
		ENDFOR
		This.lStrict = llStrict
		This.nErrors = lnErrors
		This.cLastError = lcError
		This.cLastErrorCode = lcCode
		RETURN lnBad
	ENDFUNC

	* ¿Puede ese motor con esa consulta? .T., o .F. con el fallo del motor en cLastErrorCode y cLastError (el
	* mismo que daría Sql), o query_not_found o engine_unknown. No toca aWarnings: es la pregunta de un fichero concreto.
	FUNCTION CheckQuery(tcName, tcEngine)
		LOCAL lcEngine, loDef, llStrict, llOk
		This.ClearLastError()
		lcEngine = LOWER(ALLTRIM(TRANSFORM(tcEngine)))
		IF !(" " + lcEngine + " " $ FQ_ENGINES)
			RETURN This.Fail("engine_unknown", "unknown engine " + TRANSFORM(tcEngine) + "; the engines are" + RTRIM(FQ_ENGINES))
		ENDIF
		loDef = This.Get(tcName)
		IF ISNULL(loDef)
			RETURN .F.
		ENDIF
		* Con lStrict no lanza, como CheckEngine: que el motor no pueda es la respuesta que se pide.
		llStrict = This.lStrict
		This.lStrict = .F.
		llOk = !ISNULL(This.EngineText(loDef, lcEngine))
		This.lStrict = llStrict
		RETURN llOk
	ENDFUNC

	* Un aviso de lo que un motor no puede: el código del error, el fichero y la línea, y el motivo. Si el
	* motivo acaba en «(fichero(línea))», que es la línea del error (la del «-- sort:», la del texto de vfp), esa
	* es la del aviso y se quita del texto; si no (macro_unsupported dice el nombre), la de la consulta. Igual
	* para una celda E. Con tlOnce (un tramo que acumula), no se añade si ya está entre los del motor.
	PROTECTED PROCEDURE WarnEngine(toDef, tcEngine, tcCode, tcReason, tlOnce)
		LOCAL lcReason, lnLine, lcTail, lnAt, lcRest
		lcReason = tcReason
		lnLine = toDef.nLine
		IF !EMPTY(toDef.cFile)
			lcTail = " (" + JUSTFNAME(toDef.cFile) + "("
			lnAt = RAT(lcTail, lcReason)
			lcRest = IIF(lnAt > 0, SUBSTR(lcReason, lnAt + LEN(lcTail)), "")
			IF LEN(lcRest) > 2 AND RIGHT(lcRest, 2) == "))" AND LEN(CHRTRAN(LEFT(lcRest, LEN(lcRest) - 2), "0123456789", "")) = 0
				lnLine = VAL(LEFT(lcRest, LEN(lcRest) - 2))
				lcReason = LEFT(lcReason, lnAt - 1)
			ENDIF
		ENDIF
		IF tlOnce AND This.HasEngineWarning(tcCode, toDef.cFile, lnLine)
			RETURN
		ENDIF
		This.Warn(tcCode, toDef.cFile, lnLine, "on " + tcEngine + ", " + lcReason)
	ENDPROC

	* ¿Hay ya, detrás de los de la carga, un aviso con ese código, ese fichero y esa línea? ASCAN busca en la
	* columna del fichero (2), desde la fila que se le da, y devuelve la fila (14: exacto y con mayúsculas).
	PROTECTED FUNCTION HasEngineWarning(tcCode, tcFile, tnLine)
		LOCAL lnRow
		lnRow = This.nWarningsLoaded
		DO WHILE lnRow < This.nWarnings
			lnRow = ASCAN(This.aWarnings, tcFile, lnRow + 1, This.nWarnings - lnRow, 2, 14)
			IF lnRow = 0
				EXIT
			ENDIF
			IF This.aWarnings[lnRow, 1] == tcCode AND This.aWarnings[lnRow, 3] = tnLine
				RETURN .T.
			ENDIF
		ENDDO
		RETURN .F.
	ENDFUNC

	* Lo que dice el ejecutor de su fallo (su cLastError, si lo tiene).
	PROTECTED FUNCTION ExecutorError(toDb, tcCaught)
		LOCAL lcMsg
		lcMsg = tcCaught
		IF EMPTY(lcMsg) AND PEMSTATUS(toDb, "cLastError", 5)
			lcMsg = TRANSFORM(toDb.cLastError)
		ENDIF
		RETURN "the executor failed" + IIF(EMPTY(lcMsg), "", ": " + lcMsg) + " (" + This.cLastQuery + ")"
	ENDFUNC

	PROTECTED FUNCTION ExecutorErrors(toDb)
		RETURN IIF(PEMSTATUS(toDb, "nErrors", 5) AND VARTYPE(toDb.nErrors) == "N", toDb.nErrors, 0)
	ENDFUNC

	* ---------------------------------------------------------------- el lector de .sql

	* Un .sql a un QueryDef, o .NULL. con sus errores en aLoadErrors.
	PROTECTED FUNCTION ReadQuery(tcFile)
		LOCAL lcText, laL[1], lnN, lnI, lcLine, lcTrim, lcBody, lcKey, lcVal, lnColon, llHeader, loDef, ;
			lnBefore, lcCur, lnCurLine, lcBuf, lnNameLine, lnKindLine, lnSortLine, laEng[1], lnEng, lcStem, loPar
		lnBefore = This.nLoadErrors
		lcText = FILETOSTR(tcFile)
		lnN = ALINES(laL, lcText, 0)
		loDef = CREATEOBJECT("QueryDef")
		loDef.cFile = tcFile
		lnNameLine = 0
		lnKindLine = 0
		lnSortLine = 0
		llHeader = .T.
		lcCur = ""          && "" el común; si no, el motor de la variante que se está leyendo
		lcBuf = ""
		lnCurLine = 0
		lnEng = 0
		FOR lnI = 1 TO lnN
			lcLine = laL[lnI]
			lcTrim = ALLTRIM(lcLine, 1, " ", CHR(9))
			lcKey = ""
			lcVal = ""
			IF LEFT(lcTrim, 2) == "--"
				lcBody = ALLTRIM(SUBSTR(lcTrim, 3), 1, " ", CHR(9))
				lnColon = AT(":", lcBody)
				IF lnColon > 1
					lcKey = LOWER(LEFT(lcBody, lnColon - 1))
					lcVal = ALLTRIM(SUBSTR(lcBody, lnColon + 1), 1, " ", CHR(9))
					IF !INLIST(lcKey, "name", "description", "kind", "param", "sort", "engine", "ident")
						lcKey = ""
					ENDIF
				ENDIF
			ENDIF
			* «-- engine:» abre una variante, en la cabecera o en el cuerpo.
			IF lcKey == "engine"
				This.FlushText(loDef, lcCur, lcBuf, lnCurLine, tcFile)
				llHeader = .F.
				lcCur = LOWER(This.StripComment(lcVal))
				lcBuf = ""
				lnCurLine = 0
				DO CASE
				CASE !(" " + lcCur + " " $ FQ_ENGINES) OR EMPTY(lcCur)
					This.LoadError("engine_unknown", tcFile, lnI, "unknown engine '" + lcCur + "'; the engines are" + RTRIM(FQ_ENGINES))
					lcCur = "?"
				CASE ASCAN(laEng, lcCur, 1, -1, 1, 7) > 0
					This.LoadError("engine_duplicate", tcFile, lnI, "a second section for " + lcCur)
					lcCur = "?"
				OTHERWISE
					lnEng = lnEng + 1
					DIMENSION laEng[lnEng]
					laEng[lnEng] = lcCur
				ENDCASE
				LOOP
			ENDIF
			IF llHeader
				DO CASE
				CASE EMPTY(lcTrim)
					LOOP
				CASE LEFT(lcTrim, 2) == "--" AND EMPTY(lcKey)
					* Un comentario de la cabecera que no es una clave.
					LOOP
				CASE LEFT(lcTrim, 2) == "--"
					lcVal = This.StripComment(lcVal)
					DO CASE
					CASE lcKey == "name"
						loDef.cName = lcVal
						lnNameLine = lnI
					CASE lcKey == "description"
						loDef.cDescription = lcVal
					CASE lcKey == "kind"
						loDef.cKind = LOWER(lcVal)
						lnKindLine = lnI
					CASE lcKey == "param"
						This.ReadParam(loDef, lcVal, tcFile, lnI)
					CASE lcKey == "sort"
						This.ReadSort(loDef, lcVal, tcFile, lnI)
						lnSortLine = lnI
					CASE lcKey == "ident"
						This.ReadIdent(loDef, lcVal, tcFile, lnI)
					ENDCASE
					LOOP
				OTHERWISE
					llHeader = .F.
				ENDCASE
			ENDIF
			IF lnCurLine = 0
				IF EMPTY(lcTrim)
					LOOP
				ENDIF
				lnCurLine = lnI
				lcBuf = lcLine
			ELSE
				lcBuf = lcBuf + FQ_CRLF + lcLine
			ENDIF
		ENDFOR
		This.FlushText(loDef, lcCur, lcBuf, lnCurLine, tcFile)

		* La cabecera.
		lcStem = JUSTSTEM(tcFile)
		DO CASE
		CASE EMPTY(loDef.cName)
			This.LoadError("header_name_missing", tcFile, 1, "the header has no '-- name:' (it has to be " + lcStem + ")")
		CASE !(LOWER(loDef.cName) == LOWER(lcStem))
			This.LoadError("header_name_mismatch", tcFile, lnNameLine, "the name is '" + loDef.cName + "' and the file is " + ;
				JUSTFNAME(tcFile) + ": the name is the file name without .sql")
		ENDCASE
		DO CASE
		CASE EMPTY(loDef.cKind)
			This.LoadError("header_kind_missing", tcFile, 1, "the header has no '-- kind:' (read or write)")
		CASE !INLIST(loDef.cKind, "read", "write")
			This.LoadError("header_kind_invalid", tcFile, lnKindLine, "the kind is '" + loDef.cKind + "': it is read or write")
		ENDCASE
		IF EMPTY(loDef.cSql)
			This.LoadError("sql_missing", tcFile, 1, "there is no SQL under the header")
		ENDIF
		IF This.nLoadErrors = lnBefore
			This.CheckTexts(loDef, tcFile, lnSortLine)
		ENDIF
		IF This.nLoadErrors > lnBefore
			RETURN .NULL.
		ENDIF
		RETURN loDef
	ENDFUNC

	* Lo que va detrás de un segundo «--» en una línea de cabecera es un comentario.
	PROTECTED FUNCTION StripComment(tcVal)
		LOCAL lnAt
		lnAt = AT(" --", tcVal)
		RETURN ALLTRIM(IIF(lnAt > 0, LEFT(tcVal, lnAt - 1), tcVal), 1, " ", CHR(9))
	ENDFUNC

	* Guarda un texto leído (sin las líneas en blanco del final) como común o como variante.
	PROTECTED PROCEDURE FlushText(toDef, tcEngine, tcBuf, tnLine, tcFile)
		LOCAL lcText
		lcText = RTRIM(tcBuf, 1, " ", CHR(9), CHR(13), CHR(10))
		DO CASE
		CASE tcEngine == "?"
		CASE EMPTY(tcEngine)
			toDef.cSql = lcText
			toDef.nLine = tnLine
		CASE EMPTY(lcText)
			This.LoadError("sql_missing", tcFile, tnLine, "the section for " + tcEngine + " has no SQL")
		OTHERWISE
			toDef.oVariants.Add(lcText, tcEngine)
			ADDPROPERTY(toDef, "nLine_" + tcEngine, tnLine)
		ENDCASE
	ENDPROC

	* «-- param: nombre tipo [required] [list] [default <literal>]»
	PROTECTED PROCEDURE ReadParam(toDef, tcVal, tcFile, tnLine)
		LOCAL loPar, lcName, lcType, lnWords, lnW, lcWord, lnAt, lcLit, lvValue, lcRest, lcPrefix
		lcName = GETWORDNUM(tcVal, 1)
		lcType = UPPER(GETWORDNUM(tcVal, 2))
		DO CASE
		CASE !This.oText.IsName(lcName, .F.)
			This.LoadError("param_name_invalid", tcFile, tnLine, "'" + lcName + "' is not a parameter name (a letter or _, then letters, digits or _)")
			RETURN
		CASE " " + LOWER(lcName) + " " $ FqReservedNames()
			lcPrefix = LEFT(STRTRAN(GETWORDNUM(toDef.cName + ".", 1, "."), "_", ""), 4)
			This.LoadError("param_reserved", tcFile, tnLine, LOWER(lcName) + "; use " + LOWER(IIF(EMPTY(lcPrefix), "p", lcPrefix)) + "_" + LOWER(lcName) + ;
				" (it is a member of the object of parameters: a None of FoxNone is a Custom)")
			RETURN
		CASE toDef.oParams.GetKey(LOWER(lcName)) > 0
			This.LoadError("param_duplicate", tcFile, tnLine, lcName + " is declared twice")
			RETURN
		CASE EMPTY(lcType) OR !(" " + lcType + " " $ FQ_TYPES) OR LEN(lcType) # 1
			This.LoadError("param_type_invalid", tcFile, tnLine, "the type of " + lcName + " is '" + lcType + "': it is one of" + RTRIM(FQ_TYPES))
			RETURN
		ENDCASE
		loPar = CREATEOBJECT("QueryParam")
		loPar.cName = lcName
		loPar.cType = lcType
		* Las opciones, en cualquier orden; default se lleva el resto de la línea.
		lcRest = This.AfterWords(tcVal, 2)
		DO WHILE !EMPTY(lcRest)
			lcWord = LOWER(GETWORDNUM(lcRest, 1))
			DO CASE
			CASE lcWord == "required"
				loPar.lRequired = .T.
			CASE lcWord == "list"
				loPar.lList = .T.
			CASE lcWord == "default"
				lcLit = ALLTRIM(SUBSTR(lcRest, 8))
				lvValue = .NULL.
				IF EMPTY(lcLit) OR !This.ReadLiteral(lcLit, lcType, @lvValue)
					This.LoadError("default_type", tcFile, tnLine, "the default of " + lcName + " (" + lcLit + ") is not a " + lcType + " literal")
					RETURN
				ENDIF
				loPar.vDefault = lvValue
				loPar.lHasDefault = .T.
				EXIT
			OTHERWISE
				This.LoadError("param_flag_invalid", tcFile, tnLine, "'" + lcWord + "' after the type of " + lcName + ": it is required, list or default <literal>")
				RETURN
			ENDCASE
			lcRest = ALLTRIM(SUBSTR(lcRest, LEN(lcWord) + 1))
		ENDDO
		IF loPar.lList AND loPar.lHasDefault
			This.LoadError("default_type", tcFile, tnLine, lcName + " is a list, and a list takes no default")
			RETURN
		ENDIF
		toDef.oParams.Add(loPar, LOWER(lcName))
	ENDPROC

	* Un literal de default: número, 'cadena' o "cadena", {} o {^aaaa-mm-dd[ hh:mm[:ss]]}, .T./.F., .NULL.
	* Se lee a mano: no se evalúa nada del fichero.
	PROTECTED FUNCTION ReadLiteral(tcLit, tcType, rvValue)
		LOCAL lcL, lcIn, lnY, lnM, lnD, lnH, lnMi, lnS, ldD, loErr, llOk, lcTime
		lcL = ALLTRIM(tcLit)
		DO CASE
		CASE UPPER(lcL) == ".NULL."
			rvValue = .NULL.
			RETURN .T.
		CASE INLIST(UPPER(lcL), ".T.", ".F.")
			rvValue = (UPPER(lcL) == ".T.")
			RETURN tcType == "L"
		CASE LEN(lcL) >= 2 AND INLIST(LEFT(lcL, 1), "'", '"') AND RIGHT(lcL, 1) == LEFT(lcL, 1)
			rvValue = SUBSTR(lcL, 2, LEN(lcL) - 2)
			RETURN INLIST(tcType, "C", "M")
		CASE lcL == "{}"
			DO CASE
			CASE tcType == "D"
				rvValue = {}
				RETURN .T.
			CASE tcType == "T"
				rvValue = {/:}
				RETURN .T.
			ENDCASE
			RETURN .F.
		CASE LEFT(lcL, 2) == "{^" AND RIGHT(lcL, 1) == "}"
			lcIn = ALLTRIM(SUBSTR(lcL, 3, LEN(lcL) - 3))
			IF !(SUBSTR(lcIn, 5, 1) == "-" AND SUBSTR(lcIn, 8, 1) == "-") OR !ISDIGIT(LEFT(lcIn, 1))
				RETURN .F.
			ENDIF
			lnY = VAL(LEFT(lcIn, 4))
			lnM = VAL(SUBSTR(lcIn, 6, 2))
			lnD = VAL(SUBSTR(lcIn, 9, 2))
			lcTime = ALLTRIM(SUBSTR(lcIn, 11))
			llOk = .T.
			TRY
				IF EMPTY(lcTime)
					rvValue = DATE(lnY, lnM, lnD)
				ELSE
					lnH = VAL(GETWORDNUM(lcTime, 1, ":"))
					lnMi = VAL(GETWORDNUM(lcTime, 2, ":"))
					lnS = VAL(GETWORDNUM(lcTime, 3, ":"))
					rvValue = DATETIME(lnY, lnM, lnD, lnH, lnMi, lnS)
				ENDIF
			CATCH TO loErr
				llOk = .F.
			ENDTRY
			IF !llOk
				RETURN .F.
			ENDIF
			DO CASE
			CASE tcType == "D"
				RETURN EMPTY(lcTime)
			CASE tcType == "T"
				rvValue = IIF(EMPTY(lcTime), DTOT(rvValue), rvValue)
				RETURN .T.
			ENDCASE
			RETURN .F.
		CASE This.IsNumber(lcL)
			rvValue = VAL(lcL)
			DO CASE
			CASE tcType == "N"
				RETURN .T.
			CASE tcType == "I"
				RETURN rvValue = INT(rvValue)
			CASE tcType == "Y"
				rvValue = NTOM(rvValue)
				RETURN .T.
			ENDCASE
			RETURN .F.
		ENDCASE
		RETURN .F.
	ENDFUNC

	* Lo que queda de una línea después de sus tnWords primeras palabras (espacios y tabuladores las
	* separan), tal cual: un literal entre comillas conserva sus espacios.
	PROTECTED FUNCTION AfterWords(tcVal, tnWords)
		LOCAL lnPos, lnLen, lnW
		lnPos = 1
		lnLen = LEN(tcVal)
		FOR lnW = 1 TO tnWords
			DO WHILE lnPos <= lnLen AND INLIST(SUBSTR(tcVal, lnPos, 1), " ", CHR(9))
				lnPos = lnPos + 1
			ENDDO
			DO WHILE lnPos <= lnLen AND !INLIST(SUBSTR(tcVal, lnPos, 1), " ", CHR(9))
				lnPos = lnPos + 1
			ENDDO
		ENDFOR
		RETURN ALLTRIM(SUBSTR(tcVal, lnPos), 1, " ", CHR(9))
	ENDFUNC

	PROTECTED FUNCTION IsNumber(tcL)
		LOCAL lcL, lnI, lcC, llDigit, llDot
		lcL = IIF(INLIST(LEFT(tcL, 1), "-", "+"), SUBSTR(tcL, 2), tcL)
		llDigit = .F.
		llDot = .F.
		FOR lnI = 1 TO LEN(lcL)
			lcC = SUBSTR(lcL, lnI, 1)
			DO CASE
			CASE ISDIGIT(lcC)
				llDigit = .T.
			CASE lcC == "." AND !llDot
				llDot = .T.
			OTHERWISE
				RETURN .F.
			ENDCASE
		ENDFOR
		RETURN llDigit
	ENDFUNC

	* «-- ident: nombre forma», con forma = digits | letters | alnum | ident y una longitud N o N-M.
	PROTECTED PROCEDURE ReadIdent(toDef, tcVal, tcFile, tnLine)
		LOCAL lcName, lcKind, lcLen, lnDash, lnMin, lnMax, loI
		lcName = GETWORDNUM(tcVal, 1)
		lcKind = LOWER(GETWORDNUM(tcVal, 2))
		lcLen = GETWORDNUM(tcVal, 3)
		lnDash = AT("-", lcLen)
		lnMin = VAL(IIF(lnDash = 0, lcLen, LEFT(lcLen, lnDash - 1)))
		lnMax = VAL(IIF(lnDash = 0, lcLen, SUBSTR(lcLen, lnDash + 1)))
		DO CASE
		CASE GETWORDCOUNT(tcVal) # 3 OR !This.oText.IsName(lcName, .F.) OR !(" " + lcKind + " " $ FQ_IDENT_KINDS) OR ;
				LEN(CHRTRAN(lcLen, "0123456789-", "")) > 0 OR OCCURS("-", lcLen) > 1 OR lnMin < 1 OR lnMax < lnMin
			This.LoadError("ident_form_invalid", tcFile, tnLine, "'-- ident: " + tcVal + "' has no form: a name, then digits, letters, " + ;
				"alnum or ident, and a length (2 or 1-8)")
		CASE toDef.oIdents.GetKey(LOWER(lcName)) > 0
			This.LoadError("ident_form_invalid", tcFile, tnLine, "a second '-- ident: " + lcName + "'")
		OTHERWISE
			loI = CREATEOBJECT("Empty")
			ADDPROPERTY(loI, "cName", lcName)
			ADDPROPERTY(loI, "cKind", lcKind)
			ADDPROPERTY(loI, "nMin", lnMin)
			ADDPROPERTY(loI, "nMax", lnMax)
			ADDPROPERTY(loI, "nLine", tnLine)
			toDef.oIdents.Add(loI, LOWER(lcName))
			toDef.cIdentNames = IIF(EMPTY(toDef.cIdentNames), " ", toDef.cIdentNames) + LOWER(lcName) + " "
		ENDCASE
	ENDPROC

	* «-- sort: col, col…»
	PROTECTED PROCEDURE ReadSort(toDef, tcVal, tcFile, tnLine)
		LOCAL laC[1], lnC, lnI, lcCol
		lnC = ALINES(laC, tcVal, 1 + 4, ",")
		IF lnC = 0
			This.LoadError("bad_option", tcFile, tnLine, "'-- sort:' has no columns")
			RETURN
		ENDIF
		DIMENSION toDef.aSortList[lnC]
		FOR lnI = 1 TO lnC
			lcCol = laC[lnI]
			IF !This.oText.IsName(lcCol, .T.)
				This.LoadError("bad_option", tcFile, tnLine, "'" + lcCol + "' in '-- sort:' is not a column name")
				RETURN
			ENDIF
			toDef.aSortList[lnI] = lcCol
		ENDFOR
		toDef.nSort = lnC
		toDef.nSortLine = tnLine
	ENDPROC

	* Lo que se comprueba de los textos: los :nombre contra los declarados, kind con la guarda, {sort},
	* {if} y las macros. En el común y en cada variante.
	PROTECTED PROCEDURE CheckTexts(toDef, tcFile, tnSortLine)
		LOCAL loUsed, lcText, lnLine, lnV, lcEngine, llSortMacro, loPar, lcFirst, lcProblem, loIdentsUsed, loM, loI, loMarks
		loUsed = CREATEOBJECT("Collection")
		loIdentsUsed = CREATEOBJECT("Collection")
		llSortMacro = .F.
		FOR lnV = 0 TO toDef.oVariants.Count
			IF lnV = 0
				lcEngine = ""
				lcText = toDef.cSql
				lnLine = toDef.nLine
			ELSE
				lcEngine = toDef.oVariants.GetKey(lnV)
				lcText = toDef.oVariants.Item(lnV)
				lnLine = GETPEM(toDef, "nLine_" + lcEngine)
			ENDIF
			This.CheckNames(toDef, lcText, lnLine, tcFile, loUsed)
			lcFirst = This.oGuard.FirstWord(lcText)
			DO CASE
			CASE toDef.cKind == "read" AND !INLIST(lcFirst, "SELECT", "WITH")
				This.LoadError("kind_mismatch", tcFile, lnLine, "the query is read and the text" + IIF(EMPTY(lcEngine), "", " for " + lcEngine) + ;
					" starts with " + IIF(EMPTY(lcFirst), "nothing", lcFirst) + " (a read starts with SELECT or WITH)")
			CASE toDef.cKind == "write" AND INLIST(lcFirst, "SELECT", "WITH")
				This.LoadError("kind_mismatch", tcFile, lnLine, "the query is write and the text" + IIF(EMPTY(lcEngine), "", " for " + lcEngine) + ;
					" starts with " + lcFirst + " (a write starts with INSERT, UPDATE, DELETE, ...)")
			ENDCASE
			lcProblem = This.oText.CheckMarkers(lcText, toDef, This.oMacroNames)
			IF !EMPTY(lcProblem)
				This.LoadError(This.oText.cErrorCode, tcFile, lnLine + This.oText.nErrorLine, lcProblem)
			ENDIF
			IF This.oText.lHasSort
				llSortMacro = .T.
			ENDIF
			loMarks = This.oText.Markers(lcText)
			FOR EACH loM IN loMarks
				IF loM.cName == "ident" AND loIdentsUsed.GetKey(LOWER(loM.cArgs)) = 0
					loIdentsUsed.Add(.T., LOWER(loM.cArgs))
				ENDIF
			ENDFOR
		ENDFOR
		* Un nombre no puede ser identificador y parámetro a la vez, y un identificador que ningún texto usa es un aviso.
		FOR EACH loI IN toDef.oIdents
			DO CASE
			CASE toDef.oParams.GetKey(LOWER(loI.cName)) > 0
				This.LoadError("ident_param_clash", tcFile, loI.nLine, loI.cName + " is both an identifier and a parameter: pick one")
			CASE loIdentsUsed.GetKey(LOWER(loI.cName)) = 0
				This.Warn("ident_unused", tcFile, loI.nLine, loI.cName + " is declared and no text uses it")
			ENDCASE
		ENDFOR
		DO CASE
		CASE toDef.nSort > 0 AND !llSortMacro
			This.LoadError("sort_without_macro", tcFile, tnSortLine, "there is a '-- sort:' and no {sort} in the text")
		CASE toDef.nSort = 0 AND llSortMacro
			This.LoadError("macro_sort_without_list", tcFile, toDef.nLine, "there is a {sort} and no '-- sort:' with the columns it takes")
		CASE llSortMacro AND toDef.oParams.GetKey("sort") > 0
			This.LoadError("param_reserved", tcFile, toDef.nLine, "sort; with {sort} in the text, oParams.sort is the order the caller picks")
		ENDCASE
		FOR EACH loPar IN toDef.oParams
			IF loUsed.GetKey(LOWER(loPar.cName)) = 0
				This.Warn("param_unused", tcFile, toDef.nLine, loPar.cName + " is declared and no text uses it")
			ENDIF
		ENDFOR
	ENDPROC

	* Cada :nombre del texto tiene que estar declarado; apunta los que se usan.
	PROTECTED PROCEDURE CheckNames(toDef, tcText, tnLine, tcFile, toUsed)
		LOCAL loFound, lnI, lcName
		loFound = This.oText.Names(tcText)
		FOR lnI = 1 TO loFound.Count
			lcName = loFound.GetKey(lnI)
			IF toDef.oParams.GetKey(lcName) = 0
				This.LoadError("param_undeclared", tcFile, tnLine + loFound.Item(lnI), ":" + lcName + " is in the text and not in the header ('-- param: " + lcName + " <type>')")
			ENDIF
			IF toUsed.GetKey(lcName) = 0
				toUsed.Add(lcName, lcName)
			ENDIF
		ENDFOR
	ENDPROC

	* ---------------------------------------------------------------- errores

	PROTECTED PROCEDURE ClearLoad
		This.cCheckedEngine = ""
		This.nLoadErrors = 0
		DIMENSION This.aLoadErrors[1, 4]
		This.aLoadErrors = ""
		This.nWarnings = 0
		DIMENSION This.aWarnings[1, 4]
		This.aWarnings = ""
	ENDPROC

	PROTECTED PROCEDURE LoadError(tcCode, tcFile, tnLine, tcMessage)
		This.nLoadErrors = This.nLoadErrors + 1
		DIMENSION This.aLoadErrors[This.nLoadErrors, 4]
		This.aLoadErrors[This.nLoadErrors, 1] = tcCode
		This.aLoadErrors[This.nLoadErrors, 2] = tcFile
		This.aLoadErrors[This.nLoadErrors, 3] = tnLine
		This.aLoadErrors[This.nLoadErrors, 4] = tcCode + ": " + tcMessage
	ENDPROC

	PROTECTED PROCEDURE Warn(tcCode, tcFile, tnLine, tcMessage)
		This.nWarnings = This.nWarnings + 1
		DIMENSION This.aWarnings[This.nWarnings, 4]
		This.aWarnings[This.nWarnings, 1] = tcCode
		This.aWarnings[This.nWarnings, 2] = tcFile
		This.aWarnings[This.nWarnings, 3] = tnLine
		This.aWarnings[This.nWarnings, 4] = tcCode + ": " + tcMessage
	ENDPROC

	PROTECTED FUNCTION Fail(tcCode, tcMessage)
		RETURN This.FailText(tcCode, tcCode + ": " + tcMessage)
	ENDFUNC

	* El fallo con el texto entero de cLastError (el de CheckFile y LoadFile no empieza por el código).
	PROTECTED FUNCTION FailText(tcCode, tcText)
		This.nErrors = This.nErrors + 1
		This.cLastErrorCode = tcCode
		This.cLastError = CHRTRAN(tcText, CHR(13) + CHR(10) + CHR(9), "   ")
		IF This.lStrict
			ERROR This.cLastError
		ENDIF
		RETURN .F.
	ENDFUNC

	PROTECTED PROCEDURE ClearLastError
		This.cLastError = ""
		This.cLastErrorCode = ""
	ENDPROC
ENDDEFINE


* ======================================================================== *
* QueryCompiler: compila una carpeta de .sql a un .fq. Es un QueryStore: carga la carpeta como
* LoadFolder (todo o nada, los mismos códigos), con las macros del cliente dadas antes con AddMacro, y
* escribe por cada consulta su cabecera ya leída y sus siete textos ya resueltos por motor.
*
* El formato, texto delimitado, en CP1252 como los .sql:
*   registros separados por CHR(30), campos por CHR(31)
*   1. la cabecera: FQ1 | versión del formato (2) | fecha y hora (TTOC(…, 3)) | versión de FoxQuery |
*      cifrado (1/0) | cuántas consultas | el IV en hexadecimal (vacío sin cifrar) | la longitud del cuerpo
*      en bytes (lo que va entre la cabecera y el HMAC)
*   2. una por consulta, sin cifrar: nombre | kind | descripción | fichero | línea | parámetros | sort |
*      y los siete textos, en el orden sqlserver mysql mariadb postgresql firebird sqlite vfp: «T» y el
*      texto (la variante o el común, macros expandidas, huecos de {limit}/{offset}, {if}/{sort}/listas tal
*      cual), o «E» y el código, CHR(29) y el motivo donde ese motor no puede
*        parámetros: uno tras otro separados por CHR(29), cada uno nombre CHR(28) tipo CHR(28) flags (R
*        required, L list) CHR(28) default («D» y FqValueText, o vacío)
*        sort: las columnas de «-- sort:» separadas por CHR(29)
*      cifrado: el cuerpo (las consultas unidas por CHR(30)) en AES-256 CBC con la clave SHA-256(cKey) y el
*      IV de la cabecera, en binario tal cual (decodificar base64 haría Load mucho más lento): se corta por
*      la longitud de la cabecera, no por CHR(30)
*   3. el último: el HMAC-SHA256, en hexadecimal, de todos los bytes de delante (sin el CHR(30) que lo
*      separa), con la clave FqCatalogMacKey(cKey o la fija). Primero se cifra y después se firma.
* ======================================================================== *
DEFINE CLASS QueryCompiler AS QueryStore
	cFq = ""               && el último .fq escrito

	* .T. si escribió el .fq; si no, .F. con el error (y los de carga en aLoadErrors, como LoadFolder).
	FUNCTION Build(tcFolder, tcFq, tcKey, tlEncrypt)
		LOCAL lcKey, llStrict, lnErrors, lcError, lcCode, lcBody, loDef, lcRec, lcIv, lcCipher, lcHead, lcContent, lcMac, ;
			lcSafety, loErr, llOk, lnWritten, lcFolder
		lcKey = IIF(VARTYPE(tcKey) == "C", tcKey, "")
		This.cFq = ""
		IF tlEncrypt AND EMPTY(lcKey)
			RETURN This.Fail("catalog_key_required", "an encrypted catalog needs your key: with the fixed key of the library it hides nothing")
		ENDIF
		IF VARTYPE(tcFq) # "C" OR EMPTY(tcFq)
			RETURN This.Fail("catalog_invalid", "Build needs the name of the .fq to write")
		ENDIF
		IF !This.LoadFolder(tcFolder)
			RETURN .F.
		ENDIF
		* Lo que un motor no puede, Build lo guarda en el .fq como aviso y sigue. Los errores de
		* EngineText no cuentan.
		llStrict = This.lStrict
		lnErrors = This.nErrors
		lcError = This.cLastError
		lcCode = This.cLastErrorCode
		This.lStrict = .F.
		lcBody = ""
		llOk = .T.
		FOR EACH loDef IN This.oQueries
			lcRec = This.CatalogRecord(loDef)
			IF ISNULL(lcRec)
				llOk = .F.
				EXIT
			ENDIF
			lcBody = lcBody + IIF(EMPTY(lcBody), "", CHR(30)) + lcRec
		ENDFOR
		* nWarningsLoaded se queda en lo que fijó LoadFolder: los avisos de las celdas E van detrás, y un CheckEngine
		* después de Build los repone en vez de sumarlos.
		This.lStrict = llStrict
		This.nErrors = lnErrors
		This.cLastError = lcError
		This.cLastErrorCode = lcCode
		IF !llOk
			RETURN This.Fail("catalog_invalid", loDef.cName + " has a character the .fq uses as a separator (CHR(28) to CHR(31))")
		ENDIF
		lcIv = ""
		IF tlEncrypt
			lcIv = FqCryptoRandom(16)
			lcCipher = FqCryptoAes(FqCryptoSha256(lcKey), lcIv, lcBody, .T.)
			IF ISNULL(lcCipher)
				RETURN This.Fail("catalog_invalid", "CryptoAPI did not encrypt the catalog")
			ENDIF
			lcBody = lcCipher
		ENDIF
		lcHead = FQ_MAGIC + CHR(31) + FQ_FORMAT + CHR(31) + TTOC(DATETIME(), 3) + CHR(31) + This.cVersion + CHR(31) + ;
			IIF(tlEncrypt, "1", "0") + CHR(31) + TRANSFORM(This.oQueries.Count) + CHR(31) + STRCONV(lcIv, 15) + CHR(31) + TRANSFORM(LEN(lcBody))
		lcContent = lcHead + CHR(30) + lcBody
		lcMac = FqCryptoHmac(FqCatalogMacKey(lcKey), lcContent)
		IF EMPTY(lcMac)
			RETURN This.Fail("catalog_invalid", "CryptoAPI did not sign the catalog")
		ENDIF
		* STRTOFILE no lanza nada cuando no puede escribir (el .fq abierto en un editor de VFP, con FOPEN, por
		* otro proceso, de solo lectura, o una carpeta que no existe): devuelve 0 y el fichero queda como estaba.
		* Por eso se compara lo que devuelve con lo que se manda; si no, Build diría .T. sin haber escrito nada.
		lcContent = lcContent + CHR(30) + STRCONV(lcMac, 15)
		* Con la carpeta que no existe, STRTOFILE también devuelve 0 sin lanzar nada, y el mensaje de los bytes
		* mandaría a buscar un editor. Se mira antes de escribir y se dice la carpeta, como la escribió el usuario.
		* DIRECTORY con 1, porque una carpeta oculta también vale; sin FULLPATH, que busca en SET PATH.
		lcFolder = JUSTPATH(tcFq)
		IF !EMPTY(lcFolder) AND !DIRECTORY(lcFolder, 1)
			RETURN This.Fail("catalog_not_written", "the catalog could not be written to " + tcFq + ": the folder " + lcFolder + " does not exist")
		ENDIF
		lcSafety = SET("SAFETY")
		lnWritten = -1
		loErr = .NULL.
		SET SAFETY OFF
		TRY
			lnWritten = STRTOFILE(lcContent, tcFq)
		CATCH TO loErr
		FINALLY
			SET SAFETY &lcSafety
		ENDTRY
		IF !ISNULL(loErr) OR lnWritten # LEN(lcContent)
			RETURN This.Fail("catalog_not_written", "the catalog could not be written to " + tcFq + ": " + ;
				TRANSFORM(MAX(lnWritten, 0)) + " of " + TRANSFORM(LEN(lcContent)) + " bytes (is the file open in an editor, or read-only?)" + ;
				IIF(ISNULL(loErr), "", ": " + loErr.Message))
		ENDIF
		This.cFq = tcFq
		RETURN .T.
	ENDFUNC

	* El registro de una consulta (sin cifrar), o .NULL. si algo lleva un separador del .fq.
	PROTECTED FUNCTION CatalogRecord(toDef)
		LOCAL lcP, loPar, lcS, lnI, laE[1], lnE, lcText, lcRec, lcCell, loI
		lcP = ""
		FOR EACH loPar IN toDef.oParams
			lcP = lcP + IIF(EMPTY(lcP), "", CHR(29)) + loPar.cName + CHR(28) + loPar.cType + CHR(28) + ;
				IIF(loPar.lRequired, "R", "") + IIF(loPar.lList, "L", "") + CHR(28) + IIF(loPar.lHasDefault, "D" + FqValueText(loPar.vDefault), "")
		ENDFOR
		* Las «-- ident:» van con los parámetros, con el tipo @forma (digits, letters…), la longitud y su línea; un
		* .fq de antes no lleva ninguna y se lee igual (el formato no cambia de versión).
		FOR EACH loI IN toDef.oIdents
			lcP = lcP + IIF(EMPTY(lcP), "", CHR(29)) + loI.cName + CHR(28) + "@" + loI.cKind + CHR(28) + ;
				TRANSFORM(loI.nMin) + "-" + TRANSFORM(loI.nMax) + CHR(28) + "L" + TRANSFORM(loI.nLine)
		ENDFOR
		lcS = ""
		FOR lnI = 1 TO toDef.nSort
			lcS = lcS + IIF(lnI = 1, "", CHR(29)) + toDef.aSortList[lnI]
		ENDFOR
		IF This.HasSeparator(toDef.cName + toDef.cKind + toDef.cDescription + toDef.cFile) OR This.HasSeparator(CHRTRAN(lcP, CHR(28) + CHR(29), "")) OR ;
				This.HasSeparator(CHRTRAN(lcS, CHR(29), ""))
			RETURN .NULL.
		ENDIF
		lcRec = toDef.cName + CHR(31) + toDef.cKind + CHR(31) + toDef.cDescription + CHR(31) + toDef.cFile + CHR(31) + ;
			TRANSFORM(toDef.nLine) + CHR(31) + lcP + CHR(31) + lcS
		lnE = ALINES(laE, FQ_ENGINE_ORDER, 1, " ")
		FOR lnI = 1 TO lnE
			lcText = This.EngineText(toDef, laE[lnI])
			IF ISNULL(lcText)
				lcText = SUBSTR(This.cLastError, LEN(This.cLastErrorCode) + 3)
				This.WarnEngine(toDef, laE[lnI], This.cLastErrorCode, lcText)     && se guarda en el .fq y se avisa
				lcCell = "E" + This.cLastErrorCode + CHR(29) + lcText
			ELSE
				lcCell = "T" + lcText
			ENDIF
			IF This.HasSeparator(lcText)
				RETURN .NULL.
			ENDIF
			lcRec = lcRec + CHR(31) + lcCell
		ENDFOR
		RETURN lcRec
	ENDFUNC

	PROTECTED FUNCTION HasSeparator(tcText)
		RETURN !(tcText == CHRTRAN(tcText, CHR(28) + CHR(29) + CHR(30) + CHR(31), ""))
	ENDFUNC
ENDDEFINE


* ======================================================================== *
* QueryExecutor: lo común de los ejecutores de la librería (QueryOdbc y QueryLocal). Cumple el contrato
* que QueryStore espera: cEngine, Query(cSql, cCursor, oParams), Execute(cSql, oParams) y
* Scalar(cSql, oParams), con nErrors y cLastError. Se pueden llamar a pelo, con el texto y el objeto
* del usuario: antes de tocar el motor se comprueba que cada :nombre del texto está en el objeto
* (PEMSTATUS(…, 5), nunca TYPE()); un nombre que falta es param_missing y no llega nada al motor, que
* en un SQLEXEC abriría «View Parameter», un diálogo modal que TRY no atrapa.
* ======================================================================== *
DEFINE CLASS QueryExecutor AS Custom
	cEngine = ""
	lStrict = .F.
	nErrors = 0
	cLastError = ""
	cLastErrorCode = ""
	cLastSql = ""          && el último texto que se mandó al motor, ya reescrito

	PROTECTED oText
	oText = .NULL.

	PROCEDURE Init
		This.oText = CREATEOBJECT("QueryText")
	ENDPROC

	* Qué llamadas dejan el área que estaba seleccionada. Run no: deja el cursor de la consulta
	* seleccionado, como SELECT … INTO CURSOR y SQLEXEC, y el usuario sigue con BROWSE o SCAN. Scalar y
	* Execute sí: su cursor se cierra, y el área vacía que queda no le sirve a nadie.
	PROTECTED FUNCTION KeepsArea(tcCall)
		RETURN !(tcCall == "run")
	ENDFUNC

	* El área seleccionada y si tenía algo abierto, para AreaBack.
	PROTECTED FUNCTION AreaNow
		RETURN TRANSFORM(SELECT()) + "|" + IIF(EMPTY(ALIAS()), "0", "1")
	ENDFUNC

	* Después de tcCall, el área de antes si esa llamada la repone (KeepsArea); si estaba vacía, SELECT 0 (una vacía: el
	* número de antes puede tener ya un cursor). El puntero de las tablas no se toca: un UPDATE de VFP lo mueve siempre.
	PROTECTED PROCEDURE AreaBack(tcWas, tcCall)
		IF !This.KeepsArea(tcCall)
			RETURN
		ENDIF
		IF GETWORDNUM(tcWas, 2, "|") == "1"
			SELECT (VAL(GETWORDNUM(tcWas, 1, "|")))
		ELSE
			SELECT 0
		ENDIF
	ENDPROC

	* Lo que se comprueba antes de tocar el motor. Devuelve el texto como lo ejecutará el método que
	* llama (y en roArgs el Empty con los :nombre del texto, que ese método guarda en una local suya), o
	* .NULL. con el error puesto.
	PROTECTED FUNCTION Ready(tcSql, toParams, roArgs)
		LOCAL loNames, loArgs, lnI, lcName, lcSql
		This.cLastSql = ""
		IF VARTYPE(tcSql) # "C" OR EMPTY(tcSql)
			=This.Fail("sql_missing", "there is no SQL to run")
			RETURN .NULL.
		ENDIF
		IF !This.CanRun()
			RETURN .NULL.
		ENDIF
		loNames = This.oText.Names(tcSql)
		IF !This.NamesThere(loNames, toParams)
			RETURN .NULL.
		ENDIF
		* Una copia con lo que el texto usa, nada más: el objeto del llamador no se toca ni llega al motor.
		loArgs = CREATEOBJECT("Empty")
		FOR lnI = 1 TO loNames.Count
			lcName = loNames.GetKey(lnI)
			IF VARTYPE(toParams) == "O" AND PEMSTATUS(toParams, lcName, 5)
				ADDPROPERTY(loArgs, lcName, This.ToEngine(GETPEM(toParams, lcName)))
			ENDIF
		ENDFOR
		lcSql = This.Rewritten(tcSql, loNames)
		This.cLastSql = lcSql
		roArgs = loArgs
		RETURN lcSql
	ENDFUNC

	PROTECTED FUNCTION NamesThere(toNames, toParams)
		LOCAL lnI, lcName
		FOR lnI = 1 TO toNames.Count
			lcName = toNames.GetKey(lnI)
			IF !(VARTYPE(toParams) == "O" AND PEMSTATUS(toParams, lcName, 5))
				RETURN This.Fail("param_missing", ":" + lcName + " is in the text and the object of parameters has no " + lcName + ;
					" (nothing was sent to the engine)")
			ENDIF
		ENDFOR
		RETURN .T.
	ENDFUNC

	* Cada ejecutor dice si puede correr y cómo queda el texto.
	PROTECTED FUNCTION CanRun
		RETURN .T.
	ENDFUNC

	PROTECTED FUNCTION Rewritten(tcSql, toNames)
		RETURN tcSql
	ENDFUNC

	* El valor como lo tiene que recibir el motor.
	PROTECTED FUNCTION ToEngine(tvValue)
		RETURN tvValue
	ENDFUNC

	PROTECTED FUNCTION Fail(tcCode, tcMessage)
		This.nErrors = This.nErrors + 1
		This.cLastErrorCode = tcCode
		This.cLastError = CHRTRAN(tcCode + ": " + tcMessage, CHR(13) + CHR(10) + CHR(9), "   ")
		IF This.lStrict
			ERROR This.cLastError
		ENDIF
		RETURN .F.
	ENDFUNC
ENDDEFINE


* ======================================================================== *
* QueryOdbc: el handle a pelo del usuario (el de SQLCONNECT o SQLSTRINGCONNECT). La librería no
* conecta, no desconecta y no cambia ninguna propiedad del handle: las transacciones, DispWarnings y
* lo demás son del usuario, con SQLSETPROP, SQLCOMMIT y SQLROLLBACK sobre su handle.
*
*   loDb = CREATEOBJECT("QueryOdbc", lnHandle)     && o loDb.nHandle = lnHandle, o loDb.Attach(lnHandle)
*   ? loDb.cEngine                                 && detectado por el driver: sqlite, sqlserver…
*
* cEngine escrito manda: si ya tiene algo cuando llega el handle, no se detecta; y escrito después de
* la detección, se queda lo escrito. Vacío, se pregunta SQL_DBMS_NAME al driver (SQLGetInfo, 17) y se
* traduce con EngineFromDbmsName(); otro nombre es engine_unknown y el usuario escribe cEngine él.
* :nombre se reescribe a ?loFqArgs.nombre dentro del método que hace el SQLEXEC, con el Empty en esa
* local. En SQLite, las cadenas van a UTF-8 en esa copia y las columnas de texto vuelven a
* CP1252.
* ======================================================================== *
DEFINE CLASS QueryOdbc AS QueryExecutor
	nHandle = 0
	cDbmsName = ""         && lo que dijo el driver (SQL_DBMS_NAME, 17) en la última detección
	cDriver = ""           && el fichero del driver (SQL_DRIVER_NAME, 6), informativo: en MySQL importa más que el motor

	PROTECTED cDetected
	cDetected = ""         && el cEngine que puso la detección (si sigue igual, otro handle detecta otra vez)

	PROCEDURE Init(tnHandle, tcEngine)
		DODEFAULT()
		IF VARTYPE(tcEngine) == "C" AND !EMPTY(tcEngine)
			This.cEngine = LOWER(ALLTRIM(tcEngine))
		ENDIF
		IF VARTYPE(tnHandle) == "N" AND tnHandle > 0
			This.nHandle = tnHandle
		ENDIF
	ENDPROC

	* El handle del usuario. .T. si queda listo (con cEngine).
	FUNCTION Attach(tnHandle)
		This.nHandle = tnHandle
		RETURN This.nHandle > 0 AND !EMPTY(This.cEngine)
	ENDFUNC

	* Asignar el handle detecta el motor, salvo que cEngine lo haya escrito el usuario.
	PROCEDURE nHandle_Assign(tnHandle)
		This.nHandle = IIF(VARTYPE(tnHandle) == "N", tnHandle, 0)
		IF This.nHandle > 0 AND (EMPTY(This.cEngine) OR This.cEngine == This.cDetected)
			=This.Detect()
		ENDIF
	ENDPROC

	* Pregunta el motor al driver del handle. .T. si lo reconoce (y lo deja en cEngine).
	FUNCTION Detect
		LOCAL lnHdbc, lcEngine, loErr
		This.cDbmsName = ""
		This.cDriver = ""
		lnHdbc = 0
		TRY
			lnHdbc = SQLGETPROP(This.nHandle, "ODBChdbc")
		CATCH TO loErr
			lnHdbc = 0
		ENDTRY
		IF VARTYPE(lnHdbc) # "N" OR lnHdbc <= 0
			IF This.cEngine == This.cDetected
				This.cEngine = ""
				This.cDetected = ""
			ENDIF
			RETURN This.Fail("not_connected", "the handle " + TRANSFORM(This.nHandle) + " is not an open connection of SQLCONNECT or SQLSTRINGCONNECT")
		ENDIF
		This.cDbmsName = This.Info(lnHdbc, 17)
		This.cDriver = This.Info(lnHdbc, 6)
		lcEngine = This.EngineFromDbmsName(This.cDbmsName)
		IF EMPTY(lcEngine)
			IF This.cEngine == This.cDetected
				This.cEngine = ""
				This.cDetected = ""
			ENDIF
			RETURN This.Fail("engine_unknown", "the ODBC driver (" + This.cDriver + ") says the engine is '" + This.cDbmsName + ;
				"'; write cEngine yourself, one of" + RTRIM(FQ_ENGINES))
		ENDIF
		This.cEngine = lcEngine
		This.cDetected = lcEngine
		RETURN .T.
	ENDFUNC

	* SQL_DBMS_NAME -> cEngine. Pura: "" si no conoce el nombre.
	FUNCTION EngineFromDbmsName(tcName)
		LOCAL lcName
		lcName = IIF(VARTYPE(tcName) == "C", LOWER(ALLTRIM(tcName)), "")
		DO CASE
		CASE lcName == "microsoft sql server"
			RETURN "sqlserver"
		CASE lcName == "mariadb"
			RETURN "mariadb"
		CASE lcName == "mysql"
			RETURN "mysql"
		CASE lcName == "postgresql"
			RETURN "postgresql"
		CASE lcName == "firebird"
			RETURN "firebird"
		CASE lcName == "sqlite"
			RETURN "sqlite"
		ENDCASE
		RETURN ""
	ENDFUNC

	* Una consulta a un cursor (vacío: c_fr_query, como FoxRemote, para que el cursor no cambie con el ejecutor). .T. o .F.
	FUNCTION Query(tcSql, tcCursor, toParams)
		LOCAL loFqArgs, lcSql, lcCursor, lnR, laCount[1], loErr, lcArea
		lcCursor = IIF(VARTYPE(tcCursor) == "C" AND !EMPTY(tcCursor), ALLTRIM(tcCursor), "c_fr_query")
		lcArea = This.AreaNow()
		loFqArgs = .NULL.
		lcSql = This.Ready(tcSql, toParams, @loFqArgs)
		IF ISNULL(lcSql)
			RETURN .F.
		ENDIF
		TRY
			lnR = SQLEXEC(This.nHandle, lcSql, lcCursor, laCount)
		CATCH TO loErr
			lnR = -1
		ENDTRY
		This.AreaBack(lcArea, "run")
		IF lnR < 1
			RETURN This.OdbcFail(loErr)
		ENDIF
		This.FromServerText(lcCursor)
		RETURN .T.
	ENDFUNC

	* Las filas que tocó (las que cuenta el driver en la segunda columna de aCountInfo;
	* 0 si no lo dice), o -1.
	FUNCTION Execute(tcSql, toParams)
		LOCAL loFqArgs, lcSql, lcCursor, lnR, laCount[1], loErr, lnRows, lnI, lcArea
		lcArea = This.AreaNow()
		loFqArgs = .NULL.
		lcSql = This.Ready(tcSql, toParams, @loFqArgs)
		IF ISNULL(lcSql)
			RETURN -1
		ENDIF
		lcCursor = SYS(2015)
		TRY
			lnR = SQLEXEC(This.nHandle, lcSql, lcCursor, laCount)
		CATCH TO loErr
			lnR = -1
		ENDTRY
		IF USED(lcCursor)
			USE IN (lcCursor)
		ENDIF
		This.AreaBack(lcArea, "execute")
		IF lnR < 1
			=This.OdbcFail(loErr)
			RETURN -1
		ENDIF
		lnRows = 0
		IF ALEN(laCount, 2) >= 2
			FOR lnI = 1 TO ALEN(laCount, 1)
				IF VARTYPE(laCount[lnI, 2]) == "N" AND laCount[lnI, 2] > 0
					lnRows = lnRows + laCount[lnI, 2]
				ENDIF
			ENDFOR
		ENDIF
		RETURN lnRows
	ENDFUNC

	* El primer campo de la primera fila; sin filas, .NULL. sin error. Si falla, .NULL. y nErrors sube.
	FUNCTION Scalar(tcSql, toParams)
		LOCAL loFqArgs, lcSql, lcCursor, lnR, loErr, lvValue, laF[1], lcArea
		lcArea = This.AreaNow()
		lvValue = .NULL.
		loFqArgs = .NULL.
		lcSql = This.Ready(tcSql, toParams, @loFqArgs)
		IF ISNULL(lcSql)
			RETURN .NULL.
		ENDIF
		lcCursor = SYS(2015)
		TRY
			lnR = SQLEXEC(This.nHandle, lcSql, lcCursor)
			IF lnR >= 1 AND USED(lcCursor)
				This.FromServerText(lcCursor)
				IF !EOF(lcCursor) AND FCOUNT(lcCursor) > 0
					lvValue = EVALUATE(lcCursor + "." + FIELD(1, lcCursor))
					=AFIELDS(laF, lcCursor)
					lvValue = This.BigIntValue(lvValue, laF[1, 2], laF[1, 3])
				ENDIF
			ENDIF
		CATCH TO loErr
			lnR = -1
		FINALLY
			IF USED(lcCursor)
				USE IN (lcCursor)
			ENDIF
			This.AreaBack(lcArea, "scalar")
		ENDTRY
		IF lnR < 1
			=This.OdbcFail(loErr)
			RETURN .NULL.
		ENDIF
		RETURN lvValue
	ENDFUNC

	PROTECTED FUNCTION CanRun
		IF This.nHandle < 1
			RETURN This.Fail("not_connected", "there is no handle: Attach(nHandle) with the one of SQLCONNECT or SQLSTRINGCONNECT")
		ENDIF
		IF EMPTY(This.cEngine)
			RETURN This.Detect()
		ENDIF
		RETURN .T.
	ENDFUNC

	* :nombre -> ?loFqArgs.nombre: loFqArgs es la local de Query, Execute y Scalar.
	PROTECTED FUNCTION Rewritten(tcSql, toNames)
		RETURN This.oText.Style(tcSql, "loFqArgs")
	ENDFUNC

	* SQLite guarda UTF-8 y su driver pasa los bytes tal cual: las cadenas, a UTF-8 en la copia.
	PROTECTED FUNCTION ToEngine(tvValue)
		IF This.cEngine == "sqlite" AND VARTYPE(tvValue) == "C"
			RETURN STRCONV(tvValue, 9)
		ENDIF
		RETURN tvValue
	ENDFUNC

	* AERROR tras un SQLEXEC negativo: «error N: mensaje ODBC». Nada por pantalla.
	PROTECTED FUNCTION OdbcFail(toErr)
		LOCAL laErr[1], lcMsg
		DO CASE
		CASE VARTYPE(toErr) == "O"
			lcMsg = "error " + TRANSFORM(toErr.ErrorNo) + ": " + toErr.Message
		CASE AERROR(laErr) > 0
			lcMsg = "error " + TRANSFORM(laErr[1, 1]) + ": " + TRANSFORM(laErr[1, 2])
		OTHERWISE
			lcMsg = "the statement failed and the driver said nothing"
		ENDCASE
		RETURN This.Fail("query_failed", lcMsg)
	ENDFUNC

	* Una propiedad del driver por SQLGetInfo, o "".
	PROTECTED FUNCTION Info(tnHdbc, tnType)
		LOCAL lcBuf, lnLen, lnR, loErr
		lcBuf = REPLICATE(CHR(0), 256)
		lnLen = 0
		lnR = -1
		TRY
			DECLARE SHORT SQLGetInfo IN odbc32 AS FqSqlGetInfo INTEGER hdbc, SHORT nInfoType, STRING @cBuf, SHORT nBufLen, SHORT @nLen
			lnR = FqSqlGetInfo(tnHdbc, tnType, @lcBuf, 256, @lnLen)
		CATCH TO loErr
			lnR = -1
		ENDTRY
		RETURN IIF(INLIST(lnR, 0, 1), LEFT(lcBuf, MAX(MIN(lnLen, 255), 0)), "")
	ENDFUNC

	* SQLite: las columnas de texto del cursor, de UTF-8 a CP1252.
	PROTECTED PROCEDURE FromServerText(tcAlias)
		LOCAL laF[1], lnI, laText[1], lnT, lcField, lvValue, lnSelect
		IF !(This.cEngine == "sqlite") OR !USED(tcAlias)
			RETURN
		ENDIF
		lnT = 0
		FOR lnI = 1 TO AFIELDS(laF, tcAlias)
			IF INLIST(laF[lnI, 2], "C", "M", "V")
				lnT = lnT + 1
				DIMENSION laText[lnT]
				laText[lnT] = laF[lnI, 1]
			ENDIF
		ENDFOR
		IF lnT = 0
			RETURN
		ENDIF
		lnSelect = SELECT()
		SELECT (tcAlias)
		SCAN
			FOR lnI = 1 TO lnT
				lcField = laText[lnI]
				lvValue = EVALUATE(lcField)
				IF !ISNULL(lvValue) AND !EMPTY(lvValue)
					REPLACE (lcField) WITH STRCONV(lvValue, 11)
				ENDIF
			ENDFOR
		ENDSCAN
		GO TOP
		SELECT (lnSelect)
	ENDPROC

	* VFP recibe un BIGINT como C(20): se devuelve como número.
	PROTECTED FUNCTION BigIntValue(tvValue, tcType, tnWidth)
		IF INLIST(tcType, "C", "V") AND BETWEEN(tnWidth, 19, 21) AND VARTYPE(tvValue) == "C" AND !EMPTY(tvValue) ;
				AND EMPTY(CHRTRAN(ALLTRIM(tvValue), "0123456789-", ""))
			RETURN VAL(tvValue)
		ENDIF
		RETURN tvValue
	ENDFUNC
ENDDEFINE


* ======================================================================== *
* QueryLocal: el dialecto vfp sobre DBF. Las tablas las resuelve VFP como siempre (el alias
* abierto, SET PATH, la base de datos abierta): la librería no abre ni cierra tablas ni sesiones.
* :nombre se reescribe a loFqArgs.nombre y la sentencia corre por macro dentro del propio método que
* tiene el Empty en esa local (EXECSCRIPT no la vería: error 13). Mientras corre, SET ANSI ON
* (con OFF, city = 'Os' casa con 'Oslo'), y después se deja como estaba, también si falla. Igual
* SET DELETED ON: una fila borrada no existe en ningún servidor, y el mismo .sql tiene que dar las
* mismas filas en los siete dialectos; con lDeletedOn = .F. no se toca. Con lAnsiOn = .F., SET ANSI
* tampoco: ANSI ON es un 30 a 40 % más lento en joins grandes sobre DBF, y el usuario puede preferir el suyo.
* Y siempre SET TABLEPROMPT OFF: una tabla que no está da el error 1 (query_failed) en vez del diálogo
* «Abrir», que dejaría el programa esperando a una persona. Y SYS(3055, 2040): con el 320 de VFP, una
* lista de más de 158 elementos da el error 1812 sobre DBF, y en los servidores va. Las líneas de
* comentario («--») del texto se quitan, y los saltos de línea se cambian por espacios: una macro se corta
* en el primer CR.
* ======================================================================== *
DEFINE CLASS QueryLocal AS QueryExecutor
	cEngine = "vfp"
	lDeletedOn = .T.       && SET DELETED ON mientras corre (y como estaba después)
	lAnsiOn = .T.          && SET ANSI ON mientras corre (y como estaba después); .F., no se toca

	PROTECTED oGuard
	oGuard = .NULL.

	PROCEDURE Init
		DODEFAULT()
		This.oGuard = CREATEOBJECT("QueryKindGuard")
	ENDPROC

	* Fijo: los DBF hablan el dialecto vfp.
	PROCEDURE cEngine_Assign(tvValue)
	ENDPROC

	* Una SELECT a un cursor (vacío: c_fr_query, como FoxRemote, para que el cursor no cambie con el ejecutor). .T. o .F.
	FUNCTION Query(tcSql, tcCursor, toParams)
		LOCAL loFqArgs, lcFqSql, lcFqCursor, lcSets, llOk, loErr, lcFqArea
		lcFqCursor = IIF(VARTYPE(tcCursor) == "C" AND !EMPTY(tcCursor), ALLTRIM(tcCursor), "c_fr_query")
		lcFqArea = This.AreaNow()
		loFqArgs = .NULL.
		lcFqSql = This.Ready(tcSql, toParams, @loFqArgs)
		IF ISNULL(lcFqSql)
			RETURN .F.
		ENDIF
		lcFqSql = lcFqSql + FQ_LOCAL_INTO
		This.cLastSql = lcFqSql
		IF LEN(lcFqSql) > FQ_VFP_LINE
			RETURN This.Fail("sql_too_long", This.TooLong(lcFqSql))
		ENDIF
		llOk = .F.
		lcSets = This.SetsOn()
		TRY
			&lcFqSql
			llOk = .T.
		CATCH TO loErr
			llOk = .F.
		FINALLY
			This.SetsBack(lcSets)
			This.AreaBack(lcFqArea, "run")
		ENDTRY
		IF !llOk
			RETURN This.Fail("query_failed", "error " + TRANSFORM(loErr.ErrorNo) + ": " + loErr.Message)
		ENDIF
		RETURN .T.
	ENDFUNC

	* Un INSERT, UPDATE o DELETE local: las filas que tocó (_TALLY), o -1. Una SELECT no: sin INTO
	* abriría una ventana. INSERT … VALUES no toca _TALLY (solo INSERT … SELECT): se marca antes y,
	* si sigue con la marca, fue una fila. La marca se lee tal como queda: _TALLY = -1 guarda
	* 4294967295.
	FUNCTION Execute(tcSql, toParams)
		LOCAL loFqArgs, lcFqSql, lcSets, lnRows, loErr, lcFirst, lnMark, lcFqArea
		lcFqArea = This.AreaNow()
		loFqArgs = .NULL.
		lcFqSql = This.Ready(tcSql, toParams, @loFqArgs)
		IF ISNULL(lcFqSql)
			RETURN -1
		ENDIF
		lcFirst = This.oGuard.FirstWord(lcFqSql)
		IF INLIST(lcFirst, "SELECT", "WITH")
			=This.Fail("wrong_kind", "Execute() runs INSERT, UPDATE or DELETE; a SELECT goes to Query() or Scalar()")
			RETURN -1
		ENDIF
		IF LEN(lcFqSql) > FQ_VFP_LINE
			=This.Fail("sql_too_long", This.TooLong(lcFqSql))
			RETURN -1
		ENDIF
		lnRows = -1
		lcSets = This.SetsOn()
		TRY
			_TALLY = -1
			lnMark = _TALLY
			&lcFqSql
			lnRows = IIF(_TALLY = lnMark, IIF(lcFirst == "INSERT", 1, 0), _TALLY)
		CATCH TO loErr
			lnRows = -1
		FINALLY
			This.SetsBack(lcSets)
			This.AreaBack(lcFqArea, "execute")
		ENDTRY
		IF lnRows < 0
			=This.Fail("query_failed", "error " + TRANSFORM(loErr.ErrorNo) + ": " + loErr.Message)
		ENDIF
		RETURN lnRows
	ENDFUNC

	* El primer campo de la primera fila; sin filas, .NULL. sin error. Si falla, .NULL. y nErrors sube.
	FUNCTION Scalar(tcSql, toParams)
		LOCAL loFqArgs, lcFqSql, lcFqCursor, lcSets, llOk, loErr, lvValue, lcFqArea
		lcFqArea = This.AreaNow()
		lvValue = .NULL.
		loFqArgs = .NULL.
		lcFqSql = This.Ready(tcSql, toParams, @loFqArgs)
		IF ISNULL(lcFqSql)
			RETURN .NULL.
		ENDIF
		lcFqCursor = SYS(2015)
		lcFqSql = lcFqSql + FQ_LOCAL_INTO
		This.cLastSql = lcFqSql
		IF LEN(lcFqSql) > FQ_VFP_LINE
			=This.Fail("sql_too_long", This.TooLong(lcFqSql))
			RETURN .NULL.
		ENDIF
		llOk = .F.
		lcSets = This.SetsOn()
		TRY
			&lcFqSql
			IF !EOF(lcFqCursor) AND FCOUNT(lcFqCursor) > 0
				lvValue = EVALUATE(lcFqCursor + "." + FIELD(1, lcFqCursor))
			ENDIF
			llOk = .T.
		CATCH TO loErr
			llOk = .F.
		FINALLY
			IF USED(lcFqCursor)
				USE IN (lcFqCursor)
			ENDIF
			This.SetsBack(lcSets)
			This.AreaBack(lcFqArea, "scalar")
		ENDTRY
		IF !llOk
			=This.Fail("query_failed", "error " + TRANSFORM(loErr.ErrorNo) + ": " + loErr.Message)
			RETURN .NULL.
		ENDIF
		RETURN lvValue
	ENDFUNC

	* :nombre -> loFqArgs.nombre (sin ?: es una expresión de VFP), sin las líneas de comentario, y los
	* saltos de línea a espacios.
	PROTECTED FUNCTION Rewritten(tcSql, toNames)
		LOCAL loMap, lnI, lcName
		loMap = CREATEOBJECT("Collection")
		FOR lnI = 1 TO toNames.Count
			lcName = toNames.GetKey(lnI)
			loMap.Add("loFqArgs." + lcName, lcName)
		ENDFOR
		RETURN CHRTRAN(This.oText.WithoutCommentLines(This.oText.Rewrite(tcSql, loMap, "")), CHR(13) + CHR(10), "  ")
	ENDFUNC

	* Por qué un texto no corre en vfp, con su longitud y el límite.
	PROTECTED FUNCTION TooLong(tcSql)
		RETURN "the statement is " + TRANSFORM(LEN(tcSql)) + " characters as QueryLocal runs it, and VFP runs " + ;
			TRANSFORM(FQ_VFP_LINE) + " at most in one line (a longer one stops with error 18, Line is too long); a long list makes it grow: give fewer elements, or " + ;
			"write a shorter -- engine: vfp text"
	ENDFUNC

	* Con lAnsiOn, SET ANSI ON; con lDeletedOn, SET DELETED ON; SET TABLEPROMPT OFF; y SYS(3055, 2040)
	* (SYS(3055) devuelve un número). Devuelve cómo estaban, para SetsBack.
	PROTECTED FUNCTION SetsOn
		LOCAL lcWas
		lcWas = SET("ANSI") + "|" + SET("DELETED") + "|" + SET("TABLEPROMPT") + "|" + TRANSFORM(SYS(3055))
		IF This.lAnsiOn
			SET ANSI ON
		ENDIF
		IF This.lDeletedOn
			SET DELETED ON
		ENDIF
		SET TABLEPROMPT OFF
		=SYS(3055, 2040)
		RETURN lcWas
	ENDFUNC

	PROTECTED PROCEDURE SetsBack(tcWas)
		LOCAL lcAnsi, lcDeleted, lcPrompt
		lcAnsi = GETWORDNUM(tcWas, 1, "|")
		lcDeleted = GETWORDNUM(tcWas, 2, "|")
		lcPrompt = GETWORDNUM(tcWas, 3, "|")
		SET ANSI &lcAnsi
		SET DELETED &lcDeleted
		SET TABLEPROMPT &lcPrompt
		=SYS(3055, VAL(GETWORDNUM(tcWas, 4, "|")))
	ENDPROC
ENDDEFINE


* ======================================================================== *
* QueryText: el resolutor. No conoce el almacén: recibe el texto, el QueryDef y el objeto del llamador.
* ======================================================================== *
DEFINE CLASS QueryText AS Custom
	cErrorCode = ""
	cError = ""
	nErrorLine = 0         && en CheckMarkers: la línea del problema, contada desde la primera del texto
	lHasSort = .F.

	* Un nombre: una letra o _, y después letras, dígitos o _. Con tlDotted,
	* además puntos (una columna calificada, c.name).
	FUNCTION IsName(tcName, tlDotted)
		LOCAL lnI, lcC
		IF VARTYPE(tcName) # "C" OR EMPTY(tcName) OR !(ISALPHA(LEFT(tcName, 1)) OR LEFT(tcName, 1) == "_")
			RETURN .F.
		ENDIF
		FOR lnI = 2 TO LEN(tcName)
			lcC = SUBSTR(tcName, lnI, 1)
			IF !(ISALPHA(lcC) OR ISDIGIT(lcC) OR lcC == "_" OR (tlDotted AND lcC == "." AND SUBSTR(tcName, lnI + 1, 1) # "."))
				RETURN .F.
			ENDIF
		ENDFOR
		RETURN !(tlDotted AND RIGHT(tcName, 1) == ".")
	ENDFUNC

	* Los :nombre del texto, fuera de comillas ' y ", y el
	* :: de PostgreSQL se deja. Collection nombre en minúsculas -> línea (desde 0) de la primera vez.
	FUNCTION Names(tcText)
		LOCAL loFound, lnI, lnLen, lcCh, lcQuote, lnJ, lcName
		loFound = CREATEOBJECT("Collection")
		lcQuote = ""
		lnLen = LEN(tcText)
		lnI = 1
		DO WHILE lnI <= lnLen
			lcCh = SUBSTR(tcText, lnI, 1)
			DO CASE
			CASE !EMPTY(lcQuote)
				IF lcCh == lcQuote
					lcQuote = ""
				ENDIF
				lnI = lnI + 1
			CASE INLIST(lcCh, "'", '"')
				lcQuote = lcCh
				lnI = lnI + 1
			CASE lcCh == ":" AND SUBSTR(tcText, lnI + 1, 1) == ":"
				lnI = lnI + 2
			CASE lcCh == ":" AND (ISALPHA(SUBSTR(tcText, lnI + 1, 1)) OR SUBSTR(tcText, lnI + 1, 1) == "_")
				lnJ = lnI + 1
				DO WHILE lnJ <= lnLen AND (ISALPHA(SUBSTR(tcText, lnJ, 1)) OR ISDIGIT(SUBSTR(tcText, lnJ, 1)) OR SUBSTR(tcText, lnJ, 1) == "_")
					lnJ = lnJ + 1
				ENDDO
				lcName = LOWER(SUBSTR(tcText, lnI + 1, lnJ - lnI - 1))
				IF loFound.GetKey(lcName) = 0
					loFound.Add(OCCURS(CHR(10), LEFT(tcText, lnI)), lcName)
				ENDIF
				lnI = lnJ
			OTHERWISE
				lnI = lnI + 1
			ENDCASE
		ENDDO
		RETURN loFound
	ENDFUNC

	* Cambia cada :nombre (con la misma regla) por lo que diga toMap (nombre -> texto) o, si no está,
	* por el estilo: "" lo deja, "?" da ?nombre, otro da ?<estilo>.nombre.
	FUNCTION Rewrite(tcText, toMap, tcStyle)
		LOCAL lcOut, lnI, lnLen, lcCh, lcQuote, lnJ, lcName, lnAt
		IF !(":" $ tcText)
			RETURN tcText
		ENDIF
		lcOut = ""
		lcQuote = ""
		lnLen = LEN(tcText)
		lnI = 1
		DO WHILE lnI <= lnLen
			lcCh = SUBSTR(tcText, lnI, 1)
			DO CASE
			CASE !EMPTY(lcQuote)
				IF lcCh == lcQuote
					lcQuote = ""
				ENDIF
				lcOut = lcOut + lcCh
				lnI = lnI + 1
			CASE INLIST(lcCh, "'", '"')
				lcQuote = lcCh
				lcOut = lcOut + lcCh
				lnI = lnI + 1
			CASE lcCh == ":" AND SUBSTR(tcText, lnI + 1, 1) == ":"
				lcOut = lcOut + "::"
				lnI = lnI + 2
			CASE lcCh == ":" AND (ISALPHA(SUBSTR(tcText, lnI + 1, 1)) OR SUBSTR(tcText, lnI + 1, 1) == "_")
				lnJ = lnI + 1
				DO WHILE lnJ <= lnLen AND (ISALPHA(SUBSTR(tcText, lnJ, 1)) OR ISDIGIT(SUBSTR(tcText, lnJ, 1)) OR SUBSTR(tcText, lnJ, 1) == "_")
					lnJ = lnJ + 1
				ENDDO
				lcName = SUBSTR(tcText, lnI + 1, lnJ - lnI - 1)
				lnAt = IIF(VARTYPE(toMap) == "O", toMap.GetKey(LOWER(lcName)), 0)
				DO CASE
				CASE lnAt > 0
					lcOut = lcOut + toMap.Item(lnAt)
				CASE EMPTY(tcStyle)
					lcOut = lcOut + ":" + lcName
				CASE tcStyle == "?"
					lcOut = lcOut + "?" + lcName
				OTHERWISE
					lcOut = lcOut + "?" + tcStyle + "." + lcName
				ENDCASE
				lnI = lnJ
			OTHERWISE
				lcOut = lcOut + lcCh
				lnI = lnI + 1
			ENDCASE
		ENDDO
		RETURN lcOut
	ENDFUNC

	FUNCTION Style(tcText, tcStyle)
		RETURN This.Rewrite(tcText, .NULL., tcStyle)
	ENDFUNC

	* Las marcas {…} del texto, fuera de comillas: devuelve una Collection de objetos con nStart, nEnd
	* (posiciones de { y }), cName (en minúsculas) y cArgs. Los literales de fecha de VFP ({^…}, {},
	* {/…}) y las secuencias de escape de ODBC ({fn …}, {d …}, {ts …}, …) no son marcas.
	FUNCTION Markers(tcText)
		LOCAL loList, lnI, lnLen, lcCh, lcQuote, lnEnd, lcIn, lcName, lcNext, loM
		loList = CREATEOBJECT("Collection")
		lcQuote = ""
		lnLen = LEN(tcText)
		lnI = 1
		DO WHILE lnI <= lnLen
			lcCh = SUBSTR(tcText, lnI, 1)
			DO CASE
			CASE !EMPTY(lcQuote)
				IF lcCh == lcQuote
					lcQuote = ""
				ENDIF
			CASE INLIST(lcCh, "'", '"')
				lcQuote = lcCh
			CASE lcCh == "{"
				lnEnd = AT("}", SUBSTR(tcText, lnI))
				lnEnd = IIF(lnEnd = 0, 0, lnI + lnEnd - 1)
				lcNext = SUBSTR(tcText, lnI + 1, 1)
				IF !INLIST(lcNext, "^", "}", "/")
					lcIn = IIF(lnEnd = 0, SUBSTR(tcText, lnI + 1), SUBSTR(tcText, lnI + 1, lnEnd - lnI - 1))
					lcName = LOWER(GETWORDNUM(ALLTRIM(lcIn), 1))
					IF !(" " + lcName + " " $ FQ_ODBC_ESCAPES)
						loM = CREATEOBJECT("Empty")
						ADDPROPERTY(loM, "nStart", lnI)
						ADDPROPERTY(loM, "nEnd", lnEnd)
						ADDPROPERTY(loM, "cName", lcName)
						ADDPROPERTY(loM, "cArgs", ALLTRIM(SUBSTR(ALLTRIM(lcIn), LEN(lcName) + 1)))
						loList.Add(loM)
					ENDIF
				ENDIF
				IF lnEnd > 0
					lnI = lnEnd
				ENDIF
			ENDCASE
			lnI = lnI + 1
		ENDDO
		RETURN loList
	ENDFUNC

	* Al cargar: {if :p}…{endif} emparejados y sin anidar, {sort} con su defecto de la lista, y que cada
	* macro la tenga algún motor. Devuelve "" o el problema (con cErrorCode y nErrorLine).
	FUNCTION CheckMarkers(tcText, toDef, toMacroNames)
		LOCAL loList, loM, llOpen, lcSpec, lcSort, lnLimits, lcProblem, loLimit
		lnLimits = 0
		loLimit = .NULL.
		This.cErrorCode = ""
		This.nErrorLine = 0
		This.lHasSort = .F.
		loList = This.Markers(tcText)
		llOpen = .F.
		FOR EACH loM IN loList
			This.nErrorLine = OCCURS(CHR(10), LEFT(tcText, loM.nStart))
			DO CASE
			CASE loM.nEnd = 0
				This.cErrorCode = "if_unbalanced"
				RETURN "a { without its }"
			CASE loM.cName == "if"
				IF llOpen
					This.cErrorCode = "if_unbalanced"
					RETURN "an {if} inside another {if} (they do not nest)"
				ENDIF
				IF !(LEFT(loM.cArgs, 1) == ":") OR !This.IsName(SUBSTR(loM.cArgs, 2), .F.)
					This.cErrorCode = "if_unbalanced"
					RETURN "{if " + loM.cArgs + "}: an {if} takes one parameter, {if :name}"
				ENDIF
				llOpen = .T.
			CASE loM.cName == "endif"
				IF !llOpen
					This.cErrorCode = "if_unbalanced"
					RETURN "an {endif} without its {if}"
				ENDIF
				llOpen = .F.
			CASE loM.cName == "sort"
				This.lHasSort = .T.
				IF !EMPTY(loM.cArgs) AND toDef.nSort > 0
					lcSort = This.SortClause(loM.cArgs, toDef)
					IF ISNULL(lcSort)
						This.cErrorCode = "bad_option"
						RETURN "{sort " + loM.cArgs + "}: " + This.cError
					ENDIF
				ENDIF
			CASE loM.cName == "limit"
				lnLimits = lnLimits + 1
				lcProblem = This.LimitArgProblem(loM.cArgs, toDef)
				DO CASE
				CASE lnLimits > 1
					This.cErrorCode = "limit_arg_invalid"
					RETURN "a query takes one {limit}"
				CASE !EMPTY(lcProblem)
					This.cErrorCode = "limit_arg_invalid"
					RETURN "{limit " + loM.cArgs + "}: " + lcProblem
				CASE !This.HasOrderBy(LEFT(tcText, loM.nStart - 1))
					This.cErrorCode = "limit_without_order_by"
					RETURN "{limit} needs an ORDER BY before it (SQL Server and VFP ask for it; the seven do, so the same rows come out)"
				ENDCASE
				loLimit = loM
			CASE loM.cName == "ident"
				IF !This.IsName(loM.cArgs, .F.) OR toDef.oIdents.GetKey(LOWER(loM.cArgs)) = 0
					This.cErrorCode = "ident_undeclared"
					RETURN "{ident " + loM.cArgs + "} is in the text and not in the header ('-- ident: " + loM.cArgs + " digits 2')"
				ENDIF
			CASE loM.cName == "offset"
				lcProblem = This.LimitArgProblem(loM.cArgs, toDef)
				DO CASE
				CASE VARTYPE(loLimit) # "O" OR !EMPTY(CHRTRAN(SUBSTR(tcText, loLimit.nEnd + 1, loM.nStart - loLimit.nEnd - 1), " " + CHR(9) + CHR(13) + CHR(10), ""))
					This.cErrorCode = "offset_without_limit"
					RETURN "{offset} goes right after {limit}"
				CASE !EMPTY(lcProblem)
					This.cErrorCode = "limit_arg_invalid"
					RETURN "{offset " + loM.cArgs + "}: " + lcProblem
				ENDCASE
			CASE VARTYPE(toMacroNames) # "O" OR toMacroNames.GetKey(loM.cName) = 0
				This.cErrorCode = "macro_unknown"
				RETURN "{" + loM.cName + "} is not a macro of any engine (AddMacro adds one)"
			ENDCASE
		ENDFOR
		IF llOpen
			This.cErrorCode = "if_unbalanced"
			RETURN "an {if} without its {endif}"
		ENDIF
		This.nErrorLine = 0
		RETURN ""
	ENDFUNC

	* Las macros de un motor: {nombre a, b} -> su plantilla con $1, $2 (y $*, todos). Antes, {limit} y
	* {offset} (ExpandLimit). Deja if, endif y sort.
	FUNCTION ExpandMacros(tcText, tcEngine, toMacros)
		LOCAL loList, lnI, loM, lcOut, lnAt, lcTpl, laArgs[1], lnArgs, lnK, lnStar, lcSep, lcAfter, lcJoin
		This.cErrorCode = ""
		This.cError = ""
		lcOut = This.ExpandLimit(tcText, tcEngine)
		IF ISNULL(lcOut)
			RETURN .NULL.
		ENDIF
		loList = This.Markers(lcOut)
		* De atrás adelante: las posiciones de las de delante no se mueven.
		FOR lnI = loList.Count TO 1 STEP -1
			loM = loList.Item(lnI)
			IF " " + loM.cName + " " $ FQ_MARKS OR loM.nEnd = 0
				LOOP
			ENDIF
			lnAt = toMacros.GetKey(tcEngine + "|" + loM.cName)
			IF lnAt = 0
				This.cErrorCode = "macro_unknown"
				This.cError = "{" + loM.cName + "} has no template for " + tcEngine
				RETURN .NULL.
			ENDIF
			lcTpl = toMacros.Item(lnAt)
			lnArgs = This.SplitArgs(loM.cArgs, @laArgs)
			* $*[sep]: todos los argumentos, unidos por sep (", " sin corchetes).
			lnStar = AT("$*", lcTpl)
			IF lnStar > 0
				lcSep = ", "
				lcAfter = SUBSTR(lcTpl, lnStar + 2)
				IF LEFT(lcAfter, 1) == "[" AND AT("]", lcAfter) > 0
					lcSep = SUBSTR(lcAfter, 2, AT("]", lcAfter) - 2)
					lcAfter = SUBSTR(lcAfter, AT("]", lcAfter) + 1)
				ENDIF
				lcJoin = ""
				FOR lnK = 1 TO lnArgs
					lcJoin = lcJoin + IIF(lnK = 1, "", lcSep) + laArgs[lnK]
				ENDFOR
				lcTpl = LEFT(lcTpl, lnStar - 1) + lcJoin + lcAfter
			ENDIF
			FOR lnK = MIN(lnArgs, 9) TO 1 STEP -1
				lcTpl = STRTRAN(lcTpl, "$" + TRANSFORM(lnK), laArgs[lnK])
			ENDFOR
			lcOut = LEFT(lcOut, loM.nStart - 1) + lcTpl + SUBSTR(lcOut, loM.nEnd + 1)
		ENDFOR
		RETURN lcOut
	ENDFUNC

	* {limit n} y {offset k} para un motor: la cláusula de cada motor, con el número escrito si es
	* un literal del .sql o con un hueco (CHR(1) nombre CHR(1)) si es un parámetro, que Bind rellena después
	* de la caché. En vfp, {limit} se quita y va TOP n detrás de SELECT [DISTINCT|ALL] (con UNION, el TOP del
	* primer SELECT recorta el resultado entero, como LIMIT al final); {offset}, y TOP 0, no existen en vfp:
	* macro_unsupported.
	FUNCTION ExpandLimit(tcText, tcEngine)
		LOCAL loList, loM, loLimit, loOffset, lcN, lcK, lcClause, lnEnd, lcOut, lnSel
		loLimit = .NULL.
		loOffset = .NULL.
		loList = This.Markers(tcText)
		FOR EACH loM IN loList
			DO CASE
			CASE loM.cName == "limit" AND ISNULL(loLimit)
				loLimit = loM
			CASE loM.cName == "offset" AND ISNULL(loOffset)
				loOffset = loM
			ENDCASE
		ENDFOR
		IF ISNULL(loLimit)
			RETURN tcText
		ENDIF
		lcN = This.LimitValue(loLimit.cArgs)
		lcK = IIF(ISNULL(loOffset), "", This.LimitValue(loOffset.cArgs))
		lnEnd = IIF(ISNULL(loOffset), loLimit.nEnd, loOffset.nEnd)
		DO CASE
		CASE tcEngine == "sqlserver"
			lcClause = "OFFSET " + IIF(EMPTY(lcK), "0", lcK) + " ROWS FETCH NEXT " + lcN + " ROWS ONLY"
		CASE tcEngine == "firebird"
			lcClause = IIF(EMPTY(lcK), "ROWS " + lcN, "OFFSET " + lcK + " ROWS FETCH NEXT " + lcN + " ROWS ONLY")
		CASE tcEngine == "vfp"
			IF !ISNULL(loOffset)
				This.cErrorCode = "macro_unsupported"
				This.cError = "{offset} in vfp: VFP does not skip rows (TOP has no offset)"
				RETURN .NULL.
			ENDIF
			IF lcN == "0"
				This.cErrorCode = "macro_unsupported"
				This.cError = "{limit 0} in vfp: TOP 0 does not exist (error 1866)"
				RETURN .NULL.
			ENDIF
			lcOut = LEFT(tcText, loLimit.nStart - 1) + SUBSTR(tcText, lnEnd + 1)
			lnSel = This.AfterSelect(lcOut)
			IF lnSel = 0
				This.cErrorCode = "macro_unsupported"
				This.cError = "{limit} in vfp needs the statement to start with SELECT (TOP goes behind it)"
				RETURN .NULL.
			ENDIF
			RETURN LEFT(lcOut, lnSel - 1) + " TOP " + lcN + SUBSTR(lcOut, lnSel)
		OTHERWISE
			lcClause = "LIMIT " + lcN + IIF(EMPTY(lcK), "", " OFFSET " + lcK)
		ENDCASE
		RETURN LEFT(tcText, loLimit.nStart - 1) + lcClause + SUBSTR(tcText, lnEnd + 1)
	ENDFUNC

	* El argumento de {limit}/{offset} como va en el texto: el entero literal, o el hueco del parámetro.
	FUNCTION LimitValue(tcArgs)
		LOCAL lcArg
		lcArg = ALLTRIM(tcArgs)
		IF LEFT(lcArg, 1) == ":"
			RETURN CHR(1) + LOWER(SUBSTR(lcArg, 2)) + CHR(1)
		ENDIF
		RETURN lcArg
	ENDFUNC

	* Los huecos de {limit}/{offset} como :nombre (lo que enseña Sql sin parámetros).
	FUNCTION HolesAsNames(tcText)
		LOCAL lcOut, lnA, lnB
		lcOut = tcText
		DO WHILE CHR(1) $ lcOut
			lnA = AT(CHR(1), lcOut)
			lnB = AT(CHR(1), lcOut, 2)
			lcOut = LEFT(lcOut, lnA - 1) + ":" + SUBSTR(lcOut, lnA + 1, lnB - lnA - 1) + SUBSTR(lcOut, lnB + 1)
		ENDDO
		RETURN lcOut
	ENDFUNC

	* "" si el argumento de {limit}/{offset} vale: un parámetro declarado N o I (no lista), o un entero.
	FUNCTION LimitArgProblem(tcArgs, toDef)
		LOCAL lcArg, lnAt, loPar
		lcArg = ALLTRIM(tcArgs)
		DO CASE
		CASE EMPTY(lcArg)
			RETURN "it takes a parameter (:rows) or a whole number"
		CASE LEFT(lcArg, 1) == ":"
			lnAt = IIF(This.IsName(SUBSTR(lcArg, 2), .F.), toDef.oParams.GetKey(LOWER(SUBSTR(lcArg, 2))), 0)
			IF lnAt = 0
				RETURN SUBSTR(lcArg, 2) + " is not a declared parameter"
			ENDIF
			loPar = toDef.oParams.Item(lnAt)
			IF !INLIST(loPar.cType, "N", "I") OR loPar.lList
				RETURN SUBSTR(lcArg, 2) + " is declared " + loPar.cType + IIF(loPar.lList, " list", "") + "; it has to be N or I"
			ENDIF
		CASE !EMPTY(CHRTRAN(lcArg, "0123456789", ""))
			RETURN lcArg + " is neither a parameter nor a whole number"
		ENDCASE
		RETURN ""
	ENDFUNC

	* ¿Hay un ORDER BY en el texto, fuera de comillas y de comentarios --?
	FUNCTION HasOrderBy(tcText)
		LOCAL lcCode, lnI, lnLen, lcCh, lcQuote
		lcCode = ""
		lcQuote = ""
		lnLen = LEN(tcText)
		lnI = 1
		DO WHILE lnI <= lnLen
			lcCh = SUBSTR(tcText, lnI, 1)
			DO CASE
			CASE !EMPTY(lcQuote)
				IF lcCh == lcQuote
					lcQuote = ""
				ENDIF
				lcCh = " "
			CASE INLIST(lcCh, "'", '"')
				lcQuote = lcCh
				lcCh = " "
			CASE lcCh == "-" AND SUBSTR(tcText, lnI + 1, 1) == "-"
				DO WHILE lnI <= lnLen AND !INLIST(SUBSTR(tcText, lnI, 1), CHR(13), CHR(10))
					lnI = lnI + 1
				ENDDO
				lcCh = " "
			ENDCASE
			lcCode = lcCode + lcCh
			lnI = lnI + 1
		ENDDO
		lcCode = " " + UPPER(CHRTRAN(lcCode, CHR(9) + CHR(13) + CHR(10) + "()", "     ")) + " "
		DO WHILE "  " $ lcCode
			lcCode = STRTRAN(lcCode, "  ", " ")
		ENDDO
		RETURN " ORDER BY " $ lcCode
	ENDFUNC

	* Dónde va TOP en una SELECT de vfp: la posición detrás de SELECT (y de DISTINCT o ALL si van), o 0
	* si la sentencia no empieza por SELECT (las líneas de comentario de delante no cuentan).
	FUNCTION AfterSelect(tcText)
		LOCAL lnI, lnLen, lcCh, lcWord, lnStart
		lnLen = LEN(tcText)
		lnI = 1
		DO WHILE lnI <= lnLen
			lcCh = SUBSTR(tcText, lnI, 1)
			DO CASE
			CASE INLIST(lcCh, " ", CHR(9), CHR(13), CHR(10))
				lnI = lnI + 1
			CASE lcCh == "-" AND SUBSTR(tcText, lnI + 1, 1) == "-"
				DO WHILE lnI <= lnLen AND !INLIST(SUBSTR(tcText, lnI, 1), CHR(13), CHR(10))
					lnI = lnI + 1
				ENDDO
			OTHERWISE
				EXIT
			ENDCASE
		ENDDO
		IF !(UPPER(SUBSTR(tcText, lnI, 6)) == "SELECT") OR ISALPHA(SUBSTR(tcText, lnI + 6, 1))
			RETURN 0
		ENDIF
		lnI = lnI + 6
		lnStart = lnI
		DO WHILE lnI <= lnLen AND INLIST(SUBSTR(tcText, lnI, 1), " ", CHR(9), CHR(13), CHR(10))
			lnI = lnI + 1
		ENDDO
		lcWord = UPPER(GETWORDNUM(SUBSTR(tcText, lnI, 20), 1))
		IF INLIST(lcWord, "DISTINCT", "ALL")
			RETURN lnI + LEN(lcWord)
		ENDIF
		RETURN lnStart
	ENDFUNC

	* Los argumentos de una macro, separados por comas fuera de paréntesis y de comillas.
	FUNCTION SplitArgs(tcArgs, raArgs)
		LOCAL lnN, lnI, lcCh, lnDepth, lcQuote, lcCur
		lnN = 0
		IF EMPTY(tcArgs)
			RETURN 0
		ENDIF
		lnDepth = 0
		lcQuote = ""
		lcCur = ""
		FOR lnI = 1 TO LEN(tcArgs)
			lcCh = SUBSTR(tcArgs, lnI, 1)
			DO CASE
			CASE !EMPTY(lcQuote)
				IF lcCh == lcQuote
					lcQuote = ""
				ENDIF
			CASE INLIST(lcCh, "'", '"')
				lcQuote = lcCh
			CASE lcCh == "("
				lnDepth = lnDepth + 1
			CASE lcCh == ")"
				lnDepth = lnDepth - 1
			CASE lcCh == "," AND lnDepth = 0
				lnN = lnN + 1
				DIMENSION raArgs[lnN]
				raArgs[lnN] = ALLTRIM(lcCur)
				lcCur = ""
				LOOP
			ENDCASE
			lcCur = lcCur + lcCh
		ENDFOR
		lnN = lnN + 1
		DIMENSION raArgs[lnN]
		raArgs[lnN] = ALLTRIM(lcCur)
		RETURN lnN
	ENDFUNC

	* Lo que depende de cada llamada: (1) los {if :p}…{endif} por presencia de p en el objeto del
	* llamador, (2) {sort} contra la lista declarada con oParams.sort, (3) cada lista :p a :p_1, :p_2…
	* (toLists: nombre -> cuántos). Sin objeto (Sql), los {if} se quitan y {sort} toma su defecto.
	FUNCTION Resolve(tcText, toDef, toParams, toLists, tcEngine)
		LOCAL loList, lnI, loM, lcOut, lnEndif, lcName, llKeep, lcSpec, lcSort, loMap, lnK, lcItems, lnN, loEnd, loPos
		This.cErrorCode = ""
		This.cError = ""
		lcOut = tcText
		* En vfp, {sort} va por la posición de cada columna en la lista del SELECT.
		loPos = .NULL.
		IF VARTYPE(tcEngine) == "C" AND tcEngine == "vfp" AND toDef.nSort > 0 AND "{sort" $ LOWER(tcText)
			loPos = This.SortPositions(tcText, toDef)
			IF ISNULL(loPos)
				RETURN .NULL.
			ENDIF
		ENDIF
		loList = This.Markers(lcOut)
		* De atrás adelante, como las macros.
		lnEndif = 0
		FOR lnI = loList.Count TO 1 STEP -1
			loM = loList.Item(lnI)
			DO CASE
			CASE loM.cName == "endif"
				lnEndif = lnI
			CASE loM.cName == "if"
				lcName = SUBSTR(loM.cArgs, 2)
				llKeep = VARTYPE(toParams) == "O" AND PEMSTATUS(toParams, lcName, 5)
				IF lnEndif > 0
					loEnd = loList.Item(lnEndif)
					lcOut = LEFT(lcOut, loM.nStart - 1) + ;
						IIF(llKeep, SUBSTR(lcOut, loM.nEnd + 1, loEnd.nStart - loM.nEnd - 1), "") + ;
						SUBSTR(lcOut, loEnd.nEnd + 1)
				ENDIF
				lnEndif = 0
			CASE loM.cName == "sort" AND lnEndif = 0
				lcSort = This.SortFor(loM.cArgs, toDef, toParams, loPos)
				IF ISNULL(lcSort)
					RETURN .NULL.
				ENDIF
				lcOut = LEFT(lcOut, loM.nStart - 1) + lcSort + SUBSTR(lcOut, loM.nEnd + 1)
			ENDCASE
		ENDFOR
		* Un {sort} dentro de un {if} que se quedó: otra pasada (el texto ya no tiene {if}).
		IF "{sort" $ LOWER(lcOut)
			loList = This.Markers(lcOut)
			FOR lnI = loList.Count TO 1 STEP -1
				loM = loList.Item(lnI)
				IF loM.cName == "sort"
					lcSort = This.SortFor(loM.cArgs, toDef, toParams, loPos)
					IF ISNULL(lcSort)
						RETURN .NULL.
					ENDIF
					lcOut = LEFT(lcOut, loM.nStart - 1) + lcSort + SUBSTR(lcOut, loM.nEnd + 1)
				ENDIF
			ENDFOR
		ENDIF
		IF VARTYPE(toLists) == "O" AND toLists.Count > 0
			loMap = CREATEOBJECT("Collection")
			FOR lnK = 1 TO toLists.Count
				lcName = toLists.GetKey(lnK)
				lnN = toLists.Item(lnK)
				lcItems = ""
				FOR lnI = 1 TO lnN
					lcItems = lcItems + IIF(lnI = 1, "", ", ") + ":" + lcName + "_" + TRANSFORM(lnI)
				ENDFOR
				loMap.Add(lcItems, lcName)
			ENDFOR
			lcOut = This.Rewrite(lcOut, loMap, "")
		ENDIF
		RETURN lcOut
	ENDFUNC

	* El ORDER BY de una llamada: oParams.sort si lo trae, si no el defecto de la marca, si no la
	* primera columna de la lista. toPos: las posiciones de SortPositions (vfp), o nada.
	FUNCTION SortFor(tcSpec, toDef, toParams, toPos)
		LOCAL lcSpec, lvSort
		lcSpec = IIF(EMPTY(tcSpec), toDef.aSortList[1], tcSpec)
		IF VARTYPE(toParams) == "O" AND PEMSTATUS(toParams, "sort", 5)
			lvSort = GETPEM(toParams, "sort")
			DO CASE
			CASE ISNULL(lvSort) OR (VARTYPE(lvSort) == "C" AND EMPTY(lvSort))
			CASE VARTYPE(lvSort) == "C"
				lcSpec = lvSort
			OTHERWISE
				This.cErrorCode = "bad_option"
				This.cError = "sort is " + VARTYPE(lvSort) + "; it is text: a column of '-- sort:' and ASC or DESC"
				RETURN .NULL.
			ENDCASE
		ENDIF
		RETURN This.SortClause(lcSpec, toDef, toPos)
	ENDFUNC

	* «col [ASC|DESC][, col [ASC|DESC]]…» contra la lista: devuelve las columnas como las escribió la
	* cabecera (nunca el texto del llamador) o .NULL. con bad_option. Con toPos (vfp), la posición de cada
	* columna en la lista del SELECT en vez de su nombre: ORDER BY 2 DESC, 1.
	FUNCTION SortClause(tcSpec, toDef, toPos)
		LOCAL laItems[1], lnN, lnI, lcItem, lcCol, lcDir, lnAt, lcOut, lnW
		This.cErrorCode = ""
		This.cError = ""
		lcOut = ""
		lnN = ALINES(laItems, tcSpec, 1, ",")
		IF lnN = 0
			This.cErrorCode = "bad_option"
			This.cError = "sort is empty"
			RETURN .NULL.
		ENDIF
		FOR lnI = 1 TO lnN
			lcItem = CHRTRAN(laItems[lnI], CHR(9), " ")
			lnW = GETWORDCOUNT(lcItem)
			lcCol = GETWORDNUM(lcItem, 1)
			lcDir = UPPER(GETWORDNUM(lcItem, 2))
			lnAt = ASCAN(toDef.aSortList, lcCol, 1, -1, 1, 7)
			IF lnW = 0 OR lnW > 2 OR lnAt = 0 OR (lnW = 2 AND !INLIST(lcDir, "ASC", "DESC"))
				This.cErrorCode = "bad_option"
				This.cError = "sort '" + ALLTRIM(laItems[lnI]) + "' is not one of the columns of '-- sort:' (" + ;
					This.SortList(toDef) + "), with ASC or DESC"
				RETURN .NULL.
			ENDIF
			lcOut = lcOut + IIF(lnI = 1, "", ", ") + IIF(VARTYPE(toPos) == "O", TRANSFORM(toPos.Item(lnAt)), toDef.aSortList[lnAt]) + IIF(lnW = 2, " " + lcDir, "")
		ENDFOR
		RETURN lcOut
	ENDFUNC

	FUNCTION SortList(toDef)
		LOCAL lcList, lnI
		lcList = ""
		FOR lnI = 1 TO toDef.nSort
			lcList = lcList + IIF(lnI = 1, "", ", ") + toDef.aSortList[lnI]
		ENDFOR
		RETURN lcList
	ENDFUNC

	* La posición de cada columna del «-- sort:» en la lista del SELECT del texto, en el orden de la
	* cabecera; o .NULL. con sort_not_in_select si una no está (o la lista es un *). Una columna casa con un
	* elemento por su nombre o por su expresión entera (a.id con a.id).
	FUNCTION SortPositions(tcText, toDef)
		LOCAL loItems, loPos, loIt, lnI, lnK, lnAt, lcCol, lcList, llStar
		This.cErrorCode = ""
		This.cError = ""
		loItems = This.SelectItems(tcText)
		loPos = CREATEOBJECT("Collection")
		lcList = ""
		llStar = .F.
		IF !ISNULL(loItems)
			FOR EACH loIt IN loItems
				lcList = lcList + IIF(EMPTY(lcList), "", ", ") + loIt.cName
				llStar = llStar OR loIt.cName == "*"
			ENDFOR
		ENDIF
		FOR lnI = 1 TO toDef.nSort
			lcCol = LOWER(toDef.aSortList[lnI])
			lnAt = 0
			IF !ISNULL(loItems)
				FOR lnK = 1 TO loItems.Count
					loIt = loItems.Item(lnK)
					IF loIt.cName == lcCol OR loIt.cExpr == lcCol
						lnAt = lnK
						EXIT
					ENDIF
				ENDFOR
			ENDIF
			IF lnAt = 0
				This.cErrorCode = "sort_not_in_select"
				This.cError = toDef.aSortList[lnI] + " of '-- sort:' is not in the SELECT list (" + IIF(EMPTY(lcList), "none", lcList) + ;
					") of the vfp text" + IIF(llStar, ": a SELECT * has no list to find it in", "") + ;
					"; in vfp, {sort} writes the position of the column in that list (" + ;
					IIF(EMPTY(toDef.cFile), toDef.cName, JUSTFNAME(toDef.cFile) + "(" + TRANSFORM(toDef.nSortLine) + ")") + ")"
				RETURN .NULL.
			ENDIF
			loPos.Add(lnAt)
		ENDFOR
		RETURN loPos
	ENDFUNC

	* La lista del SELECT de un texto. Se mira sin literales ni comentarios --, y lo que va entre
	* paréntesis o llaves es un nivel más. Va del primer SELECT del nivel de fuera (saltando DISTINCT, ALL y
	* TOP n [PERCENT]) al FROM del mismo nivel, partida por las comas de ese nivel; con UNION, es la del primer
	* SELECT. De cada elemento, en minúsculas: cName, lo de detrás del último AS; si no hay AS y hay más de una
	* palabra, la última; si no, lo de detrás del último punto («*» para * o x.*); y cExpr, el elemento sin
	* blancos. .NULL. si el texto no tiene un SELECT en el nivel de fuera.
	FUNCTION SelectItems(tcText)
		LOCAL lcCode, lnLen, lnI, lcCh, lcQuote, lnDepth, lcFlat, lcUp, lnSel, lnStart, lnEnd, lcWord, loItems, ;
			lnA, lcItem, lcItemFlat, lnW, lnK, lcName, loIt, lcWs
		lcWs = " " + CHR(9) + CHR(13) + CHR(10)
		lnLen = LEN(tcText)
		* El código sin literales ni comentarios (los mismos sitios: se cambian por blancos).
		lcCode = ""
		lcQuote = ""
		lnI = 1
		DO WHILE lnI <= lnLen
			lcCh = SUBSTR(tcText, lnI, 1)
			DO CASE
			CASE !EMPTY(lcQuote)
				IF lcCh == lcQuote
					lcQuote = ""
				ENDIF
				lcCh = " "
			CASE INLIST(lcCh, "'", '"')
				lcQuote = lcCh
				lcCh = " "
			CASE lcCh == "-" AND SUBSTR(tcText, lnI + 1, 1) == "-"
				DO WHILE lnI <= lnLen AND !INLIST(SUBSTR(tcText, lnI, 1), CHR(13), CHR(10))
					lcCode = lcCode + " "
					lnI = lnI + 1
				ENDDO
				LOOP
			ENDCASE
			lcCode = lcCode + lcCh
			lnI = lnI + 1
		ENDDO
		* El nivel de fuera: lo que va dentro de () o {} (y los propios signos) se cambia por #.
		lcFlat = ""
		lnDepth = 0
		FOR lnI = 1 TO lnLen
			lcCh = SUBSTR(lcCode, lnI, 1)
			DO CASE
			CASE INLIST(lcCh, "(", "{")
				lnDepth = lnDepth + 1
				lcCh = "#"
			CASE INLIST(lcCh, ")", "}")
				lnDepth = MAX(lnDepth - 1, 0)
				lcCh = "#"
			CASE lnDepth > 0
				lcCh = "#"
			ENDCASE
			lcFlat = lcFlat + lcCh
		ENDFOR
		lcUp = UPPER(CHRTRAN(lcFlat, CHR(9) + CHR(13) + CHR(10), "   "))
		lnSel = This.WordAt(lcUp, "SELECT", 1)
		IF lnSel = 0
			RETURN .NULL.
		ENDIF
		lnStart = lnSel + 6
		DO WHILE .T.
			DO WHILE lnStart <= lnLen AND SUBSTR(lcUp, lnStart, 1) == " "
				lnStart = lnStart + 1
			ENDDO
			lcWord = GETWORDNUM(SUBSTR(lcUp, lnStart, 40), 1)
			DO CASE
			CASE INLIST(lcWord, "DISTINCT", "ALL")
				lnStart = lnStart + LEN(lcWord)
			CASE lcWord == "TOP"
				lnStart = lnStart + 3
				DO WHILE lnStart <= lnLen AND SUBSTR(lcUp, lnStart, 1) == " "
					lnStart = lnStart + 1
				ENDDO
				lnStart = lnStart + LEN(GETWORDNUM(SUBSTR(lcUp, lnStart, 40), 1))
				DO WHILE lnStart <= lnLen AND SUBSTR(lcUp, lnStart, 1) == " "
					lnStart = lnStart + 1
				ENDDO
				IF GETWORDNUM(SUBSTR(lcUp, lnStart, 40), 1) == "PERCENT"
					lnStart = lnStart + 7
				ENDIF
			OTHERWISE
				EXIT
			ENDCASE
		ENDDO
		lnEnd = This.WordAt(lcUp, "FROM", lnStart)
		lnEnd = IIF(lnEnd = 0, lnLen + 1, lnEnd)
		loItems = CREATEOBJECT("Collection")
		lnA = lnStart
		FOR lnI = lnStart TO lnEnd
			IF lnI = lnEnd OR SUBSTR(lcUp, lnI, 1) == ","
				lcItem = ALLTRIM(SUBSTR(tcText, lnA, lnI - lnA), 1, " ", CHR(9), CHR(13), CHR(10))
				lcItemFlat = ALLTRIM(SUBSTR(CHRTRAN(lcFlat, CHR(9) + CHR(13) + CHR(10), "   "), lnA, lnI - lnA))
				lnW = GETWORDCOUNT(lcItemFlat)
				lcName = ""
				FOR lnK = lnW - 1 TO 1 STEP -1
					IF UPPER(GETWORDNUM(lcItemFlat, lnK)) == "AS"
						lcName = GETWORDNUM(lcItemFlat, lnK + 1)
						EXIT
					ENDIF
				ENDFOR
				DO CASE
				CASE !EMPTY(lcName)
				CASE lnW > 1
					lcName = GETWORDNUM(lcItemFlat, lnW)
				CASE lcItemFlat == "*" OR RIGHT(lcItemFlat, 2) == ".*"
					lcName = "*"
				OTHERWISE
					lcName = SUBSTR(lcItemFlat, RAT(".", lcItemFlat) + 1)
				ENDCASE
				loIt = CREATEOBJECT("Empty")
				ADDPROPERTY(loIt, "cName", LOWER(CHRTRAN(lcName, "[]`", "")))
				ADDPROPERTY(loIt, "cExpr", LOWER(CHRTRAN(lcItem, lcWs, "")))
				loItems.Add(loIt)
				lnA = lnI + 1
			ENDIF
		ENDFOR
		RETURN loItems
	ENDFUNC

	* Quita las líneas cuyo primer carácter no blanco es «--» (un comentario del .sql, legítimo en un
	* servidor): VFP no entiende «--». Uno dentro de un literal, también si el literal ocupa varias
	* líneas, se queda. Uno detrás de SQL en la misma línea no se quita (el manual lo dice).
	FUNCTION WithoutCommentLines(tcSql)
		LOCAL laL[1], lnN, lnI, lcOut, lnKept, lcQuote, lcLine, lnC, lcCh
		IF !("--" $ tcSql)
			RETURN tcSql
		ENDIF
		lnN = ALINES(laL, tcSql)
		lcOut = ""
		lnKept = 0
		lcQuote = ""
		FOR lnI = 1 TO lnN
			lcLine = laL[lnI]
			IF EMPTY(lcQuote) AND LEFT(LTRIM(lcLine, 1, " ", CHR(9)), 2) == "--"
				LOOP
			ENDIF
			lnKept = lnKept + 1
			lcOut = lcOut + IIF(lnKept = 1, "", CHR(13) + CHR(10)) + lcLine
			FOR lnC = 1 TO LEN(lcLine)
				lcCh = SUBSTR(lcLine, lnC, 1)
				DO CASE
				CASE !EMPTY(lcQuote)
					IF lcCh == lcQuote
						lcQuote = ""
					ENDIF
				CASE INLIST(lcCh, "'", '"')
					lcQuote = lcCh
				ENDCASE
			ENDFOR
		ENDFOR
		RETURN lcOut
	ENDFUNC

	* Cada {ident x} (fuera de comillas: Markers no mira dentro) como hueco CHR(2) x CHR(2).
	FUNCTION IdentHoles(tcText)
		LOCAL loList, lnI, loM, lcOut
		IF !("{" $ tcText)
			RETURN tcText
		ENDIF
		lcOut = tcText
		loList = This.Markers(lcOut)
		FOR lnI = loList.Count TO 1 STEP -1
			loM = loList.Item(lnI)
			IF loM.cName == "ident" AND loM.nEnd > 0
				lcOut = LEFT(lcOut, loM.nStart - 1) + CHR(2) + LOWER(loM.cArgs) + CHR(2) + SUBSTR(lcOut, loM.nEnd + 1)
			ENDIF
		ENDFOR
		RETURN lcOut
	ENDFUNC

	* Para comprobar la longitud al cargar, cada hueco con la longitud máxima que declara.
	FUNCTION IdentsAtMost(tcText, toDef)
		LOCAL lcOut, lnA, lnB, lcName, lnAt
		lcOut = tcText
		DO WHILE CHR(2) $ lcOut
			lnA = AT(CHR(2), lcOut)
			lnB = AT(CHR(2), lcOut, 2)
			lcName = SUBSTR(lcOut, lnA + 1, lnB - lnA - 1)
			lnAt = toDef.oIdents.GetKey(lcName)
			lcOut = LEFT(lcOut, lnA - 1) + REPLICATE("x", IIF(lnAt > 0, toDef.oIdents.Item(lnAt).nMax, LEN(lcName))) + SUBSTR(lcOut, lnB + 1)
		ENDDO
		RETURN lcOut
	ENDFUNC

	* El texto de vfp como lo corre QueryLocal, sin los valores: cada :nombre como loFqArgs.nombre, sin las
	* líneas --, y los saltos de línea como blancos (lo mismo que QueryLocal.Rewritten).
	FUNCTION LocalText(tcText)
		LOCAL loNames, loMap, lnI, lcName
		loNames = This.Names(tcText)
		loMap = CREATEOBJECT("Collection")
		FOR lnI = 1 TO loNames.Count
			lcName = loNames.GetKey(lnI)
			loMap.Add("loFqArgs." + lcName, lcName)
		ENDFOR
		RETURN CHRTRAN(This.WithoutCommentLines(This.Rewrite(tcText, loMap, "")), CHR(13) + CHR(10), "  ")
	ENDFUNC

	* Dónde empieza una palabra entera en un texto (sin letra, dígito ni _ a los lados), desde tnFrom; o 0.
	FUNCTION WordAt(tcText, tcWord, tnFrom)
		LOCAL lnAt, lnOcc, lcBefore, lcAfter
		lnOcc = 1
		lnAt = AT(tcWord, SUBSTR(tcText, tnFrom), lnOcc)
		DO WHILE lnAt > 0
			lnAt = lnAt + tnFrom - 1
			lcBefore = IIF(lnAt = 1, " ", SUBSTR(tcText, lnAt - 1, 1))
			lcAfter = SUBSTR(tcText, lnAt + LEN(tcWord), 1)
			IF !(ISALPHA(lcBefore) OR ISDIGIT(lcBefore) OR lcBefore == "_") AND !(ISALPHA(lcAfter) OR ISDIGIT(lcAfter) OR lcAfter == "_")
				RETURN lnAt
			ENDIF
			lnOcc = lnOcc + 1
			lnAt = AT(tcWord, SUBSTR(tcText, tnFrom), lnOcc)
		ENDDO
		RETURN 0
	ENDFUNC
ENDDEFINE


* ======================================================================== *
* QueryKindGuard: la primera palabra de una SQL, sin contar los literales, los identificadores entre
* comillas ni los comentarios. Es lo que contrasta kind al cargar.
* ======================================================================== *
DEFINE CLASS QueryKindGuard AS Custom
	FUNCTION FirstWord(tcSql)
		LOCAL lcCode
		lcCode = This.Code(TRANSFORM(tcSql))
		RETURN GETWORDNUM(" " + UPPER(CHRTRAN(lcCode, "(),.;=<>+-*/%!|&^~:@#$?{}", SPACE(30))) + " ", 1)
	ENDFUNC

	*-- El texto sin literales, identificadores entre comillas ni comentarios: cada carácter de dentro
	*-- (y los tabuladores y saltos), un espacio. Un «--» acaba en el salto de línea.
	PROTECTED PROCEDURE Code
		LPARAMETERS tcSql
		LOCAL lcSql, lcCode, lnLen, lnI, lcC, lcState
		lcSql = tcSql
		lcCode = ""
		lcState = ""
		lnLen = LEN(lcSql)
		lnI = 1
		DO WHILE lnI <= lnLen
			lcC = SUBSTR(lcSql, lnI, 1)
			DO CASE
				CASE lcState == "'" OR lcState == ["] OR lcState == "`"
					IF lcC == lcState
						IF SUBSTR(lcSql, lnI + 1, 1) == lcState
							lcCode = lcCode + "  "
							lnI = lnI + 2
							LOOP
						ENDIF
						lcState = ""
					ENDIF
					lcCode = lcCode + " "
				CASE lcState == "["
					IF lcC == "]"
						lcState = ""
					ENDIF
					lcCode = lcCode + " "
				CASE lcState == "--"
					IF INLIST(lcC, CHR(13), CHR(10))
						lcState = ""
					ENDIF
					lcCode = lcCode + " "
				CASE lcState == "/*"
					IF lcC == "*" AND SUBSTR(lcSql, lnI + 1, 1) == "/"
						lcCode = lcCode + "  "
						lnI = lnI + 2
						lcState = ""
						LOOP
					ENDIF
					lcCode = lcCode + " "
				CASE lcC == "-" AND SUBSTR(lcSql, lnI + 1, 1) == "-"
					lcState = "--"
					lcCode = lcCode + " "
				CASE lcC == "/" AND SUBSTR(lcSql, lnI + 1, 1) == "*"
					lcState = "/*"
					lcCode = lcCode + "  "
					lnI = lnI + 2
					LOOP
				CASE INLIST(lcC, "'", ["], "`", "[")
					lcState = lcC
					lcCode = lcCode + " "
				CASE INLIST(lcC, CHR(9), CHR(13), CHR(10))
					lcCode = lcCode + " "
				OTHERWISE
					lcCode = lcCode + lcC
			ENDCASE
			lnI = lnI + 1
		ENDDO
		RETURN lcCode
	ENDPROC
ENDDEFINE


* ======================================================================== *
* FQ_*: las funciones, para quien no quiere clases. Debajo está la misma
* clase: FQ_LOAD crea el QueryStore y FQ_USE_* el ejecutor, los dos en _SCREEN (__oFoxQuery,
* __oFoxQueryDb), y FQ_RUN, FQ_SCALAR y FQ_EXECUTE llaman a Run, Scalar y Execute con ellos.
*
* LOS PARÁMETROS van por pares detrás de los argumentos fijos: nombre, valor, nombre, valor…
*   FQ_RUN("customers.by_city", "c_list", "city", "Oslo", "since", DATE(1980, 1, 1), "sort", "name DESC")
* Una lista, como cadena con comas ("countries", "PT,ES") o como array con @ ("countries", @laC). Si el
* primer argumento variable es un objeto, es el oParams de siempre y no hay pares. Caben 12 pares en
* FQ_RUN y 13 en FQ_SCALAR y FQ_EXECUTE (27 argumentos, lo que admite una llamada de VFP).
*
* EL CONTRATO DE ERROR:
*   - Un fallo operativo (un parámetro que falta o no cuadra, el motor que falla, una consulta que no
*     existe) no lanza nada: la función devuelve su valor de fallo (.F., .NULL. o -1) y FQ_LAST_ERROR()
*     dice por qué, con el nombre de la función delante («FQ_RUN: param_missing: city (…)»);
*     FQ_LAST_ERROR_CODE(), solo el código. Cada llamada FQ_* que hace algo empieza vaciándolos: tras una
*     que fue bien, son "". Con FQ_STRICT(.T.), el operativo también lanza.
*   - Un fallo de configuración (FQ_RUN sin FQ_LOAD, o sin FQ_USE_*) lanza ERROR, porque es un error del
*     programa. FQ_LAST_ERROR() lo dice también.
* FQ_BUILD compila una carpeta a un .fq y FQ_ADD_MACRO da una macro del cliente; FQ_ERRORS() dice todos
* los errores de la última carga o Build, no solo el primero. Con pares, un nombre que la consulta no declara es
* param_unknown antes de tocar el motor; con un objeto, las propiedades de más no cuentan.
* Las funciones que empiezan por FqSat son internas.
* ======================================================================== *

* Una carpeta de .sql (LoadFolder) o un catálogo .fq (Load, con su clave si la lleva). Crea el almacén si no
* existe; si existe, carga en el mismo (todo o nada: con un error, lo de antes se queda).
FUNCTION FQ_LOAD(tcSource, tcKey)
	LOCAL loQ, llOk, lnBefore, loErr
	FqSatBegin()
	_SCREEN.__cFoxQueryErrors = ""
	IF VARTYPE(tcSource) # "C" OR EMPTY(tcSource)
		_SCREEN.__cFoxQueryErrors = "folder_not_found: FQ_LOAD needs the folder of the .sql files, or a .fq"
		RETURN FqSatFail("FQ_LOAD", "folder_not_found", "FQ_LOAD needs the folder of the .sql files, or a .fq")
	ENDIF
	loQ = FqSatStore(.T.)
	lnBefore = loQ.nErrors
	llOk = .F.
	loErr = .NULL.
	TRY
		* Una carpeta, por lo que hay en disco; un fichero, o un nombre .fq (dentro del EXE o junto a él), Load.
		IF !DIRECTORY(tcSource) AND (FILE(tcSource) OR LOWER(JUSTEXT(ALLTRIM(tcSource))) == "fq")
			llOk = loQ.Load(tcSource, tcKey)
		ELSE
			llOk = loQ.LoadFolder(tcSource)
		ENDIF
	CATCH TO loErr
		llOk = .F.
	ENDTRY
	FqSatErrors(loQ, lnBefore, llOk, loErr)
	FqSatEngineCheck(loQ, llOk)
	RETURN FqSatOutcome("FQ_LOAD", loQ, lnBefore, llOk, loErr)
ENDFUNC

* Compila una carpeta de .sql a un catálogo .fq (QueryCompiler.Build), con las macros que se dieron con
* FQ_ADD_MACRO. Usa un compilador aparte: no toca lo que FQ_LOAD tenga cargado. cKey, la clave del .fq (sin
* ella, la fija de la librería); lEncrypt, cifrado (pide cKey). .T. o .F.; todos los errores, en FQ_ERRORS().
FUNCTION FQ_BUILD(tcFolder, tcFq, tcKey, tlEncrypt)
	LOCAL loC, loM, lnI, lcKey, lnAt, llOk, loErr
	FqSatBegin()
	_SCREEN.__cFoxQueryErrors = ""
	loC = CREATEOBJECT("QueryCompiler")
	loM = FqSatMacros()
	FOR lnI = 1 TO loM.Count
		lcKey = loM.GetKey(lnI)
		lnAt = AT("|", lcKey)
		=loC.AddMacro(LEFT(lcKey, lnAt - 1), SUBSTR(lcKey, lnAt + 1), loM.Item(lnI))
	ENDFOR
	llOk = .F.
	loErr = .NULL.
	TRY
		llOk = loC.Build(tcFolder, tcFq, IIF(VARTYPE(tcKey) == "C", tcKey, ""), VARTYPE(tlEncrypt) == "L" AND tlEncrypt)
	CATCH TO loErr
		llOk = .F.
	ENDTRY
	FqSatErrors(loC, 0, llOk, loErr)
	FqSatWarnings(loC)
	RETURN FqSatOutcome("FQ_BUILD", loC, 0, llOk, loErr)
ENDFUNC

* Una macro del cliente (AddMacro): {cName …} en el texto de cEngine se cambia por cTemplate ($1…$9, $*[sep]).
* Vale para lo cargado desde una carpeta, y FQ_BUILD se la da al compilador: queda apuntada siempre. Con
* un .fq cargado, .F. y catalog_frozen (el catálogo ya trae sus textos), pero apuntada para el próximo FQ_BUILD.
FUNCTION FQ_ADD_MACRO(tcEngine, tcName, tcTemplate)
	LOCAL loQ, loV, llOk, lnBefore, loErr
	FqSatBegin()
	* Se valida en un almacén aparte: con un .fq cargado, AddMacro diría catalog_frozen antes de mirar la macro.
	loV = CREATEOBJECT("QueryStore")
	llOk = .F.
	loErr = .NULL.
	TRY
		llOk = loV.AddMacro(tcEngine, tcName, tcTemplate)
	CATCH TO loErr
		llOk = .F.
	ENDTRY
	IF !llOk
		RETURN FqSatOutcome("FQ_ADD_MACRO", loV, 0, .F., loErr)
	ENDIF
	loQ = FqSatStore(.T.)
	=FqSatRecordMacro(tcEngine, tcName, tcTemplate)        && apuntada siempre para FQ_BUILD
	IF !EMPTY(loQ.cCatalog)
		RETURN FqSatFail("FQ_ADD_MACRO", "catalog_frozen", LOWER(ALLTRIM(tcName)) + " recorded for FQ_BUILD; the loaded " + ;
			JUSTFNAME(loQ.cCatalog) + " does not change (give the macro before FQ_BUILD)")
	ENDIF
	lnBefore = loQ.nErrors
	llOk = .F.
	loErr = .NULL.
	TRY
		llOk = loQ.AddMacro(tcEngine, tcName, tcTemplate)
	CATCH TO loErr
		llOk = .F.
	ENDTRY
	RETURN FqSatOutcome("FQ_ADD_MACRO", loQ, lnBefore, llOk, loErr)
ENDFUNC

* Vuelve a leer la carpeta de FQ_LOAD.
FUNCTION FQ_RELOAD()
	LOCAL loQ, llOk, lnBefore, loErr
	FqSatBegin()
	loQ = FqSatLoaded("FQ_RELOAD")
	IF ISNULL(loQ)
		RETURN .F.
	ENDIF
	lnBefore = loQ.nErrors
	llOk = .F.
	loErr = .NULL.
	_SCREEN.__cFoxQueryErrors = ""
	TRY
		llOk = loQ.Reload()
	CATCH TO loErr
		llOk = .F.
	ENDTRY
	FqSatErrors(loQ, lnBefore, llOk, loErr)
	FqSatEngineCheck(loQ, llOk)
	RETURN FqSatOutcome("FQ_RELOAD", loQ, lnBefore, llOk, loErr)
ENDFUNC

* Cualquier ejecutor: FoxRemote tal cual, o el del usuario (cEngine, Query, Execute, Scalar).
FUNCTION FQ_USE(toDb)
	LOCAL lcEngine
	FqSatBegin()
	IF VARTYPE(toDb) # "O" OR !PEMSTATUS(toDb, "cEngine", 5) OR !PEMSTATUS(toDb, "Query", 5) OR ;
			!PEMSTATUS(toDb, "Execute", 5) OR !PEMSTATUS(toDb, "Scalar", 5)
		RETURN FqSatFail("FQ_USE", "executor_invalid", "the executor has to be an object with cEngine, Query(), Execute() and Scalar(), " + ;
			"such as a database of FoxRemote")
	ENDIF
	lcEngine = LOWER(ALLTRIM(TRANSFORM(toDb.cEngine)))
	IF !(" " + lcEngine + " " $ FQ_ENGINES)
		RETURN FqSatFail("FQ_USE", "engine_unknown", "the executor says its engine is '" + TRANSFORM(toDb.cEngine) + "'; the engines are" + RTRIM(FQ_ENGINES))
	ENDIF
	FqSatSetDb(toDb)
	RETURN .T.
ENDFUNC

* Un QueryOdbc sobre el handle de SQLCONNECT o SQLSTRINGCONNECT del usuario.
FUNCTION FQ_USE_HANDLE(tnHandle, tcEngine)
	LOCAL loDb
	FqSatBegin()
	IF VARTYPE(tnHandle) # "N" OR tnHandle < 1
		RETURN FqSatFail("FQ_USE_HANDLE", "not_connected", "FQ_USE_HANDLE needs the handle of SQLCONNECT or SQLSTRINGCONNECT, and it got " + TRANSFORM(tnHandle))
	ENDIF
	loDb = CREATEOBJECT("QueryOdbc", tnHandle, IIF(VARTYPE(tcEngine) == "C", tcEngine, ""))
	IF EMPTY(loDb.cEngine)
		RETURN FqSatFail("FQ_USE_HANDLE", loDb.cLastErrorCode, FqSatMessage(loDb.cLastError, loDb.cLastErrorCode))
	ENDIF
	FqSatSetDb(loDb)
	RETURN .T.
ENDFUNC

* Un QueryLocal: DBF locales, el dialecto vfp.
FUNCTION FQ_USE_DBF()
	FqSatBegin()
	FqSatSetDb(CREATEOBJECT("QueryLocal"))
	RETURN .T.
ENDFUNC

* Una consulta read a un cursor (vacío: el defecto del ejecutor). .T. o .F.
FUNCTION FQ_RUN(tcName, tcCursor, tv1, tv2, tv3, tv4, tv5, tv6, tv7, tv8, tv9, tv10, tv11, tv12, tv13, ;
		tv14, tv15, tv16, tv17, tv18, tv19, tv20, tv21, tv22, tv23, tv24, tv25)
	LOCAL loQ, loDb, lvArgs, llOk, lnBefore, loErr, lcUnknown
	FqSatBegin()
	loQ = FqSatLoaded("FQ_RUN")
	loDb = FqSatInUse("FQ_RUN")
	IF ISNULL(loQ) OR ISNULL(loDb)
		RETURN .F.
	ENDIF
	lvArgs = FqSatArgs(PCOUNT() - 2, @tv1, @tv2, @tv3, @tv4, @tv5, @tv6, @tv7, @tv8, @tv9, @tv10, @tv11, @tv12, @tv13, ;
		@tv14, @tv15, @tv16, @tv17, @tv18, @tv19, @tv20, @tv21, @tv22, @tv23, @tv24, @tv25)
	IF VARTYPE(lvArgs) == "C"
		RETURN FqSatFail("FQ_RUN", "param_name_invalid", lvArgs)
	ENDIF
	lcUnknown = IIF(VARTYPE(lvArgs) == "O" AND VARTYPE(tv1) # "O", FqSatUnknown(loQ, tcName, lvArgs), "")
	IF !EMPTY(lcUnknown)
		RETURN FqSatFail("FQ_RUN", "param_unknown", lcUnknown)
	ENDIF
	lnBefore = loQ.nErrors
	llOk = .F.
	loErr = .NULL.
	TRY
		llOk = loQ.Run(loDb, tcName, lvArgs, IIF(VARTYPE(tcCursor) == "C", tcCursor, ""))
	CATCH TO loErr
		llOk = .F.
	ENDTRY
	RETURN FqSatOutcome("FQ_RUN", loQ, lnBefore, llOk, loErr)
ENDFUNC

* Una consulta read que da un valor: el valor, o .NULL. Un .NULL. legítimo deja FQ_LAST_ERROR() vacío.
FUNCTION FQ_SCALAR(tcName, tv1, tv2, tv3, tv4, tv5, tv6, tv7, tv8, tv9, tv10, tv11, tv12, tv13, ;
		tv14, tv15, tv16, tv17, tv18, tv19, tv20, tv21, tv22, tv23, tv24, tv25, tv26)
	LOCAL loQ, loDb, lvArgs, lvValue, lnBefore, loErr, lcUnknown
	FqSatBegin()
	loQ = FqSatLoaded("FQ_SCALAR")
	loDb = FqSatInUse("FQ_SCALAR")
	IF ISNULL(loQ) OR ISNULL(loDb)
		RETURN .NULL.
	ENDIF
	lvArgs = FqSatArgs(PCOUNT() - 1, @tv1, @tv2, @tv3, @tv4, @tv5, @tv6, @tv7, @tv8, @tv9, @tv10, @tv11, @tv12, @tv13, ;
		@tv14, @tv15, @tv16, @tv17, @tv18, @tv19, @tv20, @tv21, @tv22, @tv23, @tv24, @tv25, @tv26)
	IF VARTYPE(lvArgs) == "C"
		=FqSatFail("FQ_SCALAR", "param_name_invalid", lvArgs)
		RETURN .NULL.
	ENDIF
	lcUnknown = IIF(VARTYPE(lvArgs) == "O" AND VARTYPE(tv1) # "O", FqSatUnknown(loQ, tcName, lvArgs), "")
	IF !EMPTY(lcUnknown)
		=FqSatFail("FQ_SCALAR", "param_unknown", lcUnknown)
		RETURN .NULL.
	ENDIF
	lnBefore = loQ.nErrors
	lvValue = .NULL.
	loErr = .NULL.
	TRY
		lvValue = loQ.Scalar(loDb, tcName, lvArgs)
	CATCH TO loErr
		lvValue = .NULL.
	ENDTRY
	IF !FqSatOutcome("FQ_SCALAR", loQ, lnBefore, .T., loErr)
		RETURN .NULL.
	ENDIF
	RETURN lvValue
ENDFUNC

* Una consulta write: las filas que tocó, o -1.
FUNCTION FQ_EXECUTE(tcName, tv1, tv2, tv3, tv4, tv5, tv6, tv7, tv8, tv9, tv10, tv11, tv12, tv13, ;
		tv14, tv15, tv16, tv17, tv18, tv19, tv20, tv21, tv22, tv23, tv24, tv25, tv26)
	LOCAL loQ, loDb, lvArgs, lnRows, lnBefore, loErr, lcUnknown
	FqSatBegin()
	loQ = FqSatLoaded("FQ_EXECUTE")
	loDb = FqSatInUse("FQ_EXECUTE")
	IF ISNULL(loQ) OR ISNULL(loDb)
		RETURN -1
	ENDIF
	lvArgs = FqSatArgs(PCOUNT() - 1, @tv1, @tv2, @tv3, @tv4, @tv5, @tv6, @tv7, @tv8, @tv9, @tv10, @tv11, @tv12, @tv13, ;
		@tv14, @tv15, @tv16, @tv17, @tv18, @tv19, @tv20, @tv21, @tv22, @tv23, @tv24, @tv25, @tv26)
	IF VARTYPE(lvArgs) == "C"
		=FqSatFail("FQ_EXECUTE", "param_name_invalid", lvArgs)
		RETURN -1
	ENDIF
	lcUnknown = IIF(VARTYPE(lvArgs) == "O" AND VARTYPE(tv1) # "O", FqSatUnknown(loQ, tcName, lvArgs), "")
	IF !EMPTY(lcUnknown)
		=FqSatFail("FQ_EXECUTE", "param_unknown", lcUnknown)
		RETURN -1
	ENDIF
	lnBefore = loQ.nErrors
	lnRows = -1
	loErr = .NULL.
	TRY
		lnRows = loQ.Execute(loDb, tcName, lvArgs)
	CATCH TO loErr
		lnRows = -1
	ENDTRY
	IF !FqSatOutcome("FQ_EXECUTE", loQ, lnBefore, VARTYPE(lnRows) == "N" AND lnRows >= 0, loErr)
		RETURN -1
	ENDIF
	RETURN lnRows
ENDFUNC

* El texto de una consulta (Sql). Sin cEngine, el del ejecutor en uso.
FUNCTION FQ_SQL(tcName, tcEngine, tcObject, toParams)
	LOCAL loQ, loDb, lcEngine, lvText, lnBefore, loErr
	FqSatBegin()
	loQ = FqSatLoaded("FQ_SQL")
	IF ISNULL(loQ)
		RETURN .NULL.
	ENDIF
	IF VARTYPE(tcEngine) == "C" AND !EMPTY(tcEngine)
		lcEngine = tcEngine
	ELSE
		loDb = FqSatInUse("FQ_SQL")
		IF ISNULL(loDb)
			RETURN .NULL.
		ENDIF
		lcEngine = TRANSFORM(loDb.cEngine)
	ENDIF
	lnBefore = loQ.nErrors
	lvText = .NULL.
	loErr = .NULL.
	TRY
		lvText = loQ.Sql(tcName, lcEngine, IIF(VARTYPE(tcObject) == "C", tcObject, ""), toParams)
	CATCH TO loErr
		lvText = .NULL.
	ENDTRY
	IF !FqSatOutcome("FQ_SQL", loQ, lnBefore, !ISNULL(lvText), loErr)
		RETURN .NULL.
	ENDIF
	RETURN lvText
ENDFUNC

* Un objeto de parámetros: un None de FoxNone (Params del almacén), o .NULL. con foxnone_missing.
FUNCTION FQ_PARAMS()
	LOCAL loQ, loP, lnBefore, loErr
	FqSatBegin()
	loQ = FqSatStore(.T.)
	lnBefore = loQ.nErrors
	loP = .NULL.
	loErr = .NULL.
	TRY
		loP = loQ.Params()
	CATCH TO loErr
		loP = .NULL.
	ENDTRY
	IF !FqSatOutcome("FQ_PARAMS", loQ, lnBefore, !ISNULL(loP), loErr)
		RETURN .NULL.
	ENDIF
	RETURN loP
ENDFUNC

* FQ_STRICT(.T.): los fallos operativos también lanzan ERROR (el almacén y los ejecutores de la librería con
* lStrict). Sin argumento, solo dice cómo está. Devuelve el estado.
FUNCTION FQ_STRICT(tlOn)
	LOCAL loQ, loDb
	FqSatBegin()
	IF PCOUNT() > 0
		_SCREEN.__lFoxQueryStrict = (VARTYPE(tlOn) == "L" AND tlOn)
		loQ = FqSatStore(.F.)
		IF !ISNULL(loQ)
			loQ.lStrict = _SCREEN.__lFoxQueryStrict
		ENDIF
		loDb = FQ_DB()
		IF !ISNULL(loDb)
			FqSatHouseStrict(loDb)
		ENDIF
	ENDIF
	RETURN _SCREEN.__lFoxQueryStrict
ENDFUNC

* Fija un identificador de contexto (FQ_SET("sort", "name")) para todas las consultas que lo usan, una
* vez, al arrancar el programa; nunca en una llamada. Se valida antes de guardarlo (ident_invalid). FQ_LOAD lo conserva.
FUNCTION FQ_SET(tcName, tcValue)
	LOCAL loQ, lnBefore, llOk
	FqSatBegin()
	loQ = FqSatStore(.T.)
	lnBefore = loQ.nErrors
	llOk = loQ.SetIdent(tcName, tcValue)
	RETURN FqSatOutcome("FQ_SET", loQ, lnBefore, llOk, .NULL.)
ENDFUNC

* ¿El texto tiene solo los caracteres de tcSet? Con LEN() = 0 y no EMPTY(): EMPTY() de una cadena de
* blancos es .T., y un espacio pasaría.
FUNCTION FqIdentChars(tcValue, tcSet)
	RETURN LEN(tcValue) > 0 AND LEN(CHRTRAN(tcValue, tcSet, "")) = 0
ENDFUNC

* El QueryStore de debajo, para quien quiera crecer hacia la clase; o .NULL.
FUNCTION FQ_STORE()
	RETURN FqSatStore(.F.)
ENDFUNC

* El ejecutor en uso, o .NULL.
FUNCTION FQ_DB()
	FqSatEnsure()
	RETURN IIF(VARTYPE(_SCREEN.__oFoxQueryDb) == "O", _SCREEN.__oFoxQueryDb, .NULL.)
ENDFUNC

* Por qué falló la última llamada FQ_*, con el nombre de la función delante; "" si fue bien.
FUNCTION FQ_LAST_ERROR()
	FqSatEnsure()
	RETURN _SCREEN.__cFoxQueryLastError
ENDFUNC

* Solo el código del último fallo (param_missing, executor_failed…); "" si fue bien.
FUNCTION FQ_LAST_ERROR_CODE()
	FqSatEnsure()
	RETURN _SCREEN.__cFoxQueryLastCode
ENDFUNC

* Todos los errores de la última FQ_LOAD, FQ_RELOAD o FQ_BUILD, uno por línea: «fichero(línea): código: motivo»
* si es de un .sql, «código: motivo» si no. "" si fue bien.
FUNCTION FQ_ERRORS()
	FqSatEnsure()
	RETURN _SCREEN.__cFoxQueryErrors
ENDFUNC

* Todos los avisos del último FQ_LOAD, FQ_RELOAD o FQ_BUILD y del último FQ_USE_DBF, FQ_USE_HANDLE o FQ_USE, uno por
* línea como FQ_ERRORS(): lo declarado que ningún texto usa (param_unused, ident_unused) y lo que el motor en uso no
* puede ejecutar (sql_too_long, sort_not_in_select, macro_unsupported; FQ_RUN de esa consulta falla con el mismo
* código, y los otros motores la ejecutan). "" si no hay ninguno.
FUNCTION FQ_WARNINGS()
	FqSatEnsure()
	RETURN _SCREEN.__cFoxQueryWarnings
ENDFUNC

FUNCTION FQ_VERSION()
	RETURN "1.0.2"
ENDFUNC

* ---------------------------------------------------------------- internas

* El estado en _SCREEN, con ADDPROPERTY detrás de TYPE() = "U": un segundo SET PROCEDURE TO foxquery
* ADDITIVE no pierde nada.
PROCEDURE FqSatEnsure
	IF TYPE("_SCREEN.__oFoxQuery") = "U"
		ADDPROPERTY(_SCREEN, "__oFoxQuery", .NULL.)
	ENDIF
	IF TYPE("_SCREEN.__oFoxQueryDb") = "U"
		ADDPROPERTY(_SCREEN, "__oFoxQueryDb", .NULL.)
	ENDIF
	IF TYPE("_SCREEN.__cFoxQueryLastError") = "U"
		ADDPROPERTY(_SCREEN, "__cFoxQueryLastError", "")
	ENDIF
	IF TYPE("_SCREEN.__cFoxQueryLastCode") = "U"
		ADDPROPERTY(_SCREEN, "__cFoxQueryLastCode", "")
	ENDIF
	IF TYPE("_SCREEN.__lFoxQueryStrict") = "U"
		ADDPROPERTY(_SCREEN, "__lFoxQueryStrict", .F.)
	ENDIF
	IF TYPE("_SCREEN.__cFoxQueryErrors") = "U"
		ADDPROPERTY(_SCREEN, "__cFoxQueryErrors", "")
	ENDIF
	IF TYPE("_SCREEN.__cFoxQueryWarnings") = "U"
		ADDPROPERTY(_SCREEN, "__cFoxQueryWarnings", "")
	ENDIF
	IF TYPE("_SCREEN.__oFoxQueryMacros") = "U"
		ADDPROPERTY(_SCREEN, "__oFoxQueryMacros", .NULL.)
	ENDIF
ENDPROC

* Las macros de FQ_ADD_MACRO, para FQ_BUILD: "motor|nombre" -> plantilla.
FUNCTION FqSatMacros
	FqSatEnsure()
	IF VARTYPE(_SCREEN.__oFoxQueryMacros) # "O"
		_SCREEN.__oFoxQueryMacros = CREATEOBJECT("Collection")
	ENDIF
	RETURN _SCREEN.__oFoxQueryMacros
ENDFUNC

* Apunta una macro para FQ_BUILD (la misma clave, otra plantilla: la pisa).
FUNCTION FqSatRecordMacro(tcEngine, tcName, tcTemplate)
	LOCAL loM, lcKey
	loM = FqSatMacros()
	lcKey = LOWER(ALLTRIM(tcEngine)) + "|" + LOWER(ALLTRIM(tcName))
	IF loM.GetKey(lcKey) > 0
		loM.Remove(lcKey)
	ENDIF
	loM.Add(tcTemplate, lcKey)
	RETURN .T.
ENDFUNC

* Los nombres de los pares que la consulta no declara (sort aparte), con los que sí declara; "" si todos
* están, y "" si la consulta no existe (Run dirá query_not_found). Get corre con los errores guardados y sin
* lStrict, porque solo mira.
FUNCTION FqSatUnknown(toQ, tcName, toArgs)
	LOCAL lnErrors, lcError, lcCode, llStrict, loDef, laM[1], lnM, lnI, lcName, lcUnknown, lcDeclared, loErr
	lnErrors = toQ.nErrors
	lcError = toQ.cLastError
	lcCode = toQ.cLastErrorCode
	llStrict = toQ.lStrict
	toQ.lStrict = .F.
	loDef = .NULL.
	TRY
		loDef = toQ.Get(tcName)
	CATCH TO loErr
		loDef = .NULL.
	ENDTRY
	toQ.lStrict = llStrict
	toQ.nErrors = lnErrors
	toQ.cLastError = lcError
	toQ.cLastErrorCode = lcCode
	IF ISNULL(loDef)
		RETURN ""
	ENDIF
	lcUnknown = ""
	lnM = AMEMBERS(laM, toArgs)
	FOR lnI = 1 TO lnM
		lcName = LOWER(laM[lnI])
		IF !(lcName == "sort") AND loDef.oParams.GetKey(lcName) = 0 AND loDef.oIdents.GetKey(lcName) = 0
			lcUnknown = lcUnknown + IIF(EMPTY(lcUnknown), "", ", ") + lcName
		ENDIF
	ENDFOR
	IF EMPTY(lcUnknown)
		RETURN ""
	ENDIF
	lcDeclared = STRTRAN(loDef.ParamNames(), ",", ", ")
	RETURN lcUnknown + " (" + loDef.cName + IIF(EMPTY(lcDeclared), " declares no parameters", " declares " + lcDeclared) + ")"
ENDFUNC

* Lo que da FQ_ERRORS() tras una carga o un Build: los errores de carga, uno por línea, o el error si no es de
* un .sql. Va antes de FqSatOutcome, que con FQ_STRICT(.T.) lanza.
PROCEDURE FqSatErrors(toQ, tnBefore, tlOk, toErr)
	LOCAL lcText, lnI
	lcText = ""
	DO CASE
	CASE toQ.nLoadErrors > 0
		FOR lnI = 1 TO toQ.nLoadErrors
			lcText = lcText + IIF(lnI = 1, "", FQ_CRLF) + JUSTFNAME(TRANSFORM(toQ.aLoadErrors[lnI, 2])) + ;
				"(" + TRANSFORM(toQ.aLoadErrors[lnI, 3]) + "): " + toQ.aLoadErrors[lnI, 4]
		ENDFOR
	CASE toQ.nErrors > tnBefore
		lcText = toQ.cLastError
	CASE VARTYPE(toErr) == "O"
		lcText = "internal_error: error " + TRANSFORM(toErr.ErrorNo) + ": " + toErr.Message
	CASE !tlOk
		lcText = "internal_error: it failed and said nothing"
	ENDCASE
	_SCREEN.__cFoxQueryErrors = lcText
ENDPROC

* El principio de cada llamada que hace algo: FQ_LAST_ERROR() y FQ_LAST_ERROR_CODE() vacíos.
PROCEDURE FqSatBegin
	FqSatEnsure()
	_SCREEN.__cFoxQueryLastError = ""
	_SCREEN.__cFoxQueryLastCode = ""
ENDPROC

* El almacén; con tlCreate, lo crea si no está (con el lStrict de FQ_STRICT).
FUNCTION FqSatStore(tlCreate)
	FqSatEnsure()
	IF VARTYPE(_SCREEN.__oFoxQuery) # "O" AND tlCreate
		_SCREEN.__oFoxQuery = CREATEOBJECT("QueryStore")
		_SCREEN.__oFoxQuery.lStrict = _SCREEN.__lFoxQueryStrict
	ENDIF
	RETURN IIF(VARTYPE(_SCREEN.__oFoxQuery) == "O", _SCREEN.__oFoxQuery, .NULL.)
ENDFUNC

* El almacén con una carpeta cargada; si no, es un fallo de configuración.
FUNCTION FqSatLoaded(tcFunction)
	LOCAL loQ
	loQ = FqSatStore(.F.)
	IF ISNULL(loQ) OR (EMPTY(loQ.cFolder) AND EMPTY(loQ.cCatalog))
		FqSatConfig(tcFunction, "not_loaded", "call FQ_LOAD first")
		RETURN .NULL.
	ENDIF
	RETURN loQ
ENDFUNC

* El ejecutor en uso; si no hay, es un fallo de configuración.
FUNCTION FqSatInUse(tcFunction)
	LOCAL loDb
	loDb = FQ_DB()
	IF ISNULL(loDb)
		FqSatConfig(tcFunction, "not_connected", "call FQ_USE, FQ_USE_HANDLE or FQ_USE_DBF first")
	ENDIF
	RETURN loDb
ENDFUNC

PROCEDURE FqSatSetDb(toDb)
	LOCAL loQ
	FqSatEnsure()
	_SCREEN.__oFoxQueryDb = toDb
	FqSatHouseStrict(toDb)
	* Con consultas cargadas, lo que este motor no puede ejecutar va a FQ_WARNINGS() ahora, no al ejecutar.
	loQ = FqSatStore(.F.)
	IF !ISNULL(loQ) AND (!EMPTY(loQ.cFolder) OR !EMPTY(loQ.cCatalog))
		=loQ.CheckEngine(toDb.cEngine)
		FqSatWarnings(loQ)
	ENDIF
ENDPROC

* Después de una carga que fue bien, lo que el motor en uso no puede ejecutar es un aviso; y FQ_WARNINGS().
PROCEDURE FqSatEngineCheck(toQ, tlOk)
	IF tlOk AND VARTYPE(_SCREEN.__oFoxQueryDb) == "O"
		=toQ.CheckEngine(_SCREEN.__oFoxQueryDb.cEngine)
	ENDIF
	FqSatWarnings(toQ)
ENDPROC

* Los avisos del almacén, uno por línea como FQ_ERRORS(), a FQ_WARNINGS().
PROCEDURE FqSatWarnings(toQ)
	LOCAL lcText, lnI
	lcText = ""
	FOR lnI = 1 TO toQ.nWarnings
		lcText = lcText + IIF(lnI = 1, "", FQ_CRLF) + IIF(EMPTY(toQ.aWarnings[lnI, 2]), "", ;
			JUSTFNAME(TRANSFORM(toQ.aWarnings[lnI, 2])) + "(" + TRANSFORM(toQ.aWarnings[lnI, 3]) + "): ") + toQ.aWarnings[lnI, 4]
	ENDFOR
	_SCREEN.__cFoxQueryWarnings = lcText
ENDPROC

* El lStrict de FQ_STRICT, a un ejecutor de la librería (QueryOdbc, QueryLocal); a los demás no se toca.
PROCEDURE FqSatHouseStrict(toDb)
	LOCAL laC[1], lnI
	FOR lnI = 1 TO ACLASS(laC, toDb)
		IF UPPER(laC[lnI]) == "QUERYEXECUTOR"
			toDb.lStrict = _SCREEN.__lFoxQueryStrict
			EXIT
		ENDIF
	ENDFOR
ENDPROC

* Los argumentos variables de FQ_RUN, FQ_SCALAR y FQ_EXECUTE: .NULL. si no hay; el objeto, si el primero
* es un objeto; si son pares, un Empty con ellos (una lista como array, en una propiedad array). Un par
* mal formado devuelve el motivo (C). Aquí no se validan tipos: eso lo hace el almacén, como siempre.
FUNCTION FqSatArgs(tnArgs, tv1, tv2, tv3, tv4, tv5, tv6, tv7, tv8, tv9, tv10, tv11, tv12, tv13, ;
		tv14, tv15, tv16, tv17, tv18, tv19, tv20, tv21, tv22, tv23, tv24, tv25, tv26)
	LOCAL loArgs, loText, lnI, lcVar, lcRef, lvName, lcName, lnN, lnK
	IF tnArgs <= 0
		RETURN .NULL.
	ENDIF
	IF TYPE("tv1", 1) # "A" AND VARTYPE(tv1) == "O"
		IF tnArgs > 1
			RETURN "after the object of parameters there is nothing else: pairs or an object, not both (" + TRANSFORM(tnArgs) + " arguments)"
		ENDIF
		RETURN tv1
	ENDIF
	loArgs = CREATEOBJECT("Empty")
	loText = CREATEOBJECT("QueryText")
	FOR lnI = 1 TO tnArgs STEP 2
		lcVar = "tv" + TRANSFORM(lnI)
		IF TYPE(lcVar, 1) == "A"
			RETURN "argument " + TRANSFORM(lnI) + " is the name of a parameter, and it is an array"
		ENDIF
		lvName = EVALUATE(lcVar)
		IF VARTYPE(lvName) # "C"
			RETURN "argument " + TRANSFORM(lnI) + " is the name of a parameter, and it is " + VARTYPE(lvName) + " (" + TRANSFORM(lvName) + ")"
		ENDIF
		lcName = ALLTRIM(lvName)
		IF !loText.IsName(lcName, .F.)
			RETURN "'" + lcName + "' is not the name of a parameter: a letter or _, then letters, digits or _, without the :"
		ENDIF
		IF lnI = tnArgs
			RETURN "the parameter " + lcName + " has no value: the arguments go in pairs, name and value"
		ENDIF
		IF PEMSTATUS(loArgs, lcName, 5)
			RETURN "the parameter " + lcName + " is twice"
		ENDIF
		lcRef = "tv" + TRANSFORM(lnI + 1)
		IF TYPE(lcRef, 1) == "A"
			lnN = ALEN(&lcRef)
			ADDPROPERTY(loArgs, lcName + "[" + TRANSFORM(MAX(lnN, 1)) + "]")
			FOR lnK = 1 TO lnN
				loArgs.&lcName[lnK] = &lcRef[lnK]
			ENDFOR
		ELSE
			ADDPROPERTY(loArgs, lcName, EVALUATE(lcRef))
		ENDIF
	ENDFOR
	RETURN loArgs
ENDFUNC

* Lo que dice el almacén de una llamada: .T. si fue bien; si no, el fallo de la función y .F.
* Un cLastError que no empieza por el código (el de un error de carga, «fichero(línea): código: motivo») va
* entero detrás del nombre de la función, sin otro código delante.
FUNCTION FqSatOutcome(tcFunction, toQ, tnBefore, tlOk, toErr)
	LOCAL lcText
	DO CASE
	CASE toQ.nErrors > tnBefore
		lcText = STRTRAN(toQ.cLastError, "more in aLoadErrors)", "more in FQ_ERRORS())")
		IF LEFT(lcText, LEN(toQ.cLastErrorCode) + 2) == toQ.cLastErrorCode + ": "
			RETURN FqSatFail(tcFunction, toQ.cLastErrorCode, SUBSTR(lcText, LEN(toQ.cLastErrorCode) + 3))
		ENDIF
		RETURN FqSatFailText(tcFunction, toQ.cLastErrorCode, lcText)
	CASE VARTYPE(toErr) == "O"
		RETURN FqSatFail(tcFunction, "internal_error", "error " + TRANSFORM(toErr.ErrorNo) + ": " + toErr.Message)
	CASE !tlOk
		RETURN FqSatFail(tcFunction, "internal_error", "it failed and said nothing")
	ENDCASE
	RETURN .T.
ENDFUNC

* «code: message» -> message.
FUNCTION FqSatMessage(tcError, tcCode)
	IF LEFT(tcError, LEN(tcCode) + 2) == tcCode + ": "
		RETURN SUBSTR(tcError, LEN(tcCode) + 3)
	ENDIF
	RETURN tcError
ENDFUNC

* Un fallo operativo: FQ_LAST_ERROR() y .F.; con FQ_STRICT(.T.), además ERROR.
FUNCTION FqSatFail(tcFunction, tcCode, tcMessage)
	RETURN FqSatFailText(tcFunction, tcCode, tcCode + ": " + tcMessage)
ENDFUNC

* El fallo con el texto que va detrás del nombre de la función (el de un error de carga ya lleva el código).
FUNCTION FqSatFailText(tcFunction, tcCode, tcText)
	LOCAL lcText
	lcText = tcFunction + ": " + tcText
	FqSatEnsure()
	_SCREEN.__cFoxQueryLastError = lcText
	_SCREEN.__cFoxQueryLastCode = tcCode
	IF _SCREEN.__lFoxQueryStrict
		ERROR lcText
	ENDIF
	RETURN .F.
ENDFUNC

* Un fallo de configuración: FQ_LAST_ERROR() y ERROR, siempre.
PROCEDURE FqSatConfig(tcFunction, tcCode, tcMessage)
	FqSatEnsure()
	_SCREEN.__cFoxQueryLastError = tcFunction + ": " + tcCode + ": " + tcMessage
	_SCREEN.__cFoxQueryLastCode = tcCode
	ERROR _SCREEN.__cFoxQueryLastError
ENDPROC
