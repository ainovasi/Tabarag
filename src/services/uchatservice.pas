unit uChatService;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqldb, contnrs, uDBConnection, uChatModel;

type
  TChatService = class
  public
    function SaveMessage(const ASessionId, ARole, AContent: String): Boolean;
    function GetChatHistory(const ASessionId: String): TFPObjectList;
  end;

implementation

function TChatService.SaveMessage(const ASessionId, ARole, AContent: String): Boolean;
var
  DB: TDBConnection;
  Query: TSQLQuery;
begin
  Result := False;
  if (ASessionId = '') or (ARole = '') or (AContent = '') then Exit;

  DB := TDBConnection.GetInstance;
  DB.Connect;

  Query := TSQLQuery.Create(nil);
  try
    Query.Database := DB.Connection;
    Query.Transaction := DB.Transaction;

    Query.SQL.Text :=
      'INSERT INTO chat (session_id, role, content, created_at) ' +
      'VALUES (:session_id, :role, :content, datetime(''now'', ''localtime''));';

    Query.ParamByName('session_id').AsString := ASessionId;
    Query.ParamByName('role').AsString := ARole;
    Query.ParamByName('content').AsString := AContent;
    Query.ExecSQL;

    DB.Transaction.Commit;
    Result := True;
  except
    on E: Exception do
    begin
      DB.Transaction.Rollback;
      raise Exception.Create('Gagal menyimpan chat: ' + E.Message);
    end;
  end;

    Query.Free;

end;

function TChatService.GetChatHistory(const ASessionId: String): TFPObjectList;
var
  DB: TDBConnection;
  Query: TSQLQuery;
  ResultList: TFPObjectList;
  ChatItem: TChatItem;
begin
  ResultList := TFPObjectList.Create(True); // OwnsObjects = True
  if ASessionId = '' then
  begin
    Result := ResultList;
    Exit;
  end;

  DB := TDBConnection.GetInstance;
  DB.Connect;

  Query := TSQLQuery.Create(nil);
  try
    Query.Database := DB.Connection;
    Query.Transaction := DB.Transaction;

    Query.SQL.Text :=
      'SELECT id, session_id, role, content, created_at ' +
      'FROM chat ' +
      'WHERE session_id = :session_id ' +
      'ORDER BY id ASC;';

    Query.ParamByName('session_id').AsString := ASessionId;
    Query.Open;

    while not Query.EOF do
    begin
      ChatItem := TChatItem.Create;
      ChatItem.Id := Query.FieldByName('id').AsInteger;
      ChatItem.SessionId := Query.FieldByName('session_id').AsString;
      ChatItem.Role := Query.FieldByName('role').AsString;
      ChatItem.Content := Query.FieldByName('content').AsString;
      ChatItem.CreatedAt := Query.FieldByName('created_at').AsDateTime;

      ResultList.Add(ChatItem);
      Query.Next;
    end;
    Query.Close;
  except
    on E: Exception do
    begin
      ResultList.Free;
      raise Exception.Create('Gagal memuat riwayat chat: ' + E.Message);
    end;
  end;

    Query.Free;


  Result := ResultList;
end;

end.
