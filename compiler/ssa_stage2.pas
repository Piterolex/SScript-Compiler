Var VisitedParentNodes: TCFGNodeList;

(* FetchSSAVarID *)
Function FetchSSAVarID(Symbol: TSymbol; SearchNode: TCFGNode): TSSAVarID;

  { VisitExpression }
  Function VisitExpression(Expr: PExpressionNode): TSSAVarID;
  Var Param: PExpressionNode;
      PList: TParamList;
      I    : Integer;
      Sym  : TSymbol;
  Begin
   SetLength(Result.Values, 0);

   if (Expr = nil) Then
    Exit;

   if (Expr^.Typ in MLValueOperators) and (Expr^.Left^.Symbol = Symbol) Then
    Exit(Expr^.Left^.SSA);

   if (Expr^.Typ = mtFunctionCall) and (Expr^.Symbol <> nil) Then
   Begin
    Sym := TSymbol(Expr^.Symbol);

    Case Sym.Typ of
     stFunction: PList := Sym.mFunction.ParamList;
     stVariable: PList := Sym.mVariable.Typ.FuncParams;
     else
      TCompiler(Compiler).CompileError(eInternalError, ['{ ssa_stage2 } VisitExpression: unknown symbol type ('+IntToStr(ord(Sym.Typ))+')!']);
    End;

    For I := Low(PList) To High(PList) Do // iterate each parameter
     if (PList[I].isVar) Then
      if (I <= High(Expr^.ParamList)) Then
      Begin
       if (Expr^.ParamList[I]^.Symbol = Symbol) Then
        Exit(Expr^.ParamList[I]^.SSA);
      End;
   End;

   Result := VisitExpression(Expr^.Left);

   if (Length(Result.Values) = 0) Then
    Result := VisitExpression(Expr^.Right);

   For Param in Expr^.ParamList Do
    if (Length(Result.Values) = 0) Then
     Result := VisitExpression(Param);
  End;

  { VisitNode }
  Function VisitNode(Node, EndNode: TCFGNode; const CheckChildrenNotParent: Boolean=False; const CheckEndNode: Boolean=False): TSSAVarID;
  Var Left, Right, Parent: TSSAVarID;
      I, J               : Integer;
      Can                : Boolean;
      Child              : TCFGNode;
  Begin
   SetLength(Result.Values, 0);

   if (Node = nil) or ((not CheckEndNode) and (Node = EndNode)) or (VisitedParentNodes.IndexOf(Node) <> -1) Then
    Exit;
   VisitedParentNodes.Add(Node);

   if (Node.Typ = cetCondition) Then // if condition...
   Begin
    // -> left
    Left := VisitNode(Node.Child[0], Node.Child[2], True, True);

    if (Length(Left.Values) = 0) and
       (AnythingFromNodePointsAt(Node.Child[0], Node.Child[2], Node)) and
       (AnythingFromNodePointsAt(Node.Child[0], Node.Child[2], SearchNode)) Then // if inside a loop... (see note below)
        Left := VisitNode(SearchNode, Node.Child[2], True, True);

    // -> right
    Right := VisitNode(Node.Child[1], Node.Child[2], True, True);

    if (Length(Right.Values) = 0) and
       (AnythingFromNodePointsAt(Node.Child[1], Node.Child[2], Node)) and
       (AnythingFromNodePointsAt(Node.Child[1], Node.Child[2], SearchNode)) Then // if inside a loop... (see note below)
        Right := VisitNode(SearchNode, Node.Child[2], True, True);

    // -> parent
    Parent := VisitNode(Node.Parent, EndNode, False, True);

    {
     @Note (about that 2 long if-s above):

     Let's consider this code:
       for (var<int> i=0; i<=2; i++)
         i;
       return 0;

     In control flow graph it will look like this:
           [ i=0 ]
              |
          [ i<= 2 ]-----
          /       \     \
       [ # ]       \     \
         |          |     \
       [ i ]        |      \
         |          |       \
      [ i++ ]  [ return 0 ] |
          \                 /
           -----------------
     (# - hidden temporary node which is result of `for` loop parsing)

     If we were parsing `i` and did just 'Left := VisitNode(Node.Child[0], Node.Child[2], True);', it would return nothing (sstNone, precisely), as
     the `#` node located before the `i` node would have been parsed for the second time.
     Thus instead of clearing the `VisitedParentNodes` list (which would cause stack overflow), we're just searching from the `i` node (which hasn't
     been parsed so far).
     I guess that's all the magic here.
    }

    // coalesce left side
    For I := 0 To High(Left.Values) Do
    Begin
     SetLength(Result.Values, Length(Result.Values)+1);
     Result.Values[High(Result.Values)] := Left.Values[I];
    End;

    // coalesce right side checking if there aren't any duplicates
    For I := 0 To High(Right.Values) Do
    Begin
     Can := True;

     For J := 0 To High(Result.Values) Do
      if (Result.Values[J] = Right.Values[I]) Then
       Can := False;

     if (Can) Then
     Begin
      SetLength(Result.Values, Length(Result.Values)+1);
      Result.Values[High(Result.Values)] := Right.Values[I];
     End;
    End;

    // coalesce right side checking if there aren't any duplicates
    For I := 0 To High(Parent.Values) Do
    Begin
     Can := True;

     For J := 0 To High(Result.Values) Do
      if (Result.Values[J] = Parent.Values[I]) Then
       Can := False;

     if (Can) Then
     Begin
      SetLength(Result.Values, Length(Result.Values)+1);
      Result.Values[High(Result.Values)] := Parent.Values[I];
     End;

     // @TODO: too much DRY!
    End;
   End;

   if (CheckChildrenNotParent) Then
   Begin
    For Child in Node.Child Do
     if (Length(Result.Values) = 0) Then
      Result := VisitNode(Child, EndNode, True, CheckEndNode);
   End;

   if (Length(Result.Values) = 0) Then
    Result := VisitExpression(Node.Value);

   if (not CheckChildrenNotParent) and (Length(Result.Values) = 0) Then
    Result := VisitNode(Node.Parent, EndNode, False, CheckEndNode);
  End;

Var Origin: TCFGNode;
Begin
 if (Symbol = nil) Then
 Begin
  DevLog(dvError, 'FetchSSAVarID', 'Function called with `Symbol = nil` (shouldn''t happen!)');
  Exit;
 End;

 Origin := SearchNode;
 VisitedParentNodes.Clear;

 SetLength(Result.Values, 0);

 if (SearchNode.Typ = cetCondition) Then
 Begin
  if (AnythingFromNodePointsAt(SearchNode.Child[0], SearchNode.Child[2], SearchNode)) or
     (AnythingFromNodePointsAt(SearchNode.Child[1], SearchNode.Child[2], SearchNode)) Then
  Begin
   // if inside a loop
   Result := VisitNode(SearchNode, nil);
  End;
 End;

// SearchNode := SearchNode.Parent;

 if (Length(Result.Values) = 0) Then
  Result := VisitNode(SearchNode.Parent, nil);

 if (Length(Result.Values) = 0) Then
 Begin
  DevLog(dvWarning, 'FetchSSAVarID', 'Couldn''t fetch variable''s SSA ID; var = '+TSymbol(Symbol).Name+', line = '+IntToStr(Origin.getToken^.Line));

  With TSymbol(Symbol).mVariable do
   if (not isConst) and (not isFuncParam) Then
    TCompiler(Compiler).CompileHint(Origin.getToken, hUseOfUninitializedVariable, [RefSymbol.Name]);
 End;
End;

(* VisitExpression *)
Procedure VisitExpression(Node: TCFGNode; Expr: PExpressionNode);
Var Param: PExpressionNode;
Begin
 if (Expr = nil) Then
  Exit;

 if (Expr^.Typ = mtIdentifier) and (Length(Expr^.SSA.Values) = 0) Then // if variable with no SSA idenitifer assigned yet
  Expr^.SSA := FetchSSAVarID(TSymbol(Expr^.Symbol), Node);

 VisitExpression(Node, Expr^.Left);
 VisitExpression(Node, Expr^.Right);
 For Param in Expr^.ParamList Do
  VisitExpression(Node, Param);
End;

(* VisitNode *)
Procedure VisitNode(Node, EndNode: TCFGNode);
Var Child: TCFGNode;
Begin
 if (Node = nil) or (Node = EndNode) or (VisitedNodes.IndexOf(Node) <> -1) Then
  Exit;
 VisitedNodes.Add(Node);

 VisitExpression(Node, Node.Value); // visit node's expression

 For Child in Node.Child Do
  VisitNode(Child, EndNode);
End;

(* Execute *)
Procedure Execute;
Begin
 VisitedParentNodes := TCFGNodeList.Create;

 Try
  VisitedNodes.Clear;
  VisitNode(Func.FlowGraph.Root, nil);
 Finally
  VisitedParentNodes.Free;
 End;
End;
