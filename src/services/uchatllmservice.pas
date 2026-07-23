unit uChatLLMService;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fphttpclient, fpjson, jsonparser;

type
  TChatLLMService = class
  private
    FBaseUrl: String;
    FTemperature: Double;
  public
    constructor Create(const ABaseUrl: String = 'http://localhost:8081');

    { Mengirimkan System Prompt (berisi instruksi + konteks RAG) dan Pertanyaan User ke LLM }
    function GenerateAnswer(const ASystemPrompt, AUserQuery: String): String;

    property Temperature: Double read FTemperature write FTemperature;
  end;

implementation

constructor TChatLLMService.Create(const ABaseUrl: String);
begin
  inherited Create;
  FBaseUrl := ABaseUrl;
  FTemperature := 0.3; // Nilai rendah agar jawaban LLM lebih faktual/kaku pada konteks
end;

function TChatLLMService.GenerateAnswer(const ASystemPrompt, AUserQuery: String): String;
var
  Client: TFPHTTPClient;
  ReqBody: TStringStream;
  RootObj, MsgSystem, MsgUser: TJSONObject;
  MsgArray: TJSONArray;
  JsonPayload: String;
  RawResponse: String;

  // Variabel untuk parsing JSON respon
  JsonParser: TJSONParser;
  ResRoot: TJSONObject;
  ResChoices: TJSONArray;
  ResChoice0: TJSONObject;
  ResMessage: TJSONObject;
begin
  Result := '';
  if (ASystemPrompt = '') and (AUserQuery = '') then Exit;

  Client := TFPHTTPClient.Create(nil);
  RootObj := TJSONObject.Create;
  MsgArray := TJSONArray.Create;
  try
    // 1. Konstruksi JSON Payload secara aman (Mengurangi resiko escape string manual)
    MsgSystem := TJSONObject.Create;
    MsgSystem.Add('role', 'system');
    MsgSystem.Add('content', ASystemPrompt);
    MsgArray.Add(MsgSystem);

    MsgUser := TJSONObject.Create;
    MsgUser.Add('role', 'user');
    MsgUser.Add('content', AUserQuery);
    MsgArray.Add(MsgUser);

    RootObj.Add('messages', MsgArray);
    RootObj.Add('temperature', FTemperature);

    JsonPayload := RootObj.AsJSON;

    // 2. Eksekusi HTTP POST ke llama-server (Gemma 3 Instance)
    try
      Client.AddHeader('Content-Type', 'application/json');
      ReqBody := TStringStream.Create(JsonPayload, TEncoding.UTF8);
      try
        Client.RequestBody := ReqBody;
        RawResponse := Client.Post(FBaseUrl + '/v1/chat/completions');
      finally
        ReqBody.Free;
      end;

      // 3. Ekstraksi Hasil text generation dari JSON Respon
      if RawResponse <> '' then
      begin
        JsonParser := TJSONParser.Create(RawResponse);
        try
          ResRoot := JsonParser.Parse as TJSONObject;
          try
            ResChoices := ResRoot.Arrays['choices'];
            if (Assigned(ResChoices)) and (ResChoices.Count > 0) then
            begin
              ResChoice0 := ResChoices.Objects[0];
              ResMessage := ResChoice0.Objects['message'];
              if Assigned(ResMessage) then
                Result := ResMessage.Strings['content'];
            end;
          finally
            ResRoot.Free;
          end;
        finally
          JsonParser.Free;
        end;
      end;

    except
      on E: Exception do
        raise Exception.Create('LLM Generation Error: ' + E.Message);
    end;
  finally
    RootObj.Free; // Otomatis membebaskan MsgArray beserta turunannya
    Client.Free;
  end;
end;

end.
