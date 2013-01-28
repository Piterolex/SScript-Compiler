(*
 Copyright © by Patryk Wychowaniec, 2013
 All rights reserved.
*)
Unit Parse_Function;

 Interface
 Uses MTypes, Tokens, Variants;

 Type TMParam = Record
                 Name: String;
                 Typ : TVType;
                End;
 Type TMParamList = Array of TMParam;

 Type TMFunction = Record
                    Name      : String; // function name
                    MName     : String; // mangled name (used as a label name)
                    ModuleName: String; // module name in which function has been declared
                    Return    : TVType; // return type
                    ParamList : TMParamList;

                    ImportFile: String;

                    ConstructionList: TMConstructionList;
                    VariableList    : TMVariableList;

                    DeclToken    : TToken_P; // `{` token's line
                    isNaked      : Boolean;
                    isDeclaration: Boolean;
                    Visibility   : TMVisibility;

                    mCompiler: Pointer;
                   End;

 Procedure Parse(Compiler: Pointer);
 Function CreateFunctionMangledName(Compiler: Pointer; Func: TMFunction): String;

 Implementation
Uses Compile1, Messages, Opcodes, ExpressionCompiler, SysUtils;

{ CreateFunctionMangledName }
Function CreateFunctionMangledName(Compiler: Pointer; Func: TMFunction): String;
Var P: TMParam;
Begin
 With Func do
 Begin
  Result := '__function_'+Name+'_'+ModuleName+'_'+TCompiler(Compiler).getTypeName(Return)+'_';
  For P in ParamList Do
   Result += TCompiler(Compiler).getTypeName(P.Typ)+'_';
 End;
End;

{ Parse }
Procedure Parse(Compiler: Pointer);
Type TVarRecArray = Array of TVarRec;
     PVarRecArray = ^TVarRecArray;
Var CList: TMConstructionList;
    Func : TMFunction; // our new function
    c_ID : Integer;

{ ParseConstruction }
Procedure ParseConstruction(ID: Integer);

{ ParseUntil }
Procedure ParseUntil(M: TMConstructionType);
Begin
 Inc(c_ID);
 While (CList[c_ID].Typ <> M) Do // parse loop
 Begin
  ParseConstruction(c_ID);
  Inc(c_ID);
 End;
End;

{ RemoveRedundantPushes }
Procedure RemoveRedundantPushes;
Begin
 With TCompiler(Compiler) do
   While (OpcodeList.Last^.Opcode = o_push) Do
    With OpcodeList.Last^ do
    Begin
     if (Args[0].Value = null) Then
      OpcodeList.Delete(OpcodeList.Count-1) Else
     if not (VarToStr(Args[0].Value) = 'stp') Then // we cannot remove `push(stp)`
      OpcodeList.Delete(OpcodeList.Count-1) Else
      Break;
    End;
End;

Var Str1, Str2, Str3, Str4: String;
    EType                 : TVType;
    Item                  : PMOpcode;
Begin
With TCompiler(Compiler) do
Begin
 if (ID > High(CList)) Then
  Exit;
 With CList[ID] do
 Begin
  Case Typ of
(* ctJump *)
   ctJump:
   Begin
    PutOpcode(o_jmp, [PChar(Values[0])]);
   End;

(* ctLabel *)
   ctLabel:
   Begin
    New(Item);
    With Item^ do
    Begin
     Name    := PChar(Values[0]);
     isLabel := True;
    End;
    OpcodeList.Add(Item);
   End;

(* ctExpression *)
   ctExpression:
   Begin
    ExpressionCompiler.CompileConstruction(Compiler, Values[0]);
    RemoveRedundantPushes;
   End;

(* ctReturn *)
   ctReturn:
   Begin
    EType := ExpressionCompiler.CompileConstruction(Compiler, Values[0]);

    if (not CompareTypes(Func.Return, EType)) Then // wrong type
     CompileError(PMExpression(Values[0])^.Token, eWrongType, [getTypeName(EType), getTypeName(Func.Return)]);

    if (OpcodeList.Last^.Opcode = o_push) Then // result must be in the first register, not on the stack
     PutOpcode(o_pop, ['e'+getTypePrefix(Func.Return)+'1']);

    if (not Func.isNaked) Then
     PutOpcode(o_jmp, [':'+Func.MName+'_end']) Else
     PutOpcode(o_ret);
   End;

(* ctVoidReturn *)
   ctVoidReturn:
   Begin
    if (not isTypeVoid(Func.Return)) Then
     CompileError(PToken_P(Values[0])^, eWrongType, [getTypeName(TYPE_VOID), getTypeName(Func.Return)]);

    PutOpcode(o_ret);
   End;

(* ctInlineBytecode *)
   ctInlineBytecode: PutOpcode(PChar(Values[0]), PVarRecArray(Values[1])^, LongWord(Values[2]));

