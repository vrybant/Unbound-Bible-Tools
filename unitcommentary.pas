unit UnitCommentary;

{$ifdef linux}
  {$define zeos}
{$endif}

interface

uses
  Classes, Fgl, SysUtils, Dialogs, Graphics, IniFiles, ClipBrd, LazUtf8, DB, SQLdb,
  {$ifdef zeos} ZConnection, ZDataset, ZDbcSqLite, {$else} SQLite3conn, {$endif}
  UnitLib, UnitTitles, UnitType;

const
  BookMax = 86;

type
  TBook = class
  public
    title   : string;
    abbr    : string;
    number  : integer;
    id      : integer;
    sorting : integer;
  end;

  TCommentary = class(TFPGList<TBook>)
    {$ifdef zeos}
      Connection : TZConnection;
      Query : TZReadOnlyQuery;
    {$else}
      Connection : TSQLite3Connection;
      Transaction : TSQLTransaction;
      Query : TSQLQuery;
    {$endif}
    {-}
    info         : string;
    filePath     : string;
    fileName     : string;
    fileFormat   : TFileFormat;
    z            : TStringAlias;
    {-}
    name         : string;
    native       : string;
    abbreviation : string;
    copyright    : string;
    language     : string;
    fileType     : string;
    note         : string;
    {-}
    FirstVerse   : TVerse;
    RightToLeft  : boolean;
    compare      : boolean;
    fontName     : TFontName;
    fontSize     : integer;
    {-}
//  oldTestament : boolean;
//  newTestament : boolean;
//  apocrypha    : boolean;
    connected    : boolean;
    loaded       : boolean;
  private
    function EncodeID(id: integer): integer;
    function DecodeID(id: integer): integer;
    function SortingIndex(number: integer): integer;
    function RankContents(const Contents: TContentArray): TContentArray;
  public
    constructor Create(filePath: string);
    procedure OpenDatabase;
    procedure LoadDatabase;
    function MinBook: integer;
    function BookByNum(n: integer): TBook;
    function BookByName(s: string): TBook;
    function VerseToStr(Verse: TVerse; full: boolean): string;
    function SrtToVerse(link : string): TVerse;
    procedure SetTitles;
    function GetChapter(Verse: TVerse): TStringArray;
    function GetRange(Verse: TVerse): TStringArray;
    function GoodLink(Verse: TVerse): boolean;
    function  Search(searchString: string; SearchOptions: TSearchOptions; Range: TRange): TContentArray;
    function GetAll: TContentArray;
    procedure GetTitles(var List: TStringList);
    function  ChaptersCount(Verse: TVerse): integer;
    procedure SavePrivate(const IniFile: TIniFile);
    procedure ReadPrivate(const IniFile: TIniFile);
    destructor Destroy; override;
  end;

  TCommentaries = class(TFPGList<TCommentary>)
    Current : integer;
  private
    procedure AddBibles(path: string);
    procedure SavePrivates;
    procedure ReadPrivates;
  public
    constructor Create;
    procedure SetCurrent(FileName: string); overload;
    procedure SetCurrent(index: integer); overload;
    destructor Destroy; override;
  end;

var
  Shelf : TCommentaries;
  ActiveVerse : TVerse;

const
  apBible      = 0; // PageControl.ActivePageIndex
  apSearch     = 1;
  apCompare    = 2;
  apCommentary = 3;
  apNotes      = 4;

function Bible: TCommentary;

implementation

uses UnitSQLiteEx;

function Bible: TCommentary;
begin
  Result := Shelf[Shelf.Current];
end;

//========================================================================================
//                                     TCommentary
//========================================================================================

