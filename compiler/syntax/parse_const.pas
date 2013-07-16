(*
 Copyright © by Patryk Wychowaniec, 2013
 All rights reserved.
*)
Unit Parse_CONST;

 Interface

 Procedure Parse(Compiler: Pointer);

 Implementation
Uses Compile1, ExpressionCompiler, Tokens, symdef, Messages, Opcodes;

{ Parse }
Procedure Parse(Compiler: Pointer);
Var Variable  : TVariable;
    SymbolList: TSymbolList;
Begin
With TCompiler(Compiler), Parser do
Begin
 if not ((CompilePass = _cp2) or (inFunction)) Then // constants are parsed in the second pass or inside a function
 Begin
  read_until(_SEMICOLON);
  Exit;
 End;

 if (inFunction) Then
  SymbolList := getCurrentFunction.SymbolList Else
  SymbolList := getCurrentNamespace.SymbolList;

 While (true) Do
 Begin
  Variable := TVariable.Create;
  Variable.Attributes += [vaConst, vaDontAllocate];

  With Variable.RefSymbol do
  Begin
   Range      := getCurrentRange;
   mCompiler  := Compiler;
   Visibility := getVisibility;

   DeclToken     := next_pnt;
   DeclNamespace := getCurrentNamespace;
   DeclFunction  := getCurrentFunction;
   Name          := read_ident; // [identifier]

   RedeclarationCheck(Name); // check for redeclaration of the constant
  End;

  eat(_EQUAL); // =

  Variable.Value            := read_constant_expr; // [constant value]
  Variable.Value^.IdentName := Variable.RefSymbol.Name;

  With Variable.Value^ do
  Begin
   if (isConstant) Then // is this a constant expression?
   Begin
    Variable.Typ := getTypeFromExpression(Variable.Value);
   End Else // if it's not - show error
   Begin
    CompileError(eExpectedConstant, []);
    Variable.Value := EmptyExpression;
   End;
  End;

  SymbolList.Add(TSymbol.Create(stConstant, Variable));

  Dec(TokenPos); // ExpressionCompiler 'eats' comma.

  if (next_t = _COMMA) Then // const(...) name1=value1, name2=value2, name3=value3...
   read Else
   Begin
    semicolon;
    Break;
   End;
 End;
End;
End;
End.
