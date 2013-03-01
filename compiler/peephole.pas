(*
 Copyright © by Patryk Wychowaniec, 2013
 All rights reserved.
*)
{$MODE DELPHI}
Unit Peephole;

 Interface
 Uses Compile1, Variants;

 Procedure OptimizeBytecode(Compiler: TCompiler);

 Implementation
Uses Opcodes, SysUtils, Messages;

(* isRegister *)
{
 Returns `true` when passed primary type is a register
}
Function isRegister(T: TPrimaryType): Boolean;
Begin
 Result := T in [ptBoolReg, ptCharReg, ptIntReg, ptFloatReg, ptStringReg, ptReferenceReg];
End;

(* isInt *)
{
 Returns `true` when passed primary type is an int
}
Function isInt(T: TPrimaryType): Boolean;
Begin
 Result := T in [ptInt];
End;

(* isVariableHolder *)
{
 Returns `true` when passed opcode argument is a variable-holder.

 @Note: 'variable-holders' are registers `e_3` and `e_4`, and also a stackvals - as only there a variable
        can be allocated.
}
Function isVariableHolder(T: TMOpcodeArg): Boolean;
Begin
 Result := isRegister(T.Typ);

 if (Result) Then
  Exit(StrToInt(VarToStr(T.Value)) > 2) Else
  Exit(T.Typ = ptStackVal);
End;

(* OptimizeBytecode *)
{
 Optimizes bytecode for faster execution.
}
Procedure OptimizeBytecode(Compiler: TCompiler);
Var Pos, Pos2            : LongWord;
    oCurrent, oNext, oTmp: TMOpcode;
    pCurrent, pNext, pTmp: PMOpcode;
    CanBeRemoved         : Boolean;
    PushFix, I           : Integer;
    Optimized            : Boolean;
    TmpArg               : TMOpcodeArg;

    // isArgumentChanging
    Function isArgumentChanging(Param: Byte): Boolean;
    Begin
     Result := (oTmp.Args[Param] = oCurrent.Args[0]) or (oTmp.Args[Param] = oCurrent.Args[1]);
    End;

    // __optimize1
    Procedure __optimize1(Param: Byte);
    Begin
     if (oTmp.Args[Param] = oCurrent.Args[0]) Then
     Begin
      TmpArg           := oTmp.Args[Param];
      pTmp.Args[Param] := oCurrent.Args[1]; // replace register with value

      if (isValidOpcode(pTmp^)) Then // is it a valid opcode now?
      Begin
       if (pTmp.Args[Param].Typ = ptStackVal) and (PushFix <> 0) Then
        pTmp.Args[Param].Value -= PushFix;

       Optimized := True;
      End Else // if it's not
       pTmp.Args[Param] := TmpArg;
     End;
    End;


