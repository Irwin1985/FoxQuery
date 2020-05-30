&& ======================================================================== &&
&& Class FoxQuery
&& ======================================================================== &&
Define Class FoxQuery as Session
	datasession = 2
&& ======================================================================== &&
&& Function Init
&& ======================================================================== &&
	Function init
		Create Cursor qTest(codigo c(30))
		Insert into qTest values("pepito")
		Insert into qTest values("juanito")
		Insert into qTest values("joseito")
	EndFunc
	Function browsetable() as void
		Select qTest
		browse
	EndFunc
EndDefine