constructor TCommentary.Create(filePath: string);
begin
  inherited Create;

  {$ifdef zeos}
    Connection := TZConnection.Create(nil);
    Query := TZReadOnlyQuery.Create(nil);
    Connection.Database := filePath;
    Connection.Protocol := 'sqlite-3';
    Query.Connection := Connection;
  {$else}
    Connection := TSQLite3Connection.Create(nil);
    Connection.CharSet := 'UTF8';
    Connection.DatabaseName := filePath;
    Transaction := TSQLTransaction.Create(Connection);
    Connection.Transaction := Transaction;
    Query := TSQLQuery.Create(nil);
    Query.DataBase := Connection;
  {$endif}

  self.filePath := filePath;
  self.fileName := ExtractFileName(filePath);

  fileFormat   := unbound;
  z            := unboundStringAlias;

  name         := fileName;
  native       := '';
  abbreviation := '';
  copyright    := '';
  language     := 'english';
  filetype     := '';
  connected    := false;
  loaded       := false;
  RightToLeft  := false;
//oldTestament := false;
//newTestament := false;
//apocrypha    := false;

  OpenDatabase;
end;

function BookComparison(const Item1: TBook; const Item2: TBook): integer;
begin
  Result := Item1.sorting - Item2.sorting;
end;

procedure TCommentary.OpenDatabase;
var
  FieldNames : TStringList;
  key, value : string;
  dbhandle : Pointer;
begin
  try
    {$ifdef zeos}
      Connection.Connect;
      dbhandle := (Connection.DbcConnection as TZSQLiteConnection).GetConnectionHandle();
    {$else}
      Connection.Open;
      Transaction.Active := True;
      dbhandle := Connection.Handle;
    {$endif}

    if  not Connection.Connected then Exit;
    SQLite3CreateFunctions(dbhandle);
 // Connection.ExecuteDirect('PRAGMA case_sensitive_like = 1');
  except
    output('connection failed ' + self.fileName);
    Exit;
  end;

  try
    try
      Query.SQL.Text := 'SELECT * FROM Details';
      Query.Open;

      try info      := Query.FieldByName('Information').AsString; except end;
      try info      := Query.FieldByName('Description').AsString; except end;
      try name      := Query.FieldByName('Title'      ).AsString; except name := info; end;
      try copyright := Query.FieldByName('Copyright'  ).AsString; except end;
      try language  := Query.FieldByName('Language'   ).AsString; except end;

      connected := true;
    except
      //
    end;
  finally
    Query.Close;
  end;

  try
    try
      Query.SQL.Text := 'SELECT * FROM info';
      Query.Open;

      while not Query.Eof do
        begin
          try key   := Query.FieldByName('name' ).AsString; except end;
          try value := Query.FieldByName('value').AsString; except end;

          if key = 'description'   then name     := value;
          if key = 'detailed_info' then info     := value;
          if key = 'language'      then language := value;

          Query.Next;
        end;

      fileFormat := mybible;
      z := mybibleStringAlias;
      connected := true;
    except
      //
    end;
  finally
    Query.Close;
  end;

  FieldNames := TStringList.Create;
  try Connection.GetTableNames({$ifdef zeos}'',{$endif}FieldNames) except end;
  if FieldNames.IndexOf(z.bible) < 0 then connected := false;
  FieldNames.Free;

  language := LowerCase(language);
  RightToLeft := GetRightToLeft(language);
  RemoveTags(info);
end;

procedure TCommentary.LoadDatabase;
var
  Book : TBook;
  x, n : integer;
begin
  if loaded then exit;

  try
    try
      Query.SQL.Text := 'SELECT DISTINCT ' + z.book + ' FROM ' + z.bible;
      Query.Open;

      while not Query.Eof do
        begin
          try x := Query.FieldByName(z.book).AsInteger; except x := 0 end;
          if  x <= 0 then Continue;

          Book := TBook.Create;
          n := DecodeID(x);
          Book.number := n;
          Book.title := IntToStr(x);
          Book.id := x;
          Book.sorting := SortingIndex(n);
          Add(Book);
          Query.Next;
        end;

      SetTitles;
      firstVerse := minVerse;
      firstVerse.book := MinBook;
      Sort(BookComparison);

      loaded := true;
    except
      //
    end;
  finally
    Query.Close;
  end;

//Output(self.fileName + ' loaded');
end;

procedure TCommentary.SetTitles;
var
  Titles : TTitles;
  i : integer;
begin
  Titles := TTitles.Create(Language);

  for i:=0 to Count-1 do
    begin
      self[i].title := Titles.getTitle(self[i].number);
      self[i].abbr  := Titles.getAbbr(self[i].number);
    end;

  Titles.Free;
