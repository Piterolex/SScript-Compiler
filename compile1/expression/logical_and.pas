Procedure ParseLogicalAND;
Var TypeLeft, TypeRight: TVType;
Begin
 Result := CompileSimple(TypeLeft, TypeRight);

 With Compiler do
  if (not isTypeBool(Result)) Then
   Error(eUnsupportedOperator, [getTypeName(TypeLeft), getDisplay(Expr), getTypeName(TypeRight)]) Else
   PutOpcode(o_and, ['eb1', 'eb2']);
End;
