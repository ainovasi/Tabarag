unit uEmbeddingService;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fphttpclient, uJsonHelper;

type
  TEmbeddingService = class
  private
    FBaseUrl: String;
  public
    constructor Create(const ABaseUrl: String = 'http://localhost:8080');
    function GetEmbedding(const AText: String): String;
  end;

implementation

constructor TEmbeddingService.Create(const ABaseUrl: String);
begin
  inherited Create;
  FBaseUrl := ABaseUrl;
end;

function TEmbeddingService.GetEmbedding(const AText: String): String;
var
  Client: TFPHTTPClient;
  ReqBody: TStringStream;
  JsonPayload: String;
  RawResponse: String;
begin
  Result := '';
  if AText = '' then Exit;

  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.AddHeader('Content-Type', 'application/json');

      JsonPayload := Format('{"input": "%s"}', [TJsonHelper.EscapeJsonString(AText)]);
      ReqBody := TStringStream.Create(JsonPayload, TEncoding.UTF8);
      Client.RequestBody := ReqBody;

      RawResponse := Client.Post(FBaseUrl + '/v1/embeddings');
      Result := TJsonHelper.ExtractEmbedding(RawResponse);
    except
      on E: Exception do
        raise Exception.Create('Embedding Error: ' + E.Message);
    end;
  finally
    Client.Free;
  end;
end;

end.