end;

function TCommentary.EncodeID(id: integer): integer;
begin
  Result := id;
  if fileFormat = mybible then
    if id > 0 then
      if id <= Length(myBibleArray) then
        Result := myBibleArray[id];
end;

function TCommentary.DecodeID(id: integer): integer;
var i : integer;
begin
  Result := id;
  if fileFormat = mybible then
    if id > 0 then
      for i:=1 to Length(myBibleArray) do
        if id = myBibleArray[i] then
          begin
            Result := i;
            Exit;
          end;
end;

function TCommentary.SortingIndex(number: integer): integer;
var
  i : integer;
  l : boolean;
begin
  Result := 100;
  if number <= 0 then Exit;
  l := Orthodox(language);

  for i:=1 to Length(sortArrayEN) do
    if (not l and (number = sortArrayEN[i])) or
           (l and (number = sortArrayRU[i])) then
      begin
        Result := i;
        Exit;
      end;
end;

function TCommentary.MinBook: integer;
var i, min : integer;
begin
  min := 0;
  for i:=0 to Count-1 do
    if (Items[i].Number < min) or (min = 0) then min := Items[i].Number;
  Result := min;
end;

function TCommentary.BookByNum(n: integer): TBook;
var i : integer;
begin
  Result := nil;
  for i:=0 to Count-1 do
    if Items[i].Number = n then Result := Items[i];
end;

function TCommentary.BookByName(s: string): TBook;
var i : integer;
begin
  Result := nil;
  for i:=0 to Count-1 do
    if Items[i].Title = s then Result := Items[i];
end;

function TCommentary.VerseToStr(verse: TVerse; full: boolean): string;
var
  Book : TBook;
  title : string;
begin
  Result := 'error';

  Book := Bible.BookByNum(verse.book);
  if not Assigned(Book) then Exit;

  if full then title := Book.title else title := Book.abbr;
  if Pos('.', title) = 0 then title := title + ' ';

  Result := title + IntToStr(verse.chapter) + ':' + IntToStr(verse.number);
  if (verse.number <> 0) and (verse.count > 1) then
    Result := Result + '-' + IntToStr(verse.number + verse.count - 1);
end;

function TCommentary.SrtToVerse(link : string): TVerse;
var
  i : integer;

  procedure GetLink(i: integer; T: boolean);
  var
    s, p : string;
    len, n : integer;
    endVerse : integer;
  begin
    if T then len := Length(Items[i].title)
         else len := Length(Items[i].abbr );

    s := Copy(link,len+1,255);
    s := Trim(s);

    if Length(s) = 0 then Exit;
    if not IsNumeral(s[1]) then Exit;

    Result.count := 1;
    endVerse := 0;

    n := Pos('-',s);
    if n > 0 then
      begin
        p := Copy(s,n+1,255);
        s := Copy(s,1,n-1);
        endVerse := MyStrToInt(p);
      end;

    n := Pos(':',s);      Result.book    := Items[i].number;
    p := Copy(s,1,n-1);   Result.chapter := MyStrToInt(p);
    p := Copy(s,n+1,255); Result.number  := MyStrToInt(p);

    if endVerse > 0 then
      Result.count := endVerse - Result.number + 1;
  end;

begin
  Result.Book    := 0;
  Result.Chapter := 0;
  Result.Number  := 0;
  Result.Count   := 0;

  if Pos(':',link) = 0 then Exit;
  link := Trim(link);

  for i:=0 to Count-1 do
    begin
      if Prefix(Items[i].title,link) then GetLink(i,true );
      if Prefix(Items[i].abbr ,link) then GetLink(i,false);
    end;
end;

function TCommentary.GetChapter(Verse: TVerse): TStringArray;
var
  index, i : integer;
  id, chapter : string;
  line : string;