(* ctFOR *)
   ctFOR:
   Begin
    Str1 := PChar(Values[2]);
    Str2 := Str1+'condition';
    Str3 := Str1+'end';

    PutLabel(Str2); { condition }
    EType := ExpressionCompiler.CompileConstruction(Compiler, Values[0]);
    if (not isTypeBool(EType)) Then
     CompileError(PMExpression(Values[0])^.Token, eWrongType, [getTypeName(EType), getTypeName(TYPE_BOOL)]);

    { condition check }
    PutOpcode(o_pop, ['if']);
    PutOpcode(o_fjmp, [':'+Str3]);

    ParseUntil(ctFOR_end);

    { step }
    ExpressionCompiler.CompileConstruction(Compiler, Values[1]);
    if (OpcodeList.Last^.Opcode = o_push) Then // remove last `push` opcode created by ExpressionCompiler.
     OpcodeList.Delete(OpcodeList.Count-1);

    PutOpcode(o_jmp, [':'+Str2]);

    PutLabel(Str3); { end }
   End;

(* ctIF *)
   ctIF:
   Begin
    Str1 := PChar(Values[1]);
    Str2 := Str1+'true';
    Str3 := Str1+'false';
    Str4 := Str1+'end';

    { compile condition }
    EType := ExpressionCompiler.CompileConstruction(Compiler, Values[0]);
    if (not isTypeBool(EType)) Then
     CompileError(PMExpression(Values[0])^.Token, eWrongType, [getTypeName(EType), getTypeName(TYPE_BOOL)]);

    { jump }
    PutOpcode(o_pop, ['if']);
    PutOpcode(o_tjmp, [':'+Str2]);
    PutOpcode(o_jmp, [':'+Str3]); // or 'o_fjmp' - from here it doesn't matter

    { 'true' }
    PutLabel(Str2);
    ParseUntil(ctIF_end);
    PutOpcode(o_jmp, [':'+Str4]);

    PutLabel(Str3);

    { 'false' }
    if (CList[c_ID+1].Typ = ctIF_else) Then // compile 'else'
    Begin
     Inc(c_ID);
     ParseUntil(ctIF_end);
    End;

    PutLabel(Str4);
   End;

(* ctWHILE *)
   ctWHILE:
   Begin
    Str1 := PChar(Values[1]);
    Str2 := Str1+'condition';
    Str3 := Str1+'end';

    { condition (loop begin) }
    PutLabel(Str2);
    EType := ExpressionCompiler.CompileConstruction(Compiler, Values[0]);
    if (not isTypeBool(EType)) Then
     CompileError(PMExpression(Values[0])^.Token, eWrongType, [getTypeName(EType), getTypeName(TYPE_BOOL)]);

    { condition check }
    PutOpcode(o_pop, ['if']);
    PutOpcode(o_fjmp, [':'+Str3]);

    { loop body }
    ParseUntil(ctWHILE_end);

    PutOpcode(o_jmp, [':'+Str2]);

    { loop end }
    PutLabel(Str3);
   End;

(* ct_DO_WHILE *)
   ct_DO_WHILE:
   Begin
    Str1 := PChar(Values[1]);
    Str2 := Str1+'begin';
    Str3 := Str1+'end';

    { loop begin }
    PutLabel(Str2);

    { parse loop }
    ParseUntil(ct_DO_WHILE_end);

    { condition }
    EType := ExpressionCompiler.CompileConstruction(Compiler, Values[0]);
    if (not isTypeBool(EType)) Then
     CompileError(PMExpression(Values[0])^.Token, eWrongType, [getTypeName(EType), getTypeName(TYPE_BOOL)]);

    { condition check }
    PutOpcode(o_pop, ['if']);
    PutOpcode(o_tjmp, [':'+Str2]);

    PutLabel(Str3); { loop end }
   End;
  End;
 End;
End;
End;

Var I, AllocatedVars, SavedRegs: Integer;
    Token                      : TToken_P;
Begin
 Func.mCompiler := Compiler;

