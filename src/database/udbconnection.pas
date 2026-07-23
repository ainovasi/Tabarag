unit uDBConnection;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqlite3conn, sqldb, sqlite3;

type
  TDBConnection = class
  private
    class var FInstance: TDBConnection;
  private
    FConnection: TSQLite3Connection;
    FTransaction: TSQLTransaction;
    FDbPath: String;
    FExtPath: String;
    procedure InitializePaths;
    procedure LoadVectorExtension;
  public
    constructor Create;
    destructor Destroy; override;

    class function GetInstance: TDBConnection;

    procedure Connect;
    procedure Disconnect;

    property Connection: TSQLite3Connection read FConnection;
    property Transaction: TSQLTransaction read FTransaction;
  end;

implementation

procedure TDBConnection.InitializePaths;
var
  ExeDir: String;
begin
  ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  // Menyesuaikan struktur folder proyek: bin/data/tax_knowledge.db
  //FDbPath := ExpandFileName(ExeDir + '..' + PathDelim + 'data' + PathDelim + 'tax_knowledge.db');
  FDbPath := ExpandFileName(ExeDir +  PathDelim + 'data' + PathDelim + 'tax_knowledge.db');
  // Membuat folder data jika belum ada
  if not DirectoryExists(ExtractFilePath(FDbPath)) then
    ForceDirectories(ExtractFilePath(FDbPath));

  // Jalur ekstensi vec0 di folder yang sama dengan executable
  {$IFDEF WINDOWS}
  FExtPath := ExeDir + 'vec0.dll';
  {$ELSE}
  FExtPath := ExeDir + 'libvec0.so';
  {$ENDIF}
end;

procedure TDBConnection.LoadVectorExtension;
var
  DbHandle: PSQLite3;
  ErrMsg: PAnsiChar;
  RC: Integer;
begin
  DbHandle := PSQLite3(FConnection.Handle);
  if Assigned(DbHandle) then
  begin
    ErrMsg := nil;
    sqlite3_enable_load_extension(DbHandle, 1);

    RC := sqlite3_load_extension(DbHandle, PAnsiChar(AnsiString(FExtPath)), nil, @ErrMsg);
    if RC <> SQLITE_OK then
    begin
      raise Exception.CreateFmt('Gagal memuat ekstensi sqlite-vec: %s', [String(ErrMsg)]);
      if Assigned(ErrMsg) then sqlite3_free(ErrMsg);
    end;
  end;
end;

constructor TDBConnection.Create;
begin
  inherited Create;
  InitializePaths;

  FConnection := TSQLite3Connection.Create(nil);
  FTransaction := TSQLTransaction.Create(nil);

  FConnection.Transaction := FTransaction;
  FTransaction.Database := FConnection;

  FConnection.DatabaseName := FDbPath;
  FConnection.CharSet := 'UTF8';
end;

destructor TDBConnection.Destroy;
begin
  Disconnect;
  FTransaction.Free;
  FConnection.Free;
  inherited Destroy;
end;

class function TDBConnection.GetInstance: TDBConnection;
begin
  if not Assigned(FInstance) then
    FInstance := TDBConnection.Create;
  Result := FInstance;
end;

procedure TDBConnection.Connect;
begin
  if not FConnection.Connected then
  begin
    FConnection.Open;
    LoadVectorExtension;
  end;
end;

procedure TDBConnection.Disconnect;
begin
  if FConnection.Connected then
  begin
    if FTransaction.Active then
      FTransaction.Commit;
    FConnection.Close;
  end;
end;

initialization
  TDBConnection.FInstance := nil;

finalization
  if Assigned(TDBConnection.FInstance) then
    TDBConnection.FInstance.Free;

end.
