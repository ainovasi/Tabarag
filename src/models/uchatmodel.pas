unit uChatModel;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TChatItem = class
  private
    FId: Integer;
    FSessionId: String;
    FRole: String;
    FContent: String;
    FCreatedAt: TDateTime;
  public
    constructor Create; overload;
    constructor Create(AId: Integer; const ASessionId, ARole, AContent: String; ACreatedAt: TDateTime); overload;

    property Id: Integer read FId write FId;
    property SessionId: String read FSessionId write FSessionId;
    property Role: String read FRole write FRole;
    property Content: String read FContent write FContent;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

implementation

constructor TChatItem.Create;
begin
  FId := 0;
  FSessionId := '';
  FRole := '';
  FContent := '';
  FCreatedAt := 0.0;
end;

constructor TChatItem.Create(AId: Integer; const ASessionId, ARole, AContent: String; ACreatedAt: TDateTime);
begin
  FId := AId;
  FSessionId := ASessionId;
  FRole := ARole;
  FContent := AContent;
  FCreatedAt := ACreatedAt;
end;

end.
