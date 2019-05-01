unit ParseWin;

interface

uses
  Classes, SysUtils, StrUtils, Graphics;

function Parse(s: string; jtag: boolean; html: boolean): string;

var DefaultFont: TFont;

implementation

const
  rtf_close = '}';

function Prefix(ps, st: string): boolean;
begin
  Result := Pos(ps, st) = 1;
end;

function ToStr(value: longint): string;
begin
 System.Str(value, Result);
end;

procedure Replace(var s: string; const oldPattern, newPattern: string);
begin
  s := StringReplace(s, oldPattern, newPattern, [rfReplaceAll]);
end;

procedure DelDoubleSpace(var s: string);
begin
  s := DelSpace1(s);
end;

function ListToString(const List: TStringArray): string;
var s : string;
begin
  Result := '';
  for s in List do Result += s;
end;

function XmlToList(s: string): TStringArray;
var
  temp : string = '';
  i : integer = 0;
  c : char;
begin
  SetLength(Result,Length(s)+1);

  for c in s do
    begin
      if c = '<' then
        begin
          Result[i] := temp;
          inc(i);
          temp := '';
        end;

      temp := temp + c;

      if c = '>' then
        begin
          Result[i] := temp;
          inc(i);
          temp := '';
        end;
    end;

  if temp <> '' then
    begin
      Result[i] := temp;
      inc(i);
    end;

  SetLength(Result,i);
end;

function rtf_open: string;
begin
  Result :=
      '{\rtf1\ansi\ansicpg1251\cocoartf1187 '
    + '{\fonttbl'
    + '{\f0 default;}'
    + '{\f1 ' + DefaultFont.Name + ';}'
    + '}'
    + '{\colortbl;'
    + '\red0\green0\blue0;'        // 1 black
    + '\red192\green0\blue0;'      // 2 red
    + '\red0\green0\blue128;'      // 3 navy
    + '\red0\green128\blue0;'      // 4 green
    + '\red128\green128\blue128;'  // 5 gray
    + '\red0\green128\blue128;'    // 6 teal
    + '\red128\green0\blue0;'      // 7 maroon
    + '\red153\green102\blue51;'   // 8 brown
    + '\red139\green69\blue19;'    // 9 saddlebrown
    + '\red128\green0\blue128;'    // 10 purple
    + '}'
    + '\f1\cf1';
end;

function ParseString(s: string; j: boolean): string;
var
  r : string = '';
  color : string;
const
  jColor : boolean = false;
begin
  // Result := '\cf2 ' + s + '\cf1 '; Exit; // show tags

  if jColor then color := '\cf7' else color := '\cf1';

  if j then if s =  '<J>' then begin r := '\cf7 '; jColor := true;  end;
  if j then if s = '</J>' then begin r := '\cf1 '; jColor := false; end;

  if s =  '<f>' then r := '\cf6\super ';
  if s = '</f>' then r := color + '\nosupersub ';
  if s =  '<i>' then r := '\cf5\i ';
  if s = '</i>' then r := color + '\i0 ';
  if s =  '<l>' then r := '\cf3 ';
  if s = '</l>' then r := '\cf1 ';
  if s =  '<r>' then r := '\cf2 ';
  if s = '</r>' then r := '\cf1 ';
  if s =  '<n>' then r := '\cf5 ';       // note
  if s = '</n>' then r := color + ' ';
  if s =  '<m>' then r := '\cf5\super '; // morphology
  if s = '</m>' then r := color + '\nosupersub ';

  {$ifndef linux}
    if s =  '<S>' then r := '\cf8\super ';
    if s = '</S>' then r := color + '\nosupersub ';
  {$endif}

  s := LowerCase(s);

  if s =   '<i>' then r := '\cf5\i ';
  if s =  '<em>' then r := '\cf5\i ';
  if s =  '</i>' then r := color + '\i0 ';
  if s = '</em>' then r := color + '\i0 ';
  if s =   '<a>' then r := '\cf5 ';
  if s =  '</a>' then r := '\cf1 ';
  if s =   '<b>' then r := '\cf8\b ' ;
  if s =  '</b>' then r := '\cf1\b0 ';
  if s =   '<h>' then r := '\b ';
  if s =  '</h>' then r := '\b0 ';
  if s =  '</p>' then r := '\par ';
  if s =  '<br>' then r := '\par ';

  if s = '<tab>' then r := '\tab ';
  if s = '<rtl>' then r := '\rtlpar\qr ';
  if s = '<ltr>' then r := '\ltrpar\qr ';

  if s = '<small>' then r := '\fs18 ';

  Result := r;
end;

function ParseHtml(s: string): string;
var
  r : string = '';
begin
  r := s;
  s := LowerCase(s);

  if Prefix('<a ', s) then s := '<a>';
  if Prefix('<p ', s) then s := '<p>';

  if s =  '<i>' then r := '\i ';
  if s = '</i>' then r := '\i0 ';
  if s =  '<a>' then r := '\cf5 ';
  if s = '</a>' then r := '\cf1 ';
  if s =  '<b>' then r := '\cf8\b ' ;
  if s = '</b>' then r := '\cf1\b0 ';
  if s = '</p>' then r := '\par ';
  if s =  '<h>' then r := '\cf3 ';
  if s = '</h>' then r := '\cf1 ';
  if s = '<br>' then r := '\par ';

  if s = '<tab>' then r := '\tab ';
  if s = '<rtl>' then r := '\rtlpar\qr ';
  if s = '<ltr>' then r := '\ltrpar\qr ';

  if s =  '<sup>' then r := '\super ';
  if s = '</sup>' then r := '\nosupersub ';

  if s = '<small>' then r := '\fs20 ';

  Result := r;
end;

procedure HtmlReplacement(var s: string);
begin
  Replace(s,'&nbsp;' ,' ');
  Replace(s,'&quot;' ,'"');
  Replace(s,'&ldquo;','«');
  Replace(s,'&rdquo;','»');
  Replace(s, #09     ,' ');

  Replace(s,  '<em>', '<i>' );
  Replace(s, '</em>','</i>' );

  Replace(s,  '<strong>', '<b>' );
  Replace(s, '</strong>','</b>' );

  Replace(s, '<p/>','<p>' );
  Replace(s,'<br/>','<br><tab>');
  Replace(s, '<td>','<br><tab>');
  Replace(s, '<tr>','<br><tab>');
  Replace(s,'</td>','<br><tab>');
  Replace(s,'</tr>','<br><tab>');

  if Pos('</p>',s) = 0 then Replace(s,'<p>','<br><tab>');
  Replace(s,'</p>','<br><tab>');

  DelDoubleSpace(s);
end;

function Parse(s: string; jtag: boolean; html: boolean): string;
var
  List : TStringArray;
  i : integer;
begin
  if html then HtmlReplacement(s);
  List := XmlToList(s);

  for i:=Low(List) to High(List) do
    if Prefix('<', List[i]) then
      begin
        if not html then List[i] := ParseString(List[i], jtag);
        List[i] := ParseHtml(List[i]);
        if Prefix('<', List[i]) then List[i] := '';
      end;

  Result := Trim(ListToString(List));
  Result := rtf_open + Result + rtf_close;
end;

initialization
  DefaultFont := TFont.Create;
  DefaultFont.Name := {$ifdef windows} 'Tahoma' {$else} 'default' {$endif};
  DefaultFont.Size := 12;

finalization
  DefaultFont.Free;

end.

