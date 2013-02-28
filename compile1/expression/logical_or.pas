Procedure ParseLogicalOR;
Var TypeLeft, TypeRight: PMType;
Begin
 Result := CompileSimple(TypeLeft, TypeRight);

 With Compiler do
  if (not isTypeBool(Result)) Then
   Error(eUnsupportedOperator, [getTypeDeclaration(TypeLeft), getDisplay(Expr), getTypeDeclaration(TypeRight)]) Else
   PutOpcode(o_or, ['eb1', 'eb2']);
End;