begin
  SetLength(Result,0);

  index := EncodeID(Verse.book);
  id := IntToStr(index);
  chapter := IntToStr(Verse.chapter);

  try
    try
      Query.SQL.Text := 'SELECT * FROM ' + z.bible + ' WHERE ' + z.book + '=' + id + ' AND ' + z.chapter + '=' + chapter;
      Query.Open;

      Query.Last;
      SetLength(Result, Query.RecordCount);
      Query.First;

      for i:=0 to Query.RecordCount-1 do
        begin
          try line := Query.FieldByName(z.text).AsString; except line := '' end;
      //  line = line.replace("\n", "") // ESWORD ?
          Result[i] := line;
          Query.Next;
        end;
    except
      //
    end;
  finally
    Query.Close;
  end;
end;

function TCommentary.GetRange(Verse: TVerse): TStringArray;
var
  index, i : integer;
  id, chapter : string;
  verseNumber, toVerse : string;
  line : string;
begin
  SetLength(Result,0);

  index := EncodeID(Verse.book);
  id := IntToStr(index);
  chapter := IntToStr(Verse.chapter);
  verseNumber := IntToStr(Verse.number);
  toVerse := IntToStr(verse.number + verse.count);

  try
    try
      Query.SQL.Text := 'SELECT * FROM ' + z.bible + ' WHERE ' + z.book + '=' + id +
                        ' AND ' + z.chapter + '=' + chapter +
                        ' AND ' + z.verse + ' >= ' + verseNumber +
                        ' AND ' + z.verse + ' < ' + toVerse;
      Query.Open;

      Query.Last;
      SetLength(Result, Query.RecordCount);
      Query.First;

      for i:=0 to Query.RecordCount-1 do
        begin
          try line := Query.FieldByName(z.text).AsString; except line := '' end;
          Result[i] := line;
          Query.Next;
        end;
    except
      //
    end;
  finally
    Query.Close;
  end;
end;

function TCommentary.GoodLink(Verse: TVerse): boolean;
begin
  Result := Length(GetRange(Verse)) > 0;
end;

function TCommentary.RankContents(const Contents: TContentArray): TContentArray;
var
  i,j,k : integer;
begin
  SetLength(Result,Length(Contents));
  k:=0;
  for i:=0 to Count-1 do
    for j:=0 to Length(Contents)-1 do
      if Contents[j].verse.book = Items[i].Number then
        begin
          Result[k] := Contents[j];
          Inc(k);
        end;
end;

function TCommentary.Search(searchString: string; SearchOptions: TSearchOptions; Range: TRange): TContentArray;
var
  Contents : TContentArray;
  queryRange, from, till : string;
  i : integer;
begin
  SetLength(Result,0);
  queryRange := '';

  SetSearchOptions(searchString, SearchOptions);

  if Range.from > 0 then
    begin
      from := IntToStr(EncodeID(Range.from));
      till := IntToStr(EncodeID(Range.till));
      queryRange := ' AND ' + z.book + ' >= ' + from + ' AND ' + z.book + ' <= ' + till;
    end;

  try
    try
      Query.SQL.Text := 'SELECT * FROM ' + z.bible + ' WHERE super(' + z.text + ')=''1''' + queryRange;
      Query.Open;

      Query.Last; // must be called before RecordCount
      SetLength(Contents,Query.RecordCount);
      Query.First;

      for i:=0 to Query.RecordCount-1 do
        begin
          Contents[i].verse := noneVerse;
          try Contents[i].verse.book    := Query.FieldByName(z.book   ).AsInteger; except end;
          try Contents[i].verse.chapter := Query.FieldByName(z.chapter).AsInteger; except end;
          try Contents[i].verse.number  := Query.FieldByName(z.verse  ).AsInteger; except end;
          try Contents[i].text          := Query.FieldByName(z.text   ).AsString;  except end;
          Contents[i].verse.book := DecodeID(Contents[i].verse.book);
          Query.Next;
        end;
    finally
      Query.Close;
    end;
  except
    Exit;
  end;

  Result := RankContents(Contents);
end;

function TCommentary.GetAll: TContentArray;
var
  Contents : TContentArray;
  i : integer;