Begin
 With Compiler do
 Begin
  Pos := 0;

  While (Pos < OpcodeList.Count-2) Do
  Begin
   pCurrent := OpcodeList[Pos];
   pNext    := OpcodeList[Pos+1];

   oCurrent := pCurrent^;
   oNext    := pNext^;

   if (oCurrent.isLabel) or (oCurrent.isComment) or (oCurrent.Opcode in [o_byte, o_word, o_integer, o_extended]) Then
   Begin
    Inc(Pos);
    Continue;
   End;

   {
    mov(register, register)
    ->
    [nothing]
   }
   if (oCurrent.Opcode = o_mov) Then
   Begin
    if (oCurrent.Args[0] = oCurrent.Args[1]) Then
    Begin
     OpcodeList.Remove(pCurrent);
     Continue;
    End;
   End;

   {
    push(value)
    pop(register)
    ->
    mov(register, value)
   }
   if (oCurrent.Opcode = o_push) and (oNext.Opcode = o_pop) Then
   Begin
    if (oCurrent.Args[0] = oNext.Args[0]) Then
    Begin
     {
      push(some register)
      pop(the same register)
      ->
      [nothing]
      (it would be anyway optimized later (because this would be changed to `mov(reg, reg)` and then removed), but I'd like to do it here)
     }
     OpcodeList.Remove(pCurrent);
     OpcodeList.Remove(pNext);
     Continue;
    End;

    pCurrent.Opcode := o_mov;

    SetLength(pCurrent.Args, 2);
    pCurrent.Args[0] := oNext.Args[0];
    pCurrent.Args[1] := oCurrent.Args[0];

    OpcodeList.Remove(pNext);

    Continue;
   End;

   {
     add(register, 0)
    or
     sub(register, 0)
    ->
    [nothing]
   }
   if (oCurrent.Opcode in [o_add, o_sub]) Then
   Begin
    if (isInt(oCurrent.Args[1].Typ) and (VarToStr(oCurrent.Args[1].Value) = '0')) Then
    Begin
     OpcodeList.Remove(pCurrent);
     Continue;
    End;
   End;

   {
    mov(reg1, reg2)
    mov(reg2, reg1)
    ->
    mov(reg1, reg2)
   }
   if (oCurrent.Opcode = o_mov) and (oNext.Opcode = o_mov) Then
   Begin
    if (oCurrent.Args[0] = oNext.Args[1]) and
       (oCurrent.Args[1] = oNext.Args[0]) Then
       Begin
        OpcodeList.Remove(pNext);
        Continue;
       End;
   End;

   // @TODO: mul(register, 0) -> mov(register, 0)

   {
    mov(register, value)
    (...)
    opcode(some value or reg, register)
    ->
    opcode(some value or reg, value)

    Assuming that the register's value does not change in the opcodes between (it's checked, of course).
   }
   if (oCurrent.Opcode = o_mov) and not (oCurrent.Args[0].Typ = ptStackVal) Then
   Begin
    CanBeRemoved := False;
    Optimized    := False;
    Pos2         := Pos+1;
    PushFix      := 0;

    While (Pos2 < OpcodeList.Count-1) Do
    Begin
     pTmp := OpcodeList[Pos2];
     oTmp := pTmp^;

     if (oTmp.isLabel) Then // stop on labels
      Break;

     if (oTmp.isComment) or (Length(oTmp.Args) = 0) Then // skip comments and `nop`s()
     Begin
      Inc(Pos2);
      Continue;
     End;

     if (oTmp.Opcode in [o_mov, o_pop]) and (isArgumentChanging(0)) Then
     Begin
      CanBeRemoved := True;
      Break;
     End;

     if (oTmp.Opcode in [o_neg, o_not, o_xor, o_or, o_and, o_shr, o_shl, o_strjoin, o_add, o_sub, o_mul, o_div, o_mod]) and
        (isArgumentChanging(0)) Then
         Break; // the register's value is changing somewhere by the way

     if (oTmp.Opcode = o_arset) Then // arset(out, in, in)
      if (isArgumentChanging(0)) Then
      Begin
       CanBeRemoved := True;
       Break;
      End;

     if (oTmp.Opcode = o_arget) Then // arget(in, in, out)
      if (isArgumentChanging(2)) Then
      Begin
       CanBeRemoved := True;
       Break;
      End;

     if (oTmp.Opcode = o_arset) Then // arcrt(out, in, in)
      if (isArgumentChanging(0)) Then
      Begin
       CanBeRemoved := True;
       Break;
      End;

     if (oTmp.Opcode in [o_call, o_acall, o_jmp, o_fjmp, o_tjmp]) Then // stop on jumps and calls
      Break;

     if (oTmp.Opcode = o_arget) and (oTmp.Args[1].Typ = ptInt) Then
      PushFix -= oTmp.Args[1].Value;

     { optimize }
     For I := Low(oTmp.Args) To High(oTmp.Args) Do
      __optimize1(I);

     if (oTmp.Opcode = o_push) Then
      Inc(PushFix);

     if (oTmp.Opcode = o_pop) Then
      Dec(PushFix);

     Inc(Pos2);
    End;

    { if optimized anything }
    if (Optimized) Then
    Begin
     if (not isVariableHolder(pCurrent^.Args[0])) Then
     Begin
      if (pCurrent^.Opcode <> o_mov) Then
       CompileError(eInternalError, ['`mov` expected, but `'+Opcodes.OpcodeList[ord(pCurrent^.Opcode)].Name+'` found']);

      OpcodeList.Remove(pCurrent); // and remove the first `mov`

      Dec(Pos);
      Continue;
     End;
    End Else
    Begin
     if (not isVariableHolder(pCurrent^.Args[0])) and (CanBeRemoved) Then
     {
      the first `mov` is unusable.
      Like in this code:
       mov(ei1, 10) // current `ei1` in unused, so this `mov` can be removed and it won't affect anything
       mov(ei1, 20)
     }
     Begin
      OpcodeList.Remove(pCurrent);
      Dec(Pos);
      Continue;
     End;
    End;
   End;

   Inc(Pos);
  End;
 End;
End;
End.