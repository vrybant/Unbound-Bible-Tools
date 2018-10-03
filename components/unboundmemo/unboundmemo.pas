unit UnboundMemo;

interface

uses
  {$ifdef windows} Windows, {$endif} Forms, SysUtils, LResources,
  Classes, Graphics, Controls, ExtCtrls, LCLProc, LCLType, LazUTF8,
  RichMemo, RichMemoEx;

type
  TUnboundMemo = class(TRichMemoEx)
  protected
    procedure CreateWnd; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp  (Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyUp  (var Key: Word; Shift: TShiftState); override;
  private
    FLinkable : boolean;
    FParagraphic : boolean;
    SelStartTemp  : integer;
    SelLengthTemp : integer;
    function Foreground: integer;
    function  Colored: boolean;
    function  GetLink: string;
    function  GetParagraphNumber: integer;
    procedure GetParagraphRange;
    function  GetStartSelection: integer;
    function  GetEndSelection: integer;
  public
    Hyperlink : string;
    ParagraphStart : integer;
    ParagraphCount : integer;
    constructor Create(AOwner: TComponent); override;
    procedure SelectParagraph(n : integer);
    procedure SelectWord;
    procedure SaveSelection;
    procedure RestoreSelection;
  published
    property Linkable    : boolean read FLinkable    write FLinkable    default False;
    property Paragraphic : boolean read FParagraphic write FParagraphic default False;
  end;

procedure Register;

implementation

const
  fgText     = 0;
  fgLink     = 1;
  fgStrong   = 2;
  fgFootnote = 3;

function MyStrToInt(st: string): integer;
var v, r : integer;
begin
  st := Trim(st);
  Val(st, v, r);
  if r=0 then Result := v else Result := 0;
end;

function RemoveCRLF(s: string): string;
const
  CharLF = #10; // line feed
  CharCR = #13; // carriage return
begin
  s := StringReplace(s, CharLF, '', [rfReplaceAll]);
  s := StringReplace(s, CharCR, '', [rfReplaceAll]);
  Result := s;
end;

constructor TUnboundMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Hyperlink := '';
  ParagraphStart := 0;
  ParagraphCount := 0;
  SelStartTemp := 0;
  SelLengthTemp := 0;
  Cursor := crArrow;
end;

procedure TUnboundMemo.CreateWnd;
begin
  inherited;
  if ReadOnly then HideCursor;
end;

function TUnboundMemo.Foreground: integer;
begin
  Result := fgText;

  case SelAttributes.Color of
    clNavy   : Result := fgLink;
    clPurple : Result := fgStrong;
    clGray   : Result := fgFootnote;
  end;

end;

function TUnboundMemo.Colored: boolean;
begin
  Result := Foreground = fgLink;
end;

function TUnboundMemo.GetLink: string;
var
  fore : integer;
  x1,x2,x0 : integer;
  n1,n2 : integer;
begin
  Result := '';
  if SelLength > 0 then Exit;

  fore := Foreground;
  if fore = fgText then Exit;
  GetSel(n1{%H-},n2{%H-});

  x0 := SelStart;
  x1 := x0;
  repeat
    dec(x1);
    SetSel(x1, x1);
  until (Foreground <> fore) or (x1 < 0);

  inc(x1);
  if x1 < 0 then inc(x1);

  x2 := x0;
  repeat
    inc(x2);
    SetSel(x2, x2);
  until Foreground <> fore;

  SetSel(x1, x2); Result := RemoveCRLF(SelText);
  SetSel(n1, n2);
end;

procedure TUnboundMemo.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  {$ifdef windows} if ReadOnly or (ssCtrl in Shift) then HideCursor; {$endif}
end;

procedure TUnboundMemo.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  //if Linkable then Hyperlink := GetLink else Hyperlink := '';
  Hyperlink := GetLink;

  if Paragraphic and (Button = mbLeft) then GetParagraphRange;
  {$ifdef windows} if ReadOnly or (ssCtrl in Shift) then HideCursor; {$endif}
  inherited;
end;

procedure TUnboundMemo.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  {$ifdef windows} if ReadOnly or (ssCtrl in Shift) then HideCursor; {$endif}
end;

procedure TUnboundMemo.KeyUp(var Key: Word; Shift: TShiftState);
begin
  inherited;
  {$ifdef windows}
  if Linkable and not ReadOnly and (Key = VK_CONTROL) then ShowCaret(Handle);
  {$endif}
end;

{$ifdef windows}
function IsNumeral(c: string): boolean;
begin
  Result :=
    (c = '0') or (c = '1') or (c = '2') or (c = '3') or (c = '4') or
    (c = '5') or (c = '6') or (c = '7') or (c = '8') or (c = '9') ;
end;
{$endif}

function TUnboundMemo.GetParagraphNumber: integer;
var
  x1, x2 : integer;
  char : string;
begin
  Result := 0;
  {$ifdef windows} Hide_Selection; {$endif}
  x1 := SelStart;

  {$ifdef windows}
  if not Colored then
    while true and (x1 > 0) do
      begin
        dec(x1);
        char := GetTextRange(x1, 1);
        if IsNumeral(char) then break;
      end;
  {$endif}

  while not Colored and (x1 > 0) do
    begin
      dec(x1);
      SetSel(x1, x1);
    end;

  repeat
    dec(x1);
    SetSel(x1, x1);
  until not Colored or (x1 < 0);

  x2 := x1;
  repeat
    inc(x2);
    SetSel(x2, x2);
  until not Colored;

  inc(x1);

  SetSel(x1,x2); Result := MyStrToInt(SelText);
  SetSel(x1,x1+1);

  {$ifdef windows} Show_Selection;{$endif}
end;

procedure TUnboundMemo.GetParagraphRange;
var
  ParagraphEnd : integer;
  x1,x2 : integer;
begin
  GetSel(x1{%H-},x2{%H-});
  SetSel(x2,x2); ParagraphEnd   := GetParagraphNumber;
  SetSel(x1,x1); ParagraphStart := GetParagraphNumber;
  ParagraphCount := ParagraphEnd - ParagraphStart + 1;
  if x1 <> x2 then SetSel(x1,x2);
end;

{$ifdef windows}
procedure TUnboundMemo.SelectParagraph(n : integer);
var
  w, line : string;
  i, len, x : integer;
begin
  HideSelection := False; // important

  w := ' ' + IntToStr(n) + ' ';
  len := length(w);

  for i:=0 to LineCount - 1 do
    begin
      line := Lines[i];

      if copy(line,1,len) = w then
         begin
           x := LineIndex(i);
           SetSel(x,x+1);
           HideCursor;
         end;
    end;

  ParagraphStart := n;
  ParagraphCount := 1;
end;
{$endif}

{$ifdef unix}
procedure TUnboundMemo.SelectParagraph(n : integer);
var
  i, x : integer;
  L : boolean;
begin
  L := False;
  x := 0;

  i := 0;
  while True do
    begin
      SetSel(i,i);
      if SelStart <> i then break;

      if Colored then
        begin
          if not L then
            begin
              inc(x);
              if x = n then
                begin
                  SetSel(i,i+1);
                  break;
                end;
            end;
          L := True;
        end;

      if not Colored then L := False;
      inc(i);
    end;

  SetFocus;
end;
{$endif}

function TUnboundMemo.GetStartSelection: integer;
var
  i, temp : integer;
begin
  temp := SelStart;
     i := SelStart;

  SetSel(i-1,i);
  while (SelText <> ' ') and (i > 0)  do
    begin
      dec(i);
      SetSel(i-1,i);
    end;

  Result := i;
  SetSel(temp, temp);
end;

function TUnboundMemo.GetEndSelection: integer;
var
  i, len, temp : integer;
begin
  temp := SelStart;
     i := SelStart;
   len := i + 50;

  SetSel(i,i+1);
  while (LowerCase(SelText) <> UpperCase(SelText)) and (i < len) do
    begin
      inc(i);
      SetSel(i,i+1);
    end;

  Result := i;
  SetSel(temp, temp);
end;

procedure TUnboundMemo.SelectWord;
begin
  SelStart  := GetStartSelection;
  SelLength := GetEndSelection - SelStart;
end;

procedure TUnboundMemo.SaveSelection;
begin
  SelStartTemp  := SelStart;
  SelLengthTemp := SelLength;
end;

procedure TUnboundMemo.RestoreSelection;
begin
  SelStart  := SelStartTemp;
  SelLength := SelLengthTemp;
end;

procedure Register;
begin
  {$I unboundmemoicon.lrs}
  RegisterComponents('Common Controls',[TUnboundMemo]);
end;

end.

