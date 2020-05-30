&& ======================================================================== &&
&& Class StringBuilder
&& ======================================================================== &&
Define Class StringBuilder As Session
	Hidden aString(1)
	Hidden nStringCounter
	Hidden Content
&& ======================================================================== &&
&& Function Init
&& ======================================================================== &&
	Function Init As Void
		Lparameters tvData As Variant
		This.nStringCounter = 0
		This.Content = ""
		If Pcount() = 1
			This.Append(tvData)
		Endif
	Endfunc
&& ======================================================================== &&
&& Function Append
&& ======================================================================== &&
	Function Append As Void
		Lparameters tvData As Variant
		If Type("tvData") != "U"
			This.nStringCounter = This.nStringCounter + 1
			Dimension This.aString(This.nStringCounter)
			This.aString[This.nStringCounter] = This.ParseToString(tvData)
			This.Content = This.Content + This.aString[This.nStringCounter]
		Endif
	Endfunc
&& ======================================================================== &&
&& Hidden Function ParseToString
&& ======================================================================== &&
	Hidden Function ParseToString
		Lparameters tvData As Variant
		Local lcContent As String
		lcContent = ""
		If Type("tvData") == "O" And This.isBuilderObject(tvData)
			lcContent = tvData.ToString()
		Else
			lcContent = Transform(tvData)
		Endif
		Return lcContent
	Endfunc
&& ======================================================================== &&
&& Hidden Function isBuilderObject
&& ======================================================================== &&
	Hidden Function isBuilderObject As Boolean
		Lparameters toObject As Object
		Local lbContinue As Boolean
		lbContinue = .T.
		Try
			toObject.ToString()
		Catch
			lbContinue = .F.
		Endtry
		Return lbContinue
	Endfunc
&& ======================================================================== &&
&& Function ToString()
&& ======================================================================== &&
	Function ToString() As String
		Return This.Content
	Endfunc
&& ======================================================================== &&
&& Function AppendCodePoint()
&& ======================================================================== &&
	Function AppendCodePoint() As String
		Lparameters tnCodePoint As Integer
		If Type("tnCodePoint") == "N"
			This.Append(Chr(tnCodePoint))
		Endif
	Endfunc
&& ======================================================================== &&
&& Function Delete
&& ======================================================================== &&
	Function Delete() As Void
		Lparameters tnStart As Integer, tnEnd As Integer
		Local lcRemainingChar As String
		lcRemainingChar = Substr(This.Content, tnStart, tnEnd - tnStart)
		This.Content = Strtran(This.Content, lcRemainingChar)
	EndFunc
&& ======================================================================== &&
&& Function DeleteCharAt
&& ======================================================================== &&
	Function DeleteCharAt() As Void
		Lparameters tnIndex As Integer
		This.Delete(tnIndex, tnIndex + 1)
	EndFunc
&& ======================================================================== &&
&& Function IndexOf
&& ======================================================================== &&
	Function IndexOf() As Integer
		Lparameters tcSearchExpression As String
		Return At(tcSearchExpression, This.Content, 1)
	EndFunc	
&& ======================================================================== &&
&& Function Insert
&& ======================================================================== &&
	Function Insert() As Integer
		Lparameters tnOffset As Integer, tvData As Variant
		Local lcBeforeOffset As String, lcAfterOffset As String
		lcBeforeOffset = Substr(this.Content, 1, tnOffset)
		lcAfterOffset  = Substr(this.Content, tnOffset + 1)
		This.Content = lcBeforeOffset + This.ParseToString(tvData) + lcAfterOffset
	EndFunc
&& ======================================================================== &&
&& Function LastIndexOf
&& ======================================================================== &&
	Function LastIndexOf As Integer
		Lparameters tcSearchExpression As String
		Local lnOccurs As Integer, lnIndex As Integer
		lnOccurs = Occurs(tcSearchExpression, This.Content)
		lnIndex  = 0
		If lnOccurs > 0
			lnIndex = At(tcSearchExpression, This.Content, lnOccurs)			
		EndIf
		Return lnIndex
	EndFunc
&& ======================================================================== &&
&& Function Replace
&& ======================================================================== &&
	Function Replace
		Lparameters tnStart As Integer, tnEnd As Integer, tvData As Variant
		Local lcBeforeOffset As String, lcAfterOffset As String
		lcBeforeOffset = Substr(this.Content, 1, tnStart)
		lcAfterOffset  = Substr(this.Content, tnEnd + 1)
		This.Content = lcBeforeOffset + This.ParseToString(tvData) + lcAfterOffset
		Return This.Content
	EndFunc
&& ======================================================================== &&
&& Function Reverse
&& ======================================================================== &&
	Function Reverse As String
		lcContent = ""
		For nIndex = Len(This.Content) to 1 step -1
			lcContent = lcContent + Substr(This.Content, nIndex, 1)
		EndFor
		Return lcContent
	EndFunc
Enddefine