begin
  SetLength(Result,0);

  try
    try
      Query.SQL.Text := 'SELECT * FROM ' + z.bible;
      Query.Open;

      Query.Last; // must be called before RecordCount
      SetLength(Contents,Query.RecordCount);
      Query.First;

      for i:=0 to Query.RecordCount-1 do
        begin
          Contents[i].verse := noneVerse;
          try Contents[i].verse.book    := Query.FieldByName(z.book   ).AsInteger; except end;
          try Contents[i].verse.chapter := Query.FieldByName(z.chapter).AsInteger; except end;
          try Contents[i].verse.number  := Query.FieldByName(z.verse  ).AsInteger; except end;
          try Contents[i].text          := Query.FieldByName(z.text   ).AsString;  except end;
          Contents[i].verse.book := DecodeID(Contents[i].verse.book);
          Query.Next;
        end;
    except
      //
    end;
  finally
    Query.Close;
  end;
end;

procedure TCommentary.GetTitles(var List: TStringList);
var i : integer;
begin
  for i := 0 to self.Count - 1 do
    List.Add(self[i].Title);
end;

function TCommentary.ChaptersCount(Verse: TVerse): integer;
var
  index : integer;
  id : string;
begin
  Result := 1;

  index := EncodeID(Verse.book);
  id := IntToStr(index);

  try
    try
      Query.SQL.Text := 'SELECT MAX(' + z.chapter + ') AS Count FROM ' + z.bible + ' WHERE ' + z.book + '=' + id;
      Query.Open;

      try Result := Query.FieldByName('Count').AsInteger; except end;
    except
      //
    end;
  finally
    Query.Close;
  end;
end;

procedure TCommentary.SavePrivate(const IniFile : TIniFile);
begin
  IniFile.WriteBool(FileName, 'Compare', Compare);
end;

procedure TCommentary.ReadPrivate(const IniFile : TIniFile);
begin
  Compare := IniFile.ReadBool(FileName, 'Compare', True);
end;

destructor TCommentary.Destroy;
var
  i : integer;
begin
  for i:=0 to Count-1 do Items[i].Free;

  Query.Free;
  {$ifndef zeos} Transaction.Free; {$endif}
  Connection.Free;

  inherited Destroy;
end;

//=================================================================================================
//                                         TCommentaries
//=================================================================================================

function Comparison(const Item1: TCommentary; const Item2: TCommentary): integer;
begin
  Result := CompareText(Item1.Name, Item2.Name);
end;

constructor TCommentaries.Create;
begin
  inherited;

  AddBibles(GetUserDir + AppName);
  {$ifdef windows} if Self.Count = 0 then {$endif} AddBibles(SharePath + 'bibles');
  Sort(Comparison);

  ReadPrivates;
end;

procedure TCommentaries.AddBibles(path: string);
var
  Item : TCommentary;
  List : TStringArray;
  f : string;
begin
  List := GetFileList(path, '*.*');

  for f in List do
    begin
      Item := TCommentary.Create(f);
      if Item.connected then Add(Item) else Item.Free;
    end;
end;

procedure TCommentaries.SetCurrent(index: integer);
begin
  Current := index;
  Self[Current].LoadDatabase;
  if not Self[Current].GoodLink(ActiveVerse) then ActiveVerse := Self[Current].FirstVerse;
end;

procedure TCommentaries.SetCurrent(FileName: string);
var i : integer;
begin
  Current := 0;
  if Count = 0 then Exit;
  for i:= Count-1 downto 0 do
    if Items[i].FileName = FileName then Current := i;
  SetCurrent(Current);
end;

procedure TCommentaries.SavePrivates;
var
  IniFile : TIniFile;
  i : integer;
begin
  IniFile := TIniFile.Create(ConfigFile);
  for i:=0 to Count-1 do Items[i].SavePrivate(IniFile);
  IniFile.Free;
end;

procedure TCommentaries.ReadPrivates;
var
  IniFile : TIniFile;
  i : integer;
begin
  IniFile := TIniFile.Create(ConfigFile);
  for i:=0 to Count-1 do Items[i].ReadPrivate(IniFile);
  IniFile.Free;
end;

destructor TCommentaries.Destroy;
var i : integer;
begin
  SavePrivates;
  for i:=0 to Count-1 do Items[i].Free;
  inherited Destroy;
end;

initialization
  Shelf := TCommentaries.Create;

finalization
  Shelf.Free;

end.