With TCompiler(Compiler) do
Begin
 // read function return type
 Func.DeclToken := getToken(-1);

 eat(_LOWER); // <
 Func.Return := read_type; // [type]
 eat(_GREATER); // >

 // function name
 Func.Name          := read_ident; // [identifier]
 Func.ModuleName    := ModuleName;
 Func.ImportFile    := '';
 Func.isDeclaration := False;
 Func.Visibility    := Visibility;

 if (findTypeByName(Func.Name) <> -1) Then
  CompileError(eRedeclaration, [Func.Name]);

 if (findFunction(Func.Name) <> -1) Then // check for redeclaration
  CompileError(eRedeclaration, [Func.Name]);

 // parameter list
 eat(_BRACKET1_OP); // (

 SetLength(Func.ParamList, 0);
 While (next_t <> _BRACKET1_CL) Do
 Begin
  if (Length(Func.ParamList) > 0) Then
   eat(_COMMA); // parameters are separated by comma

  With Func do
  Begin
   SetLength(ParamList, Length(ParamList)+1); // resize the param array
   With ParamList[High(ParamList)] do // read parameter
   Begin
    Typ := read_type;

    if (next_t in [_COMMA, _BRACKET1_CL]) Then
    Begin
     if (not Func.isDeclaration) and (Length(ParamList) <> 1) Then
      CompileError(eExpectedIdentifier, [next.Display]);

     Func.isDeclaration := True;
     Continue;
    End;

    Name := read_ident;

    if (isTypeVoid(Typ)) Then // void param
     CompileError(eParamVoid, [Name]);

    // search if parameter is not duplicated
    For I := Low(ParamList) To High(ParamList)-1 Do // do not check new-read parameter
     if (ParamList[I].Name = Name) Then
     Begin
      CompileError(eRedeclaration, [Name]); // parameter has been redeclared
      Break;
     End;
   End;
  End;
 End;
 eat(_BRACKET1_CL); // read remaining parenthesis

 // read special function attributes (if found)
 Func.isNaked := False;
 While (true) Do
 Begin
  Token := read;
  Case Token.Token of
   _NAKED: Func.isNaked := True;
   _IN: Func.ImportFile := read.Display;
   else Break;
  End;
 End;
 setPosition(getPosition-1); // go back by 1 token

 Func.MName := CreateFunctionMangledName(Compiler, Func); // create function mangled name

 SetLength(Func.ConstructionList, 0); // there are no constructions in this compiled function yet
 SetLength(Func.VariableList, 0); // also - there are no variables yet

 SetLength(FunctionList, Length(FunctionList)+1); // add new function to the list
 FunctionList[High(FunctionList)] := Func;

 if (Func.ImportFile <> '') Then // if file is imported from another (already compiled) module, we don't create any bytecode
 Begin
  semicolon;
  Exit;
 End;

 if (Func.isDeclaration) and not (next_t = _SEMICOLON) Then
  CompileError(eExpected, [';', next.Display]);

 // add parameters as variables
 With Func do
  For I := Low(ParamList) To High(ParamList) Do
   __variable_create(ParamList[I].Name, ParamList[I].Typ, -I, True);

 PutLabel(Func.MName); // new label

 // function begin code
 if (not Func.isNaked) Then
 Begin
  //PutOpcode(o_push, ['stp']);
 End;
 // </>

 NewScope(sFunction); // new scope (because we're in function)
 ParseCodeBlock; // parse function's code
 RemoveScope; // and remove scope

 // now, we have a full construction list used in this function; so - let's optimize and generate bytecode! :)
 CList := FunctionList[High(FunctionList)].ConstructionList;

 { local variable allocating }
 AllocatedVars := 0;

 if (not Func.isNaked) Then
 Begin
  With FunctionList[High(FunctionList)] do
   For I := Low(VariableList) To High(VariableList) Do
    if (VariableList[I].RegID <= 0) and (not VariableList[I].isParam) Then
     Inc(AllocatedVars); // next variable to allocate

  // if `AllocatedVars == 0`, then the created here `add(stp, 0)` will be deleted in optimizer (if enabled), so we don't need to bother it.
  PutOpcode(o_add, ['stp', AllocatedVars]); // allocate space for local variables
 End;

 { saving registers values (as some variables may have been put into the registers) }
 SavedRegs := 0;
 With FunctionList[High(FunctionList)] do
 Begin
  For I := Low(VariableList) To High(VariableList) Do
   With VariableList[I] do
    if (RegID > 0) Then
    Begin
     PutOpcode(o_push, ['e'+RegChar+IntToStr(RegID)]);
     Inc(SavedRegs);
    End;

  For I := Low(VariableList) To High(VariableList) Do
   With VariableList[I] do
    if (RegID <= 0) Then
    Begin
     RegID -= SavedRegs;

     if (isParam) Then
      RegID -= AllocatedVars;
    End;
 End;

 // parse constructions
 c_ID := 0;
 Repeat
  ParseConstruction(c_ID);
  Inc(c_ID);
 Until (c_ID > High(CList));

 // function end code
 PutLabel(Func.MName+'_end');

 With FunctionList[High(FunctionList)]  do
 Begin
  For I := High(VariableList) Downto Low(VariableList) Do
   With VariableList[I] do
    if (RegID > 0) Then
     PutOpcode(o_pop, ['e'+RegChar+IntToStr(RegID)]);
 End;

 if (not Func.isNaked) Then
 Begin
  PutOpcode(o_sub, ['stp', AllocatedVars+Length(Func.ParamList)]);
  //PutOpcode(o_pop, ['stp']);
  //PutOpcode(o_sub, ['stp', Length(Func.ParamList)]);
 End;

 PutOpcode(o_ret);
 // </>
End;
End;
